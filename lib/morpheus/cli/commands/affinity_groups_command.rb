require 'morpheus/cli/cli_command'

class Morpheus::Cli::AffinityGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::AffinityHelper

  set_command_name :'affinity-groups'

  register_subcommands :list, :get, :add, :update, :remove, :violations

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @affinity_groups_interface = @api_client.affinity_groups
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
      opts.footer = "List affinity groups.\n" \
        "Requires a scope: use --cloud or --cluster. There is no unscoped list endpoint."
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
        print_dry_run @clouds_interface.dry.list_affinity_groups(cloud['id'], params)
        return
      end
      json_response = @clouds_interface.list_affinity_groups(cloud['id'], params)
      render_response(json_response, options, 'affinityGroups') do
        affinity_groups = json_response['affinityGroups']
        print_h1 "Affinity Groups: #{cloud['name']}", parse_list_subtitles(options), options
        if affinity_groups.empty?
          print cyan, "No affinity groups found.", reset, "\n"
        else
          print as_pretty_table(affinity_groups, affinity_group_list_columns, options)
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
        print_dry_run @clusters_interface.dry.list_affinity_groups(cluster['id'], params)
        return
      end
      json_response = @clusters_interface.list_affinity_groups(cluster['id'], params)
      render_response(json_response, options, 'affinityGroups') do
        affinity_groups = json_response['affinityGroups']
        print_h1 "Affinity Groups: #{cluster['name']}", parse_list_subtitles(options), options
        if affinity_groups.empty?
          print cyan, "No affinity groups found.", reset, "\n"
        else
          print as_pretty_table(affinity_groups, affinity_group_list_columns, options)
          print_results_pagination(json_response)
        end
        print reset, "\n"
      end
    else
      # There is no top-level list route: morpheus-ui ApiV1UrlMappings exposes
      # only /api/affinity-groups/{id} for show/update/delete. List stays scoped.
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
      opts.footer = "Get details about an affinity group.\n" \
        "[id] is required. This is the numeric id of the affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    id = args[0]
    params = {}
    params.merge!(parse_query_options(options))
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.get(id, params)
      return
    end
    json_response = @affinity_groups_interface.get(id, params)
    render_response(json_response, options, 'affinityGroup') do
      affinity_group = json_response['affinityGroup']
      print_h1 "Affinity Group Details", [], options
      print_description_list(affinity_group_detail_columns, affinity_group)
      if affinity_group['servers'] && affinity_group['servers'].size > 0
        print_h2 "Servers", options
        print as_pretty_table(affinity_group['servers'], [:id, :name], options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--cloud CLOUD', String, "Cloud name or id (required for cloud-scoped groups)") do |val|
        options[:options] ||= {}
        options[:options]['cloudId'] = val
      end
      opts.on('--cluster CLUSTER', String, "Cluster name or id (required for cluster-scoped groups)") do |val|
        options[:options] ||= {}
        options[:options]['clusterId'] = val
      end
      opts.on('--vm-group ID', String, "VM Group id (for VM-to-Host rules)") do |val|
        options[:options] ||= {}
        options[:options]['vmGroup'] = {'id' => val.to_i}
      end
      opts.on('--host-group ID', String, "Host Group id (for VM-to-Host rules)") do |val|
        options[:options] ||= {}
        options[:options]['hostGroup'] = {'id' => val.to_i}
      end
      opts.on('--servers ID1,ID2', Array, "Server ids (for VM-to-VM rules)") do |val|
        options[:options] ||= {}
        options[:options]['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      add_perms_options(opts, options, ['plans'])
      build_standard_add_options(opts, options)
      opts.footer = "Create a new affinity group.\n" \
        "Specify --cloud or --cluster to scope the group. " \
        "Use --vm-group and --host-group for VM-to-Host rules, or --servers for VM-to-VM rules."
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
        option_types = add_affinity_group_option_types
        affinity_group = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, {})

        preset_servers = options[:options].key?('servers')
        preset_vmhost  = options[:options].key?('vmGroup') && options[:options].key?('hostGroup')
        unless preset_servers || preset_vmhost
          shape_options = [{'name' => 'VM-to-VM (pick servers)', 'value' => 'vmToVm'},
                           {'name' => 'VM-to-Host (pick groups)', 'value' => 'vmToHost'}]
          shape = Morpheus::Cli::OptionTypes.prompt([{
            'fieldName' => 'shape', 'fieldLabel' => 'Rule Shape', 'type' => 'select',
            'required' => true, 'defaultValue' => 'vmToVm', 'selectOptions' => shape_options
          }], options[:options], @api_client, {})['shape']

          if shape == 'vmToVm'
            server_prompt = Morpheus::Cli::OptionTypes.prompt([{
              'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiTypeahead',
              'optionSource' => 'searchServers', 'searchParameter' => 'phrase',
              'description' => 'Select servers to be in the affinity group.'
            }], options[:options], @api_client, {})
            affinity_group['servers'] = server_prompt['servers'] if server_prompt['servers']
          else
            vm_group_id = Morpheus::Cli::OptionTypes.prompt([{
              'fieldName' => 'vmGroupId', 'fieldLabel' => 'VM Group ID', 'type' => 'text', 'required' => true
            }], options[:options], @api_client, {})['vmGroupId']
            host_group_id = Morpheus::Cli::OptionTypes.prompt([{
              'fieldName' => 'hostGroupId', 'fieldLabel' => 'Host Group ID', 'type' => 'text', 'required' => true
            }], options[:options], @api_client, {})['hostGroupId']
            affinity_group['vmGroup']   = {'id' => vm_group_id.to_i}
            affinity_group['hostGroup'] = {'id' => host_group_id.to_i}
          end
        else
          affinity_group['servers']   = options[:options]['servers']   if preset_servers
          affinity_group['vmGroup']   = options[:options]['vmGroup']   if preset_vmhost
          affinity_group['hostGroup'] = options[:options]['hostGroup'] if preset_vmhost
        end

        perms = prompt_permissions(options, is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])
        affinity_group['resourcePermissions'] = perms['resourcePermissions'] unless perms['resourcePermissions'].nil?
        affinity_group['tenants'] = perms['tenantPermissions'] unless perms['tenantPermissions'].nil? || perms['tenantPermissions']['accounts'].empty?
        affinity_group['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        payload = {'affinityGroup' => affinity_group}
      end

      # Create is scoped -- POST /api/clusters/{id}/affinity-groups or
      # /api/zones/{id}/affinity-groups. There is no top-level create route.
      scope_cloud   = options[:options] && options[:options]['cloudId']
      scope_cluster = options[:options] && options[:options]['clusterId']
      if scope_cloud
        cloud = find_cloud_by_name_or_id(scope_cloud)
        return 1 if cloud.nil?
        payload['affinityGroup'].delete('cloudId') if payload['affinityGroup'].is_a?(Hash)
        @clouds_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @clouds_interface.dry.create_affinity_group(cloud['id'], payload)
          return
        end
        json_response = @clouds_interface.create_affinity_group(cloud['id'], payload)
      elsif scope_cluster
        cluster = find_cluster_by_name_or_id(scope_cluster)
        return 1 if cluster.nil?
        payload['affinityGroup'].delete('clusterId') if payload['affinityGroup'].is_a?(Hash)
        @clusters_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @clusters_interface.dry.create_affinity_group(cluster['id'], payload)
          return
        end
        json_response = @clusters_interface.create_affinity_group(cluster['id'], payload)
      else
        print_error Morpheus::Terminal.angry_prompt
        puts_error "#{command_name} add requires a scope: pass --cloud CLOUD or --cluster CLUSTER\n#{optparse}"
        return 1, "scope required"
      end
      render_response(json_response, options, 'affinityGroup') do
        affinity_group = json_response['affinityGroup']
        print_green_success "Created affinity group #{affinity_group ? affinity_group['name'] : ''}"
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
      build_option_type_options(opts, options, update_affinity_group_option_types)
      opts.on('--vm-group ID', String, "VM Group id (for VM-to-Host rules)") do |val|
        options[:options] ||= {}
        options[:options]['vmGroup'] = {'id' => val.to_i}
      end
      opts.on('--host-group ID', String, "Host Group id (for VM-to-Host rules)") do |val|
        options[:options] ||= {}
        options[:options]['hostGroup'] = {'id' => val.to_i}
      end
      opts.on('--servers ID1,ID2', Array, "Server ids") do |val|
        options[:options] ||= {}
        options[:options]['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      add_perms_options(opts, options, ['plans'])
      build_standard_update_options(opts, options)
      opts.footer = "Update an affinity group.\n" \
        "[id] is required. This is the numeric id of the affinity group."
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
        payload = {'affinityGroup' => {}}
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_affinity_group_option_types, options[:options], @api_client, {})
        payload.deep_merge!({'affinityGroup' => v_prompt})

        perms = prompt_permissions(options, is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])
        payload['affinityGroup']['permissions'] = perms['resourcePermissions'] if perms['resourcePermissions']
        payload['affinityGroup']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        if options[:options]
          payload.deep_merge!({'affinityGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) || payload['affinityGroup'].key?(k) }})
        end
        if payload['affinityGroup'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @affinity_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @affinity_groups_interface.dry.update(id, payload)
        return
      end
      json_response = @affinity_groups_interface.update(id, payload)
      render_response(json_response, options, 'affinityGroup') do
        updated = json_response['affinityGroup']
        print_green_success "Updated affinity group #{updated ? updated['name'] : id}"
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
      opts.footer = "Delete an affinity group.\n" \
        "[id] is required. This is the numeric id of the affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    id = args[0]
    unless options[:yes] || ::Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete affinity group '#{id}'?", options)
      return 9, "aborted command"
    end

    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.destroy(id)
      return
    end
    begin
      json_response = @affinity_groups_interface.destroy(id)
      render_response(json_response, options) do
        print_green_success "Removed affinity group #{id}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def violations(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--cloud CLOUD', String, "Cloud name or id") do |val|
        options[:cloud] = val
      end
      opts.on('--cluster CLUSTER', String, "Cluster name or id") do |val|
        options[:cluster] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List active MUST-rule affinity violations.
" \
        "Requires a scope: use --cloud or --cluster."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)

    # AffinityGroupsController#violations returns 400 unless clusterId or
    # cloudId is supplied; scope travels in the query string, not the path.
    scope_name = nil
    if options[:cloud]
      cloud = find_cloud_by_name_or_id(options[:cloud])
      return 1 if cloud.nil?
      params['cloudId'] = cloud['id']
      scope_name = cloud['name']
    elsif options[:cluster]
      cluster = find_cluster_by_name_or_id(options[:cluster])
      return 1 if cluster.nil?
      params['clusterId'] = cluster['id']
      scope_name = cluster['name']
    else
      print_error Morpheus::Terminal.angry_prompt
      puts_error "#{command_name} violations requires a scope: pass --cloud CLOUD or --cluster CLUSTER
#{optparse}"
      return 1, "scope required"
    end

    params.merge!(parse_list_options(options))
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.violations(params)
      return
    end
    json_response = @affinity_groups_interface.violations(params)
    render_response(json_response, options, 'violations') do
      rows = json_response['violations'] || []
      print_h1 "Affinity Rule Violations: #{scope_name}", parse_list_subtitles(options), options
      if rows.empty?
        print cyan, "No violations.", reset, "
"
      else
        columns = {
          "Rule" => 'ruleName',
          "Type" => lambda {|r| r['keepTogether'] ? 'Keep Together' : 'Keep Separate' },
          "VMs" => lambda {|r| (r['affectedVms'] || []).collect {|v| v['name']}.join(', ') },
          "Empty Host Group" => lambda {|r| format_boolean(r['emptyHostGroup']) },
          "Occurred" => 'occurredAt'
        }.upcase_keys!
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset, "
"
    end
    return 0, nil
  end

  private

  def affinity_group_list_columns
    {
      "ID"            => 'id',
      "Name"          => 'name',
      "Type"          => lambda {|it| format_affinity_type(it['affinityType']) },
      "VM Group"      => lambda {|it| it['vmGroup']   ? (it['vmGroup']['name']   || it['vmGroup']['id'])   : '' },
      "Host Group"    => lambda {|it| it['hostGroup'] ? (it['hostGroup']['name'] || it['hostGroup']['id']) : '' },
      "Resource Pool" => lambda {|it| it['pool']      ? (it['pool']['name']      || it['pool']['id'])      : '' },
      "Visibility"    => lambda {|it| it['visibility'].to_s.capitalize },
      "Servers"       => lambda {|it| (it['servers'] || []).size },
    }.upcase_keys!
  end

  def affinity_group_detail_columns
    {
      "ID"            => 'id',
      "Name"          => 'name',
      "Type"          => lambda {|it| format_affinity_type(it['affinityType']) },
      "Ref Type"      => 'refType',
      "Ref ID"        => 'refId',
      "VM Group"      => lambda {|it| it['vmGroup']   ? (it['vmGroup']['name']   || it['vmGroup']['id'])   : '' },
      "Host Group"    => lambda {|it| it['hostGroup'] ? (it['hostGroup']['name'] || it['hostGroup']['id']) : '' },
      "Resource Pool" => lambda {|it| it['pool']      ? (it['pool']['name']      || it['pool']['id'])      : '' },
      "Visibility"    => lambda {|it| it['visibility'].to_s.capitalize },
      "Servers"       => lambda {|it| (it['servers'] || []).size },
      "Source"        => 'source',
      "Active"        => lambda {|it| format_boolean(it['active']) },
    }
  end

  def add_affinity_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      affinity_type_option_type(required: true, default: 'KEEP_TOGETHER'),
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'defaultValue' => true},
    ]
  end

  def update_affinity_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
      affinity_type_option_type,
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox'},
      {'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiTypeahead',
       'optionSource' => 'searchServers', 'searchParameter' => 'phrase',
       'description' => 'Select servers to be in the affinity group.'},
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
