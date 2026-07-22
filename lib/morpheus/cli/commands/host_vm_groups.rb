require 'morpheus/cli/cli_command'

class Morpheus::Cli::HostVmGroups
  include Morpheus::Cli::CliCommand

  # MORPH-14136 — CLI parity for the host-vm-groups REST surface.

  set_command_description "View and manage host / VM groups on HVM clusters."
  set_command_name :'host-vm-groups'
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @host_vm_groups_interface = @api_client.host_vm_groups
    @clusters_interface = @api_client.clusters
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} host-vm-groups list --cluster CLUSTER"
      opts.on('--cluster CLUSTER', String, "Cluster name or ID (required)") do |val|
        options[:cluster] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List host / VM groups on a cluster."
    end
    optparse.parse!(args)
    connect(options)
    if options[:cluster].nil?
      raise_command_error "--cluster is required", args, optparse
    end
    cluster = find_cluster_by_name_or_id(options[:cluster])
    return 1 if cluster.nil?
    params.merge!(parse_list_options(options))
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.list(cluster['id'], params)
      return
    end
    json_response = @host_vm_groups_interface.list(cluster['id'], params)
    render_response(json_response, options, "hostVmGroups") do
      rows = json_response["hostVmGroups"] || []
      print_h1 "Host / VM Groups", ["Cluster: #{cluster['name']}"], options
      if rows.empty?
        print cyan, "No host / VM groups found.", reset, "\n"
      else
        columns = {
          "ID" => 'id',
          "NAME" => 'name',
          "TYPE" => 'type',
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
      opts.banner = "Usage: #{prog_name} host-vm-groups get ID"
      build_standard_get_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.get(id, params)
      return
    end
    json_response = @host_vm_groups_interface.get(id, params)
    render_response(json_response, options, "hostVmGroup") do
      row = json_response["hostVmGroup"] || json_response
      print_h1 "Host / VM Group", [], options
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => 'type',
        "Ref Type" => 'refType',
        "Ref ID" => 'refId',
        "Servers" => lambda {|r| (r['servers'] || []).map {|s| s['name']}.join(', ') },
        "Visibility" => 'visibility',
        "Active" => 'active'
      }
      print_description_list(description_cols, row)
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    payload_extras = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} host-vm-groups add [--cluster CLUSTER] [--name NAME] [--type TYPE] [options]"
      opts.on('--cluster CLUSTER', String, "Cluster name or ID") do |val|
        options[:cluster] = val
      end
      opts.on('--name NAME', String, "Group name") do |val|
        payload_extras['name'] = val
      end
      opts.on('--type TYPE', String, "Group type: HOST_GROUP | VM_GROUP") do |val|
        payload_extras['type'] = val
      end
      opts.on('--servers ID1,ID2', Array, "Server IDs to include") do |val|
        payload_extras['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      opts.on('--visibility VISIBILITY', String, "Visibility: private | public") do |val|
        payload_extras['visibility'] = val
      end
      build_standard_add_options(opts, options)
      opts.footer = "Create a host or VM group on a cluster. Prompts for missing values unless -N is passed."
    end
    optparse.parse!(args)
    connect(options)

    cluster_value = options[:cluster]
    if cluster_value.nil? || cluster_value.to_s == ''
      cluster_value = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'cluster', 'fieldLabel' => 'Cluster', 'type' => 'text', 'required' => true,
        'description' => 'Cluster name or ID'
      }], options[:options], @api_client, {})['cluster']
    end
    cluster = find_cluster_by_name_or_id(cluster_value)
    return 1 if cluster.nil?

    if payload_extras['name'].nil? || payload_extras['name'].to_s == ''
      payload_extras['name'] = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'name', 'fieldLabel' => 'Group Name', 'type' => 'text', 'required' => true
      }], options[:options], @api_client, {})['name']
    end

    if payload_extras['type'].nil?
      payload_extras['type'] = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'type', 'fieldLabel' => 'Group Type', 'type' => 'select', 'required' => true,
        'defaultValue' => 'HOST_GROUP',
        'selectOptions' => [
          {'name' => 'Host Group', 'value' => 'HOST_GROUP'},
          {'name' => 'VM Group',   'value' => 'VM_GROUP'}
        ]
      }], options[:options], @api_client, {})['type']
    end

    if payload_extras['servers'].nil?
      form_opts = @host_vm_groups_interface.form_options(cluster['id'], {'hostVmGroupType' => payload_extras['type']})
      available_servers = form_opts['availableServers'] || []
      if available_servers.empty?
        print_red_alert "No servers available on cluster #{cluster['name']} for type #{payload_extras['type']}"
        return 1
      end
      print cyan, "Available Servers:", reset, "\n"
      available_servers.each {|s| print "  #{s['id']}\t#{s['name']}\n" }
      raw = Morpheus::Cli::OptionTypes.prompt([{
        'fieldName' => 'servers', 'fieldLabel' => 'Servers (comma-separated IDs)', 'type' => 'text', 'required' => true,
        'description' => 'Server IDs to include, comma-separated (e.g. 24877,24878)'
      }], options[:options], @api_client, {})['servers']
      selected_ids = raw.to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i)
      valid_ids = available_servers.map {|s| s['id'].to_i}
      invalid = selected_ids - valid_ids
      if !invalid.empty?
        print_red_alert "Invalid server IDs for this cluster/type: #{invalid.join(', ')}"
        return 1
      end
      if selected_ids.empty?
        print_red_alert "At least one server ID is required"
        return 1
      end
      payload_extras['servers'] = selected_ids.map {|id| {'id' => id}}
    end

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

    payload = {'hostVmGroup' => payload_extras}
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.create(cluster['id'], payload)
      return
    end
    json_response = @host_vm_groups_interface.create(cluster['id'], payload)
    render_response(json_response, options, "hostVmGroup") do
      print_green_success "Created host/VM group: #{json_response['hostVmGroup']['name']}"
    end
    return 0, nil
  end

  def update(args)
    options = {}
    payload_extras = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} host-vm-groups update ID [options]"
      opts.on('--servers ID1,ID2', Array, "Replace server IDs") do |val|
        payload_extras['servers'] = val.map {|s| {'id' => s.to_i}}
      end
      opts.on('--visibility VISIBILITY', String, "Visibility") do |val|
        payload_extras['visibility'] = val
      end
      build_standard_update_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    payload = {'hostVmGroup' => payload_extras}
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.update(id, payload)
      return
    end
    json_response = @host_vm_groups_interface.update(id, payload)
    render_response(json_response, options, "hostVmGroup") do
      print_green_success "Updated host/VM group #{id}"
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} host-vm-groups remove ID"
      build_standard_remove_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    id = args[0]
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to remove host/VM group #{id}?")
      return 9, "aborted"
    end
    @host_vm_groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @host_vm_groups_interface.dry.destroy(id)
      return
    end
    json_response = @host_vm_groups_interface.destroy(id)
    render_response(json_response, options) do
      print_green_success "Removed host/VM group #{id}"
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
