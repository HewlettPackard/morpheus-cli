require 'morpheus/cli/cli_command'

class Morpheus::Cli::Systems
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :systems
  set_command_description "View and manage systems."
  register_subcommands :list, :get, :add, :update, :remove

  protected

  # Systems API uses lowercase keys in payloads.
  def system_object_key
    'system'
  end

  def system_list_key
    'systems'
  end

  def system_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Layout" => lambda {|it| it['layout'] ? it['layout']['name'] : '' },
      "Status" => 'status',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) }
    }
  end

  def system_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Status" => 'status',
      "Status Message" => 'statusMessage',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "External ID" => 'externalId',
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key] || json_response
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      print reset,"\n"
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] --name --description")
      opts.on("--name NAME", String, "Updates System Name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Updates System Description") do |val|
        params['description'] = val.to_s
      end
      build_standard_update_options(opts, options, [:find_by_name])
      opts.footer = <<-EOT
Update an existing system.
[system] is required. This is the name or id of a system.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)

    system = nil
    if args[0].to_s =~ /\A\d{1,}\Z/
      json_response = rest_interface.get(args[0].to_i)
      system = json_response[rest_object_key] || json_response
    else
      system = find_by_name(rest_key, args[0])
    end
    return 1, "System not found for '#{args[0]}'" if system.nil?

    passed_options = parse_passed_options(options)
    params.deep_merge!(passed_options) unless passed_options.empty?
    params.booleanize!

    payload = parse_payload(options) || {rest_object_key => params}
    if payload[rest_object_key].nil? || payload[rest_object_key].empty?
      raise_command_error "Specify at least one option to update.\n#{optparse}"
    end

    if options[:dry_run]
      print_dry_run rest_interface.dry.update(system['id'], payload)
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.update(system['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated system #{system['id']}"
      get([system['id']] + (options[:remote] ? ['-r', options[:remote]] : []))
    end
  end
end
