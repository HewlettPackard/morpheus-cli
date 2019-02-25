require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::ContainersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  set_command_name :containers

  register_subcommands :get, :stop, :start, :restart, :suspend, :eject, :action, :actions
  register_subcommands :exec => :execution_request

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @containers_interface = @api_client.containers
    @execution_request_interface = @api_client.execution_request
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( nil, '--actions', "Display Available Actions" ) do
        options[:include_available_actions] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(arg, options)
    begin
      @containers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @containers_interface.dry.get(arg.to_i)
        return
      end
      #container = find_container_by_id(arg)
      #return 1 if container.nil?
      json_response = @containers_interface.get(arg.to_i)
      if options[:json]
        puts as_json(json_response, options, "container")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "container")
        return 0
      end

      if options[:csv]
        puts records_as_csv([json_response['container']], options)
        return 0
      end
      container = json_response['container']
      # stats = json_response['stats'] || {}
      stats = container['stats'] || {}
      
      # load_balancers = stats = json_response['loadBalancers'] || {}

      # todo: show as 'VM' instead of 'Container' maybe..err
      # may need to fetch instance by id too..
      # ${[null,'docker'].contains(instance?.layout?.provisionType?.code) ? 'CONTAINERS' : 'VMs'}

      print_h1 "Container Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        #"Name" => 'name',
        "Name" => lambda {|it| it['server'] ? it['server']['name'] : '(no server)' }, # there is a server.displayName too?
        "Type" => lambda {|it| it['containerType'] ? it['containerType']['name'] : '' },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Location" => lambda {|it| format_container_connection_string(it) },
        # "Description" => 'description',
        # "Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        # "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        # "Type" => lambda {|it| it['instanceType']['name'] },
        # "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        # "Environment" => 'instanceContext',
        # "Nodes" => lambda {|it| it['containers'] ? it['containers'].count : 0 },
        # "Connection" => lambda {|it| format_container_connection_string(it) },
        #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        "Status" => lambda {|it| format_container_status(it) }
      }
      print_description_list(description_cols, container)

      if (stats)
        print_h2 "Container Usage"
        print_stats_usage(stats)
      end

      if options[:include_available_actions]
        if (container["availableActions"])
          print_h2 "Available Actions"
          print as_pretty_table(container["availableActions"], [:id, :name])
          print reset, "\n"
        else
          print "#{yellow}No available actions#{reset}\n\n"
        end
      end

      print reset, "\n"

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(container['status'])
          print cyan
          print cyan, "Refreshing in #{options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1 # , e
    end
  end


  def stop(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _stop(arg, options)
    end
  end

  def _stop(container_id, options)
    container = find_container_by_id(container_id) # could skip this since only id is supported
    return 1 if container.nil?
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.stop(container['id'])
      return 0
    end
    json_response = @containers_interface.stop(container['id'])
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      print green, "Stopping container #{container['id']}", reset, "\n"
    end
    return 0
  end

  def start(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _start(arg, options)
    end
  end

  def _start(container_id, options)
    container = find_container_by_id(container_id) # could skip this since only id is supported
    return 1 if container.nil?
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.start(container['id'])
      return 0
    end
    json_response = @containers_interface.start(container['id'])
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      print green, "Starting container #{container['id']}", reset, "\n"
    end
    return 0
  end

  def restart(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _restart(arg, options)
    end
  end

  def _restart(container_id, options)
    container = find_container_by_id(container_id) # could skip this since only id is supported
    return 1 if container.nil?
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.restart(container['id'])
      return 0
    end
    json_response = @containers_interface.restart(container['id'])
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      print green, "Restarting container #{container['id']}", reset, "\n"
    end
    return 0
  end

  def suspend(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _suspend(arg, options)
    end
  end

  def _suspend(container_id, options)
    container = find_container_by_id(container_id) # could skip this since only id is supported
    return 1 if container.nil?
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.suspend(container['id'])
      return 0
    end
    json_response = @containers_interface.suspend(container['id'])
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      print green, "Suspending container #{container['id']}", reset, "\n"
    end
    return 0
  end

  def eject(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _eject(arg, options)
    end
  end

  def _eject(container_id, options)
    container = find_container_by_id(container_id) # could skip this since only id is supported
    return 1 if container.nil?
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.eject(container['id'])
      return 0
    end
    json_response = @containers_interface.eject(container['id'])
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      print green, "Ejecting container #{container['id']}", reset, "\n"
    end
    return 0
  end

  def actions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list]")
      opts.footer = "This outputs the list of the actions available to specified container(s)."
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    containers = []
    id_list.each do |container_id|
      container = find_container_by_id(container_id)
      if container.nil?
        # return 1
      else
        containers << container
      end
    end
    if containers.size != id_list.size
      #puts_error "containers not found"
      return 1
    end
    container_ids = containers.collect {|container| container["id"] }
    begin
      # container = find_container_by_name_or_id(args[0])
      @containers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @containers_interface.dry.available_actions(container_ids)
        return 0
      end
      json_response = @containers_interface.available_actions(container_ids)
      if options[:json]
        puts as_json(json_response, options)
      else
        title = "Container Actions: #{anded_list(id_list)}"
        print_h1 title
        available_actions = json_response["actions"]
        if (available_actions && available_actions.size > 0)
          print as_pretty_table(available_actions, [:name, :code])
          print reset, "\n"
        else
          if container_ids.size > 1
            print "#{yellow}The specified containers have no available actions in common.#{reset}\n\n"
          else
            print "#{yellow}No available actions#{reset}\n\n"
          end
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def action(args)
    options = {}
    action_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list] -a CODE")
      opts.on('-a', '--action CODE', "Container Action CODE to execute") do |val|
        action_id = val.to_s
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an action for a container or containers"
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "[id list] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    containers = []
    id_list.each do |container_id|
      container = find_container_by_id(container_id)
      if container.nil?
        # return 1
      else
        containers << container
      end
    end
    if containers.size != id_list.size
      #puts_error "containers not found"
      return 1
    end
    container_ids = containers.collect {|container| container["id"] }

    # figure out what action to run
    # assume that the action is available for all the containers..
    available_actions = containers.first['availableActions']
    if available_actions.empty?
      print_red_alert "Container #{container['id']} has no available actions"
      if container_ids.size > 1
        print_red_alert "The specified containers have no available actions in common"
      else
        print_red_alert "The specified container has no available actions"
      end
      return 1
    end
    container_action = nil
    if action_id.nil?
      available_actions_dropdown = available_actions.collect {|act| {'name' => act["name"], 'value' => act["code"]} } # already sorted
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'select', 'fieldLabel' => 'Container Action', 'selectOptions' => available_actions_dropdown, 'required' => true, 'description' => 'Choose the container action to execute'}], options[:options])
      action_id = v_prompt['code']
      container_action = available_actions.find {|act| act['code'].to_s == action_id.to_s }
    else
      container_action = available_actions.find {|act| act['code'].to_s == action_id.to_s || act['name'].to_s.downcase == action_id.to_s.downcase }
      action_id = container_action["code"] if container_action
    end
    if !container_action
      # for testing bogus actions..
      # container_action = {"id" => action_id, "name" => "Unknown"}
      raise_command_error "Container Action '#{action_id}' not found."
    end

    action_display_name = "#{container_action['name']} [#{container_action['code']}]"
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to perform action #{action_display_name} on #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end

    # return run_command_for_each_arg(containers) do |arg|
    #   _action(arg, action_id, options)
    # end
    @containers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @containers_interface.dry.action(container_ids, action_id)
      return 0
    end
    json_response = @containers_interface.action(container_ids, action_id)
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      # containers.each do |container|
      #   print green, "Action #{action_display_name} performed on container #{container['id']}", reset, "\n"
      # end
      print green, "Action #{action_display_name} performed on #{id_list.size == 1 ? 'container' : 'containers'} #{anded_list(id_list)}", reset, "\n"
    end
    return 0
  end

  def execution_request(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [options]")
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
      opts.footer = "Execute an arbitrary command or script on a container." + "\n" +
                    "[id] is required. This is the id a container." + "\n" +
                    "[script] is required. This is the script that is to be executed."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    
    begin
      container = find_container_by_id(args[0])
      return 1 if container.nil?
      params['containerId'] = container['id']
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # prompt for Script
        if script_content.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'script', 'type' => 'code-editor', 'fieldLabel' => 'Script', 'required' => true, 'description' => 'The script content'}], options[:options])
          script_content = v_prompt['script']
        end
        payload['script'] = script_content
      end
      @execution_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @execution_request_interface.dry.create(params, payload)
        return 0
      end
      # do it
      json_response = @execution_request_interface.create(params, payload)
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
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId'], "--refresh"])
      else
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

private

  def find_container_by_id(id)
    begin
      json_response = @containers_interface.get(id.to_i)
      return json_response['container']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Container not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def format_container_status(container, return_color=cyan)
    out = ""
    status_string = container['status'].to_s
    if status_string == 'running'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out << "#{white}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_container_connection_string(container)
    if !container['ports'].nil? && container['ports'].empty? == false
      connection_string = "#{container['ip']}:#{container['ports'][0]['external']}"
    else
      # eh? more logic needed here i think, see taglib morph:containerLocationMenu
      connection_string = "#{container['ip']}"
    end
  end

end
