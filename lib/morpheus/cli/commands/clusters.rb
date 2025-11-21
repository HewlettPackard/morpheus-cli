require 'morpheus/cli/cli_command'

class Morpheus::Cli::Clusters
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::WhoamiHelper
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ExecutionRequestHelper

  register_subcommands :list, :count, :get, :view, :add, :update, :remove, :logs, :history, {:'history-details' => :history_details}, {:'history-event' => :history_event_details}
  register_subcommands :list_types, :get_type
  register_subcommands :list_workers, :add_worker, :remove_worker, :update_worker_count
  register_subcommands :list_masters
  register_subcommands :upgrade_cluster
  register_subcommands :list_volumes, :remove_volume
  register_subcommands :list_namespaces, :get_namespace, :add_namespace, :update_namespace, :remove_namespace
  register_subcommands :list_containers, :remove_container, :restart_container, :get_container
  register_subcommands :list_deployments, :remove_deployment, :restart_deployment
  register_subcommands :list_stateful_sets, :remove_stateful_set, :restart_stateful_set
  register_subcommands :list_pods, :remove_pod, :restart_pod
  register_subcommands :list_jobs, :remove_job
  register_subcommands :list_services, :remove_service
  register_subcommands :list_datastores, :get_datastore, :update_datastore, :add_datastore, :remove_datastore
  register_subcommands :update_permissions
  register_subcommands :api_config, :view_api_token, :view_kube_config
  register_subcommands :wiki, :update_wiki
  register_subcommands :apply_template
  register_subcommands :refresh
  register_subcommands :list_replicasets, :list_daemonsets, :list_endpoints, :list_ingresses, :list_policies, :list_volumes, :list_volume_claims, :list_config_maps, :list_secrets
  register_subcommands :get_pod, :get_deployment, :get_replicaset, :get_daemonset, :get_endpoint, :get_ingress, :get_policy, :get_volume_claim, :get_volume, :get_config_map, :get_secret, :get_stateful_set, :get_job, :get_service
  register_subcommands :list_affinity_groups, :get_affinity_group, :update_affinity_group, :add_affinity_group, :remove_affinity_group

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clusters_interface = @api_client.clusters
    @groups_interface = @api_client.groups
    @cluster_layouts_interface = @api_client.library_cluster_layouts
    @security_groups_interface = @api_client.security_groups
    @datastores_interface = @api_client.datastores
    #@security_group_rules_interface = @api_client.security_group_rules
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @resource_pool_groups_interface = @api_client.resource_pool_groups
    @clouds_interface = @api_client.clouds
    @servers_interface = @api_client.servers
    @server_types_interface = @api_client.server_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    @provision_types_interface = @api_client.provision_types
    @service_plans_interface = @api_client.service_plans
    @user_groups_interface = @api_client.user_groups
    @accounts_interface = @api_client.accounts
    @logs_interface = @api_client.logs
    @execution_request_interface = @api_client.execution_request
    #@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List clusters."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list(params)
        return
      end
      json_response = @clusters_interface.list(params)
      render_result = render_with_format(json_response, options, 'clusters')
      return 0 if render_result

      title = "Morpheus Clusters"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      clusters = json_response['clusters']
      
      if clusters.empty?
        print cyan,"No clusters found.",reset,"\n"
      else
        print_clusters_table(clusters, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of clusters."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.get(params)
        return
      end
      json_response = @clusters_interface.get(params)
      # print number only
      if json_response['meta'] && json_response['meta']['total']
        print cyan, json_response['meta']['total'], reset, "\n"
      else
        print yellow, "unknown", reset, "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on( nil, '--hosts', "Display masters and workers" ) do
        options[:show_masters] = true
        options[:show_workers] = true
      end
      opts.on( nil, '--masters', "Display masters" ) do
        options[:show_masters] = true
      end
      opts.on( nil, '--workers', "Display workers" ) do
        options[:show_workers] = true
      end
      opts.on( nil, '--permissions', "Display permissions" ) do
        options[:show_perms] = true
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
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a cluster."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(arg, options={})
    
    begin
      @clusters_interface.setopts(options)

      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @clusters_interface.dry.get(arg.to_i)
        else
          print_dry_run @clusters_interface.dry.list({name:arg})
        end
        return 0
      end
      cluster = find_cluster_by_name_or_id(arg)
      return 1 if cluster.nil?
      json_response = nil
      if arg.to_s =~ /\A\d{1,}\Z/
        json_response = {'cluster' => cluster}  # skip redundant request
      else
        json_response = @clusters_interface.get(cluster['id'])
      end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end

      cluster = json_response['cluster']
      worker_stats = cluster['workerStats']
      clusterType = find_cluster_type_by_id(cluster['type']['id'])

      print_h1 "Morpheus Cluster"
      print cyan
      description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Labels" => lambda {|it| format_list(it['labels']) rescue '' },
          "Type" => lambda { |it| it['type']['name'] },
          #"Group" => lambda { |it| it['site']['name'] },
          "Cloud" => lambda { |it| it['zone']['name'] },
          "Location" => lambda { |it| it['location'] },
          "Layout" => lambda { |it| it['layout'] ? it['layout']['name'] : ''},
          "Integrations" => lambda {|it| format_name_and_id(it['integrations']) },
          "API Url" => 'serviceUrl',
          "Visibility" => lambda { |it| it['visibility'].to_s.capitalize },
          #"Groups" => lambda {|it| it['groups'].collect {|g| g.instance_of?(Hash) ? g['name'] : g.to_s }.join(', ') },
          #"Owner" => lambda {|it| it['owner'].instance_of?(Hash) ? it['owner']['name'] : it['ownerId'] },
          #"Tenant" => lambda {|it| it['account'].instance_of?(Hash) ? it['account']['name'] : it['accountId'] },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Enabled" => lambda { |it| format_boolean(it['enabled']) },
          "Managed" => lambda { |it| format_boolean(it['managed']) },
          "Auto Power On VMs" => lambda { |it| format_boolean(it['autoRecoverPowerState']) },
          "Status" => lambda { |it| format_cluster_status(it) }
      }
      print_description_list(description_cols, cluster)

      print_h2 "Cluster Details"
      print cyan

      print "Namespaces: #{cluster['namespacesCount']}".center(20) if !cluster['namespacesCount'].nil?
      print "Masters: #{cluster['mastersCount']}".center(20) if !cluster['mastersCount'].nil?
      print "Workers: #{cluster['workersCount']}".center(20) if !clusterType['workersCount'].nil?
      print "Volumes: #{cluster['volumesCount']}".center(20) if !cluster['volumesCount'].nil?
      print "Containers: #{cluster['containersCount']}".center(20) if !cluster['containersCount'].nil?
      print "Services: #{cluster['servicesCount']}".center(20) if !cluster['servicesCount'].nil?
      print "Jobs: #{cluster['jobsCount']}".center(20) if !cluster['jobsCount'].nil?
      print "Pods: #{cluster['podsCount']}".center(20) if !cluster['podsCount'].nil?
      print "Deployments: #{cluster['deploymentsCount']}".center(20) if !cluster['deploymentsCount'].nil?
      print "\n"

      if options[:show_masters]
        masters_json = @clusters_interface.list_masters(cluster['id'], options)
        if masters_json.nil? || masters_json['masters'].empty?
          print_h2 "Masters"
          print cyan,"No masters found.",reset,"\n"
        else
          masters = masters_json['masters']
          print_h2 "Masters"
          rows = masters.collect do |server|
            {
              id: server['id'],
              name: server['name'],
              type: (server['type']['name'] rescue server['type']),
              status: format_server_status(server),
              power: format_server_power_state(server, cyan)
            }
          end
          columns = [:id, :name, :status, :power]
          puts as_pretty_table(rows, columns, options)
        end
      end
      if options[:show_workers]
        workers_json = @clusters_interface.list_workers(cluster['id'], options)
        if workers_json.nil? || workers_json['workers'].empty?
          print_h2 "Workers"
          print cyan,"No workers found.",reset,"\n"
        else
          workers = workers_json['workers']
          print_h2 "Workers"
          rows = workers.collect do |server|
            {
              id: server['id'],
              name: server['name'],
              type: (server['type']['name'] rescue server['type']),
              status: format_server_status(server),
              power: format_server_power_state(server, cyan)
            }
          end
          columns = [:id, :name, :status, :power]
          puts as_pretty_table(rows, columns, options)
        end
      end

      if worker_stats
        print_h2 "Worker Usage"
        print cyan
        # print "CPU Usage: #{worker_stats['cpuUsage']}".center(20)
        # print "Memory: #{worker_stats['usedMemory']}".center(20)
        # print "Storage: #{worker_stats['usedStorage']}".center(20)
        print_stats_usage(worker_stats, {include: [:max_cpu, :avg_cpu, :memory, :storage]})
        print reset,"\n"
      end

      if options[:show_perms]
        permissions = cluster['permissions']
        print_permissions(permissions)
      end

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(cluster['status'])
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      opts.on('-w','--wiki', "Open the wiki tab for this cluster") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View a cluster in a web browser" + "\n" +
                    "[cluster] is required. This is the name or id of a cluster. Supports 1-N [cluster] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _view(arg, options)
    end
  end


  def _view(arg, options={})
    begin
      cluster = find_cluster_by_name_or_id(arg)
      return 1 if cluster.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/clusters/#{cluster['id']}"
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

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name]")
      opts.on( '--name NAME', "Cluster Name" ) do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on( '--resource-name NAME', "Resource Name" ) do |val|
        options[:resourceName] = val.to_s
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang' (sets server tags only)") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang' (sets server tags only)") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('-l', '--labels [LIST]', String, "Labels (sets both cluster and server)") do |val|
        options[:labels] = parse_labels(val)
        options[:resource_labels] ||= options[:labels]
      end
      opts.on('--resource-labels [LIST]', String, "Resource Labels (override server labels)") do |val|
        options[:resource_labels] = parse_labels(val)
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-t', '--cluster-type TYPE', "Cluster Type Name or ID" ) do |val|
        options[:clusterType] = val
      end
      opts.on( '-l', '--layout LAYOUT', "Layout Name or ID" ) do |val|
        options[:layout] = val
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options[:visibility] = val
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on('--workflow ID', String, "Workflow") do |val|
        options[:workflow] = val.to_i
      end
      add_server_options(opts, options)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a cluster.\n" +
                    "[name] is required. This is the name of the new cluster."
    end

    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        payload['cluster'] ||= {}
        if options[:options]
          payload['cluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
        if args[0]
          payload['cluster']['name'] = args[0]
        elsif options[:name]
          payload['cluster']['name'] = options[:name]
        end
        # if args[1]
        #   payload['cluster']['description'] = args[1]
        # elsif options[:description]
        #   payload['cluster']['description'] = options[:description]
        # end
        payload['cluster']['server'] ||= {}
        if options[:resourceName]
          payload['cluster']['server']['name'] = options[:resourceName]
        end
        if options[:description]
          payload['cluster']['description'] = options[:description]
        end
        if options[:labels]
          payload['cluster']['labels'] = options[:labels]
        end
        if options[:resource_labels]
          payload['cluster']['server'] ||= {}
          payload['cluster']['server']['labels'] = options[:resource_labels]
        end
      else
        cluster_payload = {}
        server_payload = {"config" => {}}

        # Cluster Type
        cluster_type_id = nil
        cluster_type = options[:clusterType] ? find_cluster_type_by_name_or_id(options[:clusterType]) : nil

        if cluster_type
          cluster_type_id = cluster_type['id']
        else
          available_cluster_types = cluster_types_for_dropdown

          if available_cluster_types.empty?
            print_red_alert "A cluster type is required"
            exit 1
          elsif available_cluster_types.count > 1 && !options[:no_prompt]
            cluster_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'clusterType', 'type' => 'select', 'fieldLabel' => 'Cluster Type', 'selectOptions' => cluster_types_for_dropdown, 'required' => true, 'description' => 'Select Cluster Type.'}],options[:options],@api_client,{})['clusterType']
          else
            cluster_type_code = available_cluster_types.first['code']
          end
          cluster_type = get_cluster_types.find { |ct| ct['code'] == cluster_type_code }
        end

        cluster_payload['type'] = cluster_type['code'] # {'id' => cluster_type['id']}

        # Group / Site
        group = load_group(cluster_type['code'], options)
        cluster_payload['group'] = {'id' => group['id']}

        # Cluster Name
        if args.empty? && options[:no_prompt]
          print_red_alert "No cluster name provided"
          exit 1
        elsif !args.empty?
          cluster_payload['name'] = args[0]
        elsif options[:name]
          cluster_payload['name'] = options[:name]
        else
          existing_cluster_names = @clusters_interface.list()['clusters'].collect { |cluster| cluster['name'] }
          while cluster_payload['name'].empty?
            name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Cluster Name', 'required' => true, 'description' => 'Cluster Name.'}],options[:options],@api_client,{})['name']

            if existing_cluster_names.include?(name)
              print_red_alert "Name must be unique, #{name} already exists"
            else
              cluster_payload['name'] = name
            end
          end
        end

        # Cluster Description
        # if !args.empty? && args.count > 1
        #   cluster_payload['description'] = args[1]
        # elsif options[:description]
        #   cluster_payload['description'] = options[:description]
        # elsif !options[:no_prompt]
        #   cluster_payload['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Cluster Description', 'required' => false, 'description' => 'Cluster Description.'}],options[:options],@api_client,{})['description']
        # end

        # Resource Name
        resourceName = options[:resourceName]

        if !resourceName
          resourceName = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'resourceName', 'type' => 'text', 'fieldLabel' => 'Resource Name', 'required' => false, 'description' => 'Resource Name.'}],options[:options],@api_client,{})['resourceName']
        end

        server_payload['name'] = resourceName

        # Resource Description
        description = options[:description] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false, 'description' => 'Resource Description.'}],options[:options],@api_client,{})['description']
        cluster_payload['description'] = description if description

        # Labels
        labels = options[:labels]
        if !labels && !options[:no_prompt]
          labels = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'labels', 'type' => 'text', 'fieldLabel' => 'Labels', 'required' => false, 'description' => 'Resource Labels.'}],options[:options],@api_client,{})['labels']
        end
        if labels
          cluster_payload['labels'] = labels
          server_payload['labels'] = labels
        end

        # --resource-labels to override
        if options[:resource_labels]
          server_payload['labels'] = options[:resource_labels]
        end

        # Cloud / Zone
        cloud_id = nil
        cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group['id'], options[:cloud]) : nil
        if cloud
          # load full cloud
          cloud = @clouds_interface.get(cloud['id'])['zone']
          cloud_id = cloud['id']
        else
          available_clouds = get_available_clouds(group['id'], {groupType: cluster_payload['type']})

          if available_clouds.empty?
            print_red_alert "Group #{group['name']} has no available clouds"
            exit 1
          else
            cloud_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => available_clouds, 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group['id']})['cloud']
          end
          cloud = @clouds_interface.get(cloud_id)['zone']
        end

        cloud['zoneType'] = get_cloud_type(cloud['zoneType']['id'])
        cluster_payload['cloud'] = {'id' => cloud['id']}

        # Layout
        layout = options[:layout] ? find_layout_by_name_or_id(options[:layout]) : nil

        if !layout
          available_layouts = layouts_for_dropdown(cloud['id'], cluster_type['id'])

          if !available_layouts.empty?
            layout_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'select', 'fieldLabel' => 'Layout', 'selectOptions' => available_layouts, 'required' => true, 'description' => 'Select Layout.'}],options[:options],@api_client,{})['layout']
            layout = find_layout_by_name_or_id(layout_id)
          end
        end

        cluster_payload['layout'] = {'id' => layout['id']}

        # Provision Type
        provision_type = (layout && layout['provisionType'] ? layout['provisionType'] : nil) || get_provision_type_for_zone_type(cloud['zoneType']['id'])
        provision_type = @provision_types_interface.get(provision_type['id'])['provisionType'] if !provision_type.nil?
        api_params = {zoneId: cloud['id'], siteId: group['id'], layoutId: layout['id'], groupTypeId: cluster_type['id'], provisionType: provision_type['code'], provisionTypeId: provision_type['id']}

        # Service Plan
        service_plan = prompt_service_plan(api_params, options)
        if service_plan
          server_payload['plan'] = {'id' => service_plan['id'], 'code' => service_plan['code']}
          api_params['planId'] = service_plan['id']
          plan_opts = prompt_service_plan_options(service_plan, provision_type, options)
          server_payload['servicePlanOptions'] = plan_opts if plan_opts && !plan_opts.empty?
        end

        # Controller type
        server_types = @server_types_interface.list({computeTypeId: cluster_type['controllerTypes'].first['id'], zoneTypeId: cloud['zoneType']['id'], useZoneProvisionTypes: true})['serverTypes'].reject {|it| it['provisionType']['code'] == 'manual'} unless ['mvm-cluster'].include?(cluster_type_code)
        controller_provision_type = nil
        resource_pool = nil

        if !server_types.empty?
          controller_type = server_types.first
          if controller_type['provisionType']
            if provision_type && provision_type['id'] == controller_type['provisionType']['id']
              controller_provision_type = provision_type
            else
              controller_provision_type = @provision_types_interface.get(controller_type['provisionType']['id'])['provisionType'] rescue nil
            end
          end

          if controller_provision_type && resource_pool = prompt_resource_pool(group, cloud, service_plan, controller_provision_type, options)
            if resource_pool
              server_payload['config']['resourcePoolId'] = resource_pool['id']
              api_params['config'] ||= {}
              api_params['config']['resourcePool'] = resource_pool['id']
              api_params['resourcePoolId'] = resource_pool['id']
              api_params['zonePoolId'] = resource_pool['id']
            end
          end
        end

        # Multi-disk / prompt for volumes
        if provision_type['hasVolumes']
          volumes = options[:volumes] || prompt_volumes(service_plan, provision_type, options, @api_client, api_params)
          if !volumes.empty?
            server_payload['volumes'] = volumes
          end
        end

        # Options / Custom Config
        option_type_list =
          ((controller_type.nil? ? [] : controller_type['optionTypes'].reject { |type| !type['enabled'] || type['fieldComponent'] } rescue []) +
          layout['optionTypes'] +
          (cluster_type['optionTypes'].reject { |type| 
            !type['enabled'] || !type['creatable'] || type['fieldComponent']
          } rescue []))


        # remove metadata option_type , prompt manually for that field 'tags' instead of 'metadata'
        metadata_option_type = option_type_list.find {|type| type['fieldName'] == 'metadata' }
        option_type_list = option_type_list.reject {|type| type['fieldName'] == 'metadata' }

        # remove load balancer option_type, prompt manually
        loadbalancer_option_type = option_type_list.find{|type| type['fieldName'] == 'loadBalancerId'}
        option_type_list = option_type_list.reject { |type| type['fieldName'] == 'loadBalancerId' }

        server_count = layout['serverCount']

        # KLUDGE: google zone required for network selection
        if option_type = option_type_list.find {|type| type['code'] == 'computeServerType.googleLinux.googleZoneId'}
          server_payload.deep_merge!(Morpheus::Cli::OptionTypes.prompt([option_type], options[:options], @api_client, api_params))
          api_params.deep_merge!(server_payload)
          api_params.deep_merge!(server_payload['config'])
          option_type_list = option_type_list.reject {|type| type['code'] == 'computeServerType.googleLinux.googleZoneId'}
        end

        # Networks
        # NOTE: You must choose subnets in the same availability zone
        if controller_provision_type && controller_provision_type['hasNetworks'] && cloud['zoneType']['code'] != 'esxi'
          server_payload['networkInterfaces'] = options[:networkInterfaces] || prompt_network_interfaces(cloud['id'], provision_type['id'], (resource_pool['id'] rescue nil), options.merge({:api_params => api_params}))
        end

        # Security Groups
        server_payload['securityGroups'] = prompt_security_groups_by_cloud(cloud, provision_type, resource_pool, options)

        # KLUDGE part 2: need to ask for hauwei floating ip option
        if option_type = option_type_list.find {|type| type['code'] == 'computeServerType.openstackLinux.selectFloatingIp'}
          floating_ip = load_floating_options(cluster_payload, options)
          if floating_ip != nil 
            server_payload['config']['osExternalNetworkId'] = floating_ip
          end
        end

        # Visibility
        server_payload['visibility'] = options[:visibility] || (Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'defaultValue' => 'private', 'required' => true, 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}]}], options[:options], @api_client, {})['visibility'])

        # Layout template options
        cluster_payload.deep_merge!(Morpheus::Cli::OptionTypes.prompt(load_layout_options(cluster_payload), options[:options], @api_client, api_params, options[:no_prompt], true))

        # Set node count for ssh hosts
        ssh_host_option = option_type_list.select{|it| it['fieldName'] == 'sshHosts'}.first
        ssh_host_option['minCount'] = server_count unless ssh_host_option.nil?

        # Server options
        server_payload.deep_merge!(Morpheus::Cli::OptionTypes.prompt(option_type_list, options[:options].deep_merge({:context_map => {'domain' => ''}}), @api_client, api_params, options[:no_prompt], true))

        # Metadata Tags
        if metadata_option_type
          if options[:metadata]
            metadata = parse_metadata(options[:metadata])
            server_payload['tags'] = metadata if !metadata.empty?
          else
            metadata = prompt_metadata(options)
            server_payload['tags'] = metadata if !metadata.empty?
          end
        end

        # Worker count
        if !['manual', 'external'].include?(provision_type['code'])
          default_node_count = layout['computeServers'] ? (layout['computeServers'].find {|it| it['nodeType'] == 'worker'} || {'nodeCount' => 3})['nodeCount'] : 3
          nodeCount = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "config.nodeCount", 'type' => 'number', 'fieldLabel' => "#{['docker-cluster', 'kvm-cluster'].include?(cluster_type['code']) ? 'Host' : 'Worker'} Count", 'required' => true, 'defaultValue' => default_node_count > 0 ? default_node_count : 3}], options[:options], @api_client, api_params, options[:no_prompt])['config']['nodeCount']
          server_payload['config']['nodeCount'] = nodeCount
          server_payload['nodeCount'] = nodeCount
        end

        # Create User
        if !options[:createUser].nil?
          server_payload['config']['createUser'] = options[:createUser]
        elsif !options[:no_prompt]
          current_user['windowsUsername'] || current_user['linuxUsername']
          server_payload['config']['createUser'] = (current_user['windowsUsername'] || current_user['linuxUsername']) && Morpheus::Cli::OptionTypes.confirm("Create Your User?", {:default => true})
        end

        # User Groups
        userGroup = options[:userGroup] ? find_user_group_by_name_or_id(nil, options[:userGroup]) : nil

        if userGroup
          server_payload['userGroup'] = userGroup
        elsif !options[:no_prompt]
          userGroupId = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'userGroupId', 'fieldLabel' => 'User Group', 'type' => 'select', 'required' => false, 'optionSource' => 'userGroups'}], options[:options], @api_client, api_params)['userGroupId']

          if userGroupId
            server_payload['userGroup'] = {'id' => userGroupId}
          end
        end

        # Host / Domain
        server_payload['networkDomain'] = options[:domain] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkDomain', 'fieldLabel' => 'Network Domain', 'type' => 'select', 'required' => false, 'optionSource' => 'networkDomains'}], options[:options], @api_client, api_params)['networkDomain']
        server_payload['hostname'] = options[:hostname] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hostname', 'fieldLabel' => 'Hostname', 'type' => 'text', 'required' => false, 'description' => 'Hostname', 'defaultValue' => resourceName}], options[:options], @api_client, api_params)['hostname']

        # Kube Default Repo
        if cluster_payload['type'] == 'kubernetes-cluster'
          default_repo = options[:default_repo] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultRepoAccount', 'fieldLabel' => 'Cluster Repo Account', 'type' => 'select', 'required' => false, 'optionSource' => 'dockerHubRegistries'}], options[:options], @api_client, api_params)['defaultRepoAccount']
          if default_repo != ""
            server_payload['config']['defaultRepoAccount'] = default_repo

            # Act As Image Server
            image_server = !options[:image_server].nil? ? options[:image_server] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'imageServer', 'fieldLabel' => 'Act As Image Server', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'on'}], options[:options], @api_client, api_params)['imageServer']
            if image_server != ""
              # api used to expect "on" so don't booleanize this one
              server_payload['config']['imageServer'] = image_server ? 'on' : 'off'
            end
          end
        end

        # Workflow / Automation
        if provision_type['code'] != 'manual' && controller_type && controller_type['hasAutomation']
          task_set_id = options[:workflow] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'taskSetId', 'fieldLabel' => 'Workflow', 'type' => 'select', 'required' => false, 'optionSource' => 'taskSets'}], options[:options], @api_client, api_params.merge({'phase' => 'postProvision'}))['taskSetId']

          if !task_set_id.nil?
            # server_payload['taskSet'] = {'id' => task_set_id}
            cluster_payload['taskSetId'] = task_set_id
          end
        end

        if loadbalancer_option_type
          lb_payload = { computeTypeLayoutId: cluster_payload['layout']['id']}
          # look to see if "can provision Kubevip" if so pass true as third param
          load_balancer_id = prompt_cluster_load_balancer(cluster_payload, options, can_use_kubevip(provision_type["code"], cluster_payload["type"]))
          if load_balancer_id != false
            lb_payload['loadBalancerId'] = load_balancer_id
            lb_payload['loadBalancerInstanceId'] = -1
            lb_port_result = @clusters_interface.load_balancer_port(lb_payload)
            lb_options = lb_port_result['optionTypes']
            lb_option_results = Morpheus::Cli::OptionTypes.prompt(lb_options, options[:options], @api_client, api_params)

            load_balancer_payload = {
              port: lb_port_result.dig('loadBalancerPort', 'externalPort'),
              enabled: lb_port_result.dig('loadBalancer', 'enabled'),
              loadBalancerId: load_balancer_id,
              backendPort: lb_port_result.dig('loadBalancerPort', 'internalPort'),
              loadBalancer: { id: load_balancer_id },
              vipPool: (lb_option_results.dig('domain', 'vipPool') == 'none') ? nil : lb_option_results.dig('domain', 'vipPool'),
              vipAddress: lb_option_results.dig('domain', 'vipAddress'),
              externalAddress: (lb_port_result.dig('loadBalancer', 'externalAddress') == true ) ? 'on': 'off',
              vipShared: (lb_port_result.dig('loadBalancer', 'vipShared') == true ) ? 'on' : 'off',
              vipProtocol: lb_port_result.dig('loadBalancerPort', 'loadBalanceProtocol'),
              instanceId: lb_payload['loadBalancerInstanceId'],
              name: lb_option_results['vipName']
            }
            if lb_option_results['domain']
              load_balancer_payload.merge!(lb_option_results['domain']) { |key, old_val, new_val| old_val }
            end
            cluster_payload['lbInstances'] = [load_balancer_payload.compact!]
          end
        end
        # convert sshHosts to array
        if server_payload['sshHosts']
          if server_payload['sshHosts'].is_a?(String)
            server_payload['sshHosts'] = server_payload['sshHosts'].split(",").collect {|it| {"ip" => it} }
          elsif server_payload['sshHosts'].is_a?(Object)
            server_payload['sshHosts'] = [server_payload['sshHosts']]
          elsif server_payload['sshHosts'].is_a?(Array)
            server_payload['sshHosts'] = server_payload['sshHosts'].collect {|it| it.is_a?(String) ? {"ip" => it} : it }
          end

          # inject the optionalNames array into the sshHosts if present
          if server_payload['optionalNames']
            optional_names = server_payload['optionalNames'].is_a?(String) ? server_payload['optionalNames'].split(",") : [server_payload['optionalNames']].flatten
            server_payload['sshHosts'].each_with_index do|host, i| 
              host['name'] = optional_names[i].strip if optional_names[i]
            end
          end
        end

        cluster_payload['server'] = server_payload
        payload = {'cluster' => cluster_payload}
      end
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.create(payload)
        return
      end
      json_response = @clusters_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["cluster"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] --name --description --active")
      opts.on("--name NAME", String, "Updates Cluster Name") do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Updates Cluster Description") do |val|
        options[:description] = val.to_s
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:labels] = parse_labels(val)
      end
      opts.on("--api-url [TEXT]", String, "Updates Cluster API Url") do |val|
        options[:apiUrl] = val.to_s
      end
      opts.on("--api-token [TEXT]", String, "Updates Cluster API Token") do |val|
        options[:apiToken] = val.to_s
      end
      opts.on('--active [on|off]', String, "Can be used to enable / disable the cluster. Default is on") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--managed [on|off]', String, "Can be used to enable / disable managed cluster. Default is on") do |val|
        options[:managed] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--useAgent [on|off]', String, "Use the Agent to relay communications for the Kubernetes API instead of direct.") do |val|
        options[:useAgent] = val.to_s
      end
      opts.on('--autoRecoverPowerState [on|off]', String, "Automatically Power On VMs") do |val|
        options[:autoRecoverPowerState] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on( nil, '--refresh', "Refresh cluster" ) do
        options[:refresh] = true
      end
      opts.on("--tenant ACCOUNT", String, "Account ID or Name" ) do |val|
        options[:tenant] = val
      end
      opts.on('--integrations [LIST]', Array, "Updates Cluster Integration(s), comma separated list of integration IDs") do |list|
        options[:integrations] = list ? list.collect {|it| it.to_s.strip.to_i } : []
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      payload = nil
      cluster = nil

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['cluster'] ||= {}
          payload['cluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end

        if !payload['cluster'].empty?
          cluster = find_cluster_by_name_or_id(payload['cluster']['id'] || payload['cluster']['name'])
        end
      else
        cluster = find_cluster_by_name_or_id(args[0])
        cluster_payload = {}
        cluster_payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        cluster_payload['name'] = options[:name] if !options[:name].empty?
        cluster_payload['description'] = options[:description] if !options[:description].empty?
        cluster_payload['labels'] = options[:labels] if !options[:labels].nil?
        cluster_payload['enabled'] = options[:active] if !options[:active].nil?
        cluster_payload['managed'] = options[:managed] if !options[:managed].nil?
        cluster_payload['autoRecoverPowerState'] = options[:autoRecoverPowerState] if !options[:autoRecoverPowerState].nil?
        cluster_payload['serviceUrl'] = options[:apiUrl] if !options[:apiUrl].nil?
        cluster_payload['serviceToken'] = options[:apiToken] if !options[:apiToken].nil?
        cluster_payload['refresh'] = options[:refresh] if options[:refresh] == true
        cluster_payload['tenant'] = options[:tenant] if !options[:tenant].nil?
        cluster_payload['integrations'] = options[:integrations] if !options[:integrations].nil?
        cluster_payload['useAgent'] = options[:useAgent] if !options[:useAgent].nil?
        payload = {"cluster" => cluster_payload}
      end

      if !cluster
        print_red_alert "No clusters available for update"
        exit 1
      end
      
      if payload['cluster'].empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.update(cluster['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["cluster"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    end
  end

  def remove(args)
    options = {}
    query_params = {:removeResources => 'on'}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      opts.on('--remove-resources [on|off]', ['on','off'], "Remove Infrastructure. Default is on.") do |val|
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
      opts.footer = "Delete a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster '#{cluster['name']}'?", options)
        return 9, "aborted command"
      end
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy(cluster['id'], query_params)
        return
      end
      json_response = @clusters_interface.destroy(cluster['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        msg = "Cluster #{cluster['name']} is being removed..."
        if json_response['msg'] != nil && json_response['msg'] != ''
          msg = json_response['msg']
        end
        print_green_success msg
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
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
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      params = {}
      params['level'] = params['level'].collect {|it| it.to_s.upcase }.join('|') if params['level'] # api works with INFO|WARN
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.cluster_logs(cluster['id'], params)
        return
      end
      json_response = @logs_interface.cluster_logs(cluster['id'], params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result

      logs = json_response
      title = "Cluster Logs: #{cluster['name']}"
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
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      logs = json_response['data'] || json_response['logs']
      print_h1 title, subtitles, options
      if logs.empty?
        puts "#{cyan}No logs found.#{reset}"
      else
        logs.each do |log_entry|
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
        print_results_pagination({'meta'=>{'total'=>json_response['total'],'size'=>json_response['data'].size,'max'=>(json_response['max'] || options[:max]),'offset'=>(json_response['offset'] || options[:offset] || 0)}})
      end
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      add_perms_options(opts, options)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a clusters permissions.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['permissions'] ||= {}
          payload['permissions'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        payload = {"permissions" => prompt_permissions(options.merge({:available_plans => namespace_service_plans}))}
        # if payload["permissions"] && payload["permissions"]["resourcePool"]
        #   payload["permissions"].delete("resourcePool")
        # end
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update_permissions(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.update_permissions(cluster['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["cluster"]["id"], '--permissions'] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    end
  end

  def list_workers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List workers for a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_workers(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_workers(cluster['id'], params)
      
      render_result = render_with_format(json_response, options, 'workers')
      return 0 if render_result

      title = "Morpheus Cluster Workers: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      workers = json_response['workers']
      if workers.empty?
        print cyan,"No workers found.",reset,"\n"
      else
        # more stuff to show here
        
        servers = workers
        multi_tenant = false

        # print_servers_table(servers)
        rows = servers.collect {|server|
          stats = server['stats']

          if !stats['maxMemory']
            stats['maxMemory'] = stats['usedMemory'] + stats['freeMemory']
          end
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          if options[:details]
            if stats['maxMemory'] && stats['maxMemory'].to_i != 0
              memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(8, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
            end
            if stats['maxStorage'] && stats['maxStorage'].to_i != 0
              storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(8, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
            end
          end
          row = {
            id: server['id'],
            tenant: server['account'] ? server['account']['name'] : server['accountId'],
            name: server['name'],
            platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A',
            cloud: server['zone'] ? server['zone']['name'] : '',
            type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged',
            nodes: server['containers'] ? server['containers'].size : '',
            status: format_server_status(server, cyan),
            power: format_server_power_state(server, cyan),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, :name, :type, :cloud, :nodes, :status, :power]
        if multi_tenant
          columns.insert(4, :tenant)
        end
        columns += [:cpu, :memory, :storage]
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
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

  def add_worker(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [options]")
      opts.on("--name NAME", String, "Name of the new worker") do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:labels] = parse_labels(val)
      end
      add_server_options(opts, options)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Add worker to a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" + 
                    "[name] is required. This is the name of the new worker."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['server'] ||= {}
          payload['server'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        server_payload = {'config' => {}}

        cluster_type = find_cluster_type_by_id(cluster['type']['id'])

        # If not available add set type return
        layout = find_layout_by_id(cluster['layout']['id'])

        # currently limiting to just worker types
        available_type_sets = layout['computeServers'].reject {|typeSet| !typeSet['dynamicCount']}

        if available_type_sets.empty?
          print_red_alert "Cluster #{cluster['name']} has no available server types to add"
          exit 1
        else
          type_set = available_type_sets[0]
        end

        # find servers within cluster
        server_matches = cluster['servers'].reject {|server| server['typeSet']['id'] != type_set['id']}
        server_type = find_server_type_by_id(server_matches.count > 0 ? server_matches[0]['computeServerType']['id'] : type_set['computeServerType']['id'])
        server_payload['serverType'] = {'id' => server_type['id']}

        # Name
        if options[:name].empty?
          default_name = (server_matches.count ? server_matches[0]['name'] : nil) || cluster['name']
          default_name.delete_prefix!(type_set['namePrefix']) if !type_set['namePrefix'].empty?
          default_name = default_name[0..(default_name.index(type_set['nameSuffix']) - 1)] if !type_set['nameSuffix'].nil? && default_name.index(type_set['nameSuffix'])
          default_name = (type_set['namePrefix'] || '') + default_name + (type_set['nameSuffix'] || '') + '-' + (server_matches.count + 1).to_s
          server_payload['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'Worker Name.', 'defaultValue' => default_name}],options[:options],@api_client,{})['name']
        else
          server_payload['name'] = options[:name]
        end

        # Description
        server_payload['description'] = options[:description] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Worker Description'}], options[:options], @api_client)['description']

        # Labels
        labels = options[:labels]
        if !labels && !options[:no_prompt]
          labels = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'labels', 'type' => 'text', 'fieldLabel' => 'Resource Labels', 'required' => false, 'description' => 'Resource Labels.'}],options[:options],@api_client,{})['labels']
        end

        server_payload['labels'] = labels if labels

        # Cloud
        available_clouds = options_interface.options_for_source('clouds', {groupId: cluster['site']['id'], clusterId: cluster['id'], ownerOnly: true})['data']
        cloud_id = nil

        if options[:cloud]
          cloud = available_clouds.find {|it| it['value'].to_s == options[:cloud].to_s || it['name'].casecmp?(options[:cloud].to_s)}

          if !cloud
            print_red_alert "Cloud #{options[:cloud]} is not a valid option for cluster #{cluster['name']}"
            exit 1
          end
          cloud_id = cloud['value']
        end

        if !cloud_id
          default_cloud = available_clouds.find {|it| it['value'] == cluster['zone']['id']}
          cloud_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => available_clouds, 'description' => 'Cloud', 'required' => true, 'defaultValue' => (default_cloud ? default_cloud['name'] : nil)}], options[:options], @api_client)['cloud']
          cloud_id = (default_cloud && cloud_id == default_cloud['name']) ? default_cloud['value'] : cloud_id
        end

        # resources (zone pools)
        cloud = @clouds_interface.get(cloud_id)['zone']
        cloud['zoneType'] = get_cloud_type(cloud['zoneType']['id'])
        group = @groups_interface.get(cluster['site']['id'])['group']
        provision_type = server_type['provisionType'] || {}
        provision_type = @provision_types_interface.get(provision_type['id'])['provisionType'] if !provision_type.nil?
        
        server_payload['cloud'] = {'id' => cloud_id}
        service_plan = prompt_service_plan({zoneId: cloud_id, siteId: cluster['site']['id'], provisionTypeId: server_type['provisionType']['id'], groupTypeId: cluster_type['id'], }, options)

        if service_plan
          server_payload['plan'] = {'code' => service_plan['code']}
          plan_opts = prompt_service_plan_options(service_plan, nil, options)
          server_payload['servicePlanOptions'] = plan_opts if plan_opts && !plan_opts.empty?
        end

        if resource_pool = prompt_resource_pool(cluster, cloud, service_plan, server_type['provisionType'], options)
          server_payload['config']['resourcePoolId'] = resource_pool['id']
        end

        # Multi-disk / prompt for volumes
        volumes = options[:volumes] || prompt_volumes(service_plan, provision_type, options, @api_client, {zoneId: cloud['id'], siteId: group['id']})

        if !volumes.empty?
          server_payload['volumes'] = volumes
        end

        # Networks
        # NOTE: You must choose subnets in the same availability zone
        if provision_type && cloud['zoneType']['code'] != 'esxi'
          server_payload['networkInterfaces'] = options[:networkInterfaces] || prompt_network_interfaces(cloud['id'], server_type['provisionType']['id'], (resource_pool['id'] rescue nil), options)
        end

        # Security Groups
        server_payload['securityGroups'] = prompt_security_groups_by_cloud(cloud, provision_type, resource_pool, options)

        # Worker count
        default_node_count = layout['computeServers'] ? (layout['computeServers'].find {|it| it['nodeType'] == 'worker'} || {'nodeCount' => 1})['nodeCount'] : 1
        server_payload['nodeCount'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "nodeCount", 'type' => 'number', 'fieldLabel' => "#{cluster_type['code'].include?('docker') ? 'Host' : 'Worker'} Count", 'required' => true, 'defaultValue' => default_node_count}], options[:options], @api_client, {}, options[:no_prompt])["nodeCount"]

        # Options / Custom Config
        option_type_list = (server_type['optionTypes'].reject { |type|
          !type['enabled'] || type['fieldComponent'] ||
          (['provisionType.vmware.host', 'provisionType.scvmm.host'].include?(type['code']) && cloud['config']['hideHostSelection'] == 'on') || # should this be truthy?
          (type['fieldContext'] == 'instance.networkDomain' && type['fieldName'] == 'id')
        } rescue [])
        # strip server context
        option_type_list.each do |option_type|
          if option_type['fieldContext'] == 'server' || option_type['fieldContext'] == 'domain'
            option_type['fieldContext'] = nil
          end
        end
        # remove metadata option_type , prompt manually for that field 'tags' instead of 'metadata'
        #metadata_option_type = option_type_list.find {|type| type['fieldName'] == 'metadata' }
        metadata_option_type = cluster_type['optionTypes'].find {|type| type['fieldName'] == 'metadata' }
        option_type_list = option_type_list.reject {|type| type['fieldName'] == 'metadata' }

        server_payload.deep_merge!(Morpheus::Cli::OptionTypes.prompt(option_type_list, options[:options], @api_client, {zoneId: cloud['id'], siteId: group['id'], layoutId: layout['id']}))

        # Metadata Tags
        if metadata_option_type
          if options[:metadata]
            metadata = parse_metadata(options[:metadata])
            server_payload['tags'] = metadata if !metadata.empty?
          else
            metadata = prompt_metadata(options)
            server_payload['tags'] = metadata if !metadata.empty?
          end
        end

        # Create User
        if !options[:createUser].nil?
          server_payload['config']['createUser'] = options[:createUser]
        elsif !options[:no_prompt]
          server_payload['config']['createUser'] = (current_user['windowsUsername'] || current_user['linuxUsername']) && Morpheus::Cli::OptionTypes.confirm("Create Your User?", {:default => true})
        end

        # User Groups
        userGroup = options[:userGroup] ? find_user_group_by_name_or_id(nil, options[:userGroup]) : nil

        if userGroup
          server_payload['userGroup'] = userGroup
        elsif !options[:no_prompt]
          userGroupId = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'userGroupId', 'fieldLabel' => 'User Group', 'type' => 'select', 'required' => false, 'optionSource' => 'userGroups'}], options[:options], @api_client, {})['userGroupId']

          if userGroupId
            server_payload['userGroup'] = {'id' => userGroupId}
          end
        end

        # Host / Domain
        server_payload['networkDomain'] = options[:domain] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkDomain', 'fieldLabel' => 'Network Domain', 'type' => 'select', 'required' => false, 'optionSource' => 'networkDomains'}], options[:options], @api_client, {})['networkDomain']
        server_payload['hostname'] = options[:hostname] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hostname', 'fieldLabel' => 'Hostname', 'type' => 'text', 'required' => true, 'description' => 'Hostname', 'defaultValue' => server_payload['name']}], options[:options], @api_client)['hostname']

        # Workflow / Automation
        if !options[:no_prompt]
          task_set_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'taskSet', 'fieldLabel' => 'Workflow', 'type' => 'select', 'required' => false, 'optionSource' => 'taskSets'}], options[:options], @api_client, {'phase' => 'postProvision', 'taskSetType' => 'provision'})['taskSet']

          if task_set_id
            server_payload['taskSet'] = {'id' => task_set_id}
          end
        end
        payload = {'server' => server_payload}
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.add_server(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.add_server(cluster['id'], payload)
      if options[:json]
        puts as_json(json_response)
      elsif json_response['success']
        if json_response['msg'] == nil
          print_green_success "Added worker to cluster #{cluster['name']}"
        else
          print_green_success json_response['msg']
        end
        #get_args = [json_response["cluster"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        #get(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_worker(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [worker]")
      opts.on( '-f', '--force', "Force Delete" ) do
        params[:force] = 'on'
        end
      build_standard_remove_options(opts, options)
      opts.footer = "Delete a worker from a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[worker] is required. This is the name or (server) id of an existing worker."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    params.merge!(parse_query_options(options))

    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    worker_id = args[1]
    if worker_id.empty?
      raise_command_error "missing required worker parameter"
    end

    worker = find_worker_by_name_or_id(cluster['id'], worker_id)
    if worker.nil?
      print_red_alert "Worker not found for '#{worker_id}'"
      return 1
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster worker '#{worker['name'] || worker['id']}'?", options)
      return 9, "aborted command"
    end

    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.destroy_worker(cluster['id'], worker['id'], params)
      return
    end
    json_response = @clusters_interface.destroy_worker(cluster['id'], worker['id'], params)
    render_response(json_response, options) do
      msg = "Worker #{worker['name']} is being removed from cluster #{cluster['name']}..." 
      if json_response['msg']
        msg = json_response['msg']
      end
      print_green_success msg
    end
    return 0, nil
  end

  def update_worker_count(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [worker_count]")
      build_standard_update_options(opts, options)
      opts.footer = "Resizes a cluster to the specified number of worker nodes.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[worker_count] is required. This is the desired number of workers."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)

    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    worker_count = args[1]
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'workerCount' => worker_count.to_i})
    else
      payload.deep_merge!({'workerCount' => worker_count.to_i})
    end
    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.update_worker_count(cluster['id'], payload)
      return
    end
    json_response = @clusters_interface.update_worker_count(cluster['id'], payload)
    render_response(json_response, options) do
      print_green_success "Cluster #{cluster['name']} is being resized to #{worker_count} worker nodes..." 
    end
    return 0, nil
  end

  def list_masters(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List masters for a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_masters(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_masters(cluster['id'], params)
      
      render_result = render_with_format(json_response, options, 'masters')
      return 0 if render_result

      title = "Morpheus Cluster Masters: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      masters = json_response['masters']
      if masters.empty?
        print cyan,"No masters found.",reset,"\n"
      else
        # more stuff to show here
        
        servers = masters
        multi_tenant = false

        # print_servers_table(servers)
        rows = servers.collect {|server|
          stats = server['stats']

          if !stats['maxMemory']
            stats['maxMemory'] = stats['usedMemory'] + stats['freeMemory']
          end
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          if options[:details]
            if stats['maxMemory'] && stats['maxMemory'].to_i != 0
              memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(8, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
            end
            if stats['maxStorage'] && stats['maxStorage'].to_i != 0
              storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(8, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
            end
          end
          row = {
            id: server['id'],
            tenant: server['account'] ? server['account']['name'] : server['accountId'],
            name: server['name'],
            platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A',
            cloud: server['zone'] ? server['zone']['name'] : '',
            type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged',
            nodes: server['containers'] ? server['containers'].size : '',
            status: format_server_status(server, cyan),
            power: format_server_power_state(server, cyan),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, :name, :type, :cloud, :nodes, :status, :power]
        if multi_tenant
          columns.insert(4, :tenant)
        end
        columns += [:cpu, :memory, :storage]
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
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

  def upgrade_cluster(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      build_standard_update_options(opts, options)
      opts.footer = "Updates kubernetes version (kubectl and kubeadm) of the specified cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n"
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    version_options = get_valid_upgrade_versions(cluster['id'])
    version_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetVersion', 'type' => 'select', 'fieldLabel' => 'To Version', 'selectOptions' => version_options, 'required' => true, 'description' => 'Select target version.' }],options[:options],api_client,{})
    target_version = version_options.detect{ |element| element['value']  == version_prompt['targetVersion'] }['name']

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'targetVersion' => target_version})
    else
      payload.deep_merge!({'targetVersion' => target_version})
    end
    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.do_cluster_upgrade(cluster['id'], payload)
      return
    end
    json_response = @clusters_interface.do_cluster_upgrade(cluster['id'], payload)
    render_response(json_response, options) do
      print_green_success "Cluster #{cluster['name']} is being upgraded to #{target_version}..."
    end
    return 0, nil
  end

  def list_volumes(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List volumes for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_volumes(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_volumes(cluster['id'], params)

      render_result = render_with_format(json_response, options, 'volumes')
      return 0 if render_result

      title = "Morpheus Cluster Volumes: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      volumes = json_response['volumes']
      if volumes.empty?
        print cyan,"No volumes found.",reset,"\n"
      else
        # more stuff to show here
        rows = volumes.collect do |ns|
          {
              id: ns['id'],
              name: ns['name'],
              description: ns['description'],
              status: ns['status'],
              active: ns['active'],
              cluster: cluster['name']
          }
        end
        columns = [
            :id, :name, :description, :status, :active, :cluster => lambda { |it| cluster['name'] }
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_volume(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [volume]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a volume within a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[volume] is required. This is the name or id of an existing volume."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      volume_id = args[1]

      if volume_id.empty?
        raise_command_error "missing required volume parameter"
      end

      volume = find_volume_by_name_or_id(cluster['id'], volume_id)
      if volume.nil?
        print_red_alert "Volume not found for '#{volume_id}'"
        return 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster volume '#{volume['name'] || volume['id']}'?", options)
        return 9, "aborted command"
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_volume(cluster['id'], volume['id'], params)
        return
      end
      json_response = @clusters_interface.destroy_volume(cluster['id'], volume['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error removing volume #{volume['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "Volume #{volume['name']} is being removed from cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_services(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List services for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_services(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_services(cluster['id'], params)

      render_result = render_with_format(json_response, options, 'volumes')
      return 0 if render_result

      title = "Morpheus Cluster Services: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      services = json_response['services']
      if services.empty?
        print cyan,"No services found.",reset,"\n"
      else
        # more stuff to show here
        rows = services.collect do |service|
          {
              id: service['id'],
              name: service['name'],
              type: service['type'],
              externalIp: service['externalIp'],
              externalPort: service['externalPort'],
              internalPort: service['internalPort'],
              status: service['status'],
              cluster: cluster['name']
          }
        end
        columns = [
            :id, :name, :type, :externalIp, :externalPort, :internalPort, :status, :cluster => lambda { |it| cluster['name'] }
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_service(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [service]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a service within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[service] is required. This is the name or id of an existing service."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      service_id = args[1]

      if service_id.empty?
        raise_command_error "missing required service parameter"
      end

      service = find_service_by_name_or_id(cluster['id'], service_id)
      if service.nil?
        print_red_alert "Service not found by id '#{service_id}'"
        return 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster service '#{service['name'] || service['id']}'?", options)
        return 9, "aborted command"
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_service(cluster['id'], service['id'], params)
        return
      end
      json_response = @clusters_interface.destroy_service(cluster['id'], service['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error removing service #{service['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "Service #{service['name']} is being removed from cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_jobs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List jobs for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_jobs(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_jobs(cluster['id'], params)

      render_result = render_with_format(json_response, options, 'volumes')
      return 0 if render_result

      title = "Morpheus Cluster Jobs: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      jobs = json_response['jobs']
      if jobs.empty?
        print cyan,"No jobs found.",reset,"\n"
      else
        # more stuff to show here
        rows = jobs.collect do |job|
          {
              id: job['id'],
              status: job['type'],
              namespace: job['namespace'],
              name: job['name'],
              lastRun: format_local_dt(job['lastRun']),
              cluster: cluster['name']
          }
        end
        columns = [
            :id, :status, :namespace, :name, :lastRun, :cluster => lambda { |it| cluster['name'] }
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_job(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [job]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a job within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[job] is required. This is the name or id of an existing job."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      job_id = args[1]

      if job_id.empty?
        raise_command_error "missing required job parameter"
      end

      job = find_job_by_name_or_id(cluster['id'], job_id)
      if job.nil?
        print_red_alert "Job not found by id '#{job_id}'"
        return 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster job '#{job['name'] || job['id']}'?", options)
        return 9, "aborted command"
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_job(cluster['id'], job['id'], params)
        return
      end
      json_response = @clusters_interface.destroy_job(cluster['id'], job['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error removing job #{job['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "Job #{job['name']} is being removed from cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_containers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      opts.on("--worker WORKER", String, "Worker") do |val|
        options[:worker] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List containers for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      if options[:worker]
        worker = find_host_by_name_or_id(options[:worker])
        return 1 if worker.nil?
        params['workerId'] = worker['id']
      end
      params = {}
      params.merge!(parse_list_options(options))
      params['resourceLevel'] = options[:resourceLevel] if !options[:resourceLevel].nil?
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_containers(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_containers(cluster['id'], params)

      render_result = render_with_format(json_response, options, 'containers')
      return 0 if render_result

      title = "Morpheus Cluster Containers: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      containers = json_response['containers']
      if containers.empty?
        print cyan,"No containers found.",reset,"\n"
      else
        # more stuff to show here
        rows = containers.collect do |it|
          {
              id: it['id'],
              status: it['status'],
              name: it['name'],
              instance: it['instance'].nil? ? '' : it['instance']['name'],
              type: it['containerType'].nil? ? '' : it['containerType']['name'],
              location: it['ip'],
              cluster: cluster['name']
          }
        end
        columns = [
            :id, :status, :name, :instance, :type, :location, :cluster => lambda { |it| cluster['name'] }
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_container(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [container]")
      opts.on( '-f', '--force', "Force Delete" ) do
        options[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a container within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[container] is required. This is the name or id of an existing container."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      container_id = args[1]

      if container_id.empty?
        raise_command_error "missing required container parameter"
      end

      container = find_container_by_name_or_id(cluster['id'], container_id)
      if container.nil?
        print_red_alert "Container not found by id '#{container_id}'"
        return 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster container '#{container['name'] || container['id']}'?", options)
        return 9, "aborted command"
      end

      if !options[:force].nil?
          params['force'] = options[:force]
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_container(cluster['id'], container['id'], params)
        return
      end
      json_response = @clusters_interface.destroy_container(cluster['id'], container['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error removing container #{container['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "container #{container['name']} is being removed from cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart_container(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [container]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Restart a container within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[container] is required. This is the name or id of an existing container."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      container_id = args[1]

      if container_id.empty?
        raise_command_error "missing required container parameter"
      end

      container = find_container_by_name_or_id(cluster['id'], container_id)
      if container.nil?
        print_red_alert "Container not found by id '#{container_id}'"
        return 1
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.restart_container(cluster['id'], container['id'], params)
        return
      end
      json_response = @clusters_interface.restart_container(cluster['id'], container['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error restarting container #{container['name']} for cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "Container #{container['name']} is restarting for cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def _list_container_groups(args, options, resource_type)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      params['resourceLevel'] = options[:resourceLevel] if !options[:resourceLevel].nil?
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_container_groups(cluster['id'], resource_type, params)
        return
      end
      json_response = @clusters_interface.list_container_groups(cluster['id'], resource_type, params)

      render_result = render_with_format(json_response, options, 'containers')
      return 0 if render_result

      title = "Morpheus Cluster #{resource_type.capitalize}s: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      container_groups = json_response["#{resource_type}s"]
      if container_groups.empty?
        print cyan,"No #{resource_type}s found.",reset,"\n"
      else
        # more stuff to show here
        rows = container_groups.collect do |it|
          stats = it['stats']
          cpu_usage_str = generate_usage_bar((it['totalCpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          {
              id: it['id'],
              status: it['status'],
              name: it['name'],
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan,
              storage: storage_usage_str + cyan
          }
        end
        columns = [
            :id, :status, :name, :cpu, :memory, :storage
        ]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def _get_container_group(args, options, resource_type)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      id = args[1]
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      params['resourceLevel'] = options[:resourceLevel] if !options[:resourceLevel].nil?
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.get_container_group(cluster['id'], resource_type, id, params)
        return
      end
      container_group = @clusters_interface.get_container_group(cluster['id'], resource_type, id, params)['resource']

      render_result = render_with_format(container_group, options, 'containers')
      return 0 if render_result
      resource_is = options['title'] ? options['title'].capitalize : resource_type.capitalize
      title = "Morpheus Cluster #{cluster['name']}: #{resource_is}"
      print_h1 title
      print cyan
      description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Status" => 'status',
          "metadata" => lambda { |it| as_json(it['metadata']) }
      }
      print_description_list(description_cols, container_group)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def _remove_container_group(args, options, resource_type)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      container_group_id = args[1]

      if container_group_id.empty?
        raise_command_error "missing required container parameter"
      end

      container_group = find_container_group_by_name_or_id(cluster['id'], resource_type, container_group_id)
      if container_group.nil?
        print_red_alert "#{resource_type.capitalize} not found by id '#{container_group_id}'"
        return 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster #{resource_type} '#{container_group['name'] || container_group['id']}'?", options)
        return 9, "aborted command"
      end

      params = {}
      params.merge!(parse_list_options(options))

      if !options[:force].nil?
        params['force'] = options[:force]
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_container_group(cluster['id'], container_group['id'], resource_type, params)
        return
      end
      json_response = @clusters_interface.destroy_container_group(cluster['id'], container_group['id'], resource_type, params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error removing #{resource_type} #{container_group['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "#{resource_type.capitalize} #{container_group['name']} is being removed from cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def _restart_container_group(args, options, resource_type)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      container_group_id = args[1]

      if container_group_id.empty?
        raise_command_error "missing required container parameter"
      end

      container_group = find_container_group_by_name_or_id(cluster['id'], resource_type, container_group_id)
      if container_group.nil?
        print_red_alert "#{resource_type.capitalize} not found by id '#{container_group_id}'"
        return 1
      end

      params = {}
      params.merge!(parse_list_options(options))

      if !options[:force].nil?
        params['force'] = options[:force]
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.restart_container_group(cluster['id'], container_group['id'], resource_type, params)
        return
      end
      json_response = @clusters_interface.restart_container_group(cluster['id'], container_group['id'], resource_type, params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_red_alert "Error restarting #{resource_type} #{container_group['name']} from cluster #{cluster['name']}: #{json_response['msg']}" if json_response['success'] == false
        print_green_success "#{resource_type.capitalize} #{container_group['name']} is being restarted for cluster #{cluster['name']}..." if json_response['success'] == true
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_deployments(args)
    resource_type = 'deployment'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List #{resource_type}s for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _list_container_groups(args, options,resource_type)
  end

  def get_deployment(args)
    resource_type = 'deployment'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "get #{resource_type} for a cluster.\n" +
          "[cluster] and [#{resource_type}] is required. This is the name or id of an existing cluster, and the id of the #{resource_type}"
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _get_container_group(args, options, resource_type)
  end

  def remove_deployment(args)
    resource_type = 'deployment'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      opts.on( '-f', '--force', "Force Delete" ) do
        options[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _remove_container_group(args, options, resource_type)
  end

  def restart_deployment(args)
    resource_type = 'deployment'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Restart a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _restart_container_group(args, options, resource_type)
  end

  def list_stateful_sets(args)
    resource_type = 'statefulset'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List #{resource_type}s for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _list_container_groups(args, options, resource_type)
  end

  def remove_stateful_set(args)
    resource_type = 'statefulset'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      opts.on( '-f', '--force', "Force Delete" ) do
        options[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _remove_container_group(args, options, resource_type)
  end

  def restart_stateful_set(args)
    resource_type = 'statefulset'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Restart a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _restart_container_group(args, options, resource_type)
  end

  def list_pods(args)
    resource_type = 'pod'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List #{resource_type}s for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _list_container_groups(args, options, resource_type)
  end

  def get_pod(args)
    resource_type = 'pod'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "get #{resource_type} for a cluster.\n" +
          "[cluster] and [#{resource_type}] is required. This is the name or id of an existing cluster, and the id of the #{resource_type}"
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _get_container_group(args, options, resource_type)
  end

  def remove_pod(args)
    resource_type = 'pod'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      opts.on( '-f', '--force', "Force Delete" ) do
        options[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _remove_container_group(args, options, resource_type)
  end

  def restart_pod(args)
    resource_type = 'pod'
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [#{resource_type}]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Restart a #{resource_type} within a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[#{resource_type}] is required. This is the name or id of an existing #{resource_type}."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    _restart_container_group(args, options, resource_type)
  end

  def add_namespace(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [name] [options]")
      opts.on("--name NAME", String, "Name of the new namespace") do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on('--active [on|off]', String, "Enable namespace") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      add_perms_options(opts, options)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a cluster namespace.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[name] is required. This is the name of the new namespace."
    end

    optparse.parse!(args)
    if args.count < 1 || args.count > 3
      raise_command_error "wrong number of arguments, expected 1 to 3 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['namespace'] ||= {}
          payload['namespace'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        namespace_payload = {'name' => options[:name] || (args.length > 1 ? args[1] : nil) || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'description' => 'Namespace Name', 'required' => true}], options[:options], @api_client)['name']}
        namespace_payload.deep_merge!(prompt_update_namespace(options).reject {|k,v| k.is_a?(Symbol)})
        payload = {"namespace" => namespace_payload}
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.create_namespace(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.create_namespace(cluster['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        namespace = json_response['namespace']
        print_green_success "Added namespace #{namespace['name']}"
        get_args = [cluster["id"], namespace["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        get_namespace(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_namespaces(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List namespaces for a cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_namespaces(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_namespaces(cluster['id'], params)
      
      render_result = render_with_format(json_response, options, 'namespaces')
      return 0 if render_result

      title = "Morpheus Cluster Namespaces: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      namespaces = json_response['namespaces']
      if namespaces.empty?
        print cyan,"No namespaces found.",reset,"\n"
      else
        # more stuff to show here
        rows = namespaces.collect do |ns|
          {
              id: ns['id'],
              name: ns['name'],
              description: ns['description'],
              status: ns['status'],
              active: format_boolean(ns['active']),
              cluster: cluster['name']
          }
        end
        columns = [
            :id, :name, :description, :status, :active #, :cluster => lambda { |it| cluster['name'] }
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_namespace(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [namespace]")
      opts.on( nil, '--permissions', "Display permissions" ) do
        options[:show_perms] = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a cluster namespace.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[namespace] is required. This is the name or id of an existing namespace."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      # this finds the namespace in the cluster api response, then fetches it by ID
      namespace = find_namespace_by_name_or_id(cluster['id'], args[1])
      if namespace.nil?
        print_red_alert "Namespace not found for '#{args[1]}'"
        exit 1
      end
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.get_namespace(cluster['id'], namespace['id'], params)
        return
      end
      json_response = @clusters_interface.get_namespace(cluster['id'], namespace['id'], params)
      
      render_result = render_with_format(json_response, options, 'namespace')
      return 0 if render_result

      print_h1 "Morpheus Cluster Namespace"
      print cyan
      description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Cluster" => lambda { |it| cluster['name'] },
          "Status" => 'status',
          "Active" => lambda {|it| format_boolean it['active'] }
          # more stuff to show here
      }
      print_description_list(description_cols, namespace)
      print reset,"\n"

      if options[:show_perms]
        permissions = cluster['permissions']
        print_permissions(permissions)
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_namespace(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [namespace] [options]")
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on('--active [on|off]', String, "Enable namespace") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      add_perms_options(opts, options)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a cluster namespace.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster.\n" +
                    "[namespace] is required. This is the name or id of an existing namespace."
    end

    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      namespace = find_namespace_by_name_or_id(cluster['id'], args[1])
      if namespace.nil?
        print_red_alert "Namespace not found by '#{args[1]}'"
        exit 1
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'namespace' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end
      else
        payload = {'namespace' => prompt_update_namespace(options)}

        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'namespace' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end

        if payload['namespace'].nil? || payload['namespace'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update_namespace(cluster['id'], namespace['id'], payload)
        return
      end
      json_response = @clusters_interface.update_namespace(cluster['id'], namespace['id'], payload)
      if options[:json]
        puts as_json(json_response)
      elsif !options[:quiet]
        namespace = json_response['namespace']
        print_green_success "Updated namespace #{namespace['name']}"
        get_args = [cluster["id"], namespace["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        get_namespace(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_namespace(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [namespace]")
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a namespace within a cluster."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      namespace = find_namespace_by_name_or_id(cluster['id'], args[1])
      if namespace.nil?
        print_red_alert "Namespace not found by '#{args[1]}'"
        exit 1
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster namespace '#{namespace['name']}'?", options)
        return 9, "aborted command"
      end
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.destroy_namespace(cluster['id'], namespace['id'], query_params)
        return
      end
      json_response = @clusters_interface.destroy_namespace(cluster['id'], namespace['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed cluster namespace #{namespace['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_datastores(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List datastores for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_datastores(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_datastores(cluster['id'], params)

      render_result = render_with_format(json_response, options, 'datastores')
      return 0 if render_result

      title = "Morpheus Cluster Datastores: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      datastores = json_response['datastores']
      if datastores.empty?
        print cyan,"No datastores found.",reset,"\n"
      else
        # more stuff to show here
        rows = datastores.collect do |ds|
          {
              id: ds['id'],
              name: ds['name'],
              type: ds['type'],
              capacity: format_bytes_short(ds['freeSpace']).strip,
              online: (ds['online'] == false ? red : '') + format_boolean(ds['online']) + cyan,
              active: format_boolean(ds['active']),
              visibility: ds['visibility'].nil? ? '' : ds['visibility'].to_s.capitalize,
              tenants: ds['tenants'].nil? ? '' : ds['tenants'].collect {|it| it['name']}.join(', ')
          }
        end
        columns = [
            :id, :name, :type, :capacity, :online, :active, :visibility, :tenants
        ]
        print as_pretty_table(rows, columns, options)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_datastore(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [datastore]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a cluster datastore.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[datastore] is required. This is the name or id of an existing datastore."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      # this finds the namespace in the cluster api response, then fetches it by ID
      datastore = find_datastore_by_name_or_id(cluster['id'], args[1])
      if datastore.nil?
        print_red_alert "Datastore not found for '#{args[1]}'"
        exit 1
      end
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.get_datastore(cluster['id'], datastore['id'], params)
        return
      end
      json_response = @clusters_interface.get_datastore(cluster['id'], datastore['id'], params)

      render_result = render_with_format(json_response, options, 'datastore')
      return 0 if render_result

      print_h1 "Morpheus Cluster Datastore"
      print cyan
      description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => 'type',
          "Capacity" => lambda { |it| format_bytes_short(it['freeSpace']).strip },
          "Online" => lambda { |it| (it['online'] == false ? red : '') + format_boolean(it['online']) + cyan },
          "Active" => lambda { |it| format_boolean(it['active']) },
          "Visibility" => lambda { |it| it['visibility'].nil? ? '' : it['visibility'].to_s.capitalize },
          "Tenants" => lambda { |it| it['tenants'].nil? ? '' : it['tenants'].collect {|it| it['name']}.join(', ') },
          "Cluster" => lambda { |it| cluster['name'] }
      }
      print_description_list(description_cols, datastore)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_datastore(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [options]")
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      build_option_type_options(opts, options, add_datastore_option_types)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Add datastore to a cluster.\n" +
        "[cluster] is required. This is the name or id of an existing cluster.\n" +
        "[name] is required. This is the name of the new datastore."
    end

    optparse.parse!(args)
    if args.count != 1 and args.count != 2
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload ||= {}
          payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        options[:params] ||= {}
        options[:params].merge!({:serverGroupId => cluster['id']})

        datastore = Morpheus::Cli::OptionTypes.prompt(add_datastore_option_types, options[:options], @api_client, options[:params])

        datastore_type = find_datastore_type_by_code(datastore['datastoreType'])
        datastore['datastoreType'] = {id:datastore_type['id']}

        # datastore type options
        unless datastore_type['optionTypes'].empty?
          datastore.merge!(Morpheus::Cli::OptionTypes.prompt(datastore_type['optionTypes'], options[:options].deep_merge({:context_map => {'domain' => ''}, :checkbox_as_boolean => true}), @api_client, options[:params]))
        end

        # perms
        perms = prompt_permissions(options.merge({:for_datastore => true}), ['plans', 'groupDefaults'])

        datastore['resourcePermissions'] = perms['resourcePermissions'] unless perms['resourcePermissions'].nil?
        datastore['tenants'] = perms['tenantPermissions'] unless perms['tenantPermissions'].nil?
        datastore['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        payload = {datastore:datastore}
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.create_datastore(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.create_datastore(cluster['id'], payload)
      if options[:json]
        puts as_json(json_response)
      else
        if json_response['success']
          if json_response['msg'] == nil
            print_green_success "Adding datastore to cluster #{cluster['name']}"
          else
            print_green_success json_response['msg']
          end
          execution_id = json_response['executionId']
          if !options[:no_refresh] && execution_id
            wait_for_execution_request(json_response['executionId'], options.merge({waiting_status:['new', 'pending', 'executing']}))
          end
        else
          print_red_alert "Failed to create cluster datastore #{json_response['msg']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_datastore(args)
    default_refresh_interval = 5
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [datastore]")
      opts.on( '-f', '--force', "Force Delete" ) do
        params[:force] = 'on'
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      build_standard_remove_options(opts, options)
      opts.footer = "Delete a datastore from a cluster.\n" +
        "[cluster] is required. This is the name or id of an existing cluster.\n" +
        "[datastore] is required. This is the name or id of an existing datastore."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    params.merge!(parse_query_options(options))

    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    datastore_id = args[1]
    if datastore_id.empty?
      raise_command_error "missing required worker parameter"
    end

    datastore = find_datastore_by_name_or_id(cluster['id'], datastore_id)
    if datastore.nil?
      print_red_alert "Datastore not found for '#{datastore_id}'"
      return 1
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster datastore '#{datastore['name'] || datastore['id']}'?", options)
      return 9, "aborted command"
    end

    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.destroy_datastore(cluster['id'], datastore['id'], params)
      return
    end
    json_response = @clusters_interface.destroy_datastore(cluster['id'], datastore['id'], params)
    if options[:json]
      puts as_json(json_response)
    else
      if json_response['success']
        print_green_success "Datastore #{datastore['name']} is being removed from cluster #{cluster['name']}"
        execution_id = json_response['executionId']
        if !options[:no_refresh] && execution_id
          wait_for_execution_request(execution_id, options.merge({waiting_status:['new', 'pending', 'executing']}))
        end
      else
        print_red_alert "Failed to remove cluster datastore #{json_response['msg']}"
      end
    end
    return 0, nil
  end

  def update_datastore(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [datastore] [options]")
      opts.on('--active [on|off]', String, "Enable datastore") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      add_perms_options(opts, options, ['plans', 'groupDefaults'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a cluster datastore.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[datastore] is required. This is the name or id of an existing datastore."
    end

    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      datastore = find_datastore_by_name_or_id(cluster['id'], args[1])
      if datastore.nil?
        print_red_alert "Datastore not found by '#{args[1]}'"
        exit 1
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'datastore' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end
      else
        payload = {'datastore' => {}}
        payload['datastore']['active'] = options[:active].nil? ? (Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'description' => 'Datastore Active', 'defaultValue' => true}], options[:options], @api_client))['active'] == 'on' : options[:active]

        perms = prompt_permissions(options.merge({:available_plans => namespace_service_plans}), datastore['owner']['id'] == current_user['accountId'] ? ['plans', 'groupDefaults'] : ['plans', 'groupDefaults', 'visibility', 'tenants'])
        perms_payload = {}
        perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil?
        perms_payload['tenantPermissions'] = perms['tenantPermissions'] if !perms['tenantPermissions'].nil?

        payload['datastore']['permissions'] = perms_payload
        payload['datastore']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'datastore' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end

        if payload['datastore'].nil? || payload['datastore'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update_datastore(cluster['id'], datastore['id'], payload)
        return
      end
      json_response = @clusters_interface.update_datastore(cluster['id'], datastore['id'], payload)
      if options[:json]
        puts as_json(json_response)
      elsif !options[:quiet]
        datastore = json_response['datastore']
        print_green_success "Updated datastore #{datastore['name']}"
        #get_args = [cluster["id"], datastore["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        #get_namespace(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_affinity_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      build_standard_list_options(opts, options)
      opts.footer = "List affinity groups for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    params = {}
    params.merge!(parse_list_options(options))
    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.list_affinity_groups(cluster['id'], params)
      return
    end
    json_response = @clusters_interface.list_affinity_groups(cluster['id'], params)
    render_response(json_response, options, 'affinityGroups') do
      affinity_groups = json_response['affinityGroups']
      print_h1 "Morpheus Cluster Affinity Groups: #{cluster['name']}", parse_list_subtitles(options), options
      if affinity_groups.empty?
        print cyan,"No affinity groups found.",reset,"\n"
      else          
        columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| format_affinity_type(it['affinityType']) },
          "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Servers" => lambda {|it| it['servers'].size() },
          # "Source" => lambda {|it| it['source'] },
        }.upcase_keys!
        print as_pretty_table(affinity_groups, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [affinity group]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a cluster affinity group.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[affinity group] is required. This is the name or id of an existing affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    
    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    # this finds the affinity group in the cluster api response, then fetches it by ID
    affinity_group = find_cluster_affinity_group_by_name_or_id(cluster['id'], args[1])
    if affinity_group.nil?
      print_red_alert "Affinity Group not found for '#{args[1]}'"
      exit 1
    end
    
    params = {}
    params.merge!(parse_query_options(options))
    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.get_affinity_group(cluster['id'], affinity_group['id'], params)
      return
    end
    json_response = @clusters_interface.get_affinity_group(cluster['id'], affinity_group['id'], params)
    render_response(json_response, options, 'affinityGroup') do
      affinity_group = json_response['affinityGroup']
      print_h1 "Affinity Group Details", [], options
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| format_affinity_type(it['affinityType']) },
        "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Servers" => lambda {|it| it['servers'].size() },
        "Source" => lambda {|it| it['source'] },
        "Active" => lambda {|it| format_boolean(it['active']) },
      }
      print_description_list(columns, affinity_group)
      if affinity_group['servers'].size > 0
        print_h2 "Servers", options
        print as_pretty_table(affinity_group['servers'], [:id, :name], options)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def add_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [name] [options]")
      build_option_type_options(opts, options, add_affinity_group_option_types)
      # opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
      #   options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      # end
      # opts.on(nil, '--no-refresh', "Do not refresh" ) do
      #   options[:no_refresh] = true
      # end
      build_standard_add_options(opts, options)
      opts.footer = "Add affinity group to a cluster.\n" +
        "[cluster] is required. This is the name or id of an existing cluster.\n" +
        "[name] is required. This is the name of the new affinity group."
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:2)
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      if args[1]
        options[:options]['name']  = args[1]
      end
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload ||= {}
          payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        options[:params] ||= {}
        options[:params].merge!({:serverGroupId => cluster['id']})
        option_types = add_affinity_group_option_types
        affinity_group = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])

        # affinity_group_type = find_affinity_group_type_by_code(affinity_group['affinityGroupType'])
        # affinity_group['affinityGroupType'] = {id:affinity_group_type['id']}

        # # affinity_group type options
        # unless affinity_group_type['optionTypes'].empty?
        #   affinity_group.merge!(Morpheus::Cli::OptionTypes.prompt(affinity_group_type['optionTypes'], options[:options].deep_merge({:context_map => {'domain' => ''}, :checkbox_as_boolean => true}), @api_client, options[:params]))
        # end

        # perms
        perms = prompt_permissions(options.merge({:for_affinity_group => true}), ['plans','groupDefaults'])

        affinity_group['resourcePermissions'] = perms['resourcePermissions'] unless perms['resourcePermissions'].nil?
        affinity_group['tenants'] = perms['tenantPermissions'] unless perms['tenantPermissions'].nil?
        affinity_group['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        payload = {'affinityGroup' => affinity_group}
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.create_affinity_group(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.create_affinity_group(cluster['id'], payload)
      if options[:json]
        puts as_json(json_response)
      else
        if json_response['success']
          if json_response['msg'] == nil
            print_green_success "Adding affinity group to cluster #{cluster['name']}"
          else
            print_green_success json_response['msg']
          end
          execution_id = json_response['executionId']
          if !options[:no_refresh] && execution_id
            wait_for_execution_request(json_response['executionId'], options.merge({waiting_status:['new', 'pending', 'executing']}))
          end
        else
          print_red_alert "Failed to create cluster affinity group #{json_response['msg']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] [affinity group] [options]")
      opts.on('--active [on|off]', String, "Enable affinity group") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      # add_perms_options(opts, options, ['groupDefaults'])
      build_standard_update_options(opts, options)
      opts.footer = "Update a cluster affinity group.\n" +
          "[cluster] is required. This is the name or id of an existing cluster.\n" +
          "[affinity group] is required. This is the name or id of an existing affinity group."
    end

    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      affinity_group = find_cluster_affinity_group_by_name_or_id(cluster['id'], args[1])
      if affinity_group.nil?
        print_red_alert "Affinity Group not found by '#{args[1]}'"
        exit 1
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'affinityGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end
      else
        payload = {'affinityGroup' => {}}
        payload['affinityGroup']['active'] = options[:active].nil? ? (Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'description' => 'Active', 'defaultValue' => true}], options[:options], @api_client))['active'] == 'on' : options[:active]

        perms = prompt_permissions(options.merge({:available_plans => namespace_service_plans}), affinity_group['owner']['id'] == current_user['accountId'] ? ['plans', 'groupDefaults'] : ['plans', 'groupDefaults', 'visibility', 'tenants'])
        perms_payload = {}
        perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil?
        perms_payload['tenantPermissions'] = perms['tenantPermissions'] if !perms['tenantPermissions'].nil?

        payload['affinityGroup']['permissions'] = perms_payload
        payload['affinityGroup']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'affinityGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end

        if payload['affinityGroup'].nil? || payload['affinityGroup'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update_affinity_group(cluster['id'], affinity_group['id'], payload)
        return
      end
      json_response = @clusters_interface.update_affinity_group(cluster['id'], affinity_group['id'], payload)
      if options[:json]
        puts as_json(json_response)
      elsif !options[:quiet]
        affinity_group = json_response['affinityGroup']
        print_green_success "Updated affinity group #{affinity_group['name']}"
        #get_args = [cluster["id"], affinity_group["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        #get_namespace(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_affinity_group(args)
    default_refresh_interval = 5
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [affinity group]")
      # opts.on( '-f', '--force', "Force Delete" ) do
      #   params[:force] = 'on'
      # end
      # opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
      #   options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      # end
      # opts.on(nil, '--no-refresh', "Do not refresh" ) do
      #   options[:no_refresh] = true
      # end
      build_standard_remove_options(opts, options)
      opts.footer = "Delete an affinity group from a cluster.\n" +
        "[cluster] is required. This is the name or id of an existing cluster.\n" +
        "[affinity group] is required. This is the name or id of an existing affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    params.merge!(parse_query_options(options))

    cluster = find_cluster_by_name_or_id(args[0])
    return 1 if cluster.nil?

    affinity_group_id = args[1]
    if affinity_group_id.empty?
      raise_command_error "missing required worker parameter"
    end

    affinity_group = find_cluster_affinity_group_by_name_or_id(cluster['id'], affinity_group_id)
    if affinity_group.nil?
      print_red_alert "Affinity Group not found for '#{affinity_group_id}'"
      return 1
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cluster affinity group '#{affinity_group['name'] || affinity_group['id']}'?", options)
      return 9, "aborted command"
    end

    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.destroy_affinity_group(cluster['id'], affinity_group['id'], params)
      return
    end
    json_response = @clusters_interface.destroy_affinity_group(cluster['id'], affinity_group['id'], params)
    if options[:json]
      puts as_json(json_response)
    else
      if json_response['success']
        print_green_success "Removed affinity group #{affinity_group['name']}"
        execution_id = json_response['executionId']
        if !options[:no_refresh] && execution_id
          wait_for_execution_request(execution_id, options.merge({waiting_status:['new', 'pending', 'executing']}))
        end
      else
        print_red_alert "Failed to remove cluster affinity_group #{json_response['msg']}"
      end
    end
    return 0, nil
  end

  def api_config(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display API service settings for a cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.api_config(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.api_config(cluster['id'], params)
      
      render_result = render_with_format(json_response, options)
      return 0 if render_result

      title = "Cluster API Config: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options

      service_config = json_response
      print cyan
      description_cols = {
          "Url" => 'serviceUrl',
          "Username" => 'serviceUsername',
          #"Password" => 'servicePassword',
          "Token" => 'serviceToken',
          "Access" => 'serviceAccess',
          "Cert" => 'serviceCert',
          #"Config" => 'serviceConfig',
          "Version" => 'serviceVersion',
      }
      print_description_list(description_cols, service_config)
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_kube_config(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display Kubernetes config for a cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.api_config(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.api_config(cluster['id'], params)
      
      render_result = render_with_format(json_response, options)
      return 0 if render_result

      title = "Cluster Kube Config: #{cluster['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options

      service_config = json_response
      service_access = service_config['serviceAccess']
      if service_access.to_s.empty?
        print yellow,"No kube config found.",reset,"\n\n"
        return 1
      else
        print cyan,service_access,reset,"\n\n"
        return 0
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_api_token(args)
    print_token_only = false
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.on('-t','--token-only', "Print the api token only") do
        print_token_only = true
      end
      opts.footer = "Display api token for a cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.api_config(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.api_config(cluster['id'], params)
      
      render_result = render_with_format(json_response, options)
      return 0 if render_result

      service_config = json_response
      service_token = service_config['serviceToken']

      if print_token_only
        if service_token.to_s.empty?
          print yellow,"No api token found.",reset,"\n"
          return 1
        else
          print cyan,service_token,reset,"\n"
          return 0
        end
      end

      title = "Cluster API Token: #{cluster['name']}"
      subtitles = []
      print_h1 title, subtitles, options
      
      if service_token.to_s.empty?
        print yellow,"No api token found.",reset,"\n\n"
        return 1
      else
        print cyan,service_token,reset,"\n\n"
        return 0
      end
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
      opts.banner = subcommand_usage("[cluster]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for a cluster." + "\n" +
                    "[cluster] is required. This is the name or id of a cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?


      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.wiki(cluster["id"], params)
        return
      end
      json_response = @clusters_interface.wiki(cluster["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "cluster Wiki Page: #{cluster['name']}"
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
      opts.footer = "View cluster wiki page in a web browser" + "\n" +
                    "[cluster] is required. This is the name or id of a cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/clusters/#{cluster['id']}#!wiki"

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
      opts.banner = subcommand_usage("[cluster] [options]")
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
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
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
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update_wiki(cluster["id"], payload)
        return
      end
      json_response = @clusters_interface.update_wiki(cluster["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for cluster #{cluster['name']}"
        wiki([cluster['id']])
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
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
      opts.footer = "List historical processes for a specific cluster.\n" +
          "[cluster] is required. This is the name or id of an cluster."
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
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      # params['query'] = params.delete('phrase') if params['phrase']
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.history(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.history(cluster['id'], params)
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
        title = "Cluster History: #{cluster['name']}"
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
      opts.banner = subcommand_usage("[cluster] [process-id]")
      opts.on('--process-id ID', String, "Display details about a specfic event." ) do |val|
        options[:process_id] = val
      end
      opts.add_hidden_option('process-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process.\n" +
          "[cluster] is required. This is the name or id of a cluster.\n" +
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
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.history_details(cluster['id'], process_id, params)
        return
      end
      json_response = @clusters_interface.history_details(cluster['id'], process_id, params)
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
        title = "Cluster History Details"
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

  def apply_template(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster] --specTemplate --serviceUrl")
      opts.on("--specTemplate [TEXT]", String, "Name or ID of desired Spec Template to apply to cluster") do |val|
        options[:specTemplate] = val.to_s
      end
      opts.on("--serviceUrl [TEXT]", String, "Url of template to apply to Cluster") do |val|
        options[:serviceUrl] = val.to_s
      end
       opts.on("--specYaml [TEXT]", String, "Yaml to apply to Cluster") do |val|
        options[:specYaml] = val.to_s
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Apply a Template to a Cluster.\n" +
                    "[cluster] is required. This is the name or id of an existing cluster."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      payload = nil
      cluster = nil

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['cluster'] ||= {}
          payload['cluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end

        if !payload['cluster'].empty?
          cluster = find_cluster_by_name_or_id(payload['cluster']['id'] || payload['cluster']['name'])
        end
      else
        cluster = find_cluster_by_name_or_id(args[0])
        cluster_payload = {}
        cluster_payload['specTemplate'] = options[:specTemplate] if !options[:specTemplate].empty?
        cluster_payload['serviceUrl'] = options[:serviceUrl] if !options[:serviceUrl].empty?
        cluster_payload['specYaml'] = options[:specYaml] if !options[:specYaml].empty?
        payload = cluster_payload
      end

      if !cluster
        print_red_alert "No clusters available for update"
        exit 1
      end

      if cluster_payload.empty?
        type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => "Type", 'selectOptions' => apply_temp_options, 'required' => true, 'description' => 'Choose type of template being used.'}])['type']
        if type == 'specTemplate'
          cluster_payload['specTemplate'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'specTemplate', 'type' => 'select', 'fieldLabel' => "Spec Template", 'selectOptions' => available_kube_templates, 'required' => true, 'description' => 'Choose a template.'}], options[:options])['specTemplate'] 
        elsif type == 'yaml'
          file_params = Morpheus::Cli::OptionTypes.file_content_prompt({'fieldName' => 'source', 'fieldLabel' => 'File Content', 'type' => 'file-content', 'required' => true}, {'source' => {'source' => 'local'}}, nil, {})
          cluster_payload['specYaml'] = file_params['content']
        else
          cluster_payload['specUrl'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'specUrl', 'type' => 'text', 'fieldLabel' => 'Spec Url', 'required' => true, 'description' => 'Url of template.'}])['specUrl']
        end
      end

      if options[:dry_run]
        print_dry_run @clusters_interface.dry.apply_template(cluster['id'], cluster_payload)
        return
      end

      json_response = @clusters_interface.apply_template(cluster['id'], cluster_payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['msg'] != nil
        print_red_alert "There was an error #{json_response['msg']}"
      else
        print_green_success 'Template applied to Cluster. Check Execution Request for results'
        json_response = @execution_request_interface.get(json_response['executionId'], {})

        if json_response['executionRequest'] && json_response['executionRequest']['errorMessage']
          print_red_alert "There was an error: #{json_response['executionRequest']['errorMessage']}"
          print_red_alert "execution request id: #{json_response['executionRequest']['uniqueId']}"
        else
          execution_request = json_response['executionRequest']
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
          description_cols.delete("Server ID") if execution_request['serverId'].nil?
          description_cols.delete("Instance ID") if execution_request['instanceId'].nil?
          description_cols.delete("Container ID") if execution_request['containerId'].nil?
          description_cols.delete("Exit Code") if execution_request['exitCode'].nil?
          print_description_list(description_cols, execution_request)      

          if execution_request['stdErr'].to_s.strip != '' && execution_request['stdErr'] != "stdin: is not a tty\n"
            print_h2 "Error"
            puts execution_request['stdErr'].to_s.strip
          end
          if execution_request['stdOut']
            print_h2 "Output"
            puts execution_request['stdOut'].to_s.strip
          end
          print reset, "\n"
        end
      end
    end
  end

  def history_event_details(args)
    options = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [event-id]")
      opts.on('--event-id ID', String, "Display details about a specfic event." ) do |val|
        options[:event_id] = val
      end
      opts.add_hidden_option('event-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process event.\n" +
          "[cluster] is required. This is the name or id of an cluster.\n" +
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
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.history_event_details(cluster['id'], process_event_id, params)
        return
      end
      json_response = @clusters_interface.history_event_details(cluster['id'], process_event_id, params)
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
        title = "Cluster History Event"
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

  def list_types(args)
    Morpheus::Cli::ClusterTypes.new.list(args)
  end

  def get_type(args)
    Morpheus::Cli::ClusterTypes.new.get(args)
  end

  private

  def print_clusters_table(clusters, opts={})
    table_color = opts[:color] || cyan
    rows = clusters.collect do |cluster|
      {
          id: cluster['id'],
          labels: truncate_string(format_list(cluster['labels']), 30),
          name: cluster['name'],
          type: (cluster['type']['name'] rescue ''),
          layout: (cluster['layout']['name'] rescue ''),
          workers: cluster['servers'].size,
          cloud: (cluster['zone']['name'] rescue ''),
          status: format_cluster_status(cluster)
      }
    end
    columns = [
        :id, :name, :labels, :type, :layout, :workers, :cloud, :status
    ]
    print as_pretty_table(rows, columns, opts)
  end

  def format_cluster_status(cluster, return_color=cyan)
    out = ""
    status_string = cluster['status']
    if cluster['enabled'] == false
      out << "#{red}DISABLED#{cluster['statusMessage'] ? "#{return_color} - #{cluster['statusMessage']}" : ''}#{return_color}"
    elsif status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{cluster['statusMessage'] ? "#{return_color} - #{cluster['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing' || status_string == 'removing' || status_string.include?('provision')
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{cluster['statusMessage'] ? "#{return_color} - #{cluster['statusMessage']}" : ''}#{return_color}"
    end
    out
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
    status_string = server['status']
    # todo: colorize, upcase?
    out << status_string.to_s
    out
  end

  def find_worker_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      find_worker_by_id(cluster_id, val.to_i)
    else
      find_worker_by_name(cluster_id, val)
    end
   
  end

  def find_worker_by_id(cluster_id, id)
    json_results = @clusters_interface.list_workers(cluster_id)
    filtered_results = json_results['workers'].select {|worker| worker['id'] == id}
    if filtered_results.empty? || filtered_results.count > 1
      print_red_alert "Worker not found by id #{id}"
      exit 1
    end
    filtered_results[0]
  end

  def find_worker_by_name(cluster_id, name)
    params = {phrase: name}
    json_results = @clusters_interface.list_workers(cluster_id, params)
    if json_results['workers'].empty? || json_results['workers'].count > 1
      print_red_alert "Worker not found by name #{name}"
      exit 1
    end
    json_results['workers'][0]
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

  def find_container_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {"containerId": val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_containers(cluster_id, params)
    json_results["containers"].empty? ? nil : json_results["containers"][0]
  end

  def find_container_group_by_name_or_id(cluster_id, resource_type, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {"#{resource_type}Id": val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_container_groups(cluster_id, resource_type, params)
    json_results["#{resource_type}s"].empty? ? nil : json_results["#{resource_type}s"][0]
  end

  def find_volume_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {volumeId: val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_volumes(cluster_id, params)
    json_results['volumes'].empty? ? nil : json_results['volumes'][0]
  end

  def find_service_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {serviceId: val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_services(cluster_id, params)
    json_results['services'].empty? ? nil : json_results['services'][0]
  end

  def find_namespace_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {namespaceId: val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_namespaces(cluster_id, params)
    json_results['namespaces'].empty? ? nil : json_results['namespaces'][0]
  end

  def find_datastore_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {datastoreId: val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_datastores(cluster_id, params)
    json_results['datastores'].empty? ? nil : json_results['datastores'][0]
  end

  def find_datastore_type_by_code_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_datastore_type_by_id(val) : find_datastore_type_by_code(val)
  end

  def find_datastore_type_by_id(id)
    get_datastore_types.find { |it| it['id'] == id }
  end

  def find_datastore_type_by_code(code)
    get_datastore_types.find { |it| it['code'].downcase == code.downcase }
  end

  def get_datastore_types(refresh=false)
    if !@datastore_types || refresh
      @datastore_types = @datastores_interface.types()['datastoreTypes']
    end
    @datastore_types
  end

  def find_job_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      params = {jobId: val.to_i}
    else
      params = {phrase: val}
    end
    json_results = @clusters_interface.list_jobs(cluster_id, params)
    json_results['jobs'].empty? ? nil : json_results['jobs'][0]
  end

  def find_cluster_type_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cluster_type_by_id(val) : find_cluster_type_by_name(val)
  end

  def find_cluster_type_by_id(id)
    get_cluster_types.find { |it| it['id'] == id.to_i }
  end

  def find_cluster_type_by_name(name)
    get_cluster_types.find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase }
  end

  def cluster_types_for_dropdown
    get_cluster_types.collect {|it| {'id' => it['id'], 'name' => it['name'], 'code' => it['code'], 'value' => it['code']} }
  end

  def get_cluster_types(refresh=false)
    if !@cluster_types || refresh
      @cluster_types = @clusters_interface.cluster_types()['clusterTypes']
    end
    @cluster_types
  end

  def find_layout_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_layout_by_id(val) : find_layout_by_name(val)
  end

  def find_layout_by_id(id)
    @cluster_layouts_interface.get(id)['layout'] rescue nil
  end

  def find_layout_by_name(name)
    @cluster_layouts_interface.list({phrase:name}).find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase }
  end

  def layouts_for_dropdown(zone_id, group_type_id)
    @cluster_layouts_interface.list({zoneId: zone_id, groupTypeId: group_type_id})["layouts"].collect { |it| {'id' => it['id'], 'name' => it['name'], 'value' => it['id'], 'code' => it['code']} }
  end

  def find_service_plan_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_service_plan_by_id(val) : find_service_plan_by_name(val)
  end

  def find_service_plan_by_id(id)
    @servers_interface.service_plan(id)['servicePlan'] rescue nil
  end

  def find_service_plan_by_name(name)
    @servers_interface.service_plan({phrase: name})['servicePlans'].find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase } rescue nil
  end

  def find_security_group_by_name(val)
    @security_groups_interface.list({phrase: val})['securityGroups'][0] rescue nil
  end

  def find_cloud_resource_pool_by_name_or_id(cloud_id, val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cloud_resource_pool_by_id(cloud_id, val) : find_cloud_resource_pool_by_name(cloud_id, val)
  end

  def find_cloud_resource_pool_by_name(cloud_id, name)
    get_cloud_resource_pools(cloud_id).find { |it| it['name'].downcase == name.downcase } rescue nil
  end

  def find_cloud_resource_pool_by_id(cloud_id, id)
    get_cloud_resource_pools(cloud_id).find { |it| it['id'] == id } rescue nil
  end

  def get_cloud_resource_pools(cloud_id, refresh=false)
    if !@cloud_resource_pools || refresh
      @cloud_resource_pools = @cloud_resource_pools_interface.list(cloud_id)['resourcePools']
    end
    @cloud_resource_pools
  end

  def find_server_type_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_server_type_by_name(val) : find_server_type_by_id(val)
  end

  def find_server_type_by_name(val)
    @server_types_interface.list({name: val})['serverTypes'][0] rescue nil
  end

  def find_server_type_by_id(val)
    @server_types_interface.get(val)['serverType']
  end

  def service_plans_for_dropdown(api_params)
    @servers_interface.service_plans(api_params)['plans'] rescue []
  end

  def namespace_service_plans
    @service_plans_interface.list({'provisionable' => 'any', 'provisionTypeId' => @provision_types_interface.list({'code' => 'docker'})['provisionTypes'].first['id']})['servicePlans'].collect {|it|
      {"name" => it["name"], "value" => it["id"]}
    } rescue []
  end

  def get_cloud_type(id)
    @clouds_interface.cloud_type(id)['zoneType']
  end

  def get_provision_type_for_zone_type(zone_type_id)
    @clouds_interface.cloud_type(zone_type_id)['zoneType']['provisionTypes'].first rescue nil
  end

  def can_use_kubevip(type, group_type)
    payload = {'provisionType' => type, 'groupType' => group_type }
    can_use = @clusters_interface.can_use_kubevip(payload)
    return can_use
  end

  def load_group(group_type, options)
    # Group / Site
    group_id = nil
    group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil

    if group
      group_id = group["id"]
    else
      if @active_group_id
        group_id = @active_group_id
      else
        available_groups = get_available_groups({groupType: group_type})

        if available_groups.empty?
          print_red_alert "No available groups"
          exit 1
        else available_groups.count > 1 && !options[:no_prompt]
          group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => available_groups, 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})['group']
        end
      end
    end
    @groups_interface.get(group_id)['group']
  end

  def prompt_service_plan(api_params, options)
    available_service_plans = service_plans_for_dropdown(api_params)
    if available_service_plans.empty?
      print_red_alert "Cloud #{api_params['zoneId']} has no available plans"
      exit 1
    end
    if options[:servicePlan]
      service_plan = available_service_plans.find {|sp| sp['id'] == options[:servicePlan].to_i || sp['name'] == options[:servicePlan] || sp['code'] == options[:servicePlan] }
    else
      if available_service_plans.count > 1 && !options[:no_prompt]
        service_plan_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => available_service_plans, 'required' => true, 'description' => 'Select Plan.'}],options[:options],@api_client,{},options[:no_prompt],true)['servicePlan'].to_i
      else
        service_plan_id = available_service_plans.first['id']
      end
      #service_plan = find_service_plan_by_id(service_plan_id)
      service_plan = available_service_plans.find {|sp| sp['id'] == service_plan_id.to_i || sp['name'] == service_plan_id.to_s || sp['code'] == service_plan_id.to_s }
    end
    service_plan
  end

  def prompt_service_plan_options(service_plan, provision_type, options)
    plan_options = {}
    hide_custom_options = provision_type && provision_type['code'] == 'manual'

    if !hide_custom_options
      # custom max memory
      if service_plan['customMaxMemory']
        if !options[:maxMemory]
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'maxMemory', 'type' => 'number', 'fieldLabel' => 'Max Memory (MB)', 'required' => false, 'description' => 'This will override any memory requirement set on the virtual image', 'defaultValue' => service_plan['maxMemory'] ? service_plan['maxMemory'] / (1024 * 1024) : 10 }], options[:options])
          plan_options['maxMemory'] = v_prompt['maxMemory'] * 1024 * 1024 if v_prompt['maxMemory']
        else
          plan_options['maxMemory'] = options[:maxMemory]
        end
      end

      # custom cores: max cpu, max cores, cores per socket
      if service_plan['customCores']
        if options[:cpuCount].empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cpuCount', 'type' => 'number', 'fieldLabel' => 'CPU Count', 'required' => false, 'description' => 'Set CPU Count', 'defaultValue' => service_plan['maxCpu'] ? service_plan['maxCpu'] : 1 }], options[:options])
          plan_options['cpuCount'] = v_prompt['cpuCount'] if v_prompt['cpuCount']
        else
          plan_options['cpuCount']
        end
        if options[:coreCount].empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'coreCount', 'type' => 'number', 'fieldLabel' => 'Core Count', 'required' => false, 'description' => 'Set Core Count', 'defaultValue' => service_plan['maxCores'] ? service_plan['maxCores'] : 1 }], options[:options])
          plan_options['coreCount'] = v_prompt['coreCount'] if v_prompt['coreCount']
        end
        if options[:coresPerSocket].empty? && service_plan['coresPerSocket']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'coresPerSocket', 'type' => 'number', 'fieldLabel' => 'Cores Per Socket', 'required' => false, 'description' => 'Set Core Per Socket', 'defaultValue' => service_plan['coresPerSocket']}], options[:options])
          plan_options['coresPerSocket'] = v_prompt['coresPerSocket'] if v_prompt['coresPerSocket']
        end
      end
    end
    plan_options
  end

  def add_server_options(opts, options)
    opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
      options[:cloud] = val
    end
    opts.on( '--resource-pool ID', String, "ID of the Resource Pool for Amazon VPC and Azure Resource Group" ) do |val|
      options[:resourcePool] = val
    end
    opts.on( '-p', '--plan PLAN', "Service Plan") do |val|
      options[:servicePlan] = val
    end
    opts.on( '-n', '--worker-count VALUE', String, "Worker / host count") do |val|
      options[:options]['nodeCount'] = val
    end
    opts.on('--max-memory VALUE', String, "Maximum Memory (MB)") do |val|
      options[:maxMemory] = val
    end
    opts.on('--cpu-count VALUE', String, "CPU Count") do |val|
      options[:cpuCount] = val
    end
    opts.on('--core-count VALUE', String, "Core Count") do |val|
      options[:coreCount] = val
    end
    opts.on('--cores-per-socket VALUE', String, "Cores Per Socket") do |val|
      options[:coresPerSocket] = val
    end
    opts.on('--volumes JSON', String, "Volumes Config JSON") do |val|
      begin
        volumes = JSON.parse(val.to_s)
      rescue JSON::ParserError => e
        print_red_alert "Unable to parse volumes JSON"
        exit 1
      end
      options[:volumes] = volumes.kind_of?(Array) ? volumes : [volumes]
    end
    opts.on('--volumes-file FILE', String, "Volumes Config from a local JSON or YAML file") do |val|
      config_file = File.expand_path(val)
      if !File.exist?(config_file) || !File.file?(config_file)
        print_red_alert "Specified volumes file not found: #{config_file}"
        exit 1
      end
      if config_file =~ /\.ya?ml\Z/
        begin
          volumes = YAML.load_file(config_file)
        rescue YAML::ParseError
          print_red_alert "Unable to parse volumes YAML from: #{config_file}"
          exit 1
        end
      else
        volumes =
            begin
              volumes = JSON.parse(File.read(config_file))
            rescue JSON::ParserError
              print_red_alert "Unable to parse volumes JSON from: #{config_file}"
              exit 1
            end
      end
      options[:volumes] = volumes.kind_of?(Array) ? volumes : [volumes]
    end
    opts.on('--config-file FILE', String, "Instance Config from a local JSON or YAML file") do |val|
      options['configFile'] = val.to_s
    end
    opts.on('--network-interfaces JSON', String, "Network Interfaces Config JSON") do |val|
      begin
        networkInterfaces = JSON.parse(val.to_s)
      rescue JSON::ParserError => e
        print_red_alert "Unable to parse network interfaces JSON"
        exit 1
      end
      options[:networkInterfaces] = networkInterfaces.kind_of?(Array) ? networkInterfaces : [networkInterfaces]
    end
    opts.on('--network-interfaces-file FILE', String, "Network Interfaces Config from a local JSON or YAML file") do |val|
      config_file = File.expand_path(val)
      if !File.exist?(config_file) || !File.file?(config_file)
        print_red_alert "Specified network interfaces file not found: #{config_file}"
        exit 1
      end
      if config_file =~ /\.ya?ml\Z/
        begin
          networkInterfaces = YAML.load_file(config_file)
        rescue YAML::ParseError
          print_red_alert "Unable to parse network interfaces YAML from: #{config_file}"
          exit 1
        end
      else
        networkInterfaces =
            begin
              networkInterfaces = JSON.parse(File.read(config_file))
            rescue JSON::ParserError
              print_red_alert "Unable to parse network interfaces JSON from: #{config_file}"
              exit 1
            end
      end
      options[:networkInterfaces] = networkInterfaces.kind_of?(Array) ? networkInterfaces : [networkInterfaces]
    end
    opts.on('--security-groups LIST', Array, "Security Groups") do |list|
      options[:securityGroups] = list
    end
    opts.on("--create-user [on|off]", String, "User Config: Create Your User. Default is off") do |val|
      options[:createUser] = ['true','on','1',''].include?(val.to_s)
    end
    opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
      options[:userGroup] = val
    end
    opts.on('--domain VALUE', String, "Network Domain ID") do |val|
      options[:domain] = val
    end
    opts.on('--hostname VALUE', String, "Hostname") do |val|
      options[:hostname] = val
    end
    opts.on('--default-repo-account VALUE', String, "Default Repo Account") do |val|
      options[:default_repo] = val
    end
    opts.on("--image-server [on|off]", ['on','off'], "Act As Image Server") do |val|
      options[:image_server] = ['true','on','1',''].include?(val.to_s)
    end
  end

  def add_datastore_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'datastoreType', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => 'datastoreTypes', 'description' => 'Choose a datastore type.', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'required' => true, 'displayOrder' => 3, 'defaultValue' => true},
    ]
  end

  def prompt_resource_pool(group, cloud, service_plan, provision_type, options)
    resource_pool = nil

    if provision_type && provision_type['hasZonePools']
      # Resource pool
      resource_pool_id = nil
      resource_pool = options[:resourcePool] ? find_cloud_resource_pool_by_name_or_id(cloud['id'], options[:resourcePool]) : nil

      if !resource_pool
        resource_pool_options = @options_interface.options_for_source('zonePools', {groupId: group['id'], zoneId: cloud['id']}.merge(service_plan ? {planId: service_plan['id']} : {}))['data'].reject { |it| it['id'].nil? && it['name'].nil? }

        if resource_pool_options.empty?
          print yellow,bold, "Cloud #{cloud['name']} has no available resource pools",reset,"\n\n"
          return
          #exit 1
        elsif resource_pool_options.count > 1 && !options[:no_prompt]
          resource_pool_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'resourcePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'selectOptions' => resource_pool_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Select resource pool.'}],options[:options],api_client, {})['resourcePool']
        else
          first_option = resource_pool_options.find {|it| !it['id'].nil? }
          if first_option.nil?
            print yellow,bold, "Cloud #{cloud['name']} has no available resource pools",reset,"\n\n"
            return
            #exit 1
          end
          resource_pool_id = first_option['id']
        end
        if resource_pool_id.to_s["poolGroup-"]
          resource_pool = @resource_pool_groups_interface.get(resource_pool_id)['resourcePoolGroup']
        else
          resource_pool = @cloud_resource_pools_interface.get(cloud['id'], resource_pool_id)['resourcePool']
        end
      end
    end
    resource_pool
  end

  def prompt_security_groups_by_cloud(cloud, provision_type, resource_pool, options)
    security_groups = options[:securityGroups] || []

    if security_groups.empty? && cloud['zoneType']['hasSecurityGroups'] && ['amazon', 'rds'].include?(provision_type['code']) && resource_pool
      available_security_groups = @api_client.options.options_for_source('zoneSecurityGroup', {zoneId: cloud['id'], poolId: resource_pool['id']})['data']

      if available_security_groups.empty?
        #print_red_alert "Cloud #{cloud['name']} has no available plans"
        #exit 1
      elsif available_security_groups.count > 1 && !options[:no_prompt]
        while !available_security_groups.empty? && (security_groups.empty? || Morpheus::Cli::OptionTypes.confirm("Add security group?", {:default => false}))
          security_group = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'securityGroup', 'type' => 'select', 'fieldLabel' => 'Security Group', 'selectOptions' => available_security_groups, 'required' => true, 'description' => 'Select Security Group.'}], options[:options], @api_client, {})['securityGroup']
          security_groups << security_group
          available_security_groups.reject! { |sg| sg['value'] == security_group }
        end
      else
        security_groups << available_security_groups[0]
      end
    end
    security_groups
  end

  def prompt_update_namespace(options)
    rtn = {}
    rtn['description'] = options[:description] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Namespace Description', 'required' => false}], options[:options], @api_client)['description']
    rtn['active'] = options[:active].nil? ? (Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'description' => 'Namespace Active', 'defaultValue' => true}], options[:options], @api_client))['active'] == 'on' : options[:active]

    perms = prompt_permissions(options.merge({:available_plans => namespace_service_plans}))
    if perms['resourcePool'] && !perms['resourcePool']['visibility'].nil?
      rtn['visibility'] = perms['resourcePool']['visibility']
    end
    perms.delete('resourcePool')
    rtn['permissions'] = perms
    rtn
  end

  def get_valid_upgrade_versions(cluster_id)
    result = @clusters_interface.get_upgrade_versions(cluster_id, {})
    rtn = []
    if result['versions']
      rtn = result['versions'].map.with_index {|value, idx| {'name' => value,'value' => idx}}
    end
    rtn
  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

  def load_layout_options(cluster)
    (@api_client.options.options_for_source('computeTypeLayoutParameters', {layoutId: cluster['layout']['id']})['data'] || []).collect do |it|
      it['fieldName'] = it['name']
      it['fieldLabel'] = it['displayName']
      it['fieldContext'] = 'config.templateParameter'
      if it['type'] == 'ServicePlan'
        it['optionSource'] = 'servicePlans'
        it['type'] = 'select'
        it['params'] = {:provisionType => '', :zoneId => '', :siteId => '', :resourcePoolId => ''}
        it['params'][:provisionType] = 'azure' if it['azureServicePlanType']
      elsif it['type'] == 'Subnet'
        it['optionSource'] = 'networks'
        it['type'] = 'select'
        it['params'] = {:siteId => '', :instanceId => '', :serverId => '', :zonePoolId => '', :zoneRegionId => '', :zoneId => '', :provisionType => ''}
        if cluster['type'] == 'aks-cluster'
          it['params'][:provisionType] = 'azure'
        end
      else
        it['type'] = 'text'
      end
      it
    end
  end

  def load_floating_options(cluster, options)
    floating_ip_opts = @api_client.options.options_for_source('openstackFloatingIpOptions', {optionsSourceType: 'openStack', zoneId: cluster['cloud']['id']})['data']
    floating_ip_opts = floating_ip_opts.reject {|it| it['value'] == '' }
    floating_ip = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'osExternalNetworkId', 'fieldLabel' => 'Floating IP', 'type' => 'select', 'selectOptions' => floating_ip_opts, 'required' => false, 'description' => "Select Floating IP"}], options[:options])['osExternalNetworkId']
    return floating_ip
  end

  def available_kube_templates
    option_results = options_interface.options_for_source('availableKubeTemplates')
    available_templates = option_results['data'].collect {|it|
      {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
    }
   
    return available_templates
  end

  def apply_temp_options
    [
      {"id" => "specYaml", "name" => "YAML", "value" => "yaml"},
      {"id" => 'specTemplate', "name" => "Spec Template", "value" => 'specTemplate'},
      {"id" => 'url', "name" => 'Url of Template', "value" => 'url'}
    ]
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

  def refresh(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Refresh cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cluster = find_cluster_by_name_or_id(args[0])
      return 1 if cluster.nil?
      json_response = nil

      if options[:dry_run]
          print_dry_run @clusters_interface.dry.refresh(args[0].to_i)
        return
      end
      json_response = @clusters_interface.refresh(cluster['id'])
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Refreshing cluster #{cluster['name']}..."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_replicasets(args)
    _list_resources(args, 'replicaset')
  end

  def get_replicaset(args)
    _get_resource(args, 'replicaset')
  end

  def list_daemonsets(args)
    _list_resources(args, 'daemonset')
  end

  def get_daemonset(args)
    _get_resource(args, 'daemonset')
  end


  def list_endpoints(args)
    _list_resources(args, 'endpoint')
  end

  def get_endpoint(args)
    _get_resource(args, 'endpoint')
  end

  def list_ingresses(args)
    _list_resources(args, 'ingresse')
  end

  def get_ingress(args)
    _get_resource(args, 'ingresse', {'title' => 'ingress'})
  end

  def list_policies(args)
    _list_resources(args, 'policie')
  end

  def get_policy(args)
    _get_resource(args, 'policie', {'title' => 'policy'})
  end

  def list_volume_claims(args)
    _list_resources(args, 'volumeclaim')
  end

  def get_volume_claim(args)
    _get_resource(args, 'volumeclaim')
  end

  def list_volumes(args)
    _list_resources(args, 'volume')
  end

  def get_volume(args)
    _get_resource(args, 'volume')
  end


  def list_config_maps(args)
    _list_resources(args, 'configmap')
  end

  def get_config_map(args)
    _get_resource(args, 'configmap')
  end

  def list_secrets(args)
    _list_resources(args, 'secret')
  end

  def get_secret(args)
    _get_resource(args, 'secret')
  end

  def get_container(args)
    _get_resource(args, 'container')
  end

  def get_stateful_set(args)
    _get_resource(args, 'statefulset')

  end

  def get_job(args)
    _get_resource(args, 'job')
  end

  def get_service(args)
    _get_resource(args, 'service')
  end

  private

  def _get_resource(args, resource_type, options = {})
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster] [id]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "get #{resource_type} for a cluster.\n" +
                    "[cluster] and [#{resource_type}] is required. This is the name or id of an existing cluster, and the id of the #{resource_type}"
    end
    optparse.parse!(args)
    
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    connect(options)
    _get_container_group(args, options, resource_type)
  end

  def _list_resources(args, resource_type, options = {})
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cluster]")
      opts.on("--resource-level LEVEL", String, "Resource Level") do |val|
        options[:resourceLevel] = val.to_s
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List #{resource_type}s for a cluster.\n" +
          "[cluster] is required. This is the name or id of an existing cluster."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    _list_container_groups(args, options, resource_type)
  end
  
  def find_cluster_affinity_group_by_name_or_id(cluster_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      @clusters_interface.get_affinity_group(cluster_id, val)['affinityGroup'] rescue nil
    else
      @clusters_interface.list_affinity_groups(cluster_id, {name: val})['affinityGroups'][0]
    end
  end

   def add_affinity_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'affinityType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Keep Separate', 'value' => 'KEEP_SEPARATE'}, {'name' => 'Keep Together', 'value' => 'KEEP_TOGETHER'}], 'description' => 'Choose affinity type.', 'required' => true, 'defaultValue' => 'KEEP_SEPARATE'},
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'defaultValue' => true},
      # {'fieldName' => 'pool.id', 'fieldLabel' => 'Cluster', 'type' => 'select', 'optionSourceType' => 'vmware', 'optionSource' => 'vmwareZonePoolClusters', 'description' => 'Select cluster for the affinity group.', 'required' => true},
      {'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'description' => 'Select servers to be in the affinity group.'},
    ]
  end

  def format_affinity_type(affinity_type)
    affinity_type == "KEEP_SEPARATE" ? "Keep Separate" : "Keep Together"
  end

end
