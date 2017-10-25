# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  register_subcommands :list, :get, :add, :update, :remove, :add_instance, :remove_instance, :logs, :firewall_disable, :firewall_enable, :security_groups, :apply_security_groups
  alias_subcommand :details, :get
  set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List apps."
    end
    optparse.parse!(args)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} list expects 0 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(params)
        return
      end

      json_response = @apps_interface.get(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      apps = json_response['apps']
      title = "Morpheus Apps"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if apps.empty?
        print cyan,"No apps found.",reset,"\n"
      else
        print_apps_table(apps)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_app_option_types(false))
      # opts.on( '-t', '--template ID', "App Template ID. The app template to use. The default value is 'existing' which means no template, for creating a blank app and adding existing instances." ) do |val|
      #   options['template'] = val
      # end
      # opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
      #   options[:group] = val
      # end
      # opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID." ) do |val|
      #   options[:cloud] = val
      # end
      opts.on('--config JSON', String, "App Config JSON") do |val|
        options['config'] = JSON.parse(val.to_s)
      end
      opts.on('--config-yaml YAML', String, "App Config YAML") do |val|
        options['config'] = YAML.load(val.to_s)
      end
      opts.on('--config-file FILE', String, "App Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet])
      opts.footer = "Create a new app.\n" +
                    "[name] is required. This is the name of the new app. It may also be passed as --name or inside your config."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add expects 0-1 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      options[:options] ||= {}
      if args[0] && !options[:options]['name']
        options[:options]['name'] = args[0]
      end
      # options[:options]['template'] ||= options['template']
      if options[:group] # || @active_group_id
        options[:options]['group'] ||= options[:group] # || @active_group_id
      end

      payload = {}
      config_payload = {}
      if options['config']
        config_payload = options['config']
        payload = config_payload
      elsif options['configFile']
        config_file = File.expand_path(options['configFile'])
        if !File.exists?(config_file) || !File.file?(config_file)
          print_red_alert "File not found: #{config_file}"
          return false
        end
        if config_file =~ /\.ya?ml\Z/
          config_payload = YAML.load_file(config_file)
        else
          config_payload = JSON.parse(File.read(config_file))
        end
        payload = config_payload
      else
        # prompt for Name, Description, Group, Environment
        payload = {}
        params = Morpheus::Cli::OptionTypes.prompt(add_app_option_types, options[:options], @api_client, options[:params])
        params = params.deep_compact! # remove nulls and blank strings
        group = find_group_by_name_or_id_for_provisioning(params.delete('group'))
        return if group.nil?
        payload.merge!(params)
        payload['group'] = {id: group['id'], name: group['name']}
      end

      # allow creating a blank app by default
      # sux having go merge this into user passed config/configFile
      # but it's better than making them know to enter it.
      if !payload['id']
        payload['id'] = 'existing'
        payload['templateName'] = 'Existing Instances'
      else
        # maybe validate template id
        # app_template = find_app_template_by_id(payload['id'])
      end

      if options[:dry_run]
        print_dry_run @apps_interface.dry.create(payload)
        return
      end

      json_response = @apps_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
        print "\n"
      elsif !options[:quiet]
        app = json_response["app"]
        print_green_success "Added app #{app['name']}"
        # add existing instances to blank app now?
        if !options[:no_prompt] && !payload['tiers']
          if ::Morpheus::Cli::OptionTypes::confirm("Would you like to add an instance now?", options.merge({default: false}))
            add_instance([app['id']])
            while ::Morpheus::Cli::OptionTypes::confirm("Add another instance?", options.merge({default: false})) do
              add_instance([app['id']])
            end
          end
        end
        # print details
        get([app['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
      opts.footer = "Get details about an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(app['id'])
        return
      end
      json_response = @apps_interface.get(app['id'])
      app = json_response['app']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      print_h1 "App Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        # "Group" => lambda {|it| it['group'] ? it['group']['name'] : it['siteId'] },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Status" => lambda {|it| format_app_status(it) }
      }
      print_description_list(description_cols, app)

      stats = app['stats']
      if app['instanceCount'].to_i > 0
        print_h2 "App Usage"
        print_stats_usage(stats, {include: [:memory, :storage]})
      end

      app_tiers = app['appTiers']
      if app_tiers.empty?
        puts yellow, "This app is empty", reset
      else
        app_tiers.each do |app_tier|
          print_h2 "Tier: #{app_tier['tier']['name']}\n"
          print cyan
          instances = (app_tier['appInstances'] || []).collect {|it| it['instance']}
          if instances.empty?
            puts yellow, "This tier is empty", reset
          else
            instance_table = instances.collect do |instance|
              # JD: fix bug here, status is not returned because withStats: false !?
              status_string = instance['status'].to_s
              if status_string == 'running'
                status_string = "#{green}#{status_string.upcase}#{cyan}"
              elsif status_string == 'stopped' or status_string == 'failed'
                status_string = "#{red}#{status_string.upcase}#{cyan}"
              elsif status_string == 'unknown'
                status_string = "#{white}#{status_string.upcase}#{cyan}"
              else
                status_string = "#{yellow}#{status_string.upcase}#{cyan}"
              end
              connection_string = ''
              if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
                connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
              end
              {id: instance['id'], name: instance['name'], connection: connection_string, environment: instance['instanceContext'], nodes: instance['containers'].count, status: status_string, type: instance['instanceType']['name'], group: !instance['group'].nil? ? instance['group']['name'] : nil, cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil}
            end
            tp instance_table, :id, :name, :cloud, :type, :environment, :nodes, :connection, :status
          end
        end
      end
      print cyan

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_option_type_options(opts, options, update_app_option_types(false))
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "Update an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} update expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])

      payload = {
        'app' => {id: app["id"]}
      }

      params = options[:options] || {}

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      app_keys = ['name', 'description', 'environment']
      params = params.select {|k,v| app_keys.include?(k) }
      payload['app'].merge!(params)

      if options[:dry_run]
        print_dry_run @apps_interface.dry.update(app["id"], payload)
        return
      end

      json_response = @apps_interface.update(app["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated app #{app['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def add_instance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [instance] [tier]")
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "Add an existing instance to an app.\n" +
                    "[app] is required. This is the name or id of an app." + "\n" +
                    "[instance] is required. This is the name or id of an instance." + "\n" +
                    "[tier] is required. This is the name of the tier."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add-instance expects 1-3 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
      if args[2] && args[2] !~ /\A\-/
        options[:tier_name] = args[2]
      end
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      # Only supports adding an existing instance right now..

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']

      if options[:tier_name]
        payload[:tierName] = options[:tier_name]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tier', 'fieldLabel' => 'Tier', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
        payload[:tierName] = v_prompt['tier']
      end

      if options[:dry_run]
        print_dry_run @apps_interface.dry.add_instance(app['id'], payload)
        return
      end
      json_response = @apps_interface.add_instance(app['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance #{instance['name']} to app #{app['name']}"
        #get(app['id'])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {keepBackups: 'off', force: 'off'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [-fB]")
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      opts.on('--remove-instances [on|off]', ['on','off'], "Remove instances. Default is on.") do |val|
        query_params[:removeInstances] = val
      end
      opts.on('--remove-volumes [on|off]', ['on','off'], "Remove Volumes. Default is on. Applies to certain types only.") do |val|
        query_params[:removeVolumes] = val
      end
      opts.on('--releaseEIPs', ['on','off'], "Release EIPs. Default is false. Applies to Amazon only.") do |val|
        query_params[:releaseEIPs] = val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
      opts.footer = "Delete an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the app '#{app['name']}'?", options)
        return 9
      end
      if options[:dry_run]
        print_dry_run @apps_interface.dry.destroy(app['id'], query_params)
        return
      end
      json_response = @apps_interface.destroy(app['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed app #{app['name']}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_instance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [instance]")
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "Remove an instance from an app.\n" +
                    "[app] is required. This is the name or id of an app." + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-instance expects 1-2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']

      if options[:dry_run]
        print_dry_run @apps_interface.dry.remove_instance(app['id'], payload)
        return
      end

      json_response = @apps_interface.remove_instance(app['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed instance #{instance['name']} from app #{app['name']}"
        list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List logs for an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count !=1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} logs expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      containers = []
      app['appTiers'].each do |app_tier|
        app_tier['appInstances'].each do |app_instance|
          containers += app_instance['instance']['containers']
        end
      end
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(containers, params)
        return
      end
      logs = @logs_interface.container_logs(containers, params)
      if options[:json]
        puts as_json(logs, options)
        return 0
      else
        title = "App Logs: #{app['name']}"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        # todo: startMs, endMs, sorts insteaad of sort..etc
        print_h1 title, subtitles
        logs['data'].reverse.each do |log_entry|
          log_level = ''
          case log_entry['level']
          when 'INFO'
            log_level = "#{blue}#{bold}INFO#{reset}"
          when 'DEBUG'
            log_level = "#{white}#{bold}DEBUG#{reset}"
          when 'WARN'
            log_level = "#{yellow}#{bold}WARN#{reset}"
          when 'ERROR'
            log_level = "#{red}#{bold}ERROR#{reset}"
          when 'FATAL'
            log_level = "#{red}#{bold}FATAL#{reset}"
          end
          puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}"
        end
        print reset,"\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

=begin
  def stop(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} stop expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.stop(app['id'])
        return
      end
      @apps_interface.stop(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} start expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.start(app['id'])
        return
      end
      @apps_interface.start(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} restart expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.restart(app['id'])
        return
      end
      @apps_interface.restart(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
=end

  def firewall_disable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} firewall-disable expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_disable(app['id'])
        return
      end
      @apps_interface.firewall_disable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} firewall-enable expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_enable(app['id'])
        return
      end
      @apps_interface.firewall_enable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} security-groups expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.security_groups(app['id'])
        return
      end
      json_response = @apps_interface.security_groups(app['id'])
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for App: #{app['name']}"
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      if securityGroups.empty?
        print cyan,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [--clear] [-s]")
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        options[:securityGroupIds] = []
        clear_or_secgroups_specified = true
      end
      opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        options[:securityGroupIds] = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} apply-security-groups expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if !clear_or_secgroups_specified
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} apply-security-groups requires either --clear or --secgroups\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.apply_security_groups(app['id'], options)
        return
      end
      @apps_interface.apply_security_groups(app['id'], options)
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def add_app_option_types(connected=true)
    [
      {'fieldName' => 'template', 'fieldLabel' => 'Template', 'type' => 'select', 'selectOptions' => (connected ? get_available_app_templates() : []), 'required' => true, 'defaultValue' => 'existing', 'description' => "The app template to use. The default value is 'existing' which means no template, for creating a blank app and adding existing instances."},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true},
      {'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'text', 'required' => false},
    ]
  end

  def update_app_option_types(connected=true)
    list = add_app_option_types(connected)
    list = list.reject {|it| ["template", "group"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

  def find_app_by_id(id)
    app_results = @apps_interface.get(id.to_i)
    if app_results['app'].empty?
      print_red_alert "App not found by id #{id}"
      exit 1
    end
    return app_results['app']
  end

  def find_app_by_name(name)
    app_results = @apps_interface.get({name: name})
    if app_results['apps'].empty?
      print_red_alert "App not found by name #{name}"
      exit 1
    end
    return app_results['apps'][0]
  end

  def find_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_app_by_id(val)
    else
      return find_app_by_name(val)
    end
  end

  def print_apps_table(apps, opts={})
    
    table_color = opts[:color] || cyan
    rows = apps.collect do |app|
      instances_str = (app['instanceCount'].to_i == 1) ? "1 Instance" : "#{app['instanceCount']} Instances"
      containers_str = (app['containerCount'].to_i == 1) ? "1 Container" : "#{app['containerCount']} Containers"
      stats = app['stats']
      # app_stats = app['appStats']
      cpu_usage_str = !stats ? "" : generate_usage_bar((stats['cpuUsage'] || stats['cpuUsagePeak']).to_f, 100, {max_bars: 10})
      memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
      storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
      {
        id: app['id'],
        name: app['name'],
        instances: instances_str,
        containers: containers_str,
        account: app['account'] ? app['account']['name'] : nil,
        status: format_app_status(app, table_color),
        cpu: cpu_usage_str + cyan,
        memory: memory_usage_str + table_color,
        storage: storage_usage_str + table_color
        #dateCreated: format_local_dt(app['dateCreated'])
      }
    end

    columns = [
      :id,
      :name,
      :instances,
      :containers,
      #:account,
      :status,
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    term_width = current_terminal_width()
    if term_width > 120
      columns += [
        {:cpu => {:display_name => "MAX CPU"} },
        :memory,
        :storage
      ]
    end
    # custom pretty table columns ...
    # if options[:include_fields]
    #   columns = options[:include_fields]
    # end
    # print cyan
    print as_pretty_table(rows, columns, opts) #{color: table_color}
    print reset
  end

  def format_app_status(app, return_color=cyan)
    out = ""
    status_string = app['status']
    if app['instanceCount'].to_i == 0
      # show this instead of WARNING
      out <<  "#{white}EMPTY#{return_color}"
    elsif status_string == 'running'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out <<  "#{white}#{status_string.upcase}#{return_color}"
    else
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def get_available_app_templates(refresh=false)
    if !@available_app_templates || refresh
      results = @options_interface.options_for_source('appTemplates',{})
      @available_app_templates = results['data'].collect {|it|
        {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
      }
      default_option = {"id" => "existing", "name" => "Existing Instances", "value" => "existing"}
      @available_app_templates.unshift(default_option)
    end
    #puts "get_available_app_templates() rtn: #{@available_app_templates.inspect}"
    return @available_app_templates
  end

  def get_available_environments(refresh=false)
    if !@available_environments || refresh
      # results = @options_interface.options_for_source('environments',{})
      # @available_environments = results['data'].collect {|it|
      #   {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
      # }
      # todo: api call
      @available_environments = [
        {'name' => 'Dev', 'value' => 'Dev'},
        {'name' => 'Test', 'value' => 'Test'},
        {'name' => 'Staging', 'value' => 'Staging'},
        {'name' => 'Production', 'value' => 'Production'}
      ]
    end
    #puts "get_available_environments() rtn: #{@available_environments.inspect}"
    return @available_environments
  end

end
