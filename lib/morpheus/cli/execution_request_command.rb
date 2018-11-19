require 'morpheus/cli/cli_command'
# require 'morpheus/cli/mixins/provisioning_helper'
# require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::ExecutionRequestCommand
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::InfrastructureHelper
  # include Morpheus::Cli::ProvisioningHelper

  set_command_name :'execution-request'

  register_subcommands :get, :execute, :'execute-against-lease' => :execute_against_lease
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    # @instances_interface = @api_client.instances
    # @containers_interface = @api_client.containers
    # @servers_interface = @api_client.servers
    @execution_requests_interface = @api_client.execution_request
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[uid]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.on('--refresh', String, "Refresh until execution is finished.") do |val|
        options[:refresh_until_finished] = true
      end
      opts.on('--refresh-interval seconds', String, "Refresh interval. Default is 5 seconds.") do |val|
        options[:refresh_interval] = val.to_f
      end
      opts.footer = "Get details about an execution request." + "\n" +
                    "[uid] is required. This is the unique id of an execution request."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    execution_request_id = args[0]
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @execution_requests_interface.dry.get(execution_request_id, params)
        return
      end
      json_response = @execution_requests_interface.get(execution_request_id, params)
      if options[:json]
        puts as_json(json_response, options, "executionRequest")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "executionRequest")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['executionRequest']], options)
        return 0
      end

      execution_request = json_response['executionRequest']

      # refresh until a status is reached
      if options[:refresh_until_finished]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        if execution_request['exitCode'].nil?
          print cyan
          print "Execution request has not yet finished. Refreshing every #{options[:refresh_interval]} seconds"
          while execution_request['exitCode'].nil? do
            sleep(options[:refresh_interval])
            print cyan,".",reset
            json_response = @execution_requests_interface.get(execution_request_id, params)
            execution_request = json_response['executionRequest']
          end
          #sleep_with_dots(options[:refresh_interval])
          print "\n", reset
          # get(raw_args)
        end
      end

      print_h1 "Execution Request Details"
      print cyan
      description_cols = {
        #"ID" => lambda {|it| it['id'] },
        "Unique ID" => lambda {|it| it['uniqueId'] },
        "Server ID" => lambda {|it| it['serverId'] },
        "Instance ID" => lambda {|it| it['instanceId'] },
        "Container ID" => lambda {|it| it['containerId'] },
        "Expires At" => lambda {|it| format_local_dt it['expiresAt'] },
        "Exit Code" => lambda {|it| it['exitCode'] },
        "Status" => lambda {|it| format_execution_request_status(it) },
        #"Created By" => lambda {|it| it['createdById'] },
        #"Subdomain" => lambda {|it| it['subdomain'] },
      }
      print_description_list(description_cols, execution_request)      

      if execution_request['stdErr']
        print_h2 "Error"
        puts execution_request['stdErr'].to_s.strip
      end

      print_h2 "Output"
      puts execution_request['stdOut'].to_s.strip
  
      print reset

      return 0

    
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def execute(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--server ID', String, "Server ID") do |val|
        params['serverId'] = val
      end
      opts.on('--instance ID', String, "Instance ID") do |val|
        params['instanceId'] = val
      end
      opts.on('--container ID', String, "Container ID") do |val|
        params['containerId'] = val
      end
      opts.on('--script SCRIPT', "Script to be executed" ) do |val|
        script_content = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          script_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an arbitrary script." + "\n" +
                    "[server] or [instance] or [container] is required. This is the id of a server, instance or container." + "\n" +
                    "[script] is required. This is the script that is to be executed."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if params['serverId'].nil? && params['instanceId'].nil? && params['containerId'].nil?
      puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --server or --instance or --container\n#{optparse}"
      return 1
    end
    begin
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # could prompt for Server or Container or Instance
        # prompt for Script
        if script_content.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'script', 'type' => 'code-editor', 'fieldLabel' => 'Script', 'required' => true, 'description' => 'The script content'}], options[:options])
          script_content = v_prompt['script']
        end
        payload['script'] = script_content
      end
      # dry run?
      if options[:dry_run]
        print_dry_run @execution_requests_interface.dry.create(params, payload)
        return 0
      end
      # do it
      json_response = @execution_requests_interface.create(params, payload)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      execution_request = json_response['executionRequest']
      print_green_success "Executing request #{execution_request['uniqueId']}"
      if do_refresh
        get([execution_request['uniqueId'], "--refresh"])
      else
        get([execution_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execute_against_lease(args)
    options = {}
    params = {}
    do_refresh = true
    script_content = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[uid] [options]")
      opts.on('--server ID', String, "Server ID") do |val|
        params['serverId'] = val
      end
      opts.on('--instance ID', String, "Instance ID") do |val|
        params['instanceId'] = val
      end
      opts.on('--container ID', String, "Container ID") do |val|
        params['containerId'] = val
      end
      opts.on('--script SCRIPT', "Script to be executed" ) do |val|
        script_content = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          script_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute request against lease." + "\n" +
                    "[id] is required. This is the id or an execution request." + "\n" +
                    "[script] is required. This is the script that is to be executed."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    execution_request_id = args[0]
    begin
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # could prompt for Server or Container or Instance
        # prompt for Script
        if script_content.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'script', 'type' => 'code-editor', 'fieldLabel' => 'Script', 'required' => true, 'description' => 'The script content'}], options[:options])
          script_content = v_prompt['script']
        end
        payload['script'] = script_content
      end
      # dry run?
      if options[:dry_run]
        print_dry_run @execution_requests_interface.dry.execute_against_lease(execution_request_id, params, payload)
        return 0
      end
      # do it
      json_response = @execution_requests_interface.execute_against_lease(execution_request_id, params, payload)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      execution_request = json_response['executionRequest']
      print_green_success "Executing request #{execution_request['uniqueId']} against lease"
      if do_refresh
        get([execution_request['uniqueId'], "--refresh"])
      else
        get([execution_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def format_execution_request_status(execution_request, return_color=cyan)
    out = ""
    status_str = execution_request['status']
    if status_str == 'complete'
      out << "#{green}#{status_str.upcase}#{return_color}"
    elsif status_str == 'failed' || status_str == 'expired'
      out << "#{red}#{status_str.upcase}#{return_color}"
    else
      out << "#{cyan}#{status_str.upcase}#{return_color}"
    end
    out
  end

end
