require 'morpheus/cli/cli_command'

class Morpheus::Cli::DistributedWorkers
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @distributed_workers_interface = @api_client.distributed_workers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List distributed workers."
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:0)
    params = parse_list_options(options)
    @distributed_workers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @distributed_workers_interface.dry.list(params)
      return
    end
    json_response = @distributed_workers_interface.list(params)
    render_response(json_response, options, 'distributedWorkers') do
      distributed_workers = json_response['distributedWorkers']
      print_h1 "Morpheus Distributed Workers", parse_list_subtitles(options), options
      if distributed_workers.empty?
        print cyan,"No distributed workers found.",reset,"\n"
      else
        rows = distributed_workers.collect do |distributed_worker|
          {
            id: distributed_worker['id'],
            name: distributed_worker['name'],
            enabled: format_boolean(distributed_worker['enabled']),
            proxyPort: distributed_worker['proxyPort'],
            proxyHostList: distributed_worker['proxyHostList'],
            applianceUrl: distributed_worker['applianceUrl']
          }
        end
        columns = [:id, :name, :enabled, {:proxyPort => {:display_name => "Proxy Port"} }, {:proxyHostList => {:display_name => "Proxy Host List"} }, {:applianceUrl => {:display_name => "Appliance URL"} }]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[distributed-worker]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a distributed worker.\n[distributed-worker] is required. This is the name or id of a distributed worker."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    _get(args[0], options)
  end

  def _get(id, options)
    @distributed_workers_interface.setopts(options)
    if options[:dry_run]
      if id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @distributed_workers_interface.dry.get(id.to_i)
      else
        print_dry_run @distributed_workers_interface.dry.list({name: id})
      end
      return
    end
    distributed_worker = find_distributed_worker_by_name_or_id(id)
    return 1 if distributed_worker.nil?
    json_response = {'distributedWorker' => distributed_worker}
    render_response(json_response, options, 'distributedWorker') do
      render_distributed_worker_details(distributed_worker)
    end
    return 0, nil
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_distributed_worker_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Add a distributed worker.
[name] is required. This is the name of the new distributed worker.
The generated apiKey is only shown once, on creation. Be sure to save it.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    connect(options)
    options[:options] ||= {}
    if args[0]
      options[:options]['name'] ||= args[0]
    end
    payload = parse_payload(options, 'distributedWorker')
    if payload.nil?
      params = Morpheus::Cli::OptionTypes.prompt(add_distributed_worker_option_types, options[:options], @api_client, options[:params])
      payload = {'distributedWorker' => params}
    end
    @distributed_workers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @distributed_workers_interface.dry.create(payload)
      return
    end
    json_response = @distributed_workers_interface.create(payload)
    render_response(json_response, options, 'distributedWorker') do
      distributed_worker = json_response['distributedWorker']
      print_green_success "Added distributed worker #{distributed_worker['name']}"
      api_key = distributed_worker['apiKey']
      if api_key
        print "\n"
        print_h2 "API Key"
        print yellow, "Save this API Key now. It will not be shown again.", reset, "\n"
        print cyan, api_key, reset, "\n"
      end
      render_distributed_worker_details(distributed_worker)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[distributed-worker] [options]")
      build_option_type_options(opts, options, update_distributed_worker_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a distributed worker.
[distributed-worker] is required. This is the name or id of a distributed worker.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    distributed_worker = find_distributed_worker_by_name_or_id(args[0])
    return 1 if distributed_worker.nil?
    payload = parse_payload(options, 'distributedWorker')
    if payload.nil?
      params = options[:options] || {}
      params = params.select {|k,v| params[k].to_s != "" }
      if params.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload = {'distributedWorker' => params}
    end
    payload['distributedWorker']['id'] = distributed_worker['id']
    @distributed_workers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @distributed_workers_interface.dry.update(distributed_worker['id'], payload)
      return
    end
    json_response = @distributed_workers_interface.update(distributed_worker['id'], payload)
    render_response(json_response, options, 'distributedWorker') do
      print_green_success "Updated distributed worker #{distributed_worker['name']}"
      _get(distributed_worker['id'], options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[distributed-worker]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a distributed worker.
[distributed-worker] is required. This is the name or id of a distributed worker.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    distributed_worker = find_distributed_worker_by_name_or_id(args[0])
    return 1 if distributed_worker.nil?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the distributed worker #{distributed_worker['name']}?", options)
      return 9, "aborted command"
    end
    @distributed_workers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @distributed_workers_interface.dry.destroy(distributed_worker['id'])
      return
    end
    json_response = @distributed_workers_interface.destroy(distributed_worker['id'])
    render_response(json_response, options, 'distributedWorker') do
      print_green_success "Removed distributed worker #{distributed_worker['name']}"
    end
    return 0, nil
  end

  private

  def render_distributed_worker_details(distributed_worker)
    print_h1 "Distributed Worker Details"
    print cyan
    description_cols = {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Active" => lambda {|it| format_boolean(it['active']) },
      "Proxy Port" => 'proxyPort',
      "Proxy Host List" => 'proxyHostList',
      "Appliance URL" => 'applianceUrl',
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
    print_description_list(description_cols, distributed_worker)
    print reset,"\n"
  end

  def find_distributed_worker_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_distributed_worker_by_id(val)
    else
      return find_distributed_worker_by_name(val)
    end
  end

  def find_distributed_worker_by_id(id)
    begin
      json_response = @distributed_workers_interface.get(id.to_i)
      return json_response['distributedWorker']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Distributed Worker not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_distributed_worker_by_name(name)
    distributed_workers = @distributed_workers_interface.list({name: name.to_s})['distributedWorkers']
    if distributed_workers.empty?
      print_red_alert "Distributed Worker not found by name #{name}"
      return nil
    elsif distributed_workers.size > 1
      print_red_alert "#{distributed_workers.size} distributed workers found by name #{name}"
      rows = distributed_workers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color: red})
      return nil
    else
      return distributed_workers[0]
    end
  end

  def add_distributed_worker_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1, 'description' => 'A unique name for the distributed worker.'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true, 'displayOrder' => 3},
      {'fieldName' => 'proxyHostList', 'fieldLabel' => 'Proxy Host List', 'type' => 'text', 'required' => false, 'displayOrder' => 4, 'description' => 'A comma or space separated list of proxy hosts.'},
      {'fieldName' => 'applianceUrl', 'fieldLabel' => 'Appliance URL', 'type' => 'text', 'required' => false, 'displayOrder' => 5},
    ]
  end

  def update_distributed_worker_option_types
    list = add_distributed_worker_option_types
    list.each {|it| it['required'] = false; it.delete('defaultValue') }
    list
  end

end
