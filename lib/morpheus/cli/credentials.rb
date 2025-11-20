require 'fileutils'
require 'yaml'
require 'json'
require 'io/console'
require 'rest_client'
require 'morpheus/logging'
require 'morpheus/cli/mixins/print_helper'

module Morpheus
  module Cli
    class Credentials
      include Morpheus::Cli::PrintHelper

      @@appliance_credentials_map = nil

      def initialize(appliance_name, appliance_url)
        @appliance_name = appliance_name ? appliance_name.to_sym : nil
        @appliance_url = appliance_url
      end
      
      # request_credentials will fetch a credentials wallet (access_token, refresh_token, etc)
      # By default this uses the saved credentials for the current appliance.
      # If not logged in, it will prompt for username and password to
      # authenticate with the /oauth/token API to receive an access_token.
      # If :username and :password are passed, then
      # Pass :remote_token to skip prompting and the auth api request.
      # @param options - Hash of optional settings.
      #   :username - Username for prompt.
      #   :password - Password for prompt.
      #   :remote_url - Use this url instead of the one from the current appliance. Credentials will not be saved.
      #   :remote_token - Use this access_token, skip prompting and API request.
      #   :remote_username - Username for authentication with --remote, skips saving credentials
      #   :remote_password - Password for authentication with --remote, skips saving credentials
      #   :test_only - Test only. Saved credentials will not be updated.
      # @return Hash wallet like {"access_token":"ec68be138765...", "refresh_token":"ec68be138765..."} 
      # or nil if unable to find credentials.
      def request_credentials(options = {}, do_save=true)
        #puts "request_credentials(#{options})"
        username = nil
        password = nil
        wallet = nil

        # should not need this logic in here
        if options[:remote_url]
          # @appliance_name = options[:remote_url] 
          # name should change too though or printing may be misleading.
          # @appliance_name = "remote-url"
          # @appliance_url = options[:remote_url]
          # do not save when using --remote-url
          do_save = false
        end

        if options[:remote_token]
          # user passed in a token to login with.
          # this should get token info from /oauth/token
          # OR whoami should return other wallet info like access token or maybe just the expiration date
          # for now, it just stores the access token without other wallet info
          begin
            whoami_interface = Morpheus::WhoamiInterface.new({url: @appliance_url, access_token: options[:remote_token], verify_ssl: !options[:insecure]})
            whoami_interface.setopts(options)
            if options[:dry_run]
              print_dry_run whoami_interface.dry.get()
              return nil
            end
            whoami_response = whoami_interface.get()
            if options[:json]
              puts as_json(whoami_response, options)
              print reset, "\n"
            end
            # store mock /oauth/token  auth_interface.login() result
            json_response = {'access_token' => options[:remote_token], 'token_type' => 'bearer'}
            username = whoami_response['user']['username']
            login_date = Time.now
            expire_date = nil
            if json_response['expires_in']
              expire_date = login_date.to_i + json_response['expires_in'].to_i
            end
            wallet = {
              'username' => username, 
              'login_date' => login_date.to_i,
              'expire_date' => expire_date ? expire_date.to_i : nil,
              'access_token' => json_response['access_token'], 
              'refresh_token' => json_response['refresh_token'], 
              'token_type' => json_response['token_type']
            }
          rescue ::RestClient::Exception => e
            #raise e
            print_red_alert "Token not valid."
            if options[:debug]
              print_rest_exception(e, options)
            end
            wallet = nil
          end
        else
          # ok prompt for creds..
          username = options['username'] || options[:username] || nil
          password = options['password'] || options[:password] || nil
          
          # what are these for? just use :username and :password
          if options[:remote_username]
            username = options[:remote_username]
            password = options[:remote_password]
          end
          if wallet.nil?
            unless options[:quiet] || options[:no_prompt]
              print "Enter Morpheus Credentials for #{display_appliance(@appliance_name, @appliance_url)}", "\n", reset
              if options[:client_id].empty?
                # print "Client ID: #{required_blue_prompt} #{options[:client_id]}", "\n", reset
              else
                if options[:client_id] != Morpheus::APIClient::CLIENT_ID
                  print "Client ID: #{required_blue_prompt} #{options[:client_id]}", "\n", reset
                end
              end
              if username.empty?
                # print "Username: #{required_blue_prompt} "
                # username = $stdin.gets.chomp!
                Readline.completion_append_character = ""
                Readline.basic_word_break_characters = ''
                Readline.completer_word_break_characters = '' rescue nil
                Readline.completion_proc = nil
                username = Readline.readline("Username: #{required_blue_prompt} ", false).to_s.chomp
              else
                print "Username: #{required_blue_prompt} #{username}\n"
              end
              if password.empty?
                # readline is still echoing secret with 'NUL:'' so just use $stdin on windows for now
                # and some other environments? just use noecho unless running unit tests
                if Morpheus::Cli.windows? || !Morpheus::Cli.testing?
                  print "Password: #{required_blue_prompt} "
                  # this should be my_terminal.stdin instead of STDIN and $stdin
                  password = $stdin.noecho(&:gets).chomp!
                  print "\n"
                else                

                  Readline.completion_append_character = ""
                  Readline.basic_word_break_characters = ''
                  Readline.completer_word_break_characters = '' rescue nil
                  Readline.completion_proc = nil
                  # needs to work like $stdin.noecho
                  Readline.pre_input_hook = lambda {
                    Readline.output = File.open('/dev/null', 'w')
                    #Readline.output = File.open(Morpheus::Cli.windows? ? 'NUL:' : '/dev/null', 'w')
                    #$stdout = File.open(Morpheus::Cli.windows? ? 'NUL:' : '/dev/null', 'w')
                  }
                  password = Readline.readline("Password: #{required_blue_prompt} ", false).to_s.chomp
                  Readline.pre_input_hook = nil
                  Readline.output = Morpheus::Terminal.instance.stdout #my_terminal.stdout
                  print "\n"
                end
              else
                print "Password: #{required_blue_prompt} \n"
              end
            end
            if username.empty? || password.empty?
              print_red_alert "Username and password are required to login."
              return nil
            end
            begin
              auth_interface = Morpheus::AuthInterface.new({url:@appliance_url, client_id: options[:client_id], verify_ssl: !options[:insecure]})
              auth_interface.setopts(options)
              if options[:dry_run]
                print_dry_run auth_interface.dry.login(username, password)
                return nil
              end
              json_response = auth_interface.login(username, password)
              if options[:json]
                print JSON.pretty_generate(json_response)
                print reset, "\n"
              end
              #wallet = json_response
              login_date = Time.now
              expire_date = nil
              if json_response['expires_in']
                expire_date = login_date.to_i + json_response['expires_in'].to_i
              end
              wallet = {
                'username' => username, 
                'login_date' => login_date.to_i,
                'expire_date' => expire_date ? expire_date.to_i : nil,
                'access_token' => json_response['access_token'], 
                'refresh_token' => json_response['refresh_token'], 
                'token_type' => json_response['token_type']
              }

            rescue ::RestClient::Exception => e
              #raise e
              if (e.response && e.response.code == 400)
                json_response = JSON.parse(e.response.to_s)
                error_msg = json_response['error_description'] || "Credentials not verified."
                print_red_alert error_msg
                if options[:json]
                  json_response = JSON.parse(e.response.to_s)
                  print JSON.pretty_generate(json_response)
                  print reset, "\n"
                end
              else
                print_rest_exception(e, options)
              end
              wallet = nil
            end

          end
        end

        if do_save && @appliance_name
          begin
            # save pertinent session info to the appliance
            save_credentials(@appliance_name, wallet)
            now = Time.now.to_i
            appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
            if wallet && wallet['access_token']
              save_credentials(@appliance_name, wallet)
            else
              clear_saved_credentials(@appliance_name)
            end
            if appliance
              if wallet && wallet['access_token']
                # save wallet to credentials file
                save_credentials(@appliance_name, wallet)
                # save appliances file
                appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
                appliance[:authenticated] = true
                appliance[:username] = username
                appliance[:status] = "ready"
                appliance[:last_login_at] = now
                appliance[:last_success_at] = now
                ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
              else
                # could be nice and not do this
                #logout()
                #save wallet to credentials file
                clear_saved_credentials(@appliance_name)
                now = Time.now.to_i
                appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
                appliance[:authenticated] = false
                old_username = appliance.delete(:username)
                appliance[:last_logout_at] = Time.now.to_i
                #appliance[:last_login_at] = now
                #appliance[:error] = "Credentials not verified"
                appliance.delete(:username)
                ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
                if old_username
                  print reset,"You have been automatically logged out. Goodbye #{old_username}!", reset, "\n"
                end
              end

            end
          rescue => e
            Morpheus::Logging::DarkPrinter.puts "failed to update remote appliance config: (#{e.class}) #{e.message}"
          ensure
            #::Morpheus::Cli::Remote.recalculate_variable_map()
          end
        end
        
        return wallet
      end

      def login(options = {}, do_save=true)
        request_credentials(options, do_save)
      end

      def logout()
        clear_saved_credentials(@appliance_name)
        # save pertinent session info to the appliance
        appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
        if appliance
          appliance.delete(:username) # could leave this...
          appliance[:authenticated] = false
          appliance[:last_logout_at] = Time.now.to_i
          ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
        end
        ::Morpheus::Cli::Remote.recalculate_variable_map()
        true
      end

      def use_refresh_token(refresh_token_value, options = {})
        
        wallet = load_saved_credentials

        if wallet.nil?
          print_red_alert yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
          return nil
        end

        if refresh_token_value.nil?
          if wallet['refresh_token']
            refresh_token_value = wallet['refresh_token']
          else
            print_red_alert yellow,"No refresh token found for #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
            return nil
          end
        end

        username = wallet['username']

        begin
          auth_interface = Morpheus::AuthInterface.new({url:@appliance_url, client_id: options[:client_id], verify_ssl: !options[:insecure]})
          auth_interface.setopts(options)
          if options[:dry_run]
            print_dry_run auth_interface.dry.use_refresh_token(refresh_token_value)
            return nil
          end
          json_response = auth_interface.use_refresh_token(refresh_token_value)
          #wallet = json_response
          login_date = Time.now
          expire_date = nil
          if json_response['expires_in']
            expire_date = login_date.to_i + json_response['expires_in'].to_i
          end
          wallet = {
            'username' => username, 
            'login_date' => login_date.to_i,
            'expire_date' => expire_date ? expire_date.to_i : nil,
            'access_token' => json_response['access_token'], 
            'refresh_token' => json_response['refresh_token'], 
            'token_type' => json_response['token_type']
          }
          
        rescue ::RestClient::Exception => e
          #raise e
          if (e.response && e.response.code == 400)
            json_response = JSON.parse(e.response.to_s)
            error_msg = json_response['error_description'] || "Refresh token not valid."
            print_red_alert error_msg
            if options[:json]
              json_response = JSON.parse(e.response.to_s)
              print JSON.pretty_generate(json_response)
              print reset, "\n"
            end
          else
            print_rest_exception(e, options)
          end
          wallet = nil
          # return now or else it will log them out
          return nil
        end

        # save wallet to credentials file
        save_credentials(@appliance_name, wallet)

        begin
        # save pertinent session info to the appliance
          now = Time.now.to_i
          appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
          if appliance
            if wallet && wallet['access_token']
              appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
              appliance[:authenticated] = true
              appliance[:username] = username
              appliance[:status] = "ready"
              appliance[:last_login_at] = now
              appliance[:last_success_at] = now
              ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
            else
              now = Time.now.to_i
              appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
              appliance[:authenticated] = false
              #appliance[:username] = username
              #appliance[:last_login_at] = now
              #appliance[:error] = "Credentials not verified"
              ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
            end
          end
        rescue => e
          Morpheus::Logging::DarkPrinter.puts "failed to update remote appliance config: (#{e.class}) #{e.message}"
        end
        
        
        return wallet
      end

      def clear_saved_credentials(appliance_name)
        @@appliance_credentials_map = load_credentials_file || {}
        @@appliance_credentials_map.delete(appliance_name.to_s)
        @@appliance_credentials_map.delete(appliance_name.to_sym)
        #Morpheus::Logging::DarkPrinter.puts "clearing credentials for #{appliance_name} from file #{credentials_file_path}" if Morpheus::Logging.debug?
        File.open(credentials_file_path, 'w') {|f| f.write @@appliance_credentials_map.to_yaml } #Store
        ::Morpheus::Cli::Remote.recalculate_variable_map()
        true
      end

      def load_saved_credentials(reload=false)
        if reload || !defined?(@@appliance_credentials_map) || @@appliance_credentials_map.nil?
          @@appliance_credentials_map = load_credentials_file || {}
        end
        # ok, we switched  symbols to strings, because symbols suck in yaml! need to support both
        # also we switched from just a token (symbol) to a whole object of strings
        wallet = @@appliance_credentials_map[@appliance_name.to_s] || @@appliance_credentials_map[@appliance_name.to_sym]
        if wallet.is_a?(String)
          wallet = {'access_token' => wallet}
        end
        return wallet
      end

      def load_credentials_file
        fn = credentials_file_path
        if File.exist? fn
          #Morpheus::Logging::DarkPrinter.puts "loading credentials file #{fn}" if Morpheus::Logging.debug?
          return YAML.load_file(fn)
        else
          return nil
        end
      end

      def credentials_file_path
        File.join(Morpheus::Cli.home_directory, "credentials")
      end

      # credentials wallet is {'access_token': '...', 'refresh_token': '...' 'expiration': '2019-01-01...'}
      def save_credentials(appliance_name, wallet)
        # reloading file is better for now, otherwise you can lose credentials with multiple shells.
        credential_map = load_credentials_file || {}
        
        if wallet
          credential_map[appliance_name.to_s] = wallet
        else
          # nil mean remove the damn thing
          credential_map.delete(appliance_name.to_s)
        end
        # always remove symbol, which was used pre 3.6.9
        credential_map.delete(appliance_name.to_sym)
        begin
          fn = credentials_file_path
          if !Dir.exist?(File.dirname(fn))
            FileUtils.mkdir_p(File.dirname(fn))
          end
          #Morpheus::Logging::DarkPrinter.puts "adding credentials for #{appliance_name} to #{fn}" if Morpheus::Logging.debug?
          File.open(fn, 'w') {|f| f.write credential_map.to_yaml } #Store
          FileUtils.chmod(0600, fn)
          @@appliance_credentials_map = credential_map
        rescue => e
          puts "failed to save #{fn}. #{e}"  if Morpheus::Logging.debug?
        ensure
          # recalcuate echo vars
          #puts "Recalculating variable maps for username change"
          Morpheus::Cli::Echo.recalculate_variable_map()
          # recalculate shell prompt after this change
          if Morpheus::Cli::Shell.has_instance?
            Morpheus::Cli::Shell.instance.reinitialize()
          end
        end
      end

      def rename_credentials(appliance_name, new_appliance_name)
        # reloading file is better for now, otherwise you can lose credentials with multiple shells.
        credential_map = load_credentials_file || {}

        if new_appliance_name.to_s.empty?
          puts "Cannot rename credentials without specifying a new name" 
          return nil
        elsif credential_map[new_appliance_name.to_s] || credential_map[new_appliance_name.to_sym]
          # yes you can, maybe require --force?
          puts "Cannot rename credentials to a name that already exists: #{new_appliance_name}" 
          return nil
        end
        
        # always remove symbol, which was used pre 3.6.9
        credential_map.delete(appliance_name.to_sym)
        begin
          fn = credentials_file_path
          if !Dir.exist?(File.dirname(fn))
            FileUtils.mkdir_p(File.dirname(fn))
          end
          #Morpheus::Logging::DarkPrinter.puts "renaming credentials from #{appliance_name} to #{new_appliance_name}" if Morpheus::Logging.debug?
          File.open(fn, 'w') {|f| f.write credential_map.to_yaml } #Store
          FileUtils.chmod(0600, fn)
          @@appliance_credentials_map = credential_map
        rescue => e
          puts "failed to save #{fn}. #{e}"  if Morpheus::Logging.debug?
        ensure
          # recalcuate echo vars
          #puts "Recalculating variable maps for username change"
          Morpheus::Cli::Echo.recalculate_variable_map()
          # recalculate shell prompt after this change
          if Morpheus::Cli::Shell.has_instance?
            Morpheus::Cli::Shell.instance.reinitialize()
          end
        end
      end
    end
  end
end
