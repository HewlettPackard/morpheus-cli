require 'morpheus/cli/cli_command'

class Morpheus::Cli::AffinityGroups
  include Morpheus::Cli::CliCommand

  # MORPH-14136 — CLI parity for the affinity-groups REST surface.

  set_command_description "View and manage affinity rules on HVM clusters."
  set_command_name :'affinity-groups'
  register_subcommands :list, :get, :add, :update, :remove, :violations

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @affinity_groups_interface = @api_client.affinity_groups
    @clusters_interface = @api_client.clusters
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups list --cluster CLUSTER"
      opts.on('--cluster CLUSTER', String, "Cluster name or ID (required)") do |val|
        options[:cluster] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List affinity rules on a cluster."
    end
    optparse.parse!(args)
    connect(options)
    if options[:cluster].nil? || options[:cluster].to_s == ''
      raise_command_error "--cluster is required", args, optparse
    end
    cluster = find_cluster_by_name_or_id(options[:cluster])
    return 1 if cluster.nil?
    params.merge!(parse_list_options(options))
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.list(cluster['id'], params)
      return
    end
    json_response = @affinity_groups_interface.list(cluster['id'], params)
    render_response(json_response, options, "affinityGroups") do
      rows = json_response["affinityGroups"] || []
      print_h1 "Affinity Rules", ["Cluster: #{cluster['name']}"], options
      if rows.empty?
        print cyan, "No affinity rules found.", reset, "\n"
      else
        columns = {
          "ID" => 'id',
          "NAME" => 'name',
          "TYPE" => 'affinityType',
          "VM GROUP" => lambda {|r| r['vmGroup']&.dig('name') },
          "HOST GROUP" => lambda {|r| r['hostGroup']&.dig('name') },
          "SERVERS" => lambda {|r| (r['servers'] || []).map {|s| s['name']}.join(', ') },
          "VISIBILITY" => 'visibility'
        }
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups get ID"
      build_standard_get_options(opts, options)
      opts.footer = "Get details of an affinity rule by ID."
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.get(id, params)
      return
    end
    json_response = @affinity_groups_interface.get(id, params)
    render_response(json_response, options, "affinityGroup") do
      rule = json_response["affinityGroup"] || json_response
      print_h1 "Affinity Rule", [], options
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => 'affinityType',
        "Ref Type" => 'refType',
        "Ref ID" => 'refId',
        "VM Group" => lambda {|r| r['vmGroup']&.dig('name') },
        "Host Group" => lambda {|r| r['hostGroup']&.dig('name') },
        "Servers" => lambda {|r| (r['servers'] || []).map {|s| s['name']}.join(', ') },
        "Visibility" => 'visibility',
        "Active" => 'active'
      }
      print_description_list(description_cols, rule)
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    payload_extras = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups add [--cluster CLUSTER] [--name NAME] [options]"
      opts.on('--cluster CLUSTER', String, "Cluster name or ID") do |val|
        options[:cluster] = val
      end
      opts.on('--name NAME', String, "Rule name") do |val|
        payload_extras['name'] = val
      end
      opts.on('--type TYPE', String, "Affinity type: KEEP_TOGETHER | KEEP_SEPARATE | KEEP_TOGETHER_MUST | KEEP_SEPARATE_MUST") do |val|
        payload_extras['affinityType'] = val
      end
      opts.on('--vm-group ID', String, "VM Group ID (for VM-to-Host rules)") do |val|
        payload_extras['vmGroup'] = {'id' => val.to_i}
      end
      opts.on('--host-group ID', String, "Host Group ID (for VM-to-Host rules)") do |val|
        payload_extras['hostGroup'] = {'id' => val.to_i}
      end
      opts.on('--servers ID1,ID2', Array, "Server IDs (for VM-to-VM rules)") do |val|
        payload_extras['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      opts.on('--visibility VISIBILITY', String, "Visibility: private | public") do |val|
        payload_extras['visibility'] = val
      end
      build_standard_add_options(opts, options)
      opts.footer = "Create an affinity rule on a cluster. Prompts for missing values unless -N is passed."
    end
    optparse.parse!(args)
    connect(options)

    # Cluster — either --cluster or prompt
    cluster_value = options[:cluster]
    if cluster_value.nil? || cluster_value.to_s == ''
      cluster_value = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'cluster', 'fieldLabel' => 'Cluster', 'type' => 'text', 'required' => true,
        'description' => 'Cluster name or ID'
      }], options[:options], @api_client, {})['cluster']
    end
    cluster = find_cluster_by_name_or_id(cluster_value)
    return 1 if cluster.nil?

    # Name
    if payload_extras['name'].nil? || payload_extras['name'].to_s == ''
      payload_extras['name'] = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'name', 'fieldLabel' => 'Rule Name', 'type' => 'text', 'required' => true
      }], options[:options], @api_client, {})['name']
    end

    # Type
    if payload_extras['affinityType'].nil?
      payload_extras['affinityType'] = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'affinityType', 'fieldLabel' => 'Affinity Type', 'type' => 'select', 'required' => true,
        'defaultValue' => 'KEEP_TOGETHER',
        'selectOptions' => [
          {'name' => 'Keep Together (Should)', 'value' => 'KEEP_TOGETHER'},
          {'name' => 'Keep Separate (Should)', 'value' => 'KEEP_SEPARATE'},
          {'name' => 'Keep Together (Must)',  'value' => 'KEEP_TOGETHER_MUST'},
          {'name' => 'Keep Separate (Must)',  'value' => 'KEEP_SEPARATE_MUST'}
        ]
      }], options[:options], @api_client, {})['affinityType']
    end

    # Rule shape — servers OR vmGroup+hostGroup
    has_shape = payload_extras.key?('servers') || (payload_extras.key?('vmGroup') && payload_extras.key?('hostGroup'))
    unless has_shape
      shape = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'shape', 'fieldLabel' => 'Rule Shape', 'type' => 'select', 'required' => true,
        'defaultValue' => 'vmToVm',
        'selectOptions' => [
          {'name' => 'VM-to-VM (pick servers)',  'value' => 'vmToVm'},
          {'name' => 'VM-to-Host (pick groups)', 'value' => 'vmToHost'}
        ]
      }], options[:options], @api_client, {})['shape']

      form_opts = @affinity_groups_interface.form_options(cluster['id'])
      if shape == 'vmToVm'
        available_servers = form_opts['availableServers'] || []
        if available_servers.empty?
          print_red_alert "No servers available on cluster #{cluster['name']}"
          return 1
        end
        print cyan, "Available Servers:", reset, "\n"
        available_servers.each {|s| print "  #{s['id']}\t#{s['name']}\n" }
        raw = Morpheus::Cli::OptionTypes.prompt([{
          'fieldName' => 'servers', 'fieldLabel' => 'Servers (comma-separated IDs)', 'type' => 'text', 'required' => true,
          'description' => 'Server IDs to include, comma-separated'
        }], options[:options], @api_client, {})['servers']
        selected_ids = raw.to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i)
        valid_ids = available_servers.map {|s| s['id'].to_i}
        invalid = selected_ids - valid_ids
        if !invalid.empty?
          print_red_alert "Invalid server IDs for this cluster: #{invalid.join(', ')}"
          return 1
        end
        if selected_ids.empty?
          print_red_alert "At least one server ID is required"
          return 1
        end
        payload_extras['servers'] = selected_ids.map {|id| {'id' => id}}
      else
        available_vm_groups = (form_opts['availableVmGroups'] || []).map {|g| {'name' => g['name'], 'value' => g['id']} }
        available_host_groups = (form_opts['availableHostGroups'] || []).map {|g| {'name' => g['name'], 'value' => g['id']} }
        if available_vm_groups.empty? || available_host_groups.empty?
          print_red_alert "VM-to-Host rules require at least one VM Group and one Host Group on cluster #{cluster['name']}"
          return 1
        end
        vm_group_id = Morpheus::Cli::OptionTypes.prompt([{
          'fieldName' => 'vmGroup', 'fieldLabel' => 'VM Group', 'type' => 'select', 'required' => true,
          'selectOptions' => available_vm_groups
        }], options[:options], @api_client, {})['vmGroup']
        host_group_id = Morpheus::Cli::OptionTypes.prompt([{
          'fieldName' => 'hostGroup', 'fieldLabel' => 'Host Group', 'type' => 'select', 'required' => true,
          'selectOptions' => available_host_groups
        }], options[:options], @api_client, {})['hostGroup']
        payload_extras['vmGroup'] = {'id' => vm_group_id.to_i}
        payload_extras['hostGroup'] = {'id' => host_group_id.to_i}
      end
    end

    # Visibility (optional)
    if payload_extras['visibility'].nil?
      payload_extras['visibility'] = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'required' => false,
        'defaultValue' => 'private',
        'selectOptions' => [
          {'name' => 'Private', 'value' => 'private'},
          {'name' => 'Public',  'value' => 'public'}
        ]
      }], options[:options], @api_client, {})['visibility']
    end

    payload = {'affinityGroup' => payload_extras}
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.create(cluster['id'], payload)
      return
    end
    json_response = @affinity_groups_interface.create(cluster['id'], payload)
    render_response(json_response, options, "affinityGroup") do
      print_green_success "Created affinity rule: #{json_response['affinityGroup']['name']}"
    end
    return 0, nil
  end

  def update(args)
    options = {}
    payload_extras = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups update ID [options]"
      opts.on('--name NAME', String, "New rule name") do |val|
        payload_extras['name'] = val
      end
      opts.on('--type TYPE', String, "Affinity type") do |val|
        payload_extras['affinityType'] = val
      end
      opts.on('--visibility VISIBILITY', String, "Visibility: private | public") do |val|
        payload_extras['visibility'] = val
      end
      build_standard_update_options(opts, options)
      opts.footer = "Update an affinity rule by ID."
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    payload = {'affinityGroup' => payload_extras}
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.update(id, payload)
      return
    end
    json_response = @affinity_groups_interface.update(id, payload)
    render_response(json_response, options, "affinityGroup") do
      print_green_success "Updated affinity rule #{id}"
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups remove ID"
      build_standard_remove_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to remove affinity rule #{id}?")
      return 9, "aborted"
    end
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.destroy(id)
      return
    end
    json_response = @affinity_groups_interface.destroy(id)
    render_response(json_response, options) do
      print_green_success "Removed affinity rule #{id}"
    end
    return 0, nil
  end

  def violations(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} affinity-groups violations [--cluster CLUSTER | --cloud CLOUD]"
      opts.on('--cluster CLUSTER', String, "Cluster name or ID") do |val|
        options[:cluster] = val
      end
      opts.on('--cloud CLOUD', String, "Cloud ID") do |val|
        params['cloudId'] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List active MUST-rule violations."
    end
    optparse.parse!(args)
    connect(options)
    if options[:cluster]
      cluster = find_cluster_by_name_or_id(options[:cluster])
      return 1 if cluster.nil?
      params['clusterId'] = cluster['id']
    end
    @affinity_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @affinity_groups_interface.dry.violations(params)
      return
    end
    json_response = @affinity_groups_interface.violations(params)
    render_response(json_response, options, "violations") do
      rows = json_response["violations"] || []
      print_h1 "Affinity Rule Violations", [], options
      if rows.empty?
        print cyan, "No violations.", reset, "\n"
      else
        columns = {
          "RULE" => 'ruleName',
          "TYPE" => lambda {|r| r['keepTogether'] ? 'KEEP_TOGETHER' : 'KEEP_SEPARATE' },
          "VMS" => lambda {|r| (r['affectedVms'] || []).map {|v| v['name']}.join(', ') },
          "OCCURRED" => 'occurredAt'
        }
        print as_pretty_table(rows, columns, options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  private

  def find_cluster_by_name_or_id(val)
    if val.to_s =~ /\A\d+\z/
      resp = @clusters_interface.get(val.to_i)
      resp['cluster']
    else
      resp = @clusters_interface.list({'phrase' => val.to_s})
      matches = (resp['clusters'] || []).select {|c| c['name'] == val.to_s }
      if matches.size == 1
        matches[0]
      elsif matches.empty?
        print_red_alert "Cluster not found: #{val}"
        nil
      else
        print_red_alert "Multiple clusters match #{val}; pass a numeric ID."
        nil
      end
    end
  end
end
