require 'morpheus/cli/cli_command'

class Morpheus::Cli::UserSettingsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'user-settings'

  register_subcommands :get, :update, :'update-avatar', :'view-avatar', :'regenerate-access-token', :'clear-access-token', :'list-clients'
  
  set_default_subcommand :get
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @user_settings_interface = @api_client.user_settings
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get your user settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      params.merge!(parse_list_options(options))
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.get(params)
        return
      end
      json_response = @user_settings_interface.get(params)
      if options[:json]
        puts as_json(json_response, options, "user")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "user")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['user']], options)
        return 0
      end

      user_settings = json_response['user'] || json_response['userSettings']
      access_tokens = user_settings['accessTokens'] || json_response['accessTokens'] || json_response['apiAccessTokens'] || []

      print_h1 "User Settings"
      print cyan
      description_cols = {
        #"ID" => lambda {|it| it['id'] },
        "ID" => lambda {|it| it['id'] },
        "Username" => lambda {|it| it['username'] },
        "First Name" => lambda {|it| it['firstName'] },
        "Last Name" => lambda {|it| it['lastName'] },
        "Email" => lambda {|it| it['email'] },
        "Avatar" => lambda {|it| it['avatar'] ? it['avatar'].split('/').last : '' },
        "Notifications" => lambda {|it| format_boolean(it['receiveNotifications']) },
        "Linux Username" => lambda {|it| it['linuxUsername'] },
        "Linux Password" => lambda {|it| it['linuxPassword'] },
        "Linux Key Pair" => lambda {|it| it['linuxKeyPairId'] },
        "Windows Username" => lambda {|it| it['windowsUsername'] },
        "Windows Password" => lambda {|it| it['windowsPassword'] },
      }
      print_description_list(description_cols, user_settings)      

      if access_tokens && !access_tokens.empty?
        print_h2 "API Access Tokens"
        cols = {
          #"ID" => lambda {|it| it['id'] },
          "Client ID" => lambda {|it| it['clientId'] },
          "Username" => lambda {|it| it['username'] },
          "Expiration" => lambda {|it| format_local_dt(it['expiration']) }
        }
        print cyan
        puts as_pretty_table(access_tokens, cols)
      end
      
      print reset #, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def update(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update your user settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
  
      end

      if options[:options]
        payload['user'] ||= {}
        payload['user'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
      end
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.update(params, payload)
        return
      end
      json_response = @user_settings_interface.update(params, payload)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Updated user settings"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_avatar(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[file]")
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Update your avatar profile image.\n" +
                    "[file] is required. This is the local path of a file to upload [png|jpg|svg]."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    filename = File.expand_path(args[0].to_s)
    image_file = nil
    if filename && File.file?(filename)
      # maybe validate it's an image file? [.png|jpg|svg]
      image_file = File.new(filename, 'rb')
    else
      # print_red_alert "File not found: #{filename}"
      puts_error "#{Morpheus::Terminal.angry_prompt}File not found: #{filename}"
      return 1
    end
    
    begin
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.update_avatar(image_file, params)
        return
      end
      json_response = @user_settings_interface.update_avatar(image_file, params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Updated avatar"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_avatar(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Remove your avatar profile image."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.remove_avatar(params)
        return
      end
      json_response = @user_settings_interface.remove_avatar(params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Removed avatar"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def view_avatar(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:remote])
      opts.footer = "View your avatar profile image.\n" +
                    "This opens the avatar image url with a web browser."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      
      json_response = @user_settings_interface.get(params)
      user_settings = json_response['user'] || json_response['userSettings']
      
      if user_settings['avatar']
        link = user_settings['avatar']
        if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
          system "start #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /darwin/
          system "open #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
          system "xdg-open #{link}"
        end
        return 0, nil
      else
        print_error red,"No avatar image found.",reset,"\n"
        return 1
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def regenerate_access_token(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client-id]")
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Regenerate API access token for a specific client.\n" +
                    "[client-id] is required. This is the id of an api client."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    params['clientId'] = args[0]
    begin
      payload = {}
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.regenerate_access_token(params, payload)
        return
      end
      json_response = @user_settings_interface.regenerate_access_token(params, payload)
      new_access_token = json_response['token']
      # update credentials if regenerating cli token
      if params['clientId'] == 'morph-cli'
        if new_access_token
          login_opts = {:remote_token => new_access_token}
          login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(login_opts)
        end
      end
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Regenerated #{params['clientId']} access token: #{new_access_token}"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def clear_access_token(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client-id]")
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Clear API access token for a specific client.\n" +
                    "[client-id] is required. This is the id of an api client."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    params['clientId'] = args[0]
    begin
      payload = {}
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.clear_access_token(params, payload)
        return
      end
      json_response = @user_settings_interface.clear_access_token(params, payload)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      new_access_token = json_response['token']
      # update credentials if regenerating cli token
      # if params['clientId'] == 'morph-cli'
      #   logout_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout
      # end
      print_green_success "Cleared #{params['clientId']} access token"
      if params['clientId'] == 'morph-cli'
        print yellow,"Your current access token is no longer valid, you will need to login again.",reset,"\n"
      end
      # get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      # get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_clients(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      # opts.on("--user-id ID", String, "User ID") do |val|
      #   params['userId'] = val.to_s
      # end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List available api clients."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      params.merge!(parse_list_options(options))
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.available_clients(params)
        return
      end
      json_response = @user_settings_interface.available_clients(params)
      if options[:json]
        puts as_json(json_response, options, "clients")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "clients")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['clients'], options)
        return 0
      end

      clients = json_response['clients'] || json_response['apiClients']
      print_h1 "Morpheus API Clients"
      columns = {
        "Client ID" => lambda {|it| it['clientId'] }
      }
      print cyan
      puts as_pretty_table(clients, columns)
      print reset #, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

end
