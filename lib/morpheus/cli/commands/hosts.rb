require 'morpheus/cli/cli_command'

class Morpheus::Cli::Hosts
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::LogsHelper
  set_command_name :hosts
  set_command_description "View and manage hosts (servers)."
  register_subcommands :list, :count, :get, :view, :stats, :add, :update, :remove, :logs, :start, :stop, :resize, :restart,
                       :run_workflow, :make_managed, :upgrade_agent, :snapshots, :software, :software_sync, :update_network_label,
                       {:'types' => :list_types},
                       {:exec => :execution_request},
                       :wiki, :update_wiki,
                       :maintenance, :leave_maintenance, :placement,
                       :list_devices, :assign_device, :detach_device, :attach_device,
                       :snapshot
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
    @tasks_interface = @api_client.tasks
    @task_sets_interface = @api_client.task_sets
    @servers_interface = @api_client.servers
    @server_types_interface = @api_client.server_types
    @provision_types_interface = @api_client.provision_types
    @logs_interface = @api_client.logs
    @accounts_interface = @api_client.accounts
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    @execution_request_interface = @api_client.execution_request
    @clusters_interface = @api_client.clusters
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
      opts.on( '-M', '--managed', "Show only Managed Servers" ) do |val|
        params[:managed] = true
      end
      opts.on( '-U', '--unmanaged', "Show only Unmanaged Servers" ) do |val|
        params[:managed] = false
      end
      opts.on( '-t', '--type TYPE', "Show only Certain Server Types" ) do |val|
        params[:serverType] = val
      end
      opts.on( '-p', '--power STATE', "Filter by Power Status" ) do |val|
        params[:powerState] = val
      end
      opts.on( '-i', '--ip IPADDRESS', "Filter by IP Address" ) do |val|
        params[:ip] = val
      end
      opts.on( '--cluster CLUSTER', '--cluster CLUSTER', "Filter by Cluster Name or ID" ) do |val|
        # params[:clusterId] = val
        options[:cluster] = val
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
      opts.on('--vm', "Show only virtual machines" ) do
        params[:vm] = true
      end
      opts.on('--hypervisor', "Show only VM Hypervisors" ) do
        params[:vmHypervisor] = true
      end
      opts.on('--container', "Show only Container Hypervisors" ) do
        params[:containerHypervisor] = true
      end
      opts.on('--baremetal', "Show only Baremetal Servers" ) do
        params[:bareMetalHost] = true
      end
      opts.on('--status STATUS', String, "Filter by Status" ) do |val|
        params[:status] = val
      end
      opts.on('--agent', "Show only Servers with the agent installed" ) do
        params[:agentInstalled] = true
      end
      opts.on('--noagent', "Show only Servers with No agent" ) do
        params[:agentInstalled] = false
      end
      opts.on( '--created-by USER', "Created By User Username or ID" ) do |val|
        options[:created_by] = val
      end
      opts.on( '--tenant TENANT', "Tenant Name or ID" ) do |val|
        options[:account] = val
      end
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      opts.on('--tags Name=Value',String, "Filter by tags.") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('--tag-compliant', "Displays only servers that are valid according to applied tag policies. Does not show servers that do not have tag policies." ) do
        params[:tagCompliant] = true
      end
      opts.on('--non-tag-compliant', "Displays only servers with tag compliance warnings." ) do
        params[:tagCompliant] = false
      end
      opts.on('--stats', "Display values for memory and storage usage used / max values." ) do
        options[:stats] = true
      end
      opts.on('-a', '--details', "Display all details: hostname, private ip, plan, stats, etc." ) do
        options[:details] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = "List hosts."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    
    params.merge!(parse_list_options(options))
    account = nil
    if options[:account]
      account = find_account_by_name_or_id(options[:account])
      if account.nil?
        return 1
      else
        params['accountId'] = account['id']
      end
    end
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

    if options[:created_by]
      created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:created_by])
      return if created_by_ids.nil?
      params['createdBy'] = created_by_ids
      # params['ownerId'] = created_by_ids # 4.2.1+
    end
    
    cluster = nil
    if options[:cluster]
      if options[:cluster].to_s =~ /\A\d{1,}\Z/
        params['clusterId'] = options[:cluster]
      else
        cluster = find_cluster_by_name_or_id(options[:cluster])
        return 1 if cluster.nil?
        params['clusterId'] = cluster['id']
      end
    end
    params['labels'] = options[:labels] if options[:labels]
    if options[:tags] && !options[:tags].empty?
      options[:tags].each do |k,v|
        params['tags.' + k] = v
      end
    end

    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.list(params)
      return
    end
    json_response = @servers_interface.list(params)

    # merge stats to be nice here..
    all_stats = json_response['stats']
    if options[:include_fields] || options[:all_fields]
      if json_response['servers']
        if all_stats
          json_response['servers'].each do |it|
            it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
          end
        end
      end
    end
    render_response(json_response, options, "servers") do
      
      servers = json_response['servers']
      multi_tenant = json_response['multiTenant'] == true
      title = "Morpheus Hosts"
      subtitles = []
      if account
        subtitles << "Tenant: #{account['name']}".strip
      end
      if group
        subtitles << "Group: #{group['name']}".strip
      end
      if cloud
        subtitles << "Cloud: #{cloud['name']}".strip
      end
      if cluster
        subtitles << "Cluster: #{cluster['name']}".strip
      elsif params['clusterId']
        subtitles << "Cluster: #{params['clusterId']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if servers.empty?
        print cyan,"No hosts found.",reset,"\n"
      else
        # print_servers_table(servers)
        # server returns stats in a separate key stats => {"id" => {} }
        # the id is a string right now..for some reason..
        all_stats = json_response['stats'] || {} 
        servers.each do |it|
          found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
          if found_stats
            if !it['stats']
              it['stats'] = found_stats # || {}
            else
              it['stats'] = found_stats.merge!(it['stats'])
            end
          end
        end

        rows = servers.collect {|server| 
          stats = server['stats']
          
          if !stats['maxMemory']
            stats['maxMemory'] = stats['usedMemory'] + stats['freeMemory']
          end
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
            id: server['id'],
            name: server['name'],
            external_name: server['externalName'],
            hostname: server['hostname'],
            platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A',
            type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged',
            tenant: server['account'] ? server['account']['name'] : server['accountId'],
            owner: server['owner'] ? server['owner']['username'] : server['owner'],
            cloud: server['zone'] ? server['zone']['name'] : '',
            plan: server['plan'] ? server['plan']['name'] : '',
            ip: server['externalIp'],
            internal_ip: server['internalIp'],
            nodes: server['containers'] ? server['containers'].size : '',
            # status: format_server_status(server, cyan),
            status: (options[:details]||options[:all_fields]) ? format_server_status(server, cyan) : format_server_status_friendly(server, cyan),
            power: format_server_power_state(server, cyan),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan,
            created: format_local_dt(server['dateCreated']),
            updated: format_local_dt(server['lastUpdated']),
          }
          row
        }
        # columns = [:id, :name, :type, :cloud, :ip, :internal_ip, :nodes, :status, :power]
        columns = {
          "ID" => :id,
          "Name" => :name,
          "External Name" => :external_name,
          "Hostname" => :hostname,
          "Type" => :type,
          "Owner" => :owner,
          "Tenant" => :tenant,
          "Cloud" => :cloud,
          "Plan" => :plan,
          "IP" => :ip,
          "Private IP" => :internal_ip,
          "Nodes" => :nodes,
          "Status" => :status,
          "Power" => :power,
          "CPU" => :cpu,
          "Memory" => :memory,
          "Storage" => :storage,
          "Created" => :created,
          "Updated" => :updated,
        }
        if options[:details] != true
          columns.delete("External Name")
          columns.delete("Hostname")
          columns.delete("Plan")
          columns.delete("Private IP")
          columns.delete("Owner")
          columns.delete("Tenant")
          columns.delete("Power")
          columns.delete("Created")
          columns.delete("Updated")
        end
        # hide External Name if there are none
        if !servers.find {|it| it['externalName'] && it['externalName'] != it['name']}
          columns.delete("External Name")
        end
        if !multi_tenant
          columns.delete("Tenant")
        end
        # columns += [:cpu, :memory, :storage]
        # # custom pretty table columns ...
        # if options[:include_fields]
        #   columns = options[:include_fields]
        # end
        print cyan
        print as_pretty_table(rows, columns.upcase_keys!, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def count(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on( '--tenant TENANT', "Tenant Name or ID" ) do |val|
        options[:account] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-M', '--managed', "Show only Managed Servers" ) do |val|
        params[:managed] = true
      end
      opts.on( '-U', '--unmanaged', "Show only Unmanaged Servers" ) do |val|
        params[:managed] = false
      end
      opts.on( '-t', '--type TYPE', "Show only Certain Server Types" ) do |val|
        params[:serverType] = val
      end
      opts.on( '-p', '--power STATE', "Filter by Power Status" ) do |val|
        params[:powerState] = val
      end
      opts.on( '-i', '--ip IPADDRESS', "Filter by IP Address" ) do |val|
        params[:ip] = val
      end
      opts.on('--vm', "Show only virtual machines" ) do
        params[:vm] = true
      end
      opts.on('--hypervisor', "Show only VM Hypervisors" ) do
        params[:vmHypervisor] = true
      end
      opts.on('--container', "Show only Container Hypervisors" ) do
        params[:containerHypervisor] = true
      end
      opts.on('--baremetal', "Show only Baremetal Servers" ) do
        params[:bareMetalHost] = true
      end
      opts.on('--status STATUS', "Filter by Status" ) do |val|
        params[:status] = val
      end
      opts.on('--agent', "Show only Servers with the agent installed" ) do
        params[:agentInstalled] = true
      end
      opts.on('--noagent', "Show only Servers with No agent" ) do
        params[:agentInstalled] = false
      end
      opts.on( '--created-by USER', "Created By User Username or ID" ) do |val|
        options[:created_by] = val
      end
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:details] = true
      end
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of hosts."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      account = nil
      if options[:account]
        account = find_account_by_name_or_id(options[:account])
        if account.nil?
          return 1
        else
          params['accountId'] = account['id']
        end
      end
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

      if options[:created_by]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:created_by])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
        # params['ownerId'] = created_by_ids # 4.2.1+
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.list(params)
        return
      end
      json_response = @servers_interface.list(params)
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

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( nil, '--costs', "Display Cost and Price" ) do
        options[:include_costs] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_status] ||= "provisioned,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_standard_get_options(opts, options)
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

  def _get(arg, options)
    @servers_interface.setopts(options)
    if options[:dry_run]
      if arg.to_s =~ /\A\d{1,}\Z/
        print_dry_run @servers_interface.dry.get(arg.to_i)
      else
        print_dry_run @servers_interface.dry.list({name: arg})
      end
      return
    end
    json_response = nil
    if arg.to_s =~ /\A\d{1,}\Z/
      json_response = @servers_interface.get(arg.to_i)
    else
      server = find_host_by_name_or_id(arg)
      json_response = @servers_interface.get(server['id'])
      # json_response = {"server" => server} need stats
    end
    render_response(json_response, options, "server") do
      server = json_response['server'] || json_response['host'] || {}
      #stats = server['stats'] || json_response['stats'] || {}
      stats = json_response['stats'] || {}
      tags = server['tags'] || server['metadata']
      title = "Host Details"
      print_h1 title, [], options
      print cyan
      server_columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Hostname" => 'hostname',
        "Description" => 'description',
        "Labels" => lambda {|it| format_list(it['labels']) rescue '' },
        "Tags" => lambda {|it| tags ? format_metadata(tags) : '' },
        "Owner" => lambda {|it| it['owner'] ? it['owner']['username'] : '' },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        #"Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "IP" => lambda {|it| it['externalIp'] },
        "Private IP" => lambda {|it| it['internalIp'] },
        "Type" => lambda {|it| it['computeServerType'] ? it['computeServerType']['name'] : 'unmanaged' },
        "Platform" => lambda {|it| it['serverOs'] ? it['serverOs']['name'].upcase : 'N/A' },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Cost" => lambda {|it| it['hourlyCost'] ? format_money(it['hourlyCost'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        "Price" => lambda {|it| it['hourlyPrice'] ? format_money(it['hourlyPrice'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        "Agent" => lambda {|it| it['agentInstalled'] ? "#{server['agentVersion'] || ''} updated at #{format_local_dt(server['lastAgentUpdate'])}" : '(not installed)' },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].size : 0 },
        # "Status" => lambda {|it| format_server_status(it) },
        # "Power" => lambda {|it| format_server_power_state(it) },
        "Managed" => lambda {|it| it['computeServerType'] ? it['computeServerType']['managed'] : ''},
        "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : ''},
        "Status" => lambda {|it| format_server_status_friendly(it) } # combo
      }
      server_columns.delete("Hostname") if server['hostname'].to_s.empty? || server['hostname'] == server['name']
      server_columns.delete("IP") if server['externalIp'].to_s.empty?
      server_columns.delete("Private IP") if server['internalIp'].to_s.empty?
      # server_columns.delete("Tenant") if multi_tenant != true
      server_columns.delete("Cost") if server['hourlyCost'].to_f == 0
      server_columns.delete("Price") if server['hourlyPrice'].to_f == 0 || server['hourlyPrice'] == server['hourlyCost']
      server_columns.delete("Labels") if server['labels'].nil? || server['labels'].empty?
      server_columns.delete("Instance") if server['instance'].nil?

      print_description_list(server_columns, server)

      if server['statusMessage']
        print_h2 "Status Message", options
        if server['status'] == 'failed'
          print red, server['statusMessage'], reset
        else
          print server['statusMessage']
        end
        print "\n"
      end
      if server['errorMessage']
        print_h2 "Error Message", options
        print red, server['errorMessage'], reset, "\n"
      end

      print_h2 "Host Usage", options
      print_stats_usage(stats)

      if options[:include_costs]
        print_h2 "Host Cost"
        cost_columns = {
          "Cost" => lambda {|it| it['hourlyCost'] ? format_money(it['hourlyCost'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
          "Price" => lambda {|it| it['hourlyPrice'] ? format_money(it['hourlyPrice'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        }
        print_description_list(cost_columns, server)
      end

      print reset, "\n"


      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(server['status'])
          print cyan
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end
    end
    return 0, nil
  end

  def stats(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
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
      @servers_interface.setopts(options)
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @servers_interface.dry.get(arg.to_i)
        else
          print_dry_run @servers_interface.dry.list({name: arg})
        end
        return
      end
      server = find_host_by_name_or_id(arg)
      json_response = @servers_interface.get(server['id'])
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['stats']], options)
        return 0
      end
      server = json_response['server']
      #stats = server['stats'] || json_response['stats'] || {}
      stats = json_response['stats'] || {}
      title = "Host Stats: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})"
      print_h1 title, [], options
      puts cyan + "Power: ".rjust(12) + format_server_power_state(server).to_s
      puts cyan + "Status: ".rjust(12) + format_server_status(server).to_s
      puts cyan + "Nodes: ".rjust(12) + (server['containers'] ? server['containers'].size : '').to_s
      #print_h2 "Host Usage", options
      print_stats_usage(stats, {label_width: 10})

      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
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
      server = find_host_by_name_or_id(args[0])
      params['level'] = params['level'].collect {|it| it.to_s.upcase }.join('|') if params['level'] # api works with INFO|WARN
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['order'] = params['direction'] unless params['direction'].nil? # old api version expects order instead of direction
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.server_logs([server['id']], params)
        return
      end
      json_response = @logs_interface.server_logs([server['id']], params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result
      
      title = "Host Logs: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})"
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
      # if params['containers']
      #   subtitles << "Containers: #{params['containers']}".strip
      # end
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      print_h1 title, subtitles, options
      logs = json_response['data'] || json_response['logs']
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

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud]", "[name]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type TYPE', "Server Type Code" ) do |val|
        options[:server_type_code] = val
      end
      opts.on("--security-groups LIST", Integer, "Security Groups, comma separated list of security group IDs") do |val|
        options[:security_groups] = val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata [LIST]', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        #payload.deep_merge!({'server' => passed_options}) unless passed_options.empty?
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        # support old format of `hosts add CLOUD NAME`
        if args[0]
          options[:cloud] = args[0]
        end
        if args[1]
          options[:host_name] = args[1]
        end
        # use active group by default
        options[:group] ||= @active_group_id

        params = {}
        # Group
        group_id = nil
        group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
        if group
          group_id = group["id"]
        else
          # print_red_alert "Group not found or specified!"
          # exit 1
          group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
          group_id = group_prompt['group']
        end

        # Cloud
        cloud_id = nil
        cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
        if cloud
          cloud_id = cloud["id"]
        else
          available_clouds = get_available_clouds(group_id)
          if available_clouds.empty?
            print_red_alert "Group #{group['name']} has no available clouds"
            exit 1
          end
          cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => available_clouds, 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})
          cloud_id = cloud_prompt['cloud']
          cloud = find_cloud_by_id_for_provisioning(group_id, cloud_id)
        end

        # Zone Type
        cloud_type = cloud_type_for_id(cloud['zoneTypeId'])

        # Server Type
        cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true && b['containerHypervisor'] == false }.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
        if options[:server_type_code]
          server_type_code = options[:server_type_code]
        else
          server_type_options = cloud_server_types.collect {|it| {'name' => it['name'], 'value' => it['code']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => "Server Type", 'selectOptions' => server_type_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a server type.'}], options[:options])
          server_type_code = v_prompt['type']
        end
        server_type = cloud_server_types.find {|it| it['code'] == server_type_code }
        if server_type.nil?
          print_red_alert "Server Type #{server_type_code} not found for cloud #{cloud['name']}"
          exit 1
        end

        # Server Name
        host_name = nil
        if options[:host_name]
          host_name = options[:host_name]
        else
          name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Server Name', 'type' => 'text', 'required' => true}], options[:options])
          host_name = name_prompt['name'] || ''
        end

        payload = {}
        payload.deep_merge!(passed_options) unless passed_options.empty?
        payload.deep_merge!({'server' => {
          'name' => host_name,
          'zone' => {'id' => cloud['id']},
          'computeServerType' => {'id' => server_type['id']},
        }})

        is_ilo_baremetal_host = server_type_code == 'IloBareMetalHost'

        # Service plans do not apply during iLO BareMetal server imports
        has_service_plans=!is_ilo_baremetal_host

        # uh ok, this actually expects config at root level, sibling of server
        # payload.deep_merge!({'server' => passed_options}) unless passed_options.empty?
        # prompt for service plan
        if has_service_plans
          service_plans_json = @servers_interface.service_plans({ zoneId: cloud['id'], serverTypeId: server_type["id"] })
          service_plans = service_plans_json["plans"]
          service_plans_dropdown = service_plans.collect { |sp| { 'name' => sp["name"], 'value' => sp["id"] } } # already sorted
          plan_prompt = Morpheus::Cli::OptionTypes.prompt([{ 'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server' }], options[:options])
          service_plan = service_plans.find { |sp| sp["id"] == plan_prompt['plan'].to_i }
          payload['server']['plan'] = {'id' => service_plan['id']}
          service_plan_id = service_plan['id']
        else
          service_plan_id = ""
        end

        option_type_list = server_type['optionTypes']

        # remove cpu and memory option types, which now come from the plan
        option_type_list = reject_service_plan_option_types(option_type_list)

        # need to GET provision type for optionTypes, and other settings...
        provision_type_code = server_type["provisionType"] ? server_type["provisionType"]["code"] : nil
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

        # prompt for resource pool
        pool_id = nil
        has_zone_pools = server_type["provisionType"] && server_type["provisionType"]["hasZonePools"]
        if has_zone_pools
          # pluck out the resourcePoolId option type to prompt for..why the heck is this even needed? 
          resource_pool_option_type = option_type_list.find {|opt| ['resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
          option_type_list = option_type_list.reject {|opt| ['resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
          resource_pool_option_type ||= {'fieldContext' => 'config', 'fieldName' => 'resourcePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'optionSource' => 'zonePools', 'required' => true, 'skipSingleOption' => true, 'description' => 'Select resource pool.'}
          resource_pool_prompt = Morpheus::Cli::OptionTypes.prompt([resource_pool_option_type],options[:options],api_client,{groupId: group_id, siteId: group_id, zoneId: cloud_id, cloudId: cloud_id, planId: service_plan_id, serverTypeId: server_type['id']})
          resource_pool_prompt.deep_compact!
          payload.deep_merge!(resource_pool_prompt)
          if resource_pool_option_type['fieldContext'] && resource_pool_prompt[resource_pool_option_type['fieldContext']]
            pool_id = resource_pool_prompt[resource_pool_option_type['fieldContext']][resource_pool_option_type['fieldName']]
          elsif resource_pool_prompt[resource_pool_option_type['fieldName']]
            pool_id = resource_pool_prompt[resource_pool_option_type['fieldName']]
          end
        end

        if has_service_plans
          # prompt for volumes
          volumes = prompt_volumes(service_plan, provision_type, options, @api_client, {zoneId: cloud_id, serverTypeId: server_type['id'], siteId: group_id})
          if !volumes.empty?
            payload['volumes'] = volumes
          end

          # plan customizations
          plan_opts = prompt_service_plan_options(service_plan, options, @api_client, {})
          if plan_opts && !plan_opts.empty?
            payload['servicePlanOptions'] = plan_opts
          end
        end

        # prompt for network interfaces (if supported)
        # Does not apply during iLO BareMetal server imports
        if !is_ilo_baremetal_host && server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
          begin
            network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], pool_id, options)
            if !network_interfaces.empty?
              payload['networkInterfaces'] = network_interfaces
            end
          rescue RestClient::Exception => e
            print yellow,"Unable to load network options. Proceeding...",reset,"\n"
            print_rest_exception(e, options) if Morpheus::Logging.debug?
          end
        end

        # Security Groups
        # prompt for multiple security groups
        sg_option_type = option_type_list.find {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['name'] == 'securityId')) }
        option_type_list = option_type_list.reject {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['name'] == 'securityId')) }
        # ok.. seed data has changed and serverTypes do not have this optionType anymore...
        if sg_option_type.nil?
          if server_type["provisionType"] && (server_type["provisionType"]["code"] == 'amazon')
            sg_option_type = {'fieldContext' => 'config', 'fieldName' => 'securityId', 'type' => 'select', 'fieldLabel' => 'Security Group', 'optionSource' => 'amazonSecurityGroup', 'required' => true, 'description' => 'Select security group.'}
          end
        end
        has_security_groups = !!sg_option_type
        if options[:security_groups]
          payload['securityGroups'] = options[:security_groups].collect {|sg_id| {'id' => sg_id} }
        else
          if has_security_groups
            security_groups_array = prompt_security_groups(sg_option_type, {zoneId: cloud_id, poolId: pool_id}, options)
            if !security_groups_array.empty?
              payload['securityGroups'] = security_groups_array.collect {|sg_id| {'id' => sg_id} }
            end
          end
        end

        metadata_option_type = option_type_list.find {|type| type['fieldName'] == 'metadata' }
        
        # Metadata Tags
        if metadata_option_type
          if options[:metadata]
            metadata = parse_metadata(options[:metadata])
            payload['tags'] = metadata if !metadata.empty?
          else
            metadata = prompt_metadata(options)
            payload['tags'] = metadata if !metadata.empty?
          end
        end

        api_params = {}
        api_params['zoneId'] = cloud['id']
        api_params['poolId'] = payload['config']['resourcePool'] if (payload['config'] && payload['config']['resourcePool'])
        if payload['config']
          api_params.deep_merge!(payload['config'])
        end
        #api_params.deep_merge(payload)
        params = Morpheus::Cli::OptionTypes.prompt(option_type_list,options[:options],@api_client, api_params)
        params.booleanize!
        payload.deep_merge!(params)
        
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.create(payload)
        return
      end
      json_response = @servers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        server_id = json_response["server"]["id"]
        server_name = json_response["server"]["name"]
        print_green_success "Provisioning host [#{server_id}] #{server_name}"
        # print details
        get_args = [server_id] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val == "null" ? nil : val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val == "null" ? nil : val
      end
      opts.on('--ssh-username VALUE', String, "SSH Username") do |val|
        params['sshUsername'] = val == "null" ? nil : val
      end
      opts.on('--ssh-password VALUE', String, "SSH Password") do |val|
        params['sshPassword'] = val == "null" ? nil : val
      end
      opts.on('--ssh-key-pair ID', String, "SSH Key Pair ID") do |val|
        params['sshKeyPair'] = val == "null" ? nil : {"id" => val.to_i}
      end
      opts.on('--power-schedule-type ID', String, "Power Schedule Type ID") do |val|
        params['powerScheduleType'] = val == "null" ? nil : val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        params['labels'] = parse_labels(val)
      end
      opts.on('--tags LIST', String, "Tags in the format 'name:value, name:value'. This will add and remove tags.") do |val|
        options[:tags] = val
      end
      opts.on('--metadata LIST', String, "Alias for --tags.") do |val|
        options[:tags] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('--add-tags TAGS', String, "Add Tags in the format 'name:value, name:value'. This will only add/update tags.") do |val|
        options[:add_tags] = val
      end
      opts.on('--remove-tags TAGS', String, "Remove Tags in the format 'name, name:value'. This removes tags, the :value component is optional and must match if passed.") do |val|
        options[:remove_tags] = val
      end
      # opts.on('--created-by ID', String, "Created By User ID") do |val|
      #   params['createdById'] = val
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      server = find_host_by_name_or_id(args[0])
      return 1 if server.nil?
      new_group = nil
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      params.deep_merge!(passed_options) unless passed_options.empty?
      params.booleanize!
      # metadata tags
      if options[:tags]
        params['tags'] = parse_metadata(options[:tags])
      else
        # params['tags'] = prompt_metadata(options)
      end
      if options[:add_tags]
        params['addTags'] = parse_metadata(options[:add_tags])
      end
      if options[:remove_tags]
        params['removeTags'] = parse_metadata(options[:remove_tags])
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support args and option parameters on top of payload
        if !params.empty?
          payload['server'] ||= {}
          payload['server'].deep_merge!(params)
        end
      else
        if params.empty?
          print_red_alert "Specify at least one option to update"
          puts optparse
          return 1
        end
        payload = {}
        payload['server'] = params
      end

      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.update(server["id"], payload)
        return
      end
      json_response = @servers_interface.update(server["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated host #{server['name']}"
        get([server['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      # opts.on( '-S', '--skip-remove-infrastructure', "Skip removal of underlying cloud infrastructure. Same as --remove-resources off" ) do
      #   query_params[:removeResources] = 'off'
      # end
      opts.on('--remove-resources [on|off]', ['on','off'], "Remove Infrastructure. Default is on if server is managed.") do |val|
        query_params[:removeResources] = val.nil? ? 'on' : val
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on('--remove-instances [on|off]', ['on','off'], "Remove Associated Instances. Default is off.") do |val|
        query_params[:removeInstances] = val.nil? ? 'on' : val
      end
      opts.on('--release-eips [on|off]', ['on','off'], "Release EIPs, default is on. Amazon only.") do |val|
        params[:releaseEIPs] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      server = find_host_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the server '#{server['name']}'?", options)
        exit 1
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.destroy(server['id'], query_params)
        return
      end
      json_response = @servers_interface.destroy(server['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['deleteApprovalRequired'] == true
          print_green_success "Delete Request created for Host #{server['name']}"
        else
          print_green_success "Host #{server['name']} is being removed..."
        end
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start a host.\n" +
                    "[name] is required. This is the name or id of a host. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host_ids = parse_id_list(args)
      hosts = []
      host_ids.each do |host_id|
        host = find_host_by_name_or_id(host_id)
        return 1 if host.nil?
        hosts << host
      end
      objects_label = "#{hosts.size == 1 ? 'host' : (hosts.size.to_s + ' hosts')} #{anded_list(hosts.collect {|it| it['name'] })}"
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{objects_label}?", options)
        return 9, "aborted command"
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.start(hosts.collect {|it| it['id'] })
        return
      end
      json_response = @servers_interface.start(hosts.collect {|it| it['id'] })
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Started #{objects_label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop a host.\n" +
                    "[name] is required. This is the name or id of a host. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host_ids = parse_id_list(args)
      hosts = []
      host_ids.each do |host_id|
        host = find_host_by_name_or_id(host_id)
        return 1 if host.nil?
        hosts << host
      end
      objects_label = "#{hosts.size == 1 ? 'host' : (hosts.size.to_s + ' hosts')} #{anded_list(hosts.collect {|it| it['name'] })}"
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{objects_label}?", options)
        return 9, "aborted command"
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.stop(hosts.collect {|it| it['id'] })
        return
      end
      json_response = @servers_interface.stop(hosts.collect {|it| it['id'] })
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Stopped #{objects_label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

   def restart(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart a host.\n" +
                    "[name] is required. This is the name or id of a host."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart the server '#{server['name']}'?", options)
        exit 1
      end
     @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.restart(server['id'])
        return
      end
      json_response = @servers_interface.restart(server['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Restarting #{server["name"]}"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])

      group_id = server["siteId"] || erver['group']['id']
      cloud_id = server["zoneId"] || server["zone"]["id"]
      server_type_id = server['computeServerType']['id']
      plan_id = server['plan']['id']
      payload = {
        :server => {:id => server["id"]}
      }

      # need to GET provision type for some settings...
      server_type = @server_types_interface.get(server_type_id)['serverType']
      provision_type = @provision_types_interface.get(server_type['provisionType']['id'])['provisionType']

      # avoid 500 error
      # payload[:servicePlanOptions] = {}
      unless options[:no_prompt]
        puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"
        # unless hot_resize
        #   puts "\nWARNING: Resize actions for this server will cause instances to be restarted.\n\n"
        # end
      end

      # prompt for service plan
      service_plans_json = @servers_interface.service_plans({zoneId: cloud_id, serverTypeId: server_type_id, serverId: server['id']})
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        if plan['value'] && plan['value'].to_i == plan_id.to_i
          plan['name'] = "#{plan['name']} (current)"
        end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'defaultValue' => plan_id, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['plan'].to_i }
      payload[:server][:plan] = {id: service_plan["id"]}

      # fetch volumes
      current_volumes = nil
      if server['volumes']
        current_volumes = server['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      else
        volumes_response = @servers_interface.volumes(server['id'])
        current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      end

      # prompt for volumes
      vol_options = options 
      vol_options['siteId'] = group_id
      vol_options['zoneId'] = cloud_id
      vol_options['resourcePoolId'] = server['resourcePool']['id'] if server['resourcePool']
      volumes = prompt_resize_volumes(current_volumes, service_plan, provision_type, vol_options, server)
      if !volumes.empty?
        payload[:volumes] = volumes
      end

      # plan customizations
      plan_opts = prompt_service_plan_options(service_plan, options, @api_client, {}, server)
      if plan_opts && !plan_opts.empty?
        payload['servicePlanOptions'] = plan_opts
      end

      # todo: reconfigure networks
      #       need to get provision_type_id for network info
      # prompt for network interfaces (if supported)
      # if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
      #   begin
      #     network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], null, options)
      #     if !network_interfaces.empty?
      #       payload[:networkInterfaces] = network_interfaces
      #     end
      #   rescue RestClient::Exception => e
      #     print yellow,"Unable to load network options. Proceeding...",reset,"\n"
      #     print_rest_exception(e, options) if Morpheus::Logging.debug?
      #   end
      # end

      # only amazon supports this option
      # for now, always do this
      payload[:deleteOriginalVolumes] = true
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.resize(server['id'], payload)
        return
      end
      json_response = @servers_interface.resize(server['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        unless options[:quiet]
          puts "Host #{server['name']} resizing..."
          list([])
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def make_managed(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, make_managed_option_types(false))
      opts.on('--install-agent [on|off]', String, "Install Agent? Pass false to manually install agent. Default is true.") do |val|
        options['installAgent'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('-g', '--group GROUP', String, "Group to assign to new instance.") do |val|
        options[:group] = val
      end
      # opts.on('--instance-type-id ID', String, "Instance Type ID for the new instance.") do |val|
      #   options['instanceTypeId'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      # end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host = find_host_by_name_or_id(args[0])
      if host['agentInstalled']
        print_red_alert "Agent already installed on host '#{host['name']}'"
        return false
      end
      payload = {
        'server' => {}
      }
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload.deep_merge!(passed_options)
      params = Morpheus::Cli::OptionTypes.prompt(make_managed_option_types, options[:options], @api_client, options[:params])
      server_os = params.delete('serverOs')
      if server_os
        payload['server']['serverOs'] = {id: server_os}
      end
      account_id = params.delete('account') # not yet implemented
      if account_id
        payload['server']['account'] = {id: account}
      end
      if options[:group]
        group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
        return 1 if group.nil?
        params['provisionSiteId'] = group['id']
      end
      payload['server'].merge!(params)
      ['installAgent','instanceTypeId'].each do |k|
        if options[k] != nil
          payload[k] = options[k]
        end
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run(@servers_interface.dry.make_managed(host['id'], payload), options)
        return 0
      end
      json_response = @servers_interface.make_managed(host['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Host #{host['name']} is being converted to managed."
        puts "Public Key:\n#{json_response['publicKey']}\n(copy to your authorized_keys file)"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def upgrade_agent(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Upgrade agent for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    host = find_host_by_name_or_id(args[0])
    return 1 if host.nil?

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'server' => parse_passed_options(options)})
    else
      payload.deep_merge!({'server' => parse_passed_options(options)})
    end

    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.upgrade(host['id'], payload)
      return
    end
    json_response = @servers_interface.upgrade(host['id'], payload)
    render_response(json_response, options) do
      #get([host['id']])
      if json_response['success']
        if json_response['msg'] == nil
          print_green_success "Upgrading agent on host #{host['name']}..."
        else
          print_green_success json_response['msg']
        end
        process_id = json_response['processId'] || (json_response['processIds'] ? json_response['processIds'][0] : nil)
        if process_id
          unless options[:no_refresh]
            process = wait_for_process_execution(process_id, options)
          end
        else
          # puts "No process returned"
        end
      else
        # never reached because unsuccessful requests raise an exception
        print_red_alert "API Request failed: #{json_response['msg']}"
      end
    end
  end

  def run_workflow(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host] [workflow] [options]")
      opts.on("--phase PHASE", String, "Task Phase to run for Provisioning workflows. The default is provision.") do |val|
        options[:phase] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Run workflow for a host.
[host] is required. This is the name or id of a host
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

    host = find_host_by_name_or_id(args[0])
    return 1 if host.nil?
    workflow = find_workflow_by_name_or_id(args[1])
    return 1 if workflow.nil?

    # support -O options as arbitrary params
    old_option_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
    params.deep_merge!(old_option_options) unless old_option_options.empty?

    # the payload format is unusual
    # payload example: {"taskSet": {taskSetId": {"taskSetTaskId": {"customOptions": {"dbVersion":"5.6"}}}}}
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      payload = {}
      # i guess you must pass an option if there are editable options
      # any option, heh
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
      # if params.empty? && !editable_options.empty?
      #   puts optparse
      #   option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
      #   puts "\nAvailable Options:\n#{option_lines}\n\n"
      #   return 1
      # end

    end

    if !params.empty?
      payload['taskSet'] ||= {}
      payload['taskSet']["#{workflow['id']}"] ||= {}
      payload['taskSet']["#{workflow['id']}"].deep_merge!(params)
    end
    if options[:phase]
      payload['taskPhase'] = options[:phase]
    end
    begin
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.workflow(host['id'],workflow['id'], payload)
        return
      end
      json_response = @servers_interface.workflow(host['id'],workflow['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif options[:quiet]
        return 0
      else
        print_green_success "Running workflow #{workflow['name']} on host #{host['name']} ..."
      end
      return 0
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
      opts.footer = "Execute an arbitrary command or script on a host." + "\n" +
                    "[id] is required. This is the id a host." + "\n" +
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
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?
      params['serverId'] = host['id']
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
      # dry run?
      @servers_interface.setopts(options)
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

  def server_types_for_cloud(cloud_id, options)
    connect(options)
    zone = find_zone_by_name_or_id(nil, cloud_id)
    cloud_type = cloud_type_for_id(zone['zoneTypeId'])
    cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true}
    cloud_server_types = cloud_server_types.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
    if options[:json]
      print JSON.pretty_generate(cloud_server_types)
      print "\n"
    else
      print_h1 "Morpheus Server Types - Cloud: #{zone['name']}", [], options
      if cloud_server_types.nil? || cloud_server_types.empty?
        print cyan,"No server types found for the selected cloud",reset,"\n"
      else
        cloud_server_types.each do |server_type|
          print cyan, "[#{server_type['code']}]".ljust(20), " - ", "#{server_type['name']}", "\n"
        end
      end
      print reset,"\n"
    end
  end

  def list_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List host types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:cloud]
        #return server_types_for_cloud(options[:cloud], options)
        zone = find_zone_by_name_or_id(nil, options[:cloud])
        params["zoneTypeId"] = zone['zoneTypeId']
        params["creatable"] = true
      end
      @server_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @server_types_interface.dry.list(params)
        return
      end
      json_response = @server_types_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'serverTypes')
      return 0 if render_result

      server_types = json_response['serverTypes']

      title = "Morpheus Server Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if options[:cloud]
        subtitles << "Cloud: #{options[:cloud]}"
      end
      print_h1 title, subtitles
      if server_types.empty?
        print cyan,"No server types found.",reset,"\n"
      else
        rows = server_types.collect do |server_type|
          {
            id: server_type['id'],
            code: server_type['code'],
            name: server_type['name']
          }
        end
        columns = [:id, :name, :code]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('-w','--wiki', "Open the wiki tab for this host") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View a host in a web browser" + "\n" +
                    "[host] is required. This is the name or id of a host. Supports 1-N [host] arguments."
    end
    optparse.parse!(args)
    if args.count != 1
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
      host = find_host_by_name_or_id(arg)
      return 1 if host.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/servers/#{host['id']}"
      if options[:link_tab]
        link << "#!#{options[:link_tab]}"
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

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for a host." + "\n" +
                    "[host] is required. This is the name or id of a host."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?


      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.wiki(host["id"], params)
        return
      end
      json_response = @servers_interface.wiki(host["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Host Wiki Page: #{host['name']}"
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
        return view_wiki([args[0]])
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
      opts.footer = "View host wiki page in a web browser" + "\n" +
                    "[host] is required. This is the name or id of a host."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/servers/#{host['id']}#!wiki"

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

  def update_wiki(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host] [options]")
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
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?
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
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.update_wiki(host["id"], payload)
        return
      end
      json_response = @servers_interface.update_wiki(host["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for host #{host['name']}"
        wiki([host['id']])
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
      opts.banner = subcommand_usage("[host] [snapshot]")
      # no pagination yet
      # build_standard_list_options(opts, options)
      build_standard_list_options(opts, options, [:details])
            opts.footer = <<-EOT
List snapshots for a host.
[host] is required. This is the name or id of a host.
[snapshot] is optional. This is the name or id of a snapshot.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      return 1 if server.nil?
      params = {}
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.snapshots(server['id'], params)
        return
      end
      json_response = @servers_interface.snapshots(server['id'], params)
      snapshots = json_response['snapshots']
      # [snapshots] is done with post api filtering by id or name or externalId
      if args[1]
        if args[1] =~ /\A\d{1,}\Z/
          snapshots = snapshots.select {|it| it['id'].to_s == args[1] }
        else
          # match beginning of name of externalId
          snapshots = snapshots.select {|it| it['name'].to_s.index(args[1]) == 0 || it['externalId'].to_s.index(args[1])  == 0 }
        end
        json_response['snapshots'] = snapshots # update response for -j filtering too
      end
      render_response(json_response, options, 'snapshots') do
        print_h1 "Snapshots: #{server['name']}", [], options
        if snapshots.empty?
          if args[1]
            print cyan,"No snapshots found for '#{args[1]}'",reset,"\n"
          elsif
            print cyan,"No snapshots found",reset,"\n"
          end
          print reset, "\n"
        else
          if options[:details]
            # this actually makes a request for each one here so don't go crazy... 
            if snapshots.size > 3
              print cyan, "Showing first 3 snapshots. Use the ID to get more details.", reset, "\n"
              snapshots = snapshots.first(3)
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

  def software(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List installed software for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      return 1 if server.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.software(server['id'], params)
        return
      end
      json_response = @servers_interface.software(server['id'], params)
      software = json_response['software']
      render_response(json_response, options, 'software') do
        print_h1 "Software: #{server['name']}", [], options
        if software.empty?
          print cyan,"No software found",reset,"\n"
        else
          software_column_definitions = {
            # "ID" => lambda {|it| it['id'] },
            "Name" => lambda {|it| it['name'] },
            "Version" => lambda {|it| it['packageVersion'] },
            "Publisher" => lambda {|it| it['packagePublisher'] },
            # "Release" => lambda {|it| it['packageRelease'] },
            # "Type" => lambda {|it| it['packageType'] },
            # "Architecture" => lambda {|it| it['architecture'] },
            # "Install Date" => lambda {|it| format_local_dt(it['installDate']) },
          }
          print cyan
          print as_pretty_table(software, software_column_definitions.upcase_keys!, options)
          print_results_pagination({size: software.size, total: software.size})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def software_sync(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Sync installed software for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      return 1 if server.nil?
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
      end
      params = {}
      params.merge!(parse_query_options(options))
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.software_sync(server['id'], payload, params)
        return
      end
      json_response = @servers_interface.software_sync(server['id'], payload, params)
      render_response(json_response, options) do
        print_green_success "Syncing software for host #{server['name']}"
        #get([server['id']])
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
      opts.banner = subcommand_usage("[server] [options]")
      opts.on('--network NETWORK', "Network Interface ID" ) do |val|
        options[:network] = val
      end
      opts.on('--label LABEL', "label") do |val|
        options[:label] = val
      end
      opts.footer = "Change the label of a Network Interface.\n" +
                    "Editing an Interface will not apply changes to the physical hardware. The purpose is for a manual override or data correction (mostly for self managed or baremetal servers where cloud sync is not available)\n" +
                    "[name or id] is required. The name or the id of the server.\n" +
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
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?

      network_id = options[:network]
      if network_id != nil && network_id.to_i == 0
        print_red_alert  "network must be an ID/integer above 0, not a name/string value."
        network_id = nil
      end


      if !network_id
        available_networks = get_available_networks(host)
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
        print_dry_run @servers_interface.dry.update_network_label(network_id, host["id"], payload)
        return
      end
      json_response = @servers_interface.update_network_label(network_id, host["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated label for host #{host['name']} network #{network_id} to #{label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def maintenance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('--ignoreDaemonsets [on|off]', String, "Ignore Daemonsets") do |val|
        options[:ignoreDaemonsets] = (val.to_s.empty? || val.to_s == 'on' || val.to_s == 'true')
      end
      opts.on('--force [on|off]', String, "Force") do |val|
        options[:force] = (val.to_s.empty? || val.to_s == 'on' || val.to_s == 'true')
      end
      opts.on('--deleteEmptyDir [on|off]', String, "Delete Empty Directories") do |val|
        options[:deleteEmptyDir] = (val.to_s.empty? || val.to_s == 'on' || val.to_s == 'true')
      end
      opts.on('--deleteLocalData [on|off]', String, "Delete Local Data") do |val|
        options[:deleteLocalData] = (val.to_s == 'on' || val.to_s == 'true')
      end
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Enable maintenance mode for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    server = find_host_by_name_or_id(args[0])
    return 1 if server.nil?

    # Just let the API return this error instead

    # # load server type to determine if maintenance mode is supported
    # server_type_id = server['computeServerType']['id']
    # server_type = @server_types_interface.get(server_type_id)['serverType']
    # if !server_type['hasMaintenanceMode']
    #   raise_command_error "Server type does not support maintenance mode"
    # end

    payload = {}

    if server.dig('config', 'kubernetesRole')
      payload[:server] = {}
      payload[:server][:ignoreDaemonsets] = options.fetch(:ignoreDaemonsets) do
        prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ignoreDaemonsets', 'fieldLabel' => 'Ignore Daemonsets', 'type' => 'checkbox', 'defaultValue' => true, 'required' => false}], options, @api_client, {})
        prompt['ignoreDaemonsets'] == 'on'
      end
      payload[:server][:force] = options.fetch(:force) do
        prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'force', 'fieldLabel' => 'Force', 'type' => 'checkbox', 'defaultValue' => true, 'required' => false}], options, @api_client, {})
        prompt['force'] == 'on'
      end
      payload[:server][:deleteEmptyDir] = options.fetch(:deleteEmptyDir) do
        prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deleteEmptyDir', 'fieldLabel' => 'Delete Empty Directories', 'type' => 'checkbox', 'defaultValue' => true, 'required' => false}], options, @api_client, {})
        prompt['deleteEmptyDir'] == 'on'
      end
      payload[:server][:deleteLocalData] = options.fetch(:deleteLocalData) do
        prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'deleteLocalData', 'fieldLabel' => 'Delete Local Data', 'type' => 'checkbox', 'defaultValue' => false, 'required' => false}], options, @api_client, {})
        prompt['deleteLocalData'] == 'on'
      end
    end
    
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
    end
    params = {}
    params.merge!(parse_query_options(options))

    confirm!("Are you sure you would like to enable maintenance mode on host '#{server['name']}'?", options)

    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.maintenance(server['id'], payload, params)
      return
    end
    json_response = @servers_interface.maintenance(server['id'], payload, params)
    render_response(json_response, options) do
      print_green_success "Maintenance mode enabled for host #{server['name']}"
      #get([server['id']])
    end
    return 0, nil
  end

  def leave_maintenance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Disable maintenance mode for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    server = find_host_by_name_or_id(args[0])
    return 1 if server.nil?

    # Just let the API return this error instead
    
    # # load server type to determine if maintenance mode is supported
    # server_type_id = server['computeServerType']['id']
    # server_type = @server_types_interface.get(server_type_id)['serverType']
    # if !server_type['hasMaintenanceMode']
    #   raise_command_error "Server type does not support maintenance mode"
    # end

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))
    end
    params = {}
    params.merge!(parse_query_options(options))

    confirm!("Are you sure you would like to leave maintenance mode on host '#{server['name']}'?", options)

    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.leave_maintenance(server['id'], payload, params)
      return
    end
    json_response = @servers_interface.leave_maintenance(server['id'], payload, params)
    render_response(json_response, options) do
      print_green_success "Left Maintenance Mode for host #{server['name']}"
      #get([server['id']])
    end
    return 0, nil
  end

  def placement(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Update placement for a host.
[host] is required. This is the name or id of a host.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    server = find_host_by_name_or_id(args[0])
    return 1 if server.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'server' => parse_passed_options(options)})
    else
      payload.deep_merge!({'server' => parse_passed_options(options)})
      # prompt 
      # Host (preferredParentServer.id)
      if payload['server']['host']
        options[:options] = payload['server'].remove('host')
      end
      default_host = (server['preferredParentServer'] ? server['preferredParentServer']['id'] : (server['parentServer'] ? server['parentServer']['id'] : nil))
      host = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'host', 'type' => 'select', 'fieldLabel' => 'Host', 'optionSource' => 'parentServers', 'required' => false, 'description' => 'Choose the preferred parent host for this virtual machine to be placed on.', 'defaultValue' => default_host}],options[:options],@api_client,{'serverId' => server['id']})['host']
      if !host.to_s.empty?
        payload['server']['preferredParentServer'] = {'id' => host}
      end


      # Placement Strategy (placementStrategy)
      placement_strategy = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'placementStrategy', 'type' => 'select', 'fieldLabel' => 'Placement Strategy', 'optionSource' => 'placementStrategies', 'required' => false, 'description' => 'Choose the placement strategy for this virtual machine.', 'defaultValue' => server['placementStrategy']}],options[:options],@api_client,{'serverId' => server['id']})['placementStrategy']
      if !placement_strategy.to_s.empty?
        payload['server']['placementStrategy'] = placement_strategy
      end
    end
    params = {}
    params.merge!(parse_query_options(options))

    confirm!("Are you sure you would like to update placement for host '#{server['name']}'?", options)

    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.placement(server['id'], payload, params)
      return
    end
    json_response = @servers_interface.placement(server['id'], payload, params)
    render_response(json_response, options) do
      print_green_success "Maintenance mode enabled for host #{server['name']}"
      #get([server['id']])
    end
    return 0, nil
  end

  def snapshot(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
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
Create a snapshot for a host.
[host] is required. This is the name or id of a host
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    server = find_host_by_name_or_id(args[0])
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'snapshot' => parse_passed_options(options)})
    else
      payload.deep_merge!({'snapshot' => parse_passed_options(options)})
      # prompt for name and description
      name = prompt_value({'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Snapshot Name', 'description' => "Snapshot Name. Default is \"{name}.{timestamp}\""}, options)
      payload['snapshot']['name'] = name if !name.to_s.empty?
      description = prompt_value({'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'description' => "Snapshot Description."}, options)
      payload['snapshot']['description'] = description if !description.to_s.empty?
      # need to GET provision type for some settings...
      provision_type = nil
      begin
        provision_type_id = server['computeServerType']['provisionTypeId'] rescue nil
        if provision_type_id
          provision_type = @provision_types_interface.get(provision_type_id)['provisionType']
        end
      rescue => ex
        Morpheus::Logging::DarkPrinter.puts "Failed to load provision type!" if Morpheus::Logging.debug?
      end
      if provision_type && provision_type['hasMemorySnapshots']
        # prompt for memorySnapshot
        memory_snapshot = prompt_value({'fieldName' => 'memorySnapshot', 'type' => 'checkbox', 'fieldLabel' => 'Memory Snapshot?', 'description' => "Snapshot Description."}, options)
        payload['snapshot']['memorySnapshot'] = memory_snapshot if !memory_snapshot.to_s.empty?
      end
      # convert "on" and "off" to true/false
      payload.booleanize!
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to snapshot the host '#{server['name']}'?", options)
      exit 1
    end
    @servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @servers_interface.dry.snapshot(server['id'], payload)
      return
    end
    json_response = @servers_interface.snapshot(server['id'], payload)
    render_response(json_response, options) do
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

    ## Server Devices

    def list_devices(args)
      Morpheus::Cli::ServerDevicesCommand.new.list(args)
    end
    
    def assign_device(args)
      Morpheus::Cli::ServerDevicesCommand.new.assign(args)
    end

    def attach_device(args)
      Morpheus::Cli::ServerDevicesCommand.new.attach(args)
    end
  
    def detach_device(args)
      Morpheus::Cli::ServerDevicesCommand.new.detach(args)
    end
    
  private

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
      print_red_alert "Server not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple Servers exist with the name '#{name}'"
      puts_error as_pretty_table(results['servers'], [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
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

  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      json_results = @clouds_interface.get(val.to_i)
      zone = json_results['zone']
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      json_results = @clouds_interface.list({groupId: group_id, name: val})
      zone = json_results['zones'] ? json_results['zones'][0] : nil
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end

  def find_server_type(zone, name)
    server_type = zone['serverTypes'].select do  |sv_type|
      (sv_type['name'].downcase == name.downcase || sv_type['code'].downcase == name.downcase) && sv_type['creatable'] == true
    end
    if server_type.nil?
      print_red_alert "Server Type Not Selectable"
    end
    return server_type
  end

  def cloud_type_for_id(id)
    cloud_types = @clouds_interface.cloud_types({max:1000})['zoneTypes']
    cloud_type = cloud_types.find { |z| z['id'].to_i == id.to_i}
    if cloud_type.nil?
      print_red_alert "Cloud Type not found by id #{id}"
      exit 1
    end
    return cloud_type
  end

  def find_cluster_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      find_cluster_by_id(val)
    else
      find_cluster_by_name(val)
    end
  end

  def find_cluster_by_id(id)
    json_results = @clusters_interface.get(id.to_i)
    if json_results['cluster'].empty?
      print_red_alert "Cluster not found by id #{id}"
      exit 1
    end
    json_results['cluster']
  end

  def find_cluster_by_name(name)
    json_results = @clusters_interface.list({name: name})
    if json_results['clusters'].empty? || json_results['clusters'].count > 1
      print_red_alert "Cluster not found by name #{name}"
      exit 1
    end
    json_results['clusters'][0]
  end

  def format_server_power_state(server, return_color=cyan)
    out = ""
    if server['powerState'] == 'on'
      out << "#{green}ON#{return_color}"
    elsif server['powerState'] == 'off'
      out << "#{red}OFF#{return_color}"
    else
      out << "#{white}#{server['powerState'].to_s.upcase}#{return_color}"
    end
    out
  end

  def format_server_status(server, return_color=cyan)
    out = ""
    status_string = server['status'].to_s.downcase
    if status_string == 'provisioned'
      out = "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'provisioning'
      out = "#{cyan}#{status_string.upcase}#{cyan}"
    elsif status_string == 'failed' or status_string == 'error'
      out = "#{red}#{status_string.upcase}#{return_color}"
    else
      out = "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_server_status_friendly(server, return_color=cyan)
    out = ""
    status_string = server['status'].to_s.downcase
    if status_string == 'provisioned'
      # out = format_server_power_state(server, return_color)
      # make it looks like format_instance_status
      if server['powerState'] == 'on'
        out << "#{green}RUNNING#{return_color}"
      elsif server['powerState'] == 'off'
        out << "#{red}STOPPED#{return_color}"
      else
        out << "#{white}#{server['powerState'].to_s.upcase}#{return_color}"
      end
    else
      out = format_server_status(server, return_color)
    end
    out
  end

  def get_available_networks(host)
    results = @options_interface.options_for_source('availableNetworksForHost',{serverId: host['id'].to_i})
    available_networks = results['data'].collect {|it|
      {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
    }
    return available_networks
  end
  

   def make_managed_option_types(connected=true)
    [
      #{'fieldName' => 'account', 'fieldLabel' => 'Account', 'type' => 'select', 'optionSource' => 'accounts', 'required' => true},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text'},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false},
      {'fieldName' => 'serverOs', 'fieldLabel' => 'OS Type', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false},
    ]
  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

end
