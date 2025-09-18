require 'morpheus/cli/cli_command'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper # needed? replace with OptionSourceHelper
  include Morpheus::Cli::OptionSourceHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::DeploymentsHelper
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::LogsHelper
  include Morpheus::Cli::ExecutionRequestHelper

  set_command_name :instances
  set_command_description "View and manage instances."
  register_subcommands :list, :count, :get, :view, :add, :update, :remove, 
                       :cancel_removal, :cancel_expiration, :cancel_shutdown, :extend_expiration, :extend_shutdown, :remove_from_control,
                       :history, {:'history-details' => :history_details}, {:'history-event' => :history_event_details}, 
                       :logs, :stats, :stop, :start, :restart, :actions, :action, :suspend, :eject, :stop_service, :start_service, :restart_service, 
                       :backup, :backups, :resize, :clone, :envs, :setenv, :delenv, 
                       :lock, :unlock, :clone_image,
                       :security_groups, :apply_security_groups, :run_workflow,
                       :import_snapshot, :snapshot, :snapshots, :revert_to_snapshot, :remove_all_snapshots, :remove_all_container_snapshots, :create_linked_clone,
                       :console, :status_check, {:containers => :list_containers}, 
                       :scaling, :update_scaling, {:'scaling-update' => :scaling_update},
                       {:'schedules' => :list_schedules}, :get_schedule, :add_schedule, :update_schedule, :remove_schedule, # these are scaling schedules..
                       :wiki, :update_wiki,
                       :update_network_label,
                       {:exec => :execution_request},
                       :deploys,
                       :refresh, :prepare_apply, :apply, :state
  #register_subcommands :firewall_disable, :firewall_enable
  # register_subcommands {:'lb-update' => :load_balancer_update}
  alias_subcommand :details, :get
  set_default_subcommand :list

  # hide these for now
  set_subcommands_hidden :prepare_apply
  set_subcommands_hidden :'scaling-update' # renamed to upate-scaling

  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
    @instances_interface = @api_client.instances
    @task_sets_interface = @api_client.task_sets
    @logs_interface = @api_client.logs
    @tasks_interface = @api_client.tasks
    @instance_types_interface = @api_client.instance_types
    @library_layouts_interface = @api_client.library_layouts
    @clouds_interface = @api_client.clouds
    @clouds_datastores_interface = @api_client.cloud_datastores
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @servers_interface = @api_client.servers
    @server_types_interface = @api_client.server_types
    @provision_types_interface = @api_client.provision_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    @execution_request_interface = @api_client.execution_request
    @deploy_interface = @api_client.deploy
    @deployments_interface = @api_client.deployments
    @snapshots_interface = @api_client.snapshots
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-H', '--host HOST', "Host Name or ID" ) do |val|
        options[:host] = val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val
      end
      opts.on('--agent', "Show only Instances with the agent installed" ) do
        params[:agentInstalled] = true
      end
      opts.on('--noagent', "Show only Instances with No agent" ) do
        params[:agentInstalled] = false
      end
      opts.add_hidden_option('--created-by')
      opts.on('--status STATUS', "Filter by status i.e. provisioning,running,starting,stopping") do |val|
        params['status'] = (params['status'] || []) + val.to_s.split(',').collect {|s| s.strip }.select {|s| s != "" }
      end
      opts.on( '--type CODE', String, "Filter by Instance Type code" ) do |val|
        # commas used in names a lot so use --plan one --plan two
        params['instanceType'] ||= []
        params['instanceType'] << val
      end
      opts.on( '--environment CODE', String, "Filter by Environment code(s)" ) do |val|
        # commas used in names a lot so use --plan one --plan two
        params['environment'] ||= []
        params['environment'] << val
      end
      opts.on('--pending-removal', "Include instances pending removal.") do
        options[:showDeleted] = true
      end
      opts.on('--pending-removal-only', "Only instances pending removal.") do
        options[:deleted] = true
      end
      opts.on( '--plan NAME', String, "Filter by Plan name(s)" ) do |val|
        # commas used in names a lot so use --plan one --plan two
        params['plan'] ||= []
        params['plan'] << val
      end
      opts.on( '--plan-id ID', String, "Filter by Plan id(s)" ) do |val|
        params['planId'] = parse_id_list(val)
      end
      opts.on( '--plan-code CODE', String, "Filter by Plan code(s)" ) do |val|
        params['planCode'] = parse_id_list(val)
      end
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      opts.on('--tags Name=Value',String, "Filter by tags (metadata name value pairs).") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('--stats', "Display values for memory and storage usage used / max values." ) do
        options[:stats] = true
      end
      opts.on('-a', '--details', "Display all details: plan, stats, etc" ) do
        options[:details] = true
        params['details'] = true # get more data from server this way
      end
      build_standard_list_options(opts, options)
      opts.footer = "List instances."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)

    params.merge!(parse_list_options(options))
    group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
    if group
      params['siteId'] = group['id']
    end

    # argh, this doesn't work because group_id is required for options/clouds
    # cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
    cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
    if cloud
      params['zoneId'] = cloud['id']
    end

    host = options[:host] ? find_host_by_name_or_id(options[:host]) : options[:host]
    if host
      params['serverId'] = host['id']
    end

    account = nil
    #todo: user = find_available_user_option(owner_id)

    if options[:owner]
      created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
      return if created_by_ids.nil?
      params['createdBy'] = created_by_ids
      params['ownerId'] = created_by_ids # 4.2.1+
    end

    params['showDeleted'] = true if options[:showDeleted]
    params['deleted'] = true if options[:deleted]
    if options[:tags]
      options[:tags].each do |k,v|
        params['tags.' + k] = v
      end
    end

    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.list(params)
      return 0
    end
    json_response = @instances_interface.list(params)
    all_stats = json_response['stats'] || {}
    # merge stats into each record just to be nice...
    if options[:include_fields] || options[:all_fields]
      if json_response['instances']
        if all_stats
          json_response['instances'].each do |it|
            it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
          end
        end
      end
    end
    render_response(json_response, options, "instances") do
      instances = json_response['instances']

      title = "Morpheus Instances"
      subtitles = []
      if group
        subtitles << "Group: #{group['name']}".strip
      end
      if cloud
        subtitles << "Cloud: #{cloud['name']}".strip
      end
      if host
        subtitles << "Host: #{host['name']}".strip
      end
      if options[:owner]
        subtitles << "Created By: #{options[:owner]}"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if instances.empty?
        print cyan,"No instances found.",reset,"\n"
      else
        # print_instances_table(instances)
        # server returns stats in a separate key stats => {"id" => {} }
        # the id is a string right now..for some reason..
        all_stats = json_response['stats'] || {} 
        if all_stats
          instances.each do |it|
            if !it['stats']
              found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
              it['stats'] = found_stats # || {}
            end
          end
        end

        rows = instances.collect {|instance| 
          stats = instance['stats']
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          if options[:details] || options[:stats]
            if stats['maxMemory'] && stats['maxMemory'].to_i != 0
              memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(8, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
            end
            if stats['maxStorage'] && stats['maxStorage'].to_i != 0
              storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(8, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
            end
          end
          row = {
            id: instance['id'],
            name: instance['displayName'] ? instance['displayName'] : instance['name'],
            labels: format_list(instance['labels'], '', 3),
            connection: format_instance_connection_string(instance),
            environment: instance['instanceContext'],
            user: (instance['owner'] ? (instance['owner']['username'] || instance['owner']['id']) : (instance['createdBy'].is_a?(Hash) ? instance['createdBy']['username'] : instance['createdBy'])),
            tenant: (instance['owner'] ? (instance['owner']['username'] || instance['owner']['id']) : (instance['createdBy'].is_a?(Hash) ? instance['createdBy']['username'] : instance['createdBy'])),
            nodes: instance['containers'].count,
            status: format_instance_status(instance, cyan),
            type: instance['instanceType']['name'],
            group: instance['group'] ? instance['group']['name'] : nil,
            cloud: instance['cloud'] ? instance['cloud']['name'] : nil,
            plan: instance['plan'] ? instance['plan']['name'] : '',
            version: instance['instanceVersion'] ? instance['instanceVersion'] : '',
            created: format_local_dt(instance['dateCreated']),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan, 
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, {:name => {:max_width => 50}}, :labels, :group, :cloud, 
            :type, :version, :environment, :plan,
            {:created => {:display_name => "CREATED"}}, 
            # {:tenant => {:display_name => "TENANT"}}, 
            {:user => {:display_name => "OWNER", :max_width => 20}}, 
            :nodes, {:connection => {:max_width => 30}}, :status, :cpu, :memory, :storage]
        # custom pretty table columns ... this is handled in as_pretty_table now(), 
        # todo: remove all these.. and try to always pass rows as the json data itself..
        if options[:details] != true
          columns.delete(:labels)
          columns.delete(:plan)
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-H', '--host HOST', "Host Name or ID" ) do |val|
        options[:host] = val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val
      end
      opts.add_hidden_option('--created-by')
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of instances."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
      if group
        params['siteId'] = group['id']
      end

      # argh, this doesn't work because group_id is required for options/clouds
      # cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
      cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
      if cloud
        params['zoneId'] = cloud['id']
      end

      host = options[:host] ? find_host_by_name_or_id(options[:host]) : options[:host]
      if host
        params['serverId'] = host['id']
      end

      account = nil
      if options[:owner]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
        # params['ownerId'] = created_by_ids # 4.2.1+
      end
      
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return
      end
      json_response = @instances_interface.list(params)
      # print number only
      if json_response['meta'] && json_response['meta']['total']
        print cyan, json_response['meta']['total'], reset, "\n"
      else
        print yellow, "unknown", reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    options[:create_user] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      # opts.banner = subcommand_usage("[type] [name]")
      opts.banner = subcommand_usage("[name] -c CLOUD -t TYPE")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
        options[:instance_type_code] = val
      end
      opts.on( '--name NAME', "Instance Name" ) do |val|
        options[:instance_name] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on("--environment ENV", String, "Environment code") do |val|
        options[:environment] = val.to_s
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('--labels LIST', String, "Labels (keywords) in the format 'foo, bar'") do |val|
        options[:labels] = parse_labels(val)
      end
      opts.on("--copies NUMBER", Integer, "Number of copies to provision") do |val|
        options[:copies] = val.to_i
      end
      opts.on("--layout-size NUMBER", Integer, "Apply a multiply factor of containers/vms within the instance") do |val|
        options[:layout_size] = val.to_i
      end
      opts.on( '-l', '--layout LAYOUT', "Layout ID" ) do |val|
        options[:layout] = val
      end
      opts.on( '-p', '--plan PLAN', "Service plan ID") do |val|
        options[:service_plan] = val
      end
      opts.on( '--resource-pool ID', String, "Resource pool ID" ) do |val|
        options[:resource_pool] = val
      end
      opts.on("--workflow ID", String, "Automation: Workflow ID") do |val|
        options[:workflow_id] = val
      end
      opts.on("--ports ARRAY", String, "Exposed Ports, JSON formatted list of objects containing name and port") do |val|
        # expects format like --ports '[{"name":"web","port":8080}]'
        ports_array = JSON.parse(val)
        options[:ports] = ports_array
        options[:options]['ports'] = ports_array
      end
      # opts.on('-L', "--lb", "Enable Load Balancer") do
      #   options[:enable_load_balancer] = true
      # end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is on") do |val|
        options[:create_user] = !['false','off','0'].include?(val.to_s)
      end
      opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
        options[:user_group_id] = val
      end
      opts.on("--shutdown-days DAYS", Integer, "Automation: Shutdown Days") do |val|
        options[:shutdown_days] = val.to_i
      end
      opts.on("--expire-days DAYS", Integer, "Automation: Expiration Days") do |val|
        options[:expire_days] = val.to_i
      end
      opts.on("--create-backup [on|off]", String, "Automation: Create Backups.") do |val|
        options[:create_backup] = ['on','true','1',''].include?(val.to_s.downcase) ? 'on' : 'off'
      end
      opts.on("--security-groups LIST", String, "Security Groups, comma separated list of security group IDs") do |val|
        options[:security_groups] = val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_standard_add_options(opts, options) #, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new instance." + "\n" +
                    "[name] is required. This is the new instance name." + "\n" +
                    "The available options vary by --type."
    end

    optparse.parse!(args)
    connect(options)


    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add has just 1 (optional) argument: [name].  Got #{args.count} arguments: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if args[0]
      options[:instance_name] = args[0]
    end

    if options[:payload]
      payload = options[:payload]
      # support -O OPTION switch on top of --payload
      payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      # obviously should support every option that prompt supports on top of -- payload as well
      # group, cloud and type for now
      # todo: also support :layout, service_plan, :resource_pool, etc.
      group = nil
      if options[:group]
        group = find_group_by_name_or_id_for_provisioning(options[:group])
        if group.nil?
          return 1, "group not found by #{options[:group]}"
        end
        payload.deep_merge!({"instance" => {"site" => {"id" => group["id"]} } })
      end
      if options[:cloud]
        group_id = group ? group["id"] : ((payload["instance"] && payload["instance"]["site"].is_a?(Hash)) ? payload["instance"]["site"]["id"] : nil)
        cloud = find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud])
        if cloud.nil?
          return 1, "cloud not found by #{options[:cloud]}"
        end
        payload["zoneId"] = cloud["id"]
        payload.deep_merge!({"instance" => {"cloud" => cloud["name"] } })
      end
        # if options[:cloud]
        #   group_id = group ? group["id"] : ((payload["instance"] && payload["instance"]["site"].is_a?(Hash)) ? payload["instance"]["site"]["id"] : nil)
        #   cloud = find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud])
        #   if cloud.nil?
        #     return 1, "cloud not found by #{options[:cloud]}"
        #   end
        #   payload["zoneId"] = cloud["id"]
        #   payload.deep_merge!({"instance" => {"cloud" => cloud["name"] } })
        # end
      if options[:instance_type_code]
        # should just use find_instance_type_by_name_or_id
        # note that the api actually will match name name or code
        instance_type = (options[:instance_type_code].to_s =~ /\A\d{1,}\Z/) ? find_instance_type_by_id(options[:instance_type_code]) : find_instance_type_by_code(options[:instance_type_code])
        if instance_type.nil?
          return 1, "instance type not found by #{options[:cloud]}"
        end
        payload.deep_merge!({"instance" => {"type" => instance_type["code"] } })
        payload.deep_merge!({"instance" => {"instanceType" => {"code" => instance_type["code"]} } })
      end
    else
      # use active group by default
      options[:group] ||= @active_group_id
      options[:select_datastore] = true
      options[:name_required] = true
      # prompt for all the instance configuration options
      # this provisioning helper method handles all (most) of the parsing and prompting
      # and it relies on the method to exit non-zero on error, like a bad CLOUD or TYPE value
      payload = prompt_new_instance(options)
      # clean payload of empty objects
      # note: this is temporary and should be fixed upstream in OptionTypes.prompt()
      if payload['instance'].is_a?(Hash)
        payload['instance'].keys.each do |k|
          v = payload['instance'][k]
          payload['instance'].delete(k) if v.is_a?(Hash) && v.empty?
        end
      end
      if payload['config'].is_a?(Hash)
        payload['config'].keys.each do |k|
          v = payload['config'][k]
          payload['config'].delete(k) if v.is_a?(Hash) && v.empty?
        end
      end
    end
    
    payload['instance'] ||= {}
    if options[:instance_name]
      payload['instance']['name'] = options[:instance_name]
    end
    if options[:description] && !payload['instance']['description']
      payload['instance']['description'] = options[:description]
    end
    if options[:environment] && !payload['instance']['instanceContext']
      payload['instance']['instanceContext'] = options[:environment]
    end
    payload[:copies] = options[:copies] if options[:copies] && options[:copies] > 0
    payload[:layoutSize] = options[:layout_size] if options[:layout_size] && options[:layout_size] > 0 # aka Scale Factor
    payload[:createBackup] = options[:create_backup] if !options[:create_backup].nil?
    payload['instance']['expireDays'] = options[:expire_days] if options[:expire_days]
    payload['instance']['shutdownDays'] = options[:shutdown_days] if options[:shutdown_days]
    if options.key?(:create_user)
      payload['config'] ||= {}
      payload['config']['createUser'] = options[:create_user]
    end
    if options[:user_group_id]
      payload['instance']['userGroup'] = {'id' => options[:user_group_id] }
    end
    if options[:workflow_id]
      if options[:workflow_id].to_s =~ /\A\d{1,}\Z/
        payload['taskSetId'] = options[:workflow_id].to_i
      else
        payload['taskSetName'] = options[:workflow_id]
      end
    end
    if options[:enable_load_balancer]
      lb_payload = prompt_instance_load_balancer(payload['instance'], nil, options)
      payload.deep_merge!(lb_payload)
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.create(payload)
      return 0
    end

    json_response = @instances_interface.create(payload)
    render_response(json_response, options, "instance") do
      instance_id = json_response["instance"]["id"]
      instance_name = json_response["instance"]["name"]
      print_green_success "Provisioning instance [#{instance_id}] #{instance_name}"
      # print details
      get_args = [instance_id] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
      get(get_args)
    end
    return 0, nil
  end

  def update(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--displayName VALUE', String, "Name") do |val|
        params['displayName'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--environment VALUE', String, "Environment") do |val|
        params['instanceContext'] = val
      end
      opts.on('--group GROUP', String, "Group Name or ID") do |val|
        options[:group] = val
      end
      opts.on('--labels [LIST]', String, "Labels (keywords) in the format 'foo, bar'") do |val|
        params['labels'] = parse_labels(val)
      end
      opts.on('--tags LIST', String, "Tags in the format 'name:value, name:value'. This will add and remove tags.") do |val|
        options[:tags] = val
      end
      opts.on('--add-tags TAGS', String, "Add Tags in the format 'name:value, name:value'. This will only add/update tags.") do |val|
        options[:add_tags] = val
      end
      opts.on('--remove-tags TAGS', String, "Remove Tags in the format 'name, name:value'. This removes tags, the :value component is optional and must match if passed.") do |val|
        options[:remove_tags] = val
      end
      opts.on('--power-schedule-type ID', String, "Power Schedule Type ID") do |val|
        params['powerScheduleType'] = val == "null" ? nil : val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val == 'null' ? nil : val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val == 'null' ? nil : val
      end
      opts.add_hidden_option('--created-by')
      # opts.on("--shutdown-days [DAYS]", Integer, "Automation: Shutdown Days") do |val|
      #   params['shutdownDays'] = val.to_s.empty? ? nil : val.to_i
      # end
      # opts.on("--expire-days DAYS", Integer, "Automation: Expiration Days") do |val|
      #   params['expireDays'] = val.to_s.empty? ? nil : val.to_i
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      if options[:payload]
        payload = options[:payload]
      end
      payload['instance'] ||= {}
      payload.deep_merge!({'instance' => parse_passed_options(options)})

      if options.key?(:owner) && [nil].include?(options[:owner])
        # allow clearing
        params['ownerId'] = nil
      elsif options[:owner]
        owner_id = options[:owner].to_s
        if owner_id.to_s =~ /\A\d{1,}\Z/
          # allow id without lookup
        else
          user = find_available_user_option(owner_id)
          return 1 if user.nil?
          owner_id = user['id']
        end
        params['ownerId'] = owner_id
        #payload['createdById'] = options[:owner].to_i # pre 4.2.1 api
      end
      if options[:group]
        group = find_group_by_name_or_id_for_provisioning(options[:group])
        if group.nil?
          return 1, "group not found"
        end
        payload['instance']['site'] = {'id' => group['id']}
      end
      # metadata tags
      if options[:tags]
        # api version 4.2.5 and later supports tags, older versions expect metadata
        # todo: use tags instead like everywhere else
        # payload['instance']['tags'] = parse_metadata(options[:tags])
        payload['instance']['metadata'] = parse_metadata(options[:tags])
      end
      if options[:add_tags]
        payload['instance']['addTags'] = parse_metadata(options[:add_tags])
      end
      if options[:remove_tags]
        payload['instance']['removeTags'] = parse_metadata(options[:remove_tags])
      end
      if payload['instance'].empty? && params.empty? && options[:owner].nil?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      if !params.empty?
        payload['instance'].deep_merge!(params)
      end
      payload.delete('instance') if payload['instance'] && payload['instance'].empty?
      raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated instance #{instance['name']}"
        #list([])
        get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for an instance." + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?


      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.wiki(instance["id"], params)
        return
      end
      json_response = @instances_interface.wiki(instance["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Instance Wiki Page: #{instance['name']}"
        # print_h1 "Wiki Page Details"
        print cyan

        print_description_list({
          "Page ID" => 'id',
          "Name" => 'name',
          #"Category" => 'category',
          #"Ref Type" => 'refType',
          #"Ref ID" => 'refId',
          #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
          "Updated By" => lambda {|it| it['updatedBy'] ? it['updatedBy']['username'] : '' }
        }, page)
        print reset,"\n"

        print_h2 "Page Content"
        print cyan, page['content'], reset, "\n"

      else
        print "\n"
        print cyan, "No wiki page found.", reset, "\n"
      end
      print reset,"\n"

      if open_wiki_link
        return view_wiki([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_wiki(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View instance wiki page in a web browser" + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/instances/#{instance['id']}#!wiki"

      if options[:dry_run]
        puts Morpheus::Util.open_url_command(link)
        return 0
      end
      return Morpheus::Util.open_url(link)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_wiki(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      build_option_type_options(opts, options, update_wiki_page_option_types)
      opts.on('--file FILE', "File containing the wiki content. This can be used instead of --content") do |filename|
        full_filename = File.expand_path(filename)
        if File.exist?(full_filename)
          params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      opts.on(nil, '--clear', "Clear current page content") do |val|
        params['content'] = ""
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'page' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_wiki_page_option_types, options[:options], @api_client, options[:params])
        #params = passed_options
        params.deep_merge!(passed_options)

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload.deep_merge!({'page' => params}) unless params.empty?
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_wiki(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update_wiki(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for instance #{instance['name']}"

        wiki([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_network_label(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      opts.on('--network NETWORK', "Network Interface ID" ) do |val|
        options[:network] = val
      end
      opts.on('--label LABEL', "label") do |val|
        options[:label] = val
      end
       opts.footer = "Change the label of a Network Interface.\n" +
                    "Editing an Interface will not apply changes to the physical hardware. The purpose is for a manual override or data correction (mostly for self managed or baremetal servers where cloud sync is not available)\n" +
                    "[name or id] is required. The name or the id of the instance.\n" +
                    "[network] ID of the Network Interface. (optional).\n" +
                    "[label] New Label name for the Network Interface (optional)"
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      network_id = options[:network]
      if network_id != nil && network_id.to_i == 0
        print_red_alert  "network must be an ID/integer above 0, not a name/string value."
        network_id = nil
      end

      if !network_id
        available_networks = get_available_networks(instance)
        network_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'network', 'fieldLabel' => 'Network', 'type' => 'select', 'selectOptions' => available_networks, 'required' => true, 'defaultValue' => available_networks[0], 'description' => "The networks available for relabeling"}], options[:options])
        network_id = network_prompt['network']
      end



      label = options[:label]
      while label.nil? do
        label_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'label', 'fieldLabel' => 'Label', 'type' => 'text', 'required' => true}], options[:options])
        label = label_prompt['label']
      end
      payload = { "name" => label }
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_network_label(network_id, instance["id"], payload)
        return
      end
      json_response = @instances_interface.update_network_label(network_id, instance["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated label for instance #{instance['name']} network #{network_id} to #{label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end



  def status_check(args)
    out = ""
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:quiet, :json, :remote]) # no :dry_run, just do it man
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    # todo: just return status or maybe check if instance['status'] == args[0]
    instance = find_instance_by_name_or_id(args[0])
    exit_code = 0
    if instance['status'].to_s.downcase != (args[1] || "running").to_s.downcase
      exit_code = 1
    end
    if options[:json]
      mock_json = {status: instance['status'], exit: exit_code}
      out << as_json(mock_json, options)
      out << "\n"
    elsif !options[:quiet]
      out << cyan
      out << "Status: #{format_instance_status(instance)}"
      out << reset
      out << "\n"
    end
    print out unless options[:quiet]
    exit exit_code #return exit_code
  end

  def stats(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    ids = args
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _stats(arg, options)
    end
  end

  def _stats(arg, options)
    begin
      instance = find_instance_by_name_or_id(arg)
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get(instance['id'])
        return 0
      end
      json_response = @instances_interface.get(instance['id'])
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      end
      instance = json_response['instance']
      stats = instance['stats'] || json_response['stats'] || {}
      title = "Instance Stats: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      puts cyan + "Status: ".rjust(12) + format_instance_status(instance).to_s
      puts cyan + "Nodes: ".rjust(12) + (instance['containers'] ? instance['containers'].count : '').to_s
      # print "\n"
      #print_h2 "Instance Usage", options
      print_stats_usage(stats)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def console(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '-n', '--node NODE_ID', "Scope console to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      build_common_options(opts, options, [:dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/terminal/#{instance['id']}"
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        link += "?containerId=#{options[:node_id]}"
      end

      if options[:dry_run]
        puts Morpheus::Util.open_url_command(link)
        return 0
      end
      return Morpheus::Util.open_url(link)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('-w','--wiki', "Open the wiki tab for this instance") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View an instance in a web browser" + "\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _view(arg, options)
    end
  end


  def _view(arg, options={})
    begin
      instance = find_instance_by_name_or_id(arg)
      return 1 if instance.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/instances/#{instance['id']}"
      if options[:link_tab]
        link << "#!#{options[:link_tab]}"
      end

      open_command = nil
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        open_command = "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        open_command = "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        open_command = "xdg-open #{link}"
      end

      if options[:dry_run]
        puts "system: #{open_command}"
        return 0
      end

      system(open_command)
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on('--hosts HOSTS', String, "Filter logs to specific Host ID(s)") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--servers HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--vms HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      # opts.on('--container CONTAINER', String, "Filter logs to specific Container ID(s)") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--nodes HOST', String, "alias for --containers") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
      # opts.on('--interval TIME','--interval TIME', "Interval of time to include, in seconds. Default is 30 days ago.") do |val|
      #   options[:interval] = parse_time(val).utc.iso8601
      # end
      opts.on('--level VALUE', String, "Log Level. DEBUG,INFO,WARN,ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : [val]
      end
      opts.on('--table', '--table', "Format ouput as a table.") do
        options[:table] = true
      end
      opts.on('-a', '--all', "Display all details: entire message." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      container_ids = instance['containers']
      if options[:node_id]
        if container_ids.include?(options[:node_id])
          container_ids = [options[:node_id]]
        else
          print_red_alert "Instance does not include node #{options[:node_id]}"
          return 1
        end
      end
      params['level'] = params['level'].collect {|it| it.to_s.upcase }.join('|') if params['level'] # api works with INFO|WARN
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['order'] = params['direction'] unless params['direction'].nil? # old api version expects order instead of direction
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      params['interval'] = options[:interval].to_s if options[:interval]
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(container_ids, params)
        return
      end
      json_response = @logs_interface.container_logs(container_ids, params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result
      
      title = "Instance Logs: #{instance['name']} (#{instance['instanceType'] ? instance['instanceType']['name'] : ''})"
      subtitles = parse_list_subtitles(options)
      if options[:start]
        subtitles << "Start: #{options[:start]}".strip
      end
      if options[:end]
        subtitles << "End: #{options[:end]}".strip
      end
      if params[:query]
        subtitles << "Search: #{params[:query]}".strip
      end
      if params['servers']
        subtitles << "Servers: #{params['servers']}".strip
      end
      if params['containers']
        subtitles << "Containers: #{params['containers']}".strip
      end
      if params[:query]
        subtitles << "Search: #{params[:query]}".strip
      end
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      logs = json_response['data'] || json_response['logs']
      print_h1 title, subtitles, options
      if logs.empty?
        print "#{cyan}No logs found.#{reset}\n"
      else
        print format_log_records(logs, options)
        print_results_pagination({'meta'=>{'total'=>(json_response['total']['value'] rescue json_response['total']),'size'=>logs.size,'max'=>(json_response['max'] || options[:max]),'offset'=>(json_response['offset'] || options[:offset] || 0)}})
      end
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('-a', '--all', "Display all details: containers|vms, and scaling." ) do
        options[:details] = true
        options[:include_containers] = true
        options[:include_scaling] = true
        options[:include_costs]
      end
      opts.on(nil, '--details', "Alias for --all" ) do
        options[:details] = true
        options[:include_containers] = true
        options[:include_scaling] = true
        options[:include_costs]
      end
      opts.add_hidden_option('--details')
      opts.on( nil, '--containers', "Display Instance Containers" ) do
        options[:include_containers] = true
      end
      opts.on( nil, '--nodes', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      # opts.add_hidden_option('--nodes')
      opts.on( nil, '--vms', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      # opts.add_hidden_option('--vms')
      opts.on( nil, '--scaling', "Display Instance Scaling Settings" ) do
        options[:include_scaling] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      # opts.on( nil, '--threshold', "Alias for --scaling" ) do
      #   options[:include_scaling] = true
      # end
      # opts.on( nil, '--lb', "Display Load Balancer Details" ) do
      #   options[:include_lb] = true
      # end
      build_standard_get_options(opts, options)
      opts.footer = "Get details about an instance.\n" + 
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options={})
    params = {}
    params.merge!(parse_query_options(options))
    # Use details=true to get more details from the appliance
    # if options[:details] || options[:include_containers]  || options[:include_scaling]
    if options[:details] || options[:include_containers]  || options[:include_scaling]
      params['details'] = true
    end
    instance = nil
    if id.to_s !~ /\A\d{1,}\Z/
      instance = find_instance_by_name_or_id(id)
      return 1, "Instance not found by name #{id}" if instance.nil?
      id = instance['id']
    end
    if options[:dry_run]
      print_dry_run @instances_interface.dry.get(id, params)
      return 0, nil
    end
    @instances_interface.setopts(options)
    json_response = @instances_interface.get(id, params)
    render_response(json_response, options, "instance") do
      instance = json_response['instance']
      pricing = instance['instancePrice']
      stats = instance['stats'] || json_response['stats'] || {}
      # load_balancers = json_response['loadBalancers'] || {}
      # metadata tags used to be returned as metadata and are now returned as tags
      # the problem is tags is what we used to call Labels (keywords)
      # the api will change to tags and labels, so handle the old format as long as metadata is returned.
      labels = nil
      tags = nil
      if instance.key?('labels')
        labels = instance['labels']
        tags = instance['tags']
      else
        labels = instance['tags']
        tags = instance['metadata']
      end
      # containers are fetched via separate api call
      containers = nil
      if options[:include_containers]
        # todo: can use instance['containerDetails'] in api 5.2.7/5.3.2
        if instance['containerDetails']
          containers = instance['containerDetails']
        else
          containers = @instances_interface.containers(instance['id'])['containers']
        end
      end

      # threshold is fetched via separate api call too
      instance_threshold = nil
      if options[:include_scaling]
        instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold']
      end

      # loadBalancers is returned via show
      # parse the current api format of loadBalancers.first.lbs.first
      current_instance_lb = nil
      if instance["currentLoadBalancerInstances"]
        current_instance_lb = instance['currentLoadBalancerInstances'][0]
      end

      # support old format
      if !current_instance_lb && json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      print_h1 "Instance Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Display Name" => 'displayName',
        "Description" => 'description',
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Type" => lambda {|it| it['instanceType']['name'] },
        "Layout" => lambda {|it| it['layout'] ? it['layout']['name'] : '' },
        "Version" => lambda {|it| it['instanceVersion'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Price" => lambda {|it|
          if pricing
            pricing['price'] ? format_money(pricing['price'], (pricing['currency'] || 'USD')).to_s + ' per ' + pricing['unit'].to_s : ''
          elsif it['hourlyPrice']
            format_money(it['hourlyPrice'], (it['currency'] || 'USD')).to_s + ' per hour'
          end
        },
        "Cost" => lambda {|it| 
          if pricing
            pricing['cost'] ? format_money(pricing['cost'], (pricing['currency'] || 'USD')).to_s + ' per ' + pricing['unit'].to_s : ''
          elsif it['hourlyCost']
            format_money(it['hourlyCost'], (it['currency'] || 'USD')).to_s + ' per hour'
          end
        },
        "Environment" => 'instanceContext',
        "Labels" => lambda {|it| labels ? labels.join(',') : '' },
        "Tags" => lambda {|it| tags ? tags.collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        "Owner" => lambda {|it| 
          if it['owner']
            (it['owner']['username'] || it['owner']['id'])
          else
            it['createdBy'] ? (it['createdBy']['username'] || it['createdBy']['id']) : '' 
          end
        },
        #"Tenant" => lambda {|it| it['tenant'] ? it['tenant']['name'] : '' },
        "Apps" => lambda {|it| anded_list(it['apps'] ? it['apps'].collect {|app| app['name'] } : [])},
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        "Power Schedule" => lambda {|it| (it['powerSchedule'] && it['powerSchedule']['type']) ? it['powerSchedule']['type']['name'] : '' },
        "Last Deployment" => lambda {|it| (it['lastDeploy'] ? "#{it['lastDeploy']['deployment']['name']} #{it['lastDeploy']['deploymentVersion']['userVersion']} at #{format_local_dt it['lastDeploy']['deployDate']}" : nil) rescue "" },
        "Expire Date" => lambda {|it| it['expireDate'] ? format_local_dt(it['expireDate']) : '' },
        "Shutdown Date" => lambda {|it| it['shutdownDate'] ? format_local_dt(it['shutdownDate']) : '' },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].count : 0 },
        "Connection" => lambda {|it| format_instance_connection_string(it) },
        "Locked" => lambda {|it| format_boolean(it['locked']) },
        "Status" => lambda {|it| format_instance_status(it) }
      }
      description_cols.delete("Labels") if labels.nil? || labels.empty?
      description_cols.delete("Apps") if instance['apps'].nil? || instance['apps'].empty?
      description_cols.delete("Power Schedule") if instance['powerSchedule'].nil?
      description_cols.delete("Expire Date") if instance['expireDate'].nil?
      description_cols.delete("Shutdown Date") if instance['shutdownDate'].nil?
      description_cols["Removal Date"] = lambda {|it| format_local_dt(it['removalDate'])} if instance['status'] == 'pendingRemoval'
      description_cols.delete("Last Deployment") if instance['lastDeploy'].nil?
      description_cols.delete("Locked") if instance['locked'] != true
      price_value = (pricing ? pricing['price'] : instance['hourlyPrice']).to_i
      cost_value = (pricing ? pricing['cost'] : instance['hourlyCost']).to_i
      description_cols.delete("Price") if price_value == 0
      description_cols.delete("Cost") if cost_value == 0 || cost_value == price_value
      #description_cols.delete("Environment") if instance['instanceContext'].nil?
      print_description_list(description_cols, instance)

      if instance['statusMessage']
        print_h2 "Status Message", options
        if instance['status'] == 'failed'
          print red, instance['statusMessage'], reset
        else
          print instance['statusMessage']
        end
        print "\n"
      end
      if instance['errorMessage']
        print_h2 "Error Message", options
        print red, instance['errorMessage'], reset, "\n"
      end
      if !instance['notes'].to_s.empty?
        print_h2 "Instance Notes", options
        print cyan, instance['notes'], reset, "\n"
      end
      wiki_page = instance['wikiPage']
      if wiki_page && wiki_page['content']
        print_h2 "Instance Wiki", options
        print cyan, truncate_string(wiki_page['content'], 100), reset, "\n"
        print "  Last updated by #{wiki_page['updatedBy'] ? wiki_page['updatedBy']['username'] : ''} on #{format_local_dt(wiki_page['lastUpdated'])}", reset, "\n"
      end
      if stats
        print_h2 "Instance Usage", options
        print_stats_usage(stats)
      end

      print reset, "\n"

      # if options[:include_lb]
      if current_instance_lb
        print_h2 "Load Balancer", options
        print cyan
        description_cols = {
          "LB ID" => lambda {|it| it['loadBalancer']['id'] },
          "Name" => lambda {|it| it['loadBalancer']['name'] },
          "Type" => lambda {|it| it['loadBalancer']['type'] ? it['loadBalancer']['type']['name'] : '' },
          "Host Name" => lambda {|it| it['vipHostname'] || instance['hostName'] },
          "Port" => lambda {|it| it['vipPort'] },
          "Protocol" => lambda {|it| it['vipProtocol'] || 'tcp' },
          "SSL Enabled" => lambda {|it| format_boolean(it['sslEnabled']) },
          "SSL Cert" => lambda {|it| (it['sslCert']) ? it['sslCert']['name'] : '' },
          "In" => lambda {|it| instance['currentLoadBalancerContainersIn'] },
          "Out" => lambda {|it| instance['currentLoadBalancerContainersOutrelo'] }
        }
        print_description_list(description_cols, current_instance_lb)
        print "\n", reset
      end
      # end

      if options[:include_containers]
        print_h2 "Instance Containers", options

        if containers.empty?
          print yellow,"No containers found for instance.",reset,"\n"
        else
          containers = containers.sort { |x,y| x['id'] <=> y['id'] }
          rows = containers.collect {|container| 
            stats = container['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            if stats['maxMemory'] && stats['maxMemory'].to_i != 0
              memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(7, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
            end
            if stats['maxStorage'] && stats['maxStorage'].to_i != 0
              storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(7, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
            end
            row = {
              id: container['id'],
              status: format_container_status(container),
              name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
              type: container['containerType'] ? container['containerType']['name'] : '',
              host: container['server'] ? container['server']['name'] : '',
              cloud: container['cloud'] ? container['cloud']['name'] : '',
              location: format_container_connection_string(container),
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan, 
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, :status, :name, :type, :cloud, :host, :location, :cpu, :memory, :storage]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          #print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
        end
        print reset,"\n"
      end

      if options[:include_scaling]
        print_h2 "Instance Scaling", options
        if instance_threshold.nil? || instance_threshold.empty?
          print cyan,"No scaling settings applied to this instance.",reset,"\n"
        else
          print cyan
          print_instance_threshold_description_list(instance_threshold)
          print reset,"\n"
        end
      end

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(instance['status'])
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(instance['id'], options)
        end
      end
    end
    return 0, nil
  end

  def list_containers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _list_containers(arg, options)
    end
  end

  def _list_containers(arg, options)
    params = {}
    begin
      instance = find_instance_by_name_or_id(arg)
      return 1 if instance.nil?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.containers(instance['id'], params)
        return
      end
      json_response = @instances_interface.containers(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options, "containers")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containers")
        return 0
      end

      if options[:csv]
        puts records_as_csv(json_response['containers'], options)
        return 0
      end
      

      containers = json_response['containers']
      containers = containers.sort { |x,y| x['id'] <=> y['id'] }
      title = "Instance Containers: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      if containers.empty?
        print cyan,"No containers found for instance.",reset,"\n"
      else

        rows = containers.collect {|container| 
          stats = container['stats']
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          if stats['maxMemory'] && stats['maxMemory'].to_i != 0
            memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(7, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
          end
          if stats['maxStorage'] && stats['maxStorage'].to_i != 0
            storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(7, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
          end
          row = {
            id: container['id'],
            status: format_container_status(container),
            name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
            type: container['containerType'] ? container['containerType']['name'] : '',
            cloud: container['cloud'] ? container['cloud']['name'] : '',
            location: format_container_connection_string(container),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, :status, :name, :type, :cloud, :location, :cpu, :memory, :storage]
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backups(instance['id'], params)
        return
      end
      json_response = @instances_interface.backups(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      
      if json_response['backups'] && json_response['backups'][0] && json_response['backups'][0]['backupResults']
        # new format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options


        backup = json_response['backups'][0]

        description_cols = {
          "Backup ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Type" => lambda {|it| it['backupType'] ? (it['backupType']['name'] || it['backupType']['code']) : '' },
          "Storage" => lambda {|it| it['storageProvider'] ? it['storageProvider']['name'] : '' },
          "Schedule" => lambda {|it| it['cronDescription'] || it['cronExpression'] }
        }
        print_description_list(description_cols, backup)

        backup_results = backup ? backup['backupResults'] : nil
        backup_rows = backup_results.collect {|it| 
          status_str = it['status'].to_s.upcase
          # 'START_REQUESTED' //START_REQUESTED, IN_PROGRESS, CANCEL_REQUESTED, CANCELLED, SUCCEEDED, FAILED
          if status_str == 'SUCCEEDED'
            status_str = "#{green}#{status_str.upcase}#{cyan}"
          elsif status_str == 'FAILED'
            status_str = "#{red}#{status_str.upcase}#{cyan}"
          else
            status_str = "#{cyan}#{status_str.upcase}#{cyan}"
          end
          {id: it['id'], startDate: format_local_dt(it['dateCreated']), duration: format_duration_milliseconds(it['durationMillis']), 
            size: format_bytes(it['sizeInMb'], 'MB'), status: status_str }
        }
        print_h1 "Backup Results", [], options
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          {:startDate => {:display_name => "Started"} },
          :duration,
          :size,
          :status
        ]
        print reset, "\n"
      elsif json_response['backups'].size == 0
        # no backup configured
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        print "#{yellow}No backups configured#{reset}\n\n"
      else
        # old format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        backups = json_response['backups']
        backup_rows = backups.collect {|r| 
          it = r['backup']
          {id: it['id'], name: it['name'], dateCreated: format_local_dt(it['dateCreated'])}
        }
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          :name,
          {:dateCreated => {:display_name => "Date Created"} }
        ]
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def clone(args)
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] -g GROUP")
      opts.on( '-g', '--group GROUP', "Group Name or ID for the new instance" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID for the new instance" ) do |val|
        options[:cloud] = val
      end
      opts.on('--name VALUE', String, "Name") do |val|
        options[:options]['name'] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on("--environment ENV", String, "Environment code") do |val|
        options[:environment] = val.to_s
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('--labels LIST', String, "Labels (keywords) in the format 'foo, bar'") do |val|
        options[:labels] = parse_labels(val)
      end
      # opts.on("--copies NUMBER", Integer, "Number of copies to provision") do |val|
      #   options[:copies] = val.to_i
      # end
      # opts.on("--layout-size NUMBER", Integer, "Apply a multiply factor of containers/vms within the instance") do |val|
      #   options[:layout_size] = val.to_i
      # end
      # opts.on( '-l', '--layout LAYOUT', "Layout ID" ) do |val|
      #   options[:layout] = val
      # end
      opts.on( '-p', '--plan PLAN', "Service plan ID") do |val|
        options[:service_plan] = val
      end
      opts.on( '--resource-pool ID', String, "Resource pool ID" ) do |val|
        options[:resource_pool] = val
      end
      opts.on("--workflow ID", String, "Automation: Workflow ID") do |val|
        options[:workflow_id] = val
      end
      opts.on("--ports ARRAY", String, "Exposed Ports, JSON formatted list of objects containing name and port") do |val|
        # expects format like --ports '[{"name":"web","port":8080}]'
        ports_array = JSON.parse(val)
        options[:ports] = ports_array
        options[:options]['ports'] = ports_array
      end
      # opts.on('-L', "--lb", "Enable Load Balancer") do
      #   options[:enable_load_balancer] = true
      # end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is on") do |val|
        options[:create_user] = !['false','off','0'].include?(val.to_s)
      end
      opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
        options[:user_group_id] = val
      end
      opts.on("--shutdown-days DAYS", Integer, "Automation: Shutdown Days") do |val|
        options[:shutdown_days] = val.to_i
      end
      opts.on("--expire-days DAYS", Integer, "Automation: Expiration Days") do |val|
        options[:expire_days] = val.to_i
      end
      opts.on("--create-backup [on|off]", String, "Automation: Create Backups.") do |val|
        options[:create_backup] = ['on','true','1',''].include?(val.to_s.downcase) ? 'on' : 'off'
      end
      opts.on("--security-groups LIST", String, "Security Groups, comma separated list of security group IDs") do |val|
        options[:security_groups] = val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
      end
      build_standard_post_options(opts, options, [:auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      options[:options] ||= {}
      options[:select_datastore] = true
      options[:name_required] = true

      # defaults derived from clone
      options[:default_name] = instance['name'] + '-clone' if instance['name']
      options[:default_description] = instance['description'] if !instance['description'].to_s.empty?
      options[:default_environment] = instance['environment'] if instance['environment']
      options[:default_group] = instance['group']['id'] if instance['group']
      options[:default_cloud] = instance['cloud']['name'] if instance['cloud']
      options[:default_plan] = instance['plan']['name'] if instance['plan']
      options[:default_resource_pool] = instance['config']['resourcePoolId'] if instance['config']
      options[:default_config] = instance['config']
      options[:default_security_group] = instance['config']['securityGroups'][0]['id'] if instance['config'] && (instance['config']['securityGroups'] || []).count > 0
      if instance['labels'] && !instance['labels'].empty?
        options[:default_labels] = (instance['labels'] || []).join(',')
      end
      if instance['tags'] && !instance['tags'].empty?
        options[:current_tags] = instance['tags']
      end

      # immutable derived from clone
      options[:instance_type_code] = instance['instanceType']['code'] if instance['instanceType']
      options[:version] = instance['instanceVersion']
      options[:layout] = instance['layout']['id'] if instance['layout']

      # volume defaults
      options[:options]['volumes'] = instance['volumes']

      # network defaults
      options[:options]['networkInterfaces'] = instance['interfaces']

      # use the -g GROUP or active group by default
      #options[:options]['group'] ||= (options[:group] || @active_group_id)
      # support [new-name] 
      if args[1]
        options[:options]['name'] = args[1]
      end
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) || ['networkInterfaces'].include?(k)} : {}
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        new_instance_payload = prompt_new_instance(options)

        # adjust for differences between new and clone payloads
        payload = new_instance_payload.delete('instance')
        payload.deep_merge!(new_instance_payload)
        payload['cloud'] = {'id' => payload.delete('zoneId')}
        payload['group'] = payload.delete('site')
      end
      unless passed_options.empty?
        passed_options.delete('cloud')
        passed_options.delete('group')
        payload.deep_merge!(passed_options)
      end
      
      #payload['instance'] ||= {}
      # if options[:instance_name]
      #   payload['instance']['name'] = options[:instance_name]
      # end
      # if options[:description] && !payload['instance']['description']
      #   payload['instance']['description'] = options[:description]
      # end
      # if options[:environment] && !payload['instance']['instanceContext']
      #   payload['instance']['instanceContext'] = options[:environment]
      # end
    
      #payload[:copies] = options[:copies] if options[:copies] && options[:copies] > 0
      if options[:layout_size] && options[:layout_size] > 0 # aka Scale Factor
        payload[:layoutSize] = options[:layout_size]
      end
      if !options[:create_backup].nil?
        payload[:createBackup] = options[:create_backup]
      end
      if options[:expire_days]
        payload['instance'] ||= {}
        payload['instance']['expireDays'] = options[:expire_days]
      end
      if options[:shutdown_days]
        payload['instance'] ||= {}
        payload['shutdownDays'] = options[:shutdown_days]
      end
      # JD: this actually fixed a customer problem
      # It appears to be important to pass this... not sure if config.createUser is necessary...
      if options[:create_user].nil?
        options[:create_user] = true
      end
      if options.key?(:create_user)
        payload['config'] ||= {}
        payload['config']['createUser'] = options[:create_user]
        payload['createUser'] = options[:create_user]
      end
      if options[:user_group_id]
        payload['instance'] ||= {}
        payload['instance']['userGroup'] = {'id' => options[:user_group_id] }
      end
      if options[:workflow_id]
        if options[:workflow_id].to_s =~ /\A\d{1,}\Z/
          payload['taskSetId'] = options[:workflow_id].to_i
        else
          payload['taskSetName'] = options[:workflow_id]
        end
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to clone the instance #{instance['name']} as '#{payload['name']}'?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.clone(instance['id'], payload)
        return
      end
      json_response = @instances_interface.clone(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Cloning instance #{instance['name']} to '#{payload['name']}'"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def envs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get_envs(instance['id'])
        return
      end
      json_response = @instances_interface.get_envs(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      print_h1 "Instance Envs: #{instance['name']} (#{instance['instanceType']['name']})", [], options
      print cyan
      envs = json_response['envs'] || {}
      if json_response['readOnlyEnvs']
        envs += json_response['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
      end
      columns = [:name, :value, :export]
      print_h2 "Imported Envs", options
      print as_pretty_table(envs, columns, options)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def setenv(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] VAR VALUE [-e]")
      opts.on( '-e', "Exportable" ) do |exportable|
        options[:export] = exportable
      end
      opts.on( '-M', "Masked" ) do |masked|
        options[:masked] = masked
      end
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count < 3
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
      payload = {envs: [evar]}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_env(instance['id'], payload)
        return
      end
      json_response = @instances_interface.create_env(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def delenv(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] VAR")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.del_env(instance['id'], args[1])
        return
      end
      json_response = @instances_interface.del_env(instance['id'], args[1])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    params = {'server' => true, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('--muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    params = {'server' => true, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('--muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # suspend should be server: false by default I guess..
  def suspend(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('--muteMonitoring')
      opts.on('--server [on|off]', String, "Suspend instance server. Default is off.") do |val|
        params['server'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Suspend an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.suspend(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.suspend(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Suspended instance #{instances[0]['name']}"
        else
          print_green_success "Suspended #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def eject(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Eject an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.eject(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.eject(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Ejected instance #{instances[0]['name']}"
        else
          print_green_success "Ejected #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop_service(args)
    params = {'server' => false, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('--muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start_service(args)
    params = {'server' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart_service(args)
    params = {'server' => false, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('--muteMonitoring')
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def actions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id or name list]")
      opts.footer = "List the actions available to specified instance(s)."
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} actions requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }
    begin
      # instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.available_actions(instance_ids)
        return 0
      end
      json_response = @instances_interface.available_actions(instance_ids)
      if options[:json]
        puts as_json(json_response, options)
      else
        title = "Instance Actions: #{anded_list(id_list)}"
        print_h1 title, [], options
        available_actions = json_response["actions"]
        if (available_actions && available_actions.size > 0)
          print as_pretty_table(available_actions, [:name, :code])
          print reset, "\n"
        else
          print "#{yellow}No available actions#{reset}\n\n"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def find_server_type_by_id(id)
    begin
      json_response =@server_types_interface.get(id.to_i)
      return json_response['serverType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Server Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end
  private :find_server_type_by_id

  # checks whether adding a node to the specified instance requires a resource pool input
  def addnode_requires_resource_pool?(instance, provision_type)
    return false unless provision_type && provision_type["hasZonePools"] && provision_type["zonePoolRequired"] && instance['servers']
    instance['servers'].each do |server_id|
      server = find_server_by_id(server_id)
      next unless server
      cst_id = server.dig('computeServerType', 'id')
      cst = find_server_type_by_id(cst_id)
      unless cst
        print_red_alert "Server Type not found by id #{cst_id}"
        return false
      end
      return true if cst['bareMetalHost']
    end
    false
  end
  private :addnode_requires_resource_pool?

  # Prompts for a resource pool selection when adding a node to an instance.
  # This is invoked during the Add Node action to choose a resource pool (eg. for HPE bare metal host provisioning types mandates a pool).
  def addnode_prompt_for_resource_pool(instance, options)
    zone_id = instance['cloud']['id']
    if zone_id.nil?
      print_red_alert "Instance #{instance['name']} does not have a cloud/zone assigned."
      return nil
    end
    zone_pools = @cloud_resource_pools_interface.list(zone_id)['resourcePools']
    if zone_pools.empty?
      print_red_alert "No Resource Pools are defined for the instance's cloud #{instance['cloud']['name']}. This is required to perform this action."
      return nil
    end
    zone_pools_dropdown = zone_pools.collect {|zp| {'name' => zp['name'], 'value' => zp['id']} }
    # validate input if given
    if options[:options] && options[:options]['resourcePool']
      selected_resource_pool_id = options[:options]['resourcePool'].to_i
      selected_pool = zone_pools.find {|zp| zp['id'] == selected_resource_pool_id }
      if selected_pool.nil?
        print_red_alert "Resource Pool ID #{selected_resource_pool_id} is not valid for the instance's cloud."
        return nil
      end
    end
    # auto select single
    pool_prompt = Morpheus::Cli::OptionTypes.prompt(
    [{
       'fieldName' => 'resourcePool',
       'type' => 'select',
       'fieldLabel' => 'Resource Pool',
       'selectOptions' => zone_pools_dropdown,
       'required' => true,
       'defaultValue' => zone_pools[0]['id'],
       'description' => 'Choose the Resource Pool to use for this action'
     }],
    options[:options]
    )
    selected_pool = zone_pools.find {|zp| zp['id'] == pool_prompt['resourcePool'] }
    if selected_pool.nil?
      print_red_alert "A Resource Pool is required to perform this action."
      return nil
    end
    selected_resource_pool_id = selected_pool['id']
  end
  private :addnode_prompt_for_resource_pool

  def action(args)
    options = {}
    action_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list] -a CODE")
      opts.on('-a', '--action CODE', "Instance Action CODE to execute") do |val|
        action_id = val.to_s
      end
      opts.on( '--resource-pool ID', String, "Resource pool ID for Add node action" ) do |val|
      options[:options] ||= {}
      options[:options]['resourcePool'] = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote, :options,])
      opts.footer = "Execute an action for one or many instances."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }

    # figure out what action to run
    available_actions = @instances_interface.available_actions(instance_ids)["actions"]
    if available_actions.empty?
      if instance_ids.size > 1
        print_red_alert "The specified instances have no available actions in common."
      else
        print_red_alert "The specified instance has no available actions."
      end
      return 1
    end
    instance_action = nil
    if action_id.nil?
      available_actions_dropdown = available_actions.collect {|act| {'name' => act["name"], 'value' => act["code"]} } # already sorted
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'select', 'fieldLabel' => 'Instance Action', 'selectOptions' => available_actions_dropdown, 'required' => true, 'description' => 'Choose the instance action to execute'}], options[:options])
      action_id = v_prompt['code']
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s }
    else
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s || act['name'].to_s.downcase == action_id.to_s.downcase }
      action_id = instance_action["code"] if instance_action
    end
    if !instance_action
      # for testing bogus actions..
      # instance_action = {"id" => action_id, "name" => "Unknown"}
      raise_command_error "Instance Action '#{action_id}' not found."
    end

    action_display_name = "#{instance_action['name']} [#{instance_action['code']}]"
    if action_id == 'generic-add-node' && instances.size > 1
      raise_command_error "The #{action_display_name} action can only be performed on a single instance at a time."
    end

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to perform action #{action_display_name} on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end

    selected_resource_pool_id = nil
    # Special handling for generic-add-node action to prompt for resource pool if needed.
    if action_id == 'generic-add-node'
      instance = instances[0]
      layout = instance['layout']
      provision_type_code = layout['provisionTypeCode']
      provision_type = nil
      if provision_type_code
        provision_type = provision_types_interface.list({code:provision_type_code})['provisionTypes'][0]
        if provision_type.nil?
          print_red_alert "Provision Type not found by code #{provision_type_code}"
          return 1
        end
      end

      # Check if instance containers are of 'baremetalhost' type, if so, then only prompt for resource pool.
      pool_required = addnode_requires_resource_pool?(instance, provision_type)
      if pool_required
        selected_resource_pool_id = addnode_prompt_for_resource_pool(instance, options )
        return 1 if selected_resource_pool_id.nil?
      end
    end # End of generic-add-node special handling
    # return run_command_for_each_arg(containers) do |arg|
    #   _action(arg, action_id, options)
    # end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.action(instance_ids, action_id, selected_resource_pool_id)
      return 0
    end
    json_response = @instances_interface.action(instance_ids, action_id, selected_resource_pool_id)
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      # containers.each do |container|
      #   print green, "Action #{action_display_name} performed on container #{container['id']}", reset, "\n"
      # end
      print green, "Action #{action_display_name} performed on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}", reset, "\n"
    end
    return 0
  end

  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--include-network-interfaces','--include-network-interfaces', "Populate payload networkInterfaces with current interfaces") do
        options[:include_nics] = true
      end
      build_standard_update_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1, "instance not found" if instance.nil?
    # need to load full instance details in case fetched by name
    if instance['containerDetails'].nil?
      instance = find_instance_by_id(instance['id'])
    end
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload = {
        "instance" => {:id => instance["id"]}
      }
      payload.deep_merge!(parse_passed_options(options))

      # avoid 500 error
      # payload[:servicePlanOptions] = {}

      puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"

      group_id = instance['group']['id']
      cloud_id = instance['cloud']['id']
      layout_id = instance['layout']['id']
      plan_id = instance['plan']['id']
      resource_pool_id = instance['config']['resourcePoolId'] if instance['config']
      current_plan_name = instance['plan']['name']
      
      # JD: networkInterfaces should not be needed but pre 7.0.8/8.0.0 the API does expect it to be passed
      # However if the instance has more than one server this creates duplicate nics and breaks things
      # so only continue to do it if the instance has just one server and remote version is pre 7.0.8
      # should also only do this if remote version < 7.0.8
      if options[:include_nics] || (!remote_version_gte("7.0.8") && instance['servers'] && instance['servers'].size == 1)
          current_interfaces = get_instance_interfaces(instance)
          if current_interfaces != false 
            payload['networkInterfaces'] = current_interfaces
          end
      end

      # need to GET provision type for some settings...
      provision_type = @provision_types_interface.get(instance['layout']['provisionTypeId'])['provisionType']

      # prompt for service plan
      service_plans_json = @instances_interface.service_plans({zoneId: cloud_id, siteId: group_id, layoutId: layout_id, resourcePoolId: resource_pool_id})
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        # if plan['value'] && plan['value'].to_i == plan_id.to_i
        #   plan['name'] = "#{plan['name']} (current)"
        #   current_plan_name = plan['name']
        # end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'defaultValue' => current_plan_name, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
      new_plan_id = service_plan["id"]
      #payload[:servicePlan] = new_plan_id # ew, this api uses servicePlanId instead
      #payload[:servicePlanId] = new_plan_id
      payload["instance"]["plan"] = {"id" => service_plan["id"]}

      volumes_response = @instances_interface.volumes(instance['id'])
      current_volumes = nil

      # prompt for volumes
      vol_options = options 
      vol_options['siteId'] = group_id
      vol_options['zoneId'] = cloud_id
      vol_options['resourcePoolId'] = resource_pool_id  # server['resourcePool']['id'] if server['resourcePool']
      server = instance['containerDetails'][0]['server'] rescue nil
      if server.nil?
        Morpheus::Logging::DarkPrinter.puts "Failed to load server info"
        volumes_response = @instances_interface.volumes(instance['id'])
        current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      else
         # or just use instance['volumes'] ?
        current_volumes = server['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      end
      vol_options['resourcePoolId'] = server['resourcePool']['id'] if server && server['resourcePool']
      volumes = prompt_resize_volumes(current_volumes, service_plan, provision_type, vol_options, server)
      if !volumes.empty?
        payload["volumes"] = volumes
      end

      # plan customizations
      plan_opts = prompt_service_plan_options(service_plan, options, @api_client, {}, instance)
      if plan_opts && !plan_opts.empty?
        payload['servicePlanOptions'] = plan_opts
      end

      # only amazon supports this option
      # for now, always do this
      payload["deleteOriginalVolumes"] = true
    end
    payload.delete("rootVolume")
    (1..20).each {|i| payload.delete("dataVolume#{i}") }
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.resize(instance['id'], payload)
      return
    end
    json_response = @instances_interface.resize(instance['id'], payload)
    render_response(json_response, options, 'snapshots') do
      print_green_success "Resizing instance #{instance['name']}"
    end
    return 0, nil
    
  
  end

  def backup(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to backup the instance '#{instance['name']}'?", options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backup(instance['id'])
        return
      end
      json_response = @instances_interface.backup(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        bad_results = []
        if json_response['results']
          json_response['results'].each do |result_id, result|
            if result['success'] != true
              bad_results << result['msg'] || "Failed to create backup for instance #{result_id}"
            end
          end
        end
        if bad_results.empty?
          print_green_success "Backup initiated."
          return 0
        else
          print_red_alert bad_results.join("\n")
          return 1
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def snapshot(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '--name VALUE', String, "Snapshot Name. Default is \"{name}.{timestamp}\"" ) do |val|
        options[:options]['name'] = val
      end
      opts.on( '--description VALUE', String, "Snapshot Description." ) do |val|
        options[:options]['description'] = val
      end
      opts.on('--memory-snapshot [on|off]', String, "Memory Snapshot? Whether to include the memory state in the snapshot.") do |val|
        options[:options]['memorySnapshot'] = val.to_s == '' || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--for-export [on|off]', String, "For Export? Indicates the snapshot is intended for export to storage.") do |val|
        options[:options]['forExport'] = val.to_s == '' || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      build_standard_add_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Create a snapshot for an instance.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'snapshot' => parse_passed_options(options)})
    else
      payload.deep_merge!({'snapshot' => parse_passed_options(options)})
      snapshot = payload['snapshot']
      # prompt for name and description
      name = prompt_value({'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Snapshot Name', 'description' => "Snapshot Name. Default is \"{name}.{timestamp}\""}, options)
      snapshot['name'] = name if !name.to_s.empty?
      description = prompt_value({'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'description' => "Snapshot Description."}, options)
      snapshot['description'] = description if !description.to_s.empty?
      # need to GET provision type for some settings...
      provision_type = nil
      begin
        provision_type = @provision_types_interface.get(instance['layout']['provisionTypeId'])['provisionType']
      rescue => ex
        Morpheus::Logging::DarkPrinter.puts "Failed to load provision type!" if Morpheus::Logging.debug?
      end
      if provision_type && provision_type['hasMemorySnapshots']
        # prompt for memorySnapshot
        memory_snapshot = prompt_value({'fieldName' => 'memorySnapshot', 'type' => 'checkbox', 'fieldLabel' => 'Memory Snapshot?', 'description' => "Snapshot Description."}, options)
        snapshot['memorySnapshot'] = memory_snapshot if !memory_snapshot.to_s.empty?
      end
      # convert "on" and "off" to true/false
      payload.booleanize!
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to snapshot the instance '#{instance['name']}'?", options)
      exit 1
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.snapshot(instance['id'], payload)
      return
    end
    json_response = @instances_interface.snapshot(instance['id'], payload)
    render_response(json_response, options, 'snapshots') do
      print_green_success "Snapshot initiated."
      process_id = json_response['processIds'][0] rescue nil
      if process_id
        unless options[:no_refresh]
          process = wait_for_process_execution(process_id, options)
          snapshot_id = process['resultId']
          if snapshot_id
            Morpheus::Cli::Snapshots.new.handle(["get", snapshot_id] + (options[:remote] ? ["-r",options[:remote]] : []))
          end
        end
      else
        # puts "No process returned"
      end
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off. Applies to certain types only.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on('--release-ips [on|off]', ['on','off'], "Release Floating IPs. Default is on. Applies to certain types only.") do |val|
        query_params[:releaseFloatingIps] = val.nil? ? 'on' : val
        query_params[:releaseEIPs] = query_params[:releaseFloatingIps] # old parameter before 6.0
      end
      opts.on('--releaseEIPs [on|off]', ['on','off'], "Alias for Release Floating IPs") do |val|
        query_params[:releaseFloatingIps] = val.nil? ? 'on' : val
        query_params[:releaseEIPs] = query_params[:releaseFloatingIps] # old parameter before 6.0
      end
      opts.add_hidden_option('--releaseEIPs')
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts "\n#{optparse}\n\n"
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
        exit 1
      end
      # JD: removeVolumes to maintain the old behavior with pre-3.5.2 appliances, remove me later
      if query_params[:preserveVolumes].nil?
        query_params[:removeVolumes] = 'on'
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.destroy(instance['id'],query_params)
        return
      end
      json_response = @instances_interface.destroy(instance['id'],query_params)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        print_green_success "Removing instance #{instance['name']}"
        #list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def cancel_removal(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Cancel removal of an instance.
This is a way to undo delete of an instance still pending removal.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = options[:payload] || {}
    payload.deep_merge!(parse_passed_options(options))
    instance = find_instance_by_name_or_id(args[0])
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.cancel_removal(instance['id'], params, payload)
      return
    end
    json_response = @instances_interface.cancel_removal(instance['id'], params, payload)
    render_response(json_response, options) do
      print_green_success "Canceled removal for instance #{instance['name']} ..."
      get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def cancel_expiration(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options, [:query]) # query params instead of p
      opts.footer = <<-EOT
Cancel expiration of an instance.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = options[:payload] || {}
    payload.deep_merge!(parse_passed_options(options))
    instance = find_instance_by_name_or_id(args[0])
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.cancel_expiration(instance['id'], params, payload)
      return
    end
    json_response = @instances_interface.cancel_expiration(instance['id'], params, payload)
    render_response(json_response, options) do
      print_green_success "Canceled expiration for instance #{instance['name']} ..."
      get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def cancel_shutdown(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options, [:query]) # query params instead of p
      opts.footer = <<-EOT
Cancel shutdown for an instance.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = options[:payload] || {}
    payload.deep_merge!(parse_passed_options(options))
    instance = find_instance_by_name_or_id(args[0])
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.cancel_shutdown(instance['id'], params, payload)
      return
    end
    json_response = @instances_interface.cancel_shutdown(instance['id'], params, payload)
    render_response(json_response, options) do
      print_green_success "Canceled shutdown for instance #{instance['name']} ..."
      get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def extend_expiration(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options, [:query]) # query params instead of p
      opts.footer = <<-EOT
Extend expiration for an instance.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = options[:payload] || {}
    payload.deep_merge!(parse_passed_options(options))
    instance = find_instance_by_name_or_id(args[0])
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.extend_expiration(instance['id'], params, payload)
      return
    end
    json_response = @instances_interface.extend_expiration(instance['id'], params, payload)
    render_response(json_response, options) do
      print_green_success "Extended expiration for instance #{instance['name']} ..."
      get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def extend_shutdown(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options, [:query]) # query params instead of p
      opts.footer = <<-EOT
Extend shutdown for an instance.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    payload = options[:payload] || {}
    payload.deep_merge!(parse_passed_options(options))
    instance = find_instance_by_name_or_id(args[0])
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.extend_shutdown(instance['id'], params, payload)
      return
    end
    json_response = @instances_interface.extend_shutdown(instance['id'], params, payload)
    render_response(json_response, options) do
      print_green_success "Extended shutdown for instance #{instance['name']} ..."
      get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def remove_from_control(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name or id]")
      opts.footer = "Remove a brownfield instance from Morpheus. This does not delete the cloud instance, only Morpheus' record of it.\n" +
                    "[name or id] is required. The name or the id of the instance may be listed.\n" +
                    "[name or id] [name or id] [name or id] ...  A list of names or ids, separated by a space, may be used for bulk removal."
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_from_control(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.remove_from_control(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        puts json_response
        if json_response['success'] == false
           print_red_alert json_response['msg']
        else
           print_green_success json_response['msg']
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_disable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_disable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_enable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_enable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.security_groups(instance['id'])
        return
      end
      json_response = @instances_interface.security_groups(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Instance: #{instance['name']}", [], options
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      #print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
        print "\n"
      end
      print reset, "\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    security_group_ids = nil
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [-S] [-c]")
      opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        security_group_ids = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        security_group_ids = []
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      payload = {securityGroupIds: security_group_ids}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.apply_security_groups(instance['id'], payload)
        return
      end
      json_response = @instances_interface.apply_security_groups(instance['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      if !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def run_workflow(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [workflow] [options]")
      opts.on("--phase PHASE", String, "Task Phase to run for Provisioning workflows. The default is provision.") do |val|
        options[:phase] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = <<-EOT
Run workflow for an instance.
[instance] is required. This is the name or id of an instance
[workflow] is required. This is the name or id of a workflow
By default the provision phase is executed.
Use the --phase option to execute a different phase.
The available phases are start, stop, preProvision, provision, postProvision, preDeploy, deploy, reconfigure, teardown, startup and shutdown.
      EOT
    end
    optparse.parse!(args)
    if args.count != 2
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 2 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    workflow = find_workflow_by_name_or_id(args[1])
    task_types = @tasks_interface.list_types()
    editable_options = []
    workflow['taskSetTasks'].sort{|a,b| a['taskOrder'] <=> b['taskOrder']}.each do |task_set_task|
      task_type_id = task_set_task['task']['taskType']['id']
      task_type = task_types['taskTypes'].find{ |current_task_type| current_task_type['id'] == task_type_id}
      task_opts = task_type['optionTypes'].select { |otype| otype['editable']}
      if !task_opts.nil? && !task_opts.empty?
        editable_options += task_opts.collect do |task_opt|
          new_task_opt = task_opt.clone
          new_task_opt['fieldContext'] = "#{task_set_task['id']}.#{new_task_opt['fieldContext']}"
        end
      end
    end
    params = {}
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # if params.empty? && !editable_options.empty?
    #   puts optparse
    #   option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
    #   puts "\nAvailable Options:\n#{option_lines}\n\n"
    #   exit 1
    # end

    workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
    if options[:phase]
      workflow_payload['taskPhase'] = options[:phase]
    end
    begin
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.workflow(instance['id'],workflow['id'], workflow_payload)
        return
      end
      json_response = @instances_interface.workflow(instance['id'],workflow['id'], workflow_payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      else
        print_green_success "Running workflow #{workflow['name']} on instance #{instance['name']} ..."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def snapshots(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [snapshot]")
      # no pagination yet
      # build_standard_list_options(opts, options)
      build_standard_list_options(opts, options, [:details])
            opts.footer = <<-EOT
List snapshots for an instance.
[instance] is required. This is the name or id of an instance
[snapshot] is optional. this is the name or id a snapshot to filter by.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max: 2)
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.snapshots(instance['id'], params)
        return
      end
      json_response = @instances_interface.snapshots(instance['id'], params)
      snapshots = json_response['snapshots']
      # [snapshots] is done with post api filtering by id or name or externalId
      if args[1]
        if args[1] =~ /\A\d{1,}\Z/
          snapshots = snapshots.select {|it| it['id'].to_s == args[1] }
        else
          # snapshots = snapshots.select {|it| it['name'] == args[1] || it['externalId'] == args[1] }
          # match beginning of name of externalId
          snapshots = snapshots.select {|it| it['name'].to_s.index(args[1]) == 0 || it['externalId'].to_s.index(args[1])  == 0 }
        end
        json_response['snapshots'] = snapshots # update response for -j filtering too
      end
      render_response(json_response, options, 'snapshots') do
        print_h1 "Snapshots: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        if snapshots.empty?
          if args[1]
            print cyan,"No snapshots found for '#{args[1]}'",reset,"\n"
          elsif
            print cyan,"No snapshots found",reset,"\n"
          end
          print reset, "\n"
        else
          if options[:details]
            if snapshots.size > 3
              print cyan, "Showing first 3 snapshots. Use the ID to get more details.", reset, "\n"
              snapshots = snapshots.first(3) # this actually makes a request for each one here so don't go crazy...
            end
            snapshots.each do |snapshot|
              Morpheus::Cli::Snapshots.new.handle(["get", snapshot['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
            end
          else
            # Snapshots List
            snapshot_column_definitions = {
              "ID" => lambda {|it| it['id'] },
              "Name" => lambda {|it| it['name'] },
              "Description" => lambda {|it| it['description'] },
              # "Type" => lambda {|it| it['snapshotType'] },
              "Date Created" => lambda {|it| format_local_dt(it['snapshotCreated']) },
              "Status" => lambda {|it| format_snapshot_status(it) }
            }
            print cyan
            print as_pretty_table(snapshots, snapshot_column_definitions.upcase_keys!, options)
            print_results_pagination({size: snapshots.size, total: snapshots.size})
            print reset, "\n"
          end
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def import_snapshot(args)
    options = {}
    query_params = {}
    storage_provider_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on("--storage-provider ID", String, "Optional storage provider") do |val|
        storage_provider_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to import a snapshot of the instance '#{instance['name']}'?", options)
        exit 1
      end

      payload = {}

      # Prompt for Storage Provider, use default value.
      begin
        options[:options] ||= {}
        options[:options]['storageProviderId'] = storage_provider_id if storage_provider_id
        storage_provider_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.'}], options[:options], @api_client, {})
        if !storage_provider_prompt['storageProviderId'].to_s.empty?
          payload['storageProviderId'] = storage_provider_prompt['storageProviderId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load storage providers"
        #print_rest_exception(e, options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.import_snapshot(instance['id'], query_params, payload)
        return
      end
      json_response = @instances_interface.import_snapshot(instance['id'], query_params, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot import initiated."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def revert_to_snapshot(args)
    options = {}
    instance = nil
    snapshot_id = nil

    optparse = Morpheus::Cli::OptionParser.new do |opts|
     opts.banner = subcommand_usage("[instance]")
      opts.on("--snapshot ID", String, "Optional snapshot") do |val|
        snapshot_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
           build_standard_add_options(opts, options) #, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Revert an Instance to saved Snapshot previously made." + "\n" +
                    "[snapshotId] is required. This is the id of the snapshot to replace the current instance."
    end
    
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to revert instance '#{instance['name']}'?", options)
        exit 1
      end
      options[:options]['instanceId'] = instance['id']
      begin
        snapshot_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'snapshotId', 'type' => 'select', 'fieldLabel' => 'Snapshot', 'optionSource' => 'instanceSnapshots', 'required' => true, 'description' => 'Select Snapshot.'}], {}, @api_client, options[:options])
      
        if !snapshot_prompt['snapshotId'].to_s.empty?
          snapshot_id = snapshot_prompt['snapshotId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load instance snapshots"
      end
      
      @instances_interface.setopts(options)
 
      payload = {}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.revert_to_snapshot(instance['id'], snapshot_id, payload)
        return
      end
      
      json_response = @instances_interface.revert_to_snapshot(instance['id'], snapshot_id, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot revert initiated."
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_all_container_snapshots(args)
    options = {}
    instance = nil
    container_id = nil

    optparse = Morpheus::Cli::OptionParser.new do |opts|
     opts.banner = subcommand_usage("[instance]")
      opts.on("--container ID", String, "Required container") do |val|
        container_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove all snapshots attached to an instances container." + "\n" +
                    "[containerId] is required. This is the id of the container which removes all attached snapshots."
    end
    
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove all snapshots for a container?", options)
        exit 1
      end
      options[:options]['instanceId'] = instance['id']
      begin
        container_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'containerId', 'type' => 'select', 'fieldLabel' => 'Container', 'optionSource' => 'instanceContainers', 'required' => true, 'description' => 'Select Container.'}], {}, @api_client, options[:options])
        
        if !container_prompt['containerId'].to_s.empty?
          container_id = container_prompt['containerId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load instance containers"
      end
      
      @instances_interface.setopts(options)
 
      payload = {}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_all_container_snapshots(instance['id'], container_id, payload)
        return
      end
      
      json_response = @instances_interface.remove_all_container_snapshots(instance['id'], container_id, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot delete initiated."
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_all_snapshots(args)
    options = {}
    instance = nil

    optparse = Morpheus::Cli::OptionParser.new do |opts|
     opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove all snapshots attached to an instance." + "\n" +
                    "Warning: This will remove all snapshots across all containers of an instance."
    end
    
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove all snapshots for this instance?", options)
        exit 1
      end
      options[:options]['instanceId'] = instance['id']

      @instances_interface.setopts(options)
 
      payload = {}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_all_instance_snapshots(instance['id'], payload)
        return
      end
      
      json_response = @instances_interface.remove_all_instance_snapshots(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshots attached to instance #{instance['name']} queued for deletion."
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def create_linked_clone(args)
    options = {}
    instance = nil
    snapshot_id = nil

    optparse = Morpheus::Cli::OptionParser.new do |opts|
     opts.banner = subcommand_usage("[instance]")
      opts.on("--snapshot ID", String, "Optional snapshot") do |val|
        snapshot_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Create a linked clone using the selected snapshot of an Instance." + "\n" +
                    "[snapshotId] is required. This is the id of the snapshot which the clone will refer to."
    end
    
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      options[:options]['instanceId'] = instance['id']
      begin
        snapshot_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'snapshotId', 'type' => 'select', 'fieldLabel' => 'Snapshot', 'optionSource' => 'instanceSnapshots', 'required' => true, 'description' => 'Select Snapshot.'}], {}, @api_client, options[:options])
      
        if !snapshot_prompt['snapshotId'].to_s.empty?
          snapshot_id = snapshot_prompt['snapshotId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load instance snapshots"
      end
      
      @instances_interface.setopts(options)
 
      payload = {}
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_linked_clone(instance['id'], snapshot_id, payload)
        return
      end
      
      json_response = @instances_interface.create_linked_clone(instance['id'], snapshot_id, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Linked Clone creation initiated."
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def scaling(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Show scaling threshold information for an instance."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} scaling requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _scaling(arg, options)
    end
  end

  def _scaling(arg, options)
    params = {}
    params.merge!(parse_list_options(options))
    instance = find_instance_by_name_or_id(arg)
    return 1 if instance.nil?
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.threshold(instance['id'], params)
      return 0
    end
    json_response = @instances_interface.threshold(instance['id'], params)
    if options[:json]
      puts as_json(json_response, options, "instanceThreshold")
      return 0
    elsif options[:yaml]
      puts as_yaml(json_response, options, "instanceThreshold")
      return 0
    elsif options[:csv]
      puts records_as_csv([json_response['instanceThreshold']], options)
      return 0
    end

    instance_threshold = json_response['instanceThreshold']
    instance_schedules = json_response['instanceSchedules']
    title = "Instance Scaling: [#{instance['id']}] #{instance['name']} (#{instance['instanceType']['name']})"
    print_h1 title, [], options
    if instance_threshold.empty?
      print cyan,"No scaling settings applied to this instance.",reset,"\n"
    else
      # print_h1 "Threshold Settings", [], options
      print cyan
      print_instance_threshold_description_list(instance_threshold)

      if instance_schedules && instance_schedules.size > 0
        print_h2 "Instance Schedules"
        print as_pretty_table(instance_schedules, instance_schedule_list_column_definitions(options).upcase_keys!, options)
      end
    end
    print reset, "\n"
    return 0

  end

  def scaling_update(args)
    print_error "#{yellow}DEPRECATION WARNING: `instances scaling-update` has been renamed to `instances update-scaling`. Please use `instances update-scaling` instead.#{reset}\n"
    update_scaling(args)
  end

  def update_scaling(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_option_type_options(opts, options, update_instance_scaling_option_types)
      build_option_type_options(opts, options, instance_threshold_option_types)
      build_standard_update_options(opts, options)
      opts.footer = "Update scaling threshold settings for an instance."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # load objects
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold'] || {}
    # construct payload
    object_key = 'instanceThreshold'
    payload = parse_payload(options, object_key)
    if !payload
      # payload = {object_key => {}}
      payload = {object_key => parse_passed_options(options, exclude: ['sourceThresholdId'])}
      params = {}
      params.deep_merge! Morpheus::Cli::OptionTypes.prompt(update_instance_scaling_option_types, options[:options], @api_client, {})
      source_threshold_id = params.delete('sourceThresholdId')
      customize_threshold_prompt = true
      params ||= {}
      if source_threshold_id.to_s != '' && source_threshold_id.to_s != 'custom'
        params['sourceThresholdId']= source_threshold_id.to_i
        customize_threshold_prompt = false
      end
      # always parse the threshold options but customize_threshold means prompt also
      my_option_types = instance_threshold_option_types
      if customize_threshold_prompt
        # preserve all current values by setting the prompt options defaultValue attribute
        my_option_types.each do |opt|
          field_key = opt['fieldName']
          if instance_threshold[field_key] != nil
            opt['defaultValue'] = instance_threshold[field_key]
          end
        end
        params.deep_merge! Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, {})
      else
        # preserve current values by setting the prompt options defaultValue attribute
        # only prompt for autoUp and autoDown
        my_option_types.each do |opt|
          field_key = opt['fieldName']
          if ['autoUp','autoDown'].include?(field_key)
            if instance_threshold[field_key] != nil
              opt['defaultValue'] = instance_threshold[field_key]
            end
            opt['noPrompt'] = false
          else
            opt['noPrompt'] = true
          end
        end
        params.deep_merge! Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, {})
      end
      params.booleanize! # convert checkbox "on" and "off" to true and false
      payload[object_key].deep_merge!(params)
    end
    # unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the scaling settings for instance '#{instance['name']}'?", options)
    #   return 9, "aborted command"
    # end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.update_threshold(instance['id'], payload)
      return
    end
    json_response = @instances_interface.update_threshold(instance['id'], payload)
    render_response(json_response, options) do
      print_green_success "Updated scaling settings for instance #{instance['name']}"
      # return _get_inventory(integration, integration_inventory["id"], {}, options)
    end
    return 0, nil
  end

  def list_schedules(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_get_options(opts, options) # build_standard_list_options(opts, options) # phrase,max,etc is not supported
      opts.footer = <<-EOT
List instance scaling threshold schedules.
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    parse_get_options!(args, options, params) # parse_list_options!(args, options, params) # phrase,max,etc is not supported
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.list_schedules(instance['id'], params)
      return 0, nil
    end
    json_response = @instances_interface.list_schedules(instance['id'], params)
    list_key = 'instanceSchedules'
    render_response(json_response, options, list_key) do
      records = json_response[list_key]
      title = "Morpheus Instance Schedules"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if records.nil? || records.empty?
        print cyan,"No schedules found.",reset,"\n"
      else
        print as_pretty_table(records, instance_schedule_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil

  end

  def get_schedule(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance] [schedule]")
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options) # phrase,max,etc is not supported
      opts.footer = <<-EOT
Get details about an instance scaling threshold schedule.
[instance] is required. This is the name or id of an instance
[schedule] is required. This is id of an instance schedule
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    parse_get_options!(args, options, params)
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.list(instance['id'], args[1], params)
      return 0, nil
    end
    json_response = @instances_interface.get_schedule(instance['id'], args[1], params)
    object_key = 'instanceSchedule'
    render_response(json_response, options, object_key) do
      record = json_response[object_key]
      title = "Instance Schedule Details"
      print_h1 title, options
      columns = instance_schedule_column_definitions(options)
      print print_description_list(columns, record, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def add_schedule(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on( '--threshold VALUE', String, "Threshold template to apply scaling settings with. Default is no template (custom)." ) do |val|
      #   options[:threshold] = val
      # end
      build_option_type_options(opts, options, add_instance_schedule_option_types)
      build_option_type_options(opts, options, instance_threshold_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing instance scaling threshold schedule
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    # construct payload
    object_key = 'instanceSchedule'
    payload = parse_payload(options, object_key)
    if !payload
      # payload = {object_key => {}}
      # support -O option but avoid duplicate threshold settings... so -O maxCpu, goes under threshold only
      # could just use options -O threshold.maxCpu instead, which is what the api wants...
      payload = {object_key => parse_passed_options(options, exclude: ['sourceThresholdId'] + instance_threshold_option_types.collect {|i|i['fieldName']})}
      params = {}
      params.deep_merge! Morpheus::Cli::OptionTypes.prompt(add_instance_schedule_option_types, options[:options], @api_client, {})
      source_threshold_id = params.delete('sourceThresholdId')
      customize_threshold_prompt = true
      params['threshold'] ||= {}
      if source_threshold_id.to_s != '' && source_threshold_id.to_s != 'custom'
        #params['threshold']['id']= source_threshold_id
        params['threshold']['sourceThresholdId']= source_threshold_id.to_i
        customize_threshold_prompt = false
      end
      # always parse the threshold options but customize_threshold means prompt also
      if customize_threshold_prompt
        params['threshold'].deep_merge! Morpheus::Cli::OptionTypes.prompt(instance_threshold_option_types, options[:options], @api_client, {})
      else
        params['threshold'].deep_merge! Morpheus::Cli::OptionTypes.no_prompt(instance_threshold_option_types, options[:options], @api_client, {})
      end
      params.booleanize! # convert checkbox "on" and "off" to true and false
      payload[object_key].deep_merge!(params)
      # unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the scaling settings for instance '#{instance['name']}' with the above scaling schedule?", options)
      #   return 9, "aborted command"
      # end
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.create_schedule(instance['id'], payload)
      return 0, nil
    end
    json_response = @instances_interface.create_schedule(instance['id'], payload)
    render_response(json_response, options) do
      print_green_success "Added scaling schedule for instance #{instance['name']}"
      #_scaling(instance['id'], options)
    end
    return 0, nil
  end

  def update_schedule(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance] [schedule]")
      build_option_type_options(opts, options, update_instance_schedule_option_types)
      build_option_type_options(opts, options, instance_threshold_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing instance scaling threshold schedule.
[instance] is required. This is the name or id of an instance
[schedule] is required. This is id of an instance schedule
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1, "Instance not found for '#{args[0]}'" if instance.nil?
    instance_schedule = find_instance_schedule_by_id(instance['id'], args[1])
    return 1, "Instance schedule not found for '#{args[1]}'" if instance_schedule.nil?
    # construct payload
    object_key = 'instanceSchedule'
    payload = parse_payload(options, object_key)
    if !payload
      # payload = {object_key => {}}
      # support -O option but avoid duplicate threshold settings... so -O maxCpu, goes under threshold only
      # could just use options -O threshold.maxCpu instead, which is what the api wants...
      payload = {object_key => parse_passed_options(options, exclude: ['sourceThresholdId'] + instance_threshold_option_types.collect {|i|i['fieldName']})}
      params = {}
      params.deep_merge! Morpheus::Cli::OptionTypes.no_prompt(update_instance_schedule_option_types, options[:options], @api_client, {})
      source_threshold_id = params.delete('sourceThresholdId')
      customize_threshold_prompt = true
      params['threshold'] ||= {}
      if source_threshold_id.to_s != '' && source_threshold_id.to_s != 'custom'
        #params['threshold']['id']= source_threshold_id
        params['threshold']['sourceThresholdId']= source_threshold_id.to_i
        customize_threshold_prompt = false
      end
      params['threshold'].deep_merge! Morpheus::Cli::OptionTypes.no_prompt(instance_threshold_option_types, options[:options], @api_client, {})
      params.booleanize! # convert checkbox "on" and "off" to true and false
      payload[object_key].deep_merge!(params)
      if (payload[object_key].keys - ['threshold']).empty? && payload[object_key]['threshold'].empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      # unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the scaling settings for instance '#{instance['name']}' with the above scaling schedule?", options)
      #   return 9, "aborted command"
      # end
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.update_schedule(instance['id'], instance_schedule['id'], payload)
      return 0, nil
    end
    json_response = @instances_interface.update_schedule(instance['id'], instance_schedule['id'], payload)
    render_response(json_response, options) do
      print_green_success "Updated scaling schedule for instance #{instance['name']}"
      #_scaling(instance['id'], options)
    end
    return 0, nil
  end

  def remove_schedule(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [schedule]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing instance scaling threshold schedule
[instance] is required. This is the name or id of an instance
[schedule] is required. This is id of an instance schedule
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    params.merge!(parse_query_options(options))
    instance = find_instance_by_name_or_id(args[0])
    return 1, "Instance not found for '#{args[0]}'" if instance.nil?
    instance_schedule = find_instance_schedule_by_id(instance['id'], args[1])
    return 1, "Instance schedule not found for '#{args[1]}'" if instance_schedule.nil?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the instance schedule #{instance_schedule['id']}?")
      return 9, "aborted"
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.destroy_schedule(instance['id'], instance_schedule['id'], params)
      return 0, nil
    end
    json_response = @instances_interface.destroy_schedule(instance['id'], instance_schedule['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed instance schedule #{instance_schedule['id']}"
    end
    return 0, nil
  end

  def load_balancer_update(args)
    raise "Not Yet Implemented"
    usage = "Usage: morpheus instances lb-update [instance] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      #build_option_type_options(opts, options, instance_load_balancer_option_types(nil))
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Assign a load balancer for an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-update requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # refetch to get loadBalancers from show()
      json_response = @instances_interface.get(instance['id'])

      current_instance_lb = nil
      # refetch to get current load balancer info from show()
      json_response = @instances_interface.get(instance['id'])
      #load_balancers = @instances_interface.threshold(instance['id'])['loadBalancers'] || {}
      if json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      #my_option_types = instance_load_balancer_option_types(instance)

      # todo...

      # Host Name
      # Load Balancer
      # Protocol
      # Port
      # SSL Cert
      # Scheme

      current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]

      params = {}
  
      payload = {
        'instance' => {},
        'networkLoadBalancer' => {}
      }

      cur_host_name = instance['hostName']
      #host_name = params = Morpheus::Cli::OptionTypes.prompt([{'fieldName'=>'hostName', 'label'=>'Host Name', 'defaultValue'=>cur_host_name}], options[:options], @api_client, {})
      payload['instance']['hostName'] = instance['hostName']

      #payload['loadBalancerId'] = params['loadBalancerId']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.update_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated scaling settings for instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def load_balancer_remove(args)
    usage = "Usage: morpheus instances lb-remove [instance] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove a load balancer from an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-remove requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      # re-fetch via show() get loadBalancers
      json_response = @instances_interface.get(instance['id'])
      load_balancers = json_response['instance']['loadBalancers']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      
      # no options here, just send DELETE request
      payload = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.remove_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Removed load balancer from instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history(args)
    raw_args = args.dup
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on( '-n', '--node NODE_ID', "Scope history to specific Container or VM" ) do |node_id|
      #   options[:node_id] = node_id.to_i
      # end
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      opts.on('--process-id ID', String, "Display details about a specfic process only." ) do |val|
        options[:process_id] = val
      end
      opts.on('--event-id ID', String, "Display details about a specfic process event only." ) do |val|
        options[:event_id] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes for a specific instance.\n" + 
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)

    # shortcut to other actions
    if options[:process_id]
      return history_details(raw_args)
    elsif options[:event_id]
      return history_event_details(raw_args)
    end

    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      # container_ids = instance['containers']
      # if options[:node_id] && container_ids.include?(options[:node_id])
      #   container_ids = [options[:node_id]]
      # end
      params = {}
      params.merge!(parse_list_options(options))
      # params['query'] = params.delete('phrase') if params['phrase']
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history(instance['id'], params)
        return
      end
      json_response = @instances_interface.history(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options, "processes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processes'], options)
        return 0
      else

        title = "Instance History: #{instance['name']}"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if json_response['processes'].empty?
          print "#{cyan}No process history found.#{reset}\n\n"
        else
          history_records = []
          json_response["processes"].each do |process|
            row = {
              id: process['id'],
              eventId: nil,
              uniqueId: process['uniqueId'],
              name: process['displayName'],
              description: process['description'],
              processType: process['processType'] ? (process['processType']['name'] || process['processType']['code']) : process['processTypeName'],
              createdBy: process['createdBy'] ? (process['createdBy']['displayName'] || process['createdBy']['username']) : '',
              startDate: format_local_dt(process['startDate']),
              duration: format_process_duration(process),
              status: format_process_status(process),
              error: format_process_error(process, options[:details] ? nil : 20),
              output: format_process_output(process, options[:details] ? nil : 20)
            }
            history_records << row
            process_events = process['events'] || process['processEvents']
            if options[:show_events]
              if process_events
                process_events.each do |process_event|
                  event_row = {
                    id: process['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event, options[:details] ? nil : 20),
                    output: format_process_output(process_event, options[:details] ? nil : 20)
                  }
                  history_records << event_row
                end
              else
                
              end
            end
          end
          columns = [
            {:id => {:display_name => "PROCESS ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error
          ]
          if options[:show_events]
            columns.insert(1, {:eventId => {:display_name => "EVENT ID"} })
          end
          if options[:show_output]
            columns << :output
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(history_records, columns, options)
          #print_results_pagination(json_response)
          print_results_pagination(json_response, {:label => "process", :n_label => "processes"})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_details(args)
    options = {}
    process_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [process-id]")
      opts.on('--process-id ID', String, "Display details about a specfic event." ) do |val|
        options[:process_id] = val
      end
      opts.add_hidden_option('--process-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[process-id] is required. This is the id of the process."
    end
    optparse.parse!(args)
    if args.count == 2
      process_id = args[1]
    elsif args.count == 1 && options[:process_id]
      process_id = options[:process_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_details(instance['id'], process_id, params)
        return
      end
      json_response = @instances_interface.history_details(instance['id'], process_id, params)
      if options[:json]
        puts as_json(json_response, options, "process")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "process")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['process'], options)
        return 0
      else
        process = json_response["process"]
        title = "Instance History Details"
        subtitles = []
        subtitles << " Process ID: #{process_id}"
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_details(process, options)
  
        print_h2 "Process Events", options
        process_events = process['events'] || process['processEvents'] || []
        history_records = []
        if process_events.empty?
          puts "#{cyan}No events found.#{reset}"
        else      
          process_events.each do |process_event|
            event_row = {
                    id: process_event['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event),
                    output: format_process_output(process_event)
                  }
            history_records << event_row
          end
          columns = [
            {:id => {:display_name => "EVENT ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error,
            :output
          ]
          print cyan
          print as_pretty_table(history_records, columns, options)
          print_results_pagination({size: process_events.size, total: process_events.size})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_event_details(args)
    options = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [event-id]")
      opts.on('--event-id ID', String, "Display details about a specfic event." ) do |val|
        options[:event_id] = val
      end
      opts.add_hidden_option('--event-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process event.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[event-id] is required. This is the id of the process event."
    end
    optparse.parse!(args)
    if args.count == 2
      process_event_id = args[1]
    elsif args.count == 1 && options[:event_id]
      process_event_id = options[:event_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_event_details(instance['id'], process_event_id, params)
        return
      end
      json_response = @instances_interface.history_event_details(instance['id'], process_event_id, params)
      if options[:json]
        puts as_json(json_response, options, "processEvent")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processEvent")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processEvent'], options)
        return 0
      else
        process_event = json_response['processEvent'] || json_response['event']
        title = "Instance History Event"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_event_details(process_event, options)
        print reset, "\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
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
        if File.exist?(full_filename)
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
      opts.footer = "Execute an arbitrary script or command on an instance." + "\n" +
                    "[id] is required. This is the id or name of an instance." + "\n" +
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
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      params['instanceId'] = instance['id']
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
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId'], "--refresh"]+ (options[:remote] ? ["-r",options[:remote]] : []))
      else
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId']]+ (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def deploys(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List deployments for an instance.
[instance] is required. This is the name or id of an instance
[search] is optional. Filters on deployment version identifier
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    if args.count > 1
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    # @deploy_interface.setopts(options)
    # if options[:dry_run]
    #   print_dry_run @deploy_interface.dry.list(instance['id'], params)
    #   return
    # end
    # json_response = @deploy_interface.list(instance['id'], params)

    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.deploys(instance['id'], params)
      return
    end
    json_response = @instances_interface.deploys(instance['id'], params)

    app_deploys = json_response['appDeploys']
    render_response(json_response, options, 'appDeploys') do
      print_h1 "Instance Deploys", ["#{instance['name']}"] + parse_list_subtitles(options), options
      if app_deploys.empty?
        print cyan,"No deployments found.",reset,"\n"
      else
        print as_pretty_table(app_deploys, app_deploy_column_definitions.upcase_keys!, options)
        if json_response['meta']
          print_results_pagination(json_response)
        else
          print_results_pagination({size:app_deploys.size,total:app_deploys.size.to_i})
        end

      end
      print reset,"\n"
    end
    return 0
  end

  def clone_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '--name VALUE', String, "Image Name (Template Name). Default is server name + timestamp" ) do |val|
        options[:options]['templateName'] = val
      end
      opts.on( '--folder VALUE', String, "Folder externalId or '/' to use the root folder" ) do |val|
        options[:options]['zoneFolder'] = val
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Clone to image (template) for an instance
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    # need to GET provision type for hasFolders
    provision_type_code = instance['layout']['provisionTypeCode'] rescue nil
    provision_type = nil
    if provision_type_code
      provision_type = provision_types_interface.list({code:provision_type_code})['provisionTypes'][0]
      if provision_type.nil?
        print_red_alert "Provision Type not found by code #{provision_type_code}"
        exit 1
      end
    else
      provision_type = get_provision_type_for_zone_type(cloud['zoneType']['id'])
    end
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
      if payload['templateName'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'templateName', 'type' => 'text', 'fieldLabel' => 'Image Name', 'description' => 'Choose a name for the new image template. Default is the server name + timestamp'}], options[:options])
        if v_prompt['templateName'].to_s != ''
          payload['templateName'] = v_prompt['templateName']
        end
      end
      #if instance['layout']['provisionTypeCode'] == 'vmware'
      if provision_type && provision_type["hasFolders"]
        if payload['zoneFolder'].nil?
          # vmwareFolders moved from /api/options/vmwareFolders to /api/options/vmware/vmwareFolders
          folder_prompt = nil
          begin
            folder_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zoneFolder', 'type' => 'select', 'optionSource' => 'vmwareFolders', 'optionSourceType' => 'vmware', 'fieldLabel' => 'Folder', 'description' => "Folder externalId or '/' to use the root folder", 'required' => true}], options[:options], @api_client, {siteId: instance['group']['id'], zoneId: instance['cloud']['id']})
          rescue RestClient::Exception => e
            Morpheus::Logging::DarkPrinter.puts "Failed to load folder options" if Morpheus::Logging.debug?
            begin
              folder_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zoneFolder', 'type' => 'select', 'optionSource' => 'vmwareFolders', 'fieldLabel' => 'Folder', 'description' => "Folder externalId or '/' to use the root folder", 'required' => true}], options[:options], @api_client, {siteId: instance['group']['id'], zoneId: instance['cloud']['id']})
            rescue RestClient::Exception => e2
              Morpheus::Logging::DarkPrinter.puts "Failed to load folder options from alternative endpoint too" if Morpheus::Logging.debug?
            end
          end
          if folder_prompt && folder_prompt['zoneFolder'].to_s != ''
            payload['zoneFolder'] = folder_prompt['zoneFolder']
          end
        end
      end
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.clone_image(instance['id'], payload)
      return
    end
    json_response = @instances_interface.clone_image(instance['id'], payload)
    render_response(json_response, options) do
      print_green_success "Clone Image initiated."
    end
    return 0, nil
  end

  def lock(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Lock an instance
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.lock(instance['id'], payload)
      return
    end
    json_response = @instances_interface.lock(instance['id'], payload)
    render_response(json_response, options) do
      print_green_success "Locked instance #{instance['name']}"
    end
    return 0, nil
  end

  def unlock(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Unlock an instance
[instance] is required. This is the name or id of an instance
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
    end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.unlock(instance['id'], payload)
      return
    end
    json_response = @instances_interface.unlock(instance['id'], payload)
    render_response(json_response, options) do
      print_green_success "Unlocked instance #{instance['name']}"
    end
    return 0, nil
  end

  def refresh(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Refresh an instance.
[instance] is required. This is the name or id of an instance.
This is only supported by certain types of instances such as terraform.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # construct request
      params.merge!(parse_query_options(options))
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        # raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to refresh this instance: #{instance['name']}?")
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.refresh(instance["id"], params, payload)
        return
      end
      json_response = @instances_interface.refresh(instance["id"], params, payload)
      render_response(json_response, options) do
        print_green_success "Refreshing instance #{instance['name']}"
        # return _get(instance['id'], options)
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def prepare_apply(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Prepare to apply an instance.
[instance] is required. This is the name or id of an instance.
Displays the current configuration data used by the apply command.
This is only supported by certain types of instances such as terraform.
      EOT
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # construct request
      params.merge!(parse_query_options(options))
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        # raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.prepare_apply(instance["id"], params)
        return
      end
      json_response = @instances_interface.prepare_apply(instance["id"], params)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      # print_green_success "Prepared to apply instance: #{instance['name']}"
      print_h1 "Prepared Instance: #{instance['name']}"
      instance_config = json_response['data'] 
      # instance_config = json_response if instance_config.nil?
      puts as_yaml(instance_config, options)
      #return get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      print "\n", reset
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply(args)
    default_refresh_interval = 5
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      opts.on( '-p', '--parameter NAME=VALUE', "Template parameter name and value" ) do |val|
        k, v = val.split("=")
        options[:options]['templateParameter'] ||= {}
        options[:options]['templateParameter'][k] = v
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      opts.on(nil, '--no-validate', "Do not validate planned changes before apply" ) do
        options[:no_validate] = true
      end
      opts.on(nil, '--validate-only', "Only validate planned changes, do not execute the apply command." ) do
        options[:validate_only] = true
      end
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Apply an instance.
[instance] is required. This is the name or id of an instance.
This is only supported by certain types of instances such as terraform.
By default this executes two requests to validate and then apply the changes.
The first request corresponds to the terraform plan command only.
Use --no-validate to skip this step apply changes in one step.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    # construct request
    params.merge!(parse_query_options(options))
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
      # attempt to load prepare-apply to get templateParameter values and prompt for them
      # ok, actually use options/layoutParameters to get the list of parameters
      begin
        prepare_apply_json_response = @instances_interface.prepare_apply(instance["id"])
        config = prepare_apply_json_response['data']
        variable_map = config['templateParameter']
        api_params = {layoutId: instance['layout']['id'], instanceId: instance['id'], zoneId: instance['cloud']['id'], siteId: instance['group']['id']}
        layout_parameters = @options_interface.options_for_source('layoutParameters',api_params)['data']

        if layout_parameters && !layout_parameters.empty?
          variable_option_types = []
          i = 0
          layout_parameters.each do |layout_parameter|
            var_label = layout_parameter['displayName'] || layout_parameter['name']
            var_name = layout_parameter['name']
            var_value = variable_map ? variable_map[var_name] : layout_parameter['defaultValue']
            if var_value.nil? && layout_parameter['defaultValue']
              var_value = layout_parameter['defaultValue']
            end
            var_type = (layout_parameter['passwordType'] || layout_parameter['sensitive']) ? 'password' : 'text'
            option_type = {'fieldContext' => 'templateParameter', 'fieldName' => var_name, 'fieldLabel' => var_label, 'type' => var_type, 'required' => true, 'defaultValue' => (var_value.to_s.empty? ? nil : var_value.to_s), 'displayOrder' => (i+1) }
            variable_option_types << option_type
            i+=1
          end
          blueprint_type_display = format_blueprint_type(instance['layout']['provisionTypeCode'])
          if blueprint_type_display == "terraform"
            blueprint_type_display = "Terraform"
          end
          print_h2 "#{blueprint_type_display} Variables"
          v_prompt = Morpheus::Cli::OptionTypes.prompt(variable_option_types, options[:options], @api_client)
          v_prompt.deep_compact!
          payload.deep_merge!(v_prompt)
        end
      rescue RestClient::Exception => ex
        # if e.response && e.response.code == 404
        Morpheus::Logging::DarkPrinter.puts "Unable to load config for instance apply, skipping parameter prompting" if Morpheus::Logging.debug?
        # print_rest_exception(ex, options)
        # end
      end
    end

    @instances_interface.setopts(options)
    if options[:validate_only]
      # validate only
      if options[:dry_run]
        print_dry_run @instances_interface.dry.validate_apply(instance["id"], params, payload)
        return
      end
      json_response = @instances_interface.validate_apply(instance["id"], params, payload)
      print_green_success "Validating instance #{instance['name']}"
      execution_id = json_response['executionId']
      if !options[:no_refresh]
        #Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_id, "--refresh", options[:refresh_interval].to_s]+ (options[:remote] ? ["-r",options[:remote]] : []))
        validate_execution_request = wait_for_execution_request(execution_id, options)
      end
    elsif options[:no_validate]
      # skip validate, apply only
      if options[:dry_run]
        print_dry_run @instances_interface.dry.apply(instance["id"], params, payload)
        return
      end
      json_response = @instances_interface.apply(instance["id"], params, payload)
      render_response(json_response, options) do
        print_green_success "Applying instance #{instance['name']}"
        execution_id = json_response['executionId']        
        if !options[:no_refresh]
          #Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_id, "--refresh", options[:refresh_interval].to_s]+ (options[:remote] ? ["-r",options[:remote]] : []))
          apply_execution_request = wait_for_execution_request(execution_id, options)
        end
      end
    else
      # validate and then apply
      if options[:dry_run]
        print_dry_run @instances_interface.dry.validate_apply(instance["id"], params, payload)
        print_dry_run @instances_interface.dry.apply(instance["id"], params, payload)
        return
      end
      json_response = @instances_interface.validate_apply(instance["id"], params, payload)
      print_green_success "Validating instance #{instance['name']}"
      execution_id = json_response['executionId']
      validate_execution_request = wait_for_execution_request(execution_id, options)
      if validate_execution_request['status'] != 'complete'
        print_red_alert "Validation failed. Changes will not be applied."
        return 1, "Validation failed. Changes will not be applied."
      else
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to apply these changes?")
          return 9, "aborted command"
        end
        json_response = @instances_interface.apply(instance["id"], params, payload)
        render_response(json_response, options) do
          print_green_success "Applying instance #{instance['name']}"
          execution_id = json_response['executionId']        
          if !options[:no_refresh]
            #Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_id, "--refresh", options[:refresh_interval].to_s]+ (options[:remote] ? ["-r",options[:remote]] : []))
            apply_execution_request = wait_for_execution_request(execution_id, options)
          end
        end
      end
    end
    return 0, nil
  end

  def state(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
      opts.on('--data', "Display State Data") do
        options[:include_state_data] = true
      end
      opts.on('--specs', "Display Spec Templates") do
        options[:include_spec_templates] = true
      end
      opts.on('--plan', "Display Plan Data") do
        options[:include_plan_data] = true
      end
      opts.on('--input', "Display Input") do
        options[:include_input] = true
      end
      opts.on('--output', "Display Output") do
        options[:include_output] = true
      end
      opts.on('-a','--all', "Display All Details") do
        options[:include_state_data] = true
        options[:include_spec_templates] = true
        options[:include_plan_data] = true
        options[:include_input] = true
        options[:include_output] = true
        options[:details] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View state of an instance.
[instance] is required. This is the name or id of an instance.
This is only supported by certain types of apps such as terraform.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
    # construct request
    params.merge!(parse_query_options(options))
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.state(instance["id"], params)
      return
    end
    json_response = @instances_interface.state(instance["id"], params)
    render_result = render_with_format(json_response, options)
    return 0 if render_result
    print_h1 "Instance State: #{instance['name']}", options
    # print_h2 "Workloads", options
    if json_response['workloads'] && !json_response['workloads'].empty?
      workload_columns = {
        "Name" => lambda {|it| it['subRefName'].to_s.empty? ? "#{it['refName']}" : "#{it['refName']} - #{it['subRefName']}" },
        "Last Check" => lambda {|it| format_local_dt(it['stateDate']) },
        "Status" => lambda {|it| format_ok_status(it['status'] || 'ok') },
        "Drift Status" => lambda {|it| it['iacDrift'] ? "Drift" : "No Drift" }
      }
      print as_pretty_table(json_response['workloads'], workload_columns.upcase_keys!, options)
    else
      print cyan,"No workloads found.",reset,"\n"
    end
    if options[:include_state_data]
      print_h2 "State Data", options
      puts json_response['stateData']
    end
    if options[:include_spec_templates]
      print_h2 "Spec Templates", options
      spec_templates_columns = {
        "Resource Spec" => lambda {|it| it['name'] || (it['template'] ? it['template']['name'] : nil) },
        "Attached to Source Template" => lambda {|it| format_boolean(!it['isolated']) },
        "Source Spec Template" => lambda {|it| (it['template'] ? it['template']['name'] : nil) || it['name'] }
      }
      print as_pretty_table(json_response['specs'], spec_templates_columns.upcase_keys!, options)
      # print "\n", reset
    end
    if options[:include_plan_data]
      # print_h2 "Plan Data", options
      if instance['type'] == 'terraform' || instance['layout']['provisionTypeCode'] == 'terraform'
        print_h2 "Terraform Plan", options
      else
        print_h2 "Plan Data", options
      end
      puts json_response['planData']
      # print "\n", reset
    end
    if options[:include_input]
      # print_h2 "Input"
      if json_response['input'] && json_response['input']['variables']
        print_h2 "VARIABLES", options
        input_variable_columns = {
          "Name" => lambda {|it| it['name'] },
          "Value" => lambda {|it| it['value'] }
        }
        print as_pretty_table(json_response['input']['variables'], input_variable_columns.upcase_keys!, options)
      end
      if json_response['input'] && json_response['input']['providers']
        print_h2 "PROVIDERS", options
        input_provider_columns = {
          "Name" => lambda {|it| it['name'] }
        }
        print as_pretty_table(json_response['input']['providers'], input_provider_columns.upcase_keys!, options)
      end
      if json_response['input'] && json_response['input']['data']
        print_h2 "DATA", options
        input_data_columns = {
          "Type" => lambda {|it| it['type'] },
          "Key" => lambda {|it| it['key'] },
          "Name" => lambda {|it| it['name'] }
        }
        print as_pretty_table(json_response['input']['data'], input_data_columns.upcase_keys!, options)
      end
      # print "\n", reset
    end
    if options[:include_output]
      # print_h2 "Output", options
      if json_response['output'] && json_response['output']['outputs']
        print_h2 "OUTPUTS", options
        input_variable_columns = {
          "Name" => lambda {|it| it['name'] },
          "Value" => lambda {|it| it['value'] }
        }
        print as_pretty_table(json_response['output']['outputs'], input_variable_columns.upcase_keys!, options)
      end
      # print "\n", reset
    end
    print "\n", reset
    return 0
  end

private

  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      clouds = get_available_clouds(group_id)
      zone = clouds.find {|it| it['id'] == val.to_i }
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      clouds = get_available_clouds(group_id)
      zone = clouds.find {|it| it['name'] == val.to_s }
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end

  def find_host_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Host not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_host_by_name(name)
    results = @servers_interface.list({name: name})
    if results['servers'].empty?
      print_red_alert "Host not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple hosts exist with the name #{name}. Try using id instead"
      exit 1
    end
    return results['servers'][0]
  end

  def find_host_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_host_by_id(val)
    else
      return find_host_by_name(val)
    end
  end

  def find_workflow_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_workflow_by_id(val)
    else
      return find_workflow_by_name(val)
    end
  end

  def find_workflow_by_id(id)
    begin
      json_response = @task_sets_interface.get(id.to_i)
      return json_response['taskSet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Workflow not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_workflow_by_name(name)
    workflows = @task_sets_interface.list({name: name.to_s})['taskSets']
    if workflows.empty?
      print_red_alert "Workflow not found by name #{name}"
      exit 1
    elsif workflows.size > 1
      print_red_alert "#{workflows.size} workflows by name #{name}"
      print_workflows_table(workflows, {color: red})
      print reset,"\n\n"
      exit 1
    else
      return workflows[0]
    end
  end

  def update_instance_scaling_option_types()
    [
      {'code' => 'sourceThresholdId', 'switch' => 'threshold', 'fieldName' => 'sourceThresholdId', 'fieldLabel' => 'Threshold', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        [{'name' => 'Custom', 'value' => 'custom'}] + api_client.options.options_for_source('instanceThresholdTemplates')['data'] rescue []
      }, 'description' => "Threshold template to use as source for scaling threshold settings.", 'defaultValue' => 'custom', 'required' => true}, #, 'required' => true, 'defaultValue' => ''},
      # {'fieldName' => 'autoUp', 'fieldLabel' => 'Auto Upscale', 'type' => 'checkbox', 'description' => 'Enable auto upscaling'},
      # {'fieldName' => 'autoDown', 'fieldLabel' => 'Auto Downscale', 'type' => 'checkbox', 'description' => 'Enable auto downscaling'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'minCount', 'fieldLabel' => 'Min Count', 'type' => 'number', 'description' => 'Minimum number of nodes'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'maxCount', 'fieldLabel' => 'Max Count', 'type' => 'number', 'description' => 'Maximum number of nodes'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'cpuEnabled', 'fieldLabel' => 'Enable CPU Threshold', 'type' => 'checkbox', 'description' => 'Scale when CPU thresholds are met.'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'minCpu', 'fieldLabel' => 'Min CPU', 'type' => 'number', 'description' => 'Minimum CPU percent (0-100)'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'maxCpu', 'fieldLabel' => 'Max CPU', 'type' => 'number', 'description' => 'Maximum CPU percent (0-100)'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'memoryEnabled', 'fieldLabel' => 'Enable Memory Threshold', 'type' => 'checkbox', 'description' => 'Scale when memory thresholds are met.'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory', 'type' => 'number', 'description' => 'Minimum memory percent (0-100)'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory', 'type' => 'number', 'description' => 'Maximum memory percent (0-100)'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'diskEnabled', 'fieldLabel' => 'Enable Disk Threshold', 'type' => 'checkbox', 'description' => 'Scale when storage thresholds are met.'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'minDisk', 'fieldLabel' => 'Min Disk', 'type' => 'number', 'description' => 'Minimum storage percent (0-100)'},
      # {'dependsOnCode' => 'sourceThresholdId:custom', 'fieldName' => 'maxDisk', 'fieldLabel' => 'Max Disk', 'type' => 'number', 'description' => 'Maximum storage percent (0-100)'},
    ]
  end

  def instance_load_balancer_option_types(instance=nil)
    list = []
    list << {'fieldContext' => 'instance', 'fieldName' => 'hostName', 'fieldLabel' => 'Host Name', 'type' => 'checkbox', 'description' => 'Enable auto upscaling', 'required' => true, 'defaultValue' => instance ? instance['hostName'] : nil}
    list << {'fieldName' => 'proxyProtocol', 'fieldLabel' => 'Protocol', 'type' => 'checkbox', 'description' => 'Enable auto downscaling', 'required' => true, 'defaultValue' => false}
    list
  end

  def print_instance_threshold_description_list(instance_threshold)
    description_cols = {
      # "Instance" => lambda {|it| "#{instance['id']} - #{instance['name']}" },
      "Auto Upscale" => lambda {|it| format_boolean(it['autoUp']) },
      "Auto Downscale" => lambda {|it| format_boolean(it['autoDown']) },
      #"Cloud" => lambda {|it| it['zoneId'] ? "#{it['zoneId']}" : 'Use Scale Priority' },
      "Min Count" => lambda {|it| it['minCount'] },
      "Max Count" => lambda {|it| it['maxCount'] },
      "Memory Enabled" => lambda {|it| format_boolean(it['memoryEnabled']) },
      "Min Memory" => lambda {|it| it['memoryEnabled'] ? (it['minMemory'] ? "#{it['minMemory']}%" : '') : '' },
      "Max Memory" => lambda {|it| it['memoryEnabled'] ? (it['maxMemory'] ? "#{it['maxMemory']}%" : '') : '' },
      "Disk Enabled" => lambda {|it| format_boolean(it['diskEnabled']) },
      "Min Disk" => lambda {|it| it['diskEnabled'] ? (it['minDisk'] ? "#{it['minDisk']}%" : '') : '' },
      "Max Disk" => lambda {|it| it['diskEnabled'] ? (it['maxDisk'] ? "#{it['maxDisk']}%" : '') : '' },
      "CPU Enabled" => lambda {|it| format_boolean(it['cpuEnabled']) },
      "Min CPU" => lambda {|it| it['cpuEnabled'] ? (it['minCpu'] ? "#{it['minCpu']}%" : '') : '' },
      "Max CPU" => lambda {|it| it['cpuEnabled'] ? (it['maxCpu'] ? "#{it['maxCpu']}%" : '') : '' },
      # "Iops Enabled" => lambda {|it| format_boolean(it['iopsEnabled']) },
      # "Min Iops" => lambda {|it| it['minIops'] },
      # "Max Iops" => lambda {|it| it['maxDisk'] },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
    print_description_list(description_cols, instance_threshold)
  end

  def instance_schedule_column_definitions(options)
    {
      "ID" => lambda {|it| it['id'] },
      "Start" => lambda {|it| it['startDisplay'] },
      "End" => lambda {|it| it['endDisplay'] },
      "Auto Upscale" => lambda {|it| format_boolean(it['threshold']['autoUp']) rescue nil },
      "Auto Downscale" => lambda {|it| format_boolean(it['threshold']['autoDown']) rescue nil },
      "Min Count" => lambda {|it| it['threshold']['minCount'] rescue nil },
      "Max Count" => lambda {|it| it['threshold']['maxCount'] rescue nil },
      "Enable CPU Threshold" => lambda {|it| format_boolean(it['threshold']['cpuEnabled']) rescue nil },
      "Min CPU" => lambda {|it| format_percent(it['threshold']['minCpu'], 9, true) rescue nil },
      "Max CPU" => lambda {|it| format_percent(it['threshold']['maxCpu'], 9, true) rescue nil },
      "Enable Memory Threshold" => lambda {|it| format_boolean(it['threshold']['memoryEnabled']) rescue nil },
      "Min Memory" => lambda {|it| format_percent(it['threshold']['minMemory'], 9, true) rescue nil },
      "Max Memory" => lambda {|it| format_percent(it['threshold']['maxMemory'], 9, true) rescue nil },
      "Enable Disk Threshold" => lambda {|it| format_boolean(it['threshold']['diskEnabled']) rescue nil },
      "Min Disk" => lambda {|it| format_percent(it['threshold']['minDisk'], 9, true) rescue nil },
      "Max Disk" => lambda {|it| format_percent(it['threshold']['maxDisk'], 9, true) rescue nil },
    }
  end

  def instance_schedule_list_column_definitions(options)
    instance_schedule_column_definitions(options)
  end

  def find_instance_schedule_by_id(instance_id, id)
    begin
      json_response = @instances_interface.get_schedule(instance_id, id)
      return json_response['instanceSchedule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance Schedule not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def day_of_week_dropdown()
    [
      {'name' => 'Sunday', 'value' => 1},
      {'name' => 'Monday', 'value' => 2},
      {'name' => 'Tuesday', 'value' => 3},
      {'name' => 'Wednesday', 'value' => 4},
      {'name' => 'Thursday', 'value' => 5},
      {'name' => 'Friday', 'value' => 6},
      {'name' => 'Saturday', 'value' => 7}
    ]
  end

  def add_instance_schedule_option_types()
    [
      {'code' => 'scheduleType', 'fieldName' => 'scheduleType', 'fieldLabel' => 'Schedule Type', 'type' => 'select', 'selectOptions' => [{'name'=>'Day Of Week', 'value'=>'dayOfWeek'},{'name'=>'Exact', 'value'=>'exact'}], 'description' => "Schedule type  can be recurring day of the week str or exact start and end timestamp", 'required' => true, 'defaultValue' => 'dayOfWeek'},
      {'dependsOnCode' => 'scheduleType:dayOfWeek', 'fieldName' => 'scheduleTimezone', 'fieldLabel' => 'Timezone', 'type' => 'select', 'optionSource' => 'timezones' , 'description' => "The timezone", 'defaultValue' => "UTC", 'required' => false},
      {'dependsOnCode' => 'scheduleType:dayOfWeek', 'fieldName' => 'startDayOfWeek', 'fieldLabel' => 'Start Day Of Week', 'type' => 'select', 'selectOptions' => day_of_week_dropdown, 'description' => "Start day of the week Sunday-Saturday (1-7)", 'defaultValue' => "Sunday", 'required' => true},
      {'dependsOnCode' => 'scheduleType:dayOfWeek', 'fieldName' => 'startTime', 'fieldLabel' => 'Start Time (HH:MM)', 'type' => 'text', 'description' => "Start time in HH:MM 24-hour format", 'placeHolder' => 'HH:MM', 'defaultValue' => "01:00", 'required' => true},
      {'dependsOnCode' => 'scheduleType:dayOfWeek', 'fieldName' => 'endDayOfWeek', 'fieldLabel' => 'End Day Of Week', 'type' => 'select', 'selectOptions' => day_of_week_dropdown, 'description' => "End day of the week Sunday-Saturday (1-7)", 'defaultValue' => "Sunday", 'required' => true},
      {'dependsOnCode' => 'scheduleType:dayOfWeek', 'fieldName' => 'endTime', 'fieldLabel' => 'End Time (HH:MM)', 'type' => 'text', 'description' => "End time in HH:MM 24-hour format", 'placeHolder' => 'HH:MM', 'defaultValue' => "01:00", 'required' => true},
      {'dependsOnCode' => 'scheduleType:exact', 'fieldName' => 'startDate', 'fieldLabel' => 'Start Date', 'type' => 'text', 'description' => "Exact start date timestamp in standard iso8601 format", 'placeHolder' => 'YYYY-MM-DD', 'required' => true},
      {'dependsOnCode' => 'scheduleType:exact', 'fieldName' => 'endDate', 'fieldLabel' => 'End Date', 'type' => 'text', 'description' => "Exact end date timestamp in standard iso8601 format", 'placeHolder' => 'YYYY-MM-DD', 'required' => true},
      {'switch' => 'threshold', 'fieldName' => 'sourceThresholdId', 'fieldLabel' => 'Threshold', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        [{'name' => 'Custom', 'value' => 'custom'}] + api_client.options.options_for_source('instanceThresholdTemplates')['data'] # rescue []
      }, 'description' => "Threshold template to use as source for scaling threshold settings.", 'defaultValue' => 'custom', 'required' => true}, #, 'required' => true, 'defaultValue' => ''},
    ]
  end

  def update_instance_schedule_option_types()
    option_types = add_instance_schedule_option_types.collect {|it| it.delete('required'); it.delete('defaultValue'); it.delete('dependsOnCode'); it }
    #option_types.reject! {|it| it['fieldName'] == 'sourceThresholdId' }
    option_types
  end

  def instance_threshold_option_types()
    [
      {'fieldName' => 'autoUp', 'fieldLabel' => 'Auto Upscale', 'type' => 'checkbox', 'description' => 'Enable auto upscaling'},
      {'fieldName' => 'autoDown', 'fieldLabel' => 'Auto Downscale', 'type' => 'checkbox', 'description' => 'Enable auto downscaling'},
      {'fieldName' => 'minCount', 'fieldLabel' => 'Min Count', 'type' => 'number', 'description' => 'Minimum number of nodes'},
      {'fieldName' => 'maxCount', 'fieldLabel' => 'Max Count', 'type' => 'number', 'description' => 'Maximum number of nodes'},
      {'fieldName' => 'cpuEnabled', 'fieldLabel' => 'Enable CPU Threshold', 'type' => 'checkbox', 'description' => 'Scale when CPU thresholds are met.'},
      {'fieldName' => 'minCpu', 'fieldLabel' => 'Min CPU', 'type' => 'number', 'description' => 'Minimum CPU percent (0-100)'},
      {'fieldName' => 'maxCpu', 'fieldLabel' => 'Max CPU', 'type' => 'number', 'description' => 'Maximum CPU percent (0-100)'},
      {'fieldName' => 'memoryEnabled', 'fieldLabel' => 'Enable Memory Threshold', 'type' => 'checkbox', 'description' => 'Scale when memory thresholds are met.'},
      {'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory', 'type' => 'number', 'description' => 'Minimum memory percent (0-100)'},
      {'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory', 'type' => 'number', 'description' => 'Maximum memory percent (0-100)'},
      {'fieldName' => 'diskEnabled', 'fieldLabel' => 'Enable Disk Threshold', 'type' => 'checkbox', 'description' => 'Scale when storage thresholds are met.'},
      {'fieldName' => 'minDisk', 'fieldLabel' => 'Min Disk', 'type' => 'number', 'description' => 'Minimum storage percent (0-100)'},
      {'fieldName' => 'maxDisk', 'fieldLabel' => 'Max Disk', 'type' => 'number', 'description' => 'Maximum storage percent (0-100)'},
    ]
  end
  
  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

  def app_deploy_column_definitions
    {
      "ID" => 'id',
      "Deployment" => lambda {|it| it['deployment']['name'] rescue '' },
      "Version" => lambda {|it| (it['deploymentVersion']['userVersion'] || it['deploymentVersion']['version']) rescue '' },
      "Deploy Date" => lambda {|it| format_local_dt(it['deployDate']) },
      "Status" => lambda {|it| format_app_deploy_status(it['status']) },
    }
  end

  def get_available_networks(instance)
    results = @options_interface.options_for_source('availableNetworksForInstance',{instanceId: instance['id'].to_i})
    available_networks = results['data'].collect {|it|
      {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
    }
    return available_networks
  end

  def get_instance_interfaces(instance)
    begin
      servers = instance['servers']
      interfaces = []
      servers.each do |server|
        details = @servers_interface.get(server.to_i)['server']
        details['interfaces'].each do |inter|
          interfaces.push(inter)
        end
        # only include the first one or it will create duplicates
        break
      end
      return interfaces
    rescue
      return false 
    end
  end

  def remote_version_gte(required_version)
    version = @remote_appliance[:build_version]
    return false if version.nil?
    version_numbers = version.split(".")
    required_version_numbers = required_version.split(".")
    result = true
    required_version_numbers.each_with_index do |v, i|
      if version_numbers[i].to_i > v.to_i
        break
      elsif version_numbers[i].to_i < v.to_i
        result = false
        break
      else
        # keep going
      end
    end
    return result
  end
end
