require 'morpheus/cli/cli_command'

class Morpheus::Cli::HostVmGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::AffinityHelper

  set_command_name :'host-vm-groups'

  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @host_vm_groups_interface = @api_client.host_vm_groups
    @clouds_interface = @api_client.clouds
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
      opts.on('--cloud CLOUD', String, "Filter by cloud name or id") do |val|
        options[:cloud] = val
      end
      opts.on('--cluster CLUSTER', String, "Filter by cluster name or id") do |val|
        options[:cluster] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List host/VM groups.\n" \
        "Use --cloud or --cluster to scope results. Without a scope all groups visible to the user are listed."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)

    if options[:cloud]
      cloud = find_cloud_by_name_or_id(options[:cloud])
      return 1 if cloud.nil?
      params.merge!(parse_list_options(options))
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.list_host_vm_groups(cloud['id'], params)
        return
      end
      json_response = @clouds_interface.list_host_vm_groups(cloud['id'], params)
      render_response(json_response, options, 'hostVmGroups') do
        rows = json_response['hostVmGroups']
        print_h1 "Host/VM Groups: #{cloud['name']}", parse_list_subtitles(options), options
        if rows.empty?
          print cyan, "No host/VM groups found.", reset, "\n"
        else
          print as_pretty_table(rows, host_vm_group_list_columns, options)
          print_results_pagination(json_response)
        end
        print reset, "\n"
      end
    elsif options[:cluster]
      cluster = find_cluster_by_name_or_id(options[:cluster])
      return 1 if cluster.nil?
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list_host_vm_groups(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_host_vm_groups(cluster['id'], params)
      render_response(json_response, options, 'hostVmGroups') do
        rows = json_response['hostVmGroups']
        print_h1 "Host/VM Groups: #{cluster['name']}", parse_list_subtitles(options), options
        if rows.empty?
          print cyan, "No host/VM groups found.", reset, "\n"
        else
          print as_pretty_table(rows, host_vm_group_list_columns, options)
          print_results_pagination(json_response)
        end
        print reset, "\n"
      end
    else
      # No top-level list route; /api/host-vm-groups exposes only /{id}.
      print_error Morpheus::Terminal.angry_prompt
      puts_error "#{command_name} list requires a scope: pass --cloud CLOUD or --cluster CLUSTER\n#{optparse}"
      return 1, "scope required"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a host/VM group.\n" \
        "[id] is required. This is the numeric id of the host/VM group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    id = args[0]
    params = {}
    params.merge!(parse_query_options(options))
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.get(id, params)
      return
    end
    json_response = @host_vm_groups_interface.get(id, params)
    render_response(json_response, options, 'hostVmGroup') do
      row = json_response['hostVmGroup']
      print_h1 "Host/VM Group Details", [], options
      print_description_list(host_vm_group_detail_columns, row)
      if row['servers'] && row['servers'].size > 0
        print_h2 "Servers", options
        print as_pretty_table(row['servers'], [:id, :name], options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--cloud CLOUD', String, "Cloud name or id") do |val|
        options[:options] ||= {}
        options[:options]['cloudId'] = val
      end
      opts.on('--cluster CLUSTER', String, "Cluster name or id") do |val|
        options[:options] ||= {}
        options[:options]['clusterId'] = val
      end
      opts.on('--servers ID1,ID2', Array, "Server ids to add to the group") do |val|
        options[:options] ||= {}
        options[:options]['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      add_perms_options(opts, options, ['plans'])
      build_standard_add_options(opts, options)
      opts.footer = "Create a new host/VM group.\n" \
        "Specify --cloud or --cluster to scope the group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)

    begin
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      else
        options[:options] ||= {}
        host_vm_group = Morpheus::Cli::OptionTypes.prompt(add_host_vm_group_option_types, options[:options], @api_client, {})

        unless options[:options].key?('servers')
          server_prompt = Morpheus::Cli::OptionTypes.prompt([{
            'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiTypeahead',
            'optionSource' => 'searchServers', 'searchParameter' => 'phrase',
            'description' => 'Select servers to add to the group.'
          }], options[:options], @api_client, {})
          host_vm_group['servers'] = server_prompt['servers'] if server_prompt['servers']
        else
          host_vm_group['servers'] = options[:options]['servers']
        end

        perms = prompt_permissions(options, is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])
        host_vm_group['resourcePermissions'] = perms['resourcePermissions'] unless perms['resourcePermissions'].nil?
        host_vm_group['tenants'] = perms['tenantPermissions'] unless perms['tenantPermissions'].nil? || perms['tenantPermissions']['accounts'].empty?
        host_vm_group['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        payload = {'hostVmGroup' => host_vm_group}
      end

      # Create is scoped -- POST /api/clusters/{id}/host-vm-groups or
      # /api/zones/{id}/host-vm-groups. There is no top-level create route.
      scope_cloud   = options[:options] && options[:options]['cloudId']
      scope_cluster = options[:options] && options[:options]['clusterId']
      if scope_cloud
        cloud = find_cloud_by_name_or_id(scope_cloud)
        return 1 if cloud.nil?
        payload['hostVmGroup'].delete('cloudId') if payload['hostVmGroup'].is_a?(Hash)
        @clouds_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @clouds_interface.dry.create_host_vm_group(cloud['id'], payload)
          return
        end
        json_response = @clouds_interface.create_host_vm_group(cloud['id'], payload)
      elsif scope_cluster
        cluster = find_cluster_by_name_or_id(scope_cluster)
        return 1 if cluster.nil?
        payload['hostVmGroup'].delete('clusterId') if payload['hostVmGroup'].is_a?(Hash)
        @clusters_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @clusters_interface.dry.create_host_vm_group(cluster['id'], payload)
          return
        end
        json_response = @clusters_interface.create_host_vm_group(cluster['id'], payload)
      else
        print_error Morpheus::Terminal.angry_prompt
        puts_error "#{command_name} add requires a scope: pass --cloud CLOUD or --cluster CLUSTER\n#{optparse}"
        return 1, "scope required"
      end
      render_response(json_response, options, 'hostVmGroup') do
        row = json_response['hostVmGroup']
        print_green_success "Created host/VM group #{row ? row['name'] : ''}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      handle_affinity_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      build_option_type_options(opts, options, update_host_vm_group_option_types)
      opts.on('--servers ID1,ID2', Array, "Server ids") do |val|
        options[:options] ||= {}
        options[:options]['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      add_perms_options(opts, options, ['plans'])
      build_standard_update_options(opts, options)
      opts.footer = "Update a host/VM group.\n" \
        "[id] is required. This is the numeric id of the host/VM group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      id = args[0]
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      else
        payload = {'hostVmGroup' => {}}
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_host_vm_group_option_types, options[:options], @api_client, {})
        payload.deep_merge!({'hostVmGroup' => v_prompt})

        perms = prompt_permissions(options, is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])
        payload['hostVmGroup']['permissions'] = perms['resourcePermissions'] if perms['resourcePermissions']
        payload['hostVmGroup']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        if options[:options]
          payload.deep_merge!({'hostVmGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) || payload['hostVmGroup'].key?(k) }})
        end
        if payload['hostVmGroup'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @host_vm_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @host_vm_groups_interface.dry.update(id, payload)
        return
      end
      json_response = @host_vm_groups_interface.update(id, payload)
      render_response(json_response, options, 'hostVmGroup') do
        updated = json_response['hostVmGroup']
        print_green_success "Updated host/VM group #{updated ? updated['name'] : id}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      handle_affinity_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete a host/VM group.\n" \
        "[id] is required. This is the numeric id of the host/VM group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    id = args[0]
    unless options[:yes] || ::Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete host/VM group '#{id}'?", options)
      return 9, "aborted command"
    end

    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.destroy(id)
      return
    end
    begin
      json_response = @host_vm_groups_interface.destroy(id)
      render_response(json_response, options) do
        print_green_success "Removed host/VM group #{id}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      handle_affinity_rest_exception(e, options)
      exit 1
    end
  end

  private

  def host_vm_group_list_columns
    {
      "ID"            => 'id',
      "Name"          => 'name',
      "Type"          => lambda {|it| format_host_vm_group_type(it['type']) },
      "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
      "Servers"       => lambda {|it| (it['servers'] || []).size },
    }.upcase_keys!
  end

  def host_vm_group_detail_columns
    {
      "ID"            => 'id',
      "Name"          => 'name',
      "Type"          => lambda {|it| format_host_vm_group_type(it['type']) },
      "Ref Type"      => 'refType',
      "Ref ID"        => 'refId',
      "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
      "Visibility"    => lambda {|it| it['visibility'].to_s.capitalize },
      "Servers"       => lambda {|it| (it['servers'] || []).size },
      "Source"        => 'source',
    }
  end

  def add_host_vm_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      host_vm_group_type_option_type(required: true, default: 'HOST_GROUP'),
    ]
  end

  def update_host_vm_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
    ]
  end

  def find_cluster_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      @clusters_interface.get(val.to_i)['cluster'] rescue nil
    else
      results = @clusters_interface.list({name: val})
      results['clusters'] && results['clusters'][0]
    end
  end

end
