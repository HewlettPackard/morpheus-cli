require 'morpheus/cli/cli_command'

class Morpheus::Cli::Systems
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :systems
  set_command_description "View and manage systems."
  register_subcommands :list, :get, :add, :update, :remove, :'add-uninitialized'

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

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name NAME', String, "System Name") do |val|
        params['name'] = val.to_s
      end
      opts.on('--description [TEXT]', String, "Description") do |val|
        params['description'] = val.to_s
      end
      opts.on('--type TYPE', String, "System Type ID or name") do |val|
        params['type'] = val
      end
      opts.on('--layout LAYOUT', String, "System Layout ID or name") do |val|
        params['layout'] = val
      end
      build_standard_add_options(opts, options)
      opts.footer = "Create a new system.\n[name] is optional and can be passed as the first argument."
    end
    optparse.parse!(args)
    connect(options)

    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload[rest_object_key] ||= {}
      payload[rest_object_key].deep_merge!(params) unless params.empty?
      payload[rest_object_key]['name'] ||= args[0] if args[0]
    else
      system_payload = {}

      # Name
      system_payload['name'] = params['name'] || args[0]
      if !system_payload['name'] && !options[:no_prompt]
        system_payload['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options], @api_client, {})['name']
      end
      raise_command_error "Name is required.\n#{optparse}" if system_payload['name'].to_s.empty?

      # Description
      if !params['description'] && !options[:no_prompt]
        system_payload['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false}], options[:options], @api_client, {})['description']
      else
        system_payload['description'] = params['description']
      end

      # Type
      available_types = system_types_for_dropdown
      type_val = params['type']
      if type_val
        type_id = type_val =~ /\A\d+\Z/ ? type_val.to_i : available_types.find { |t| t['name'] == type_val || t['code'] == type_val }&.dig('id')
        raise_command_error "System type not found: #{type_val}" unless type_id
        system_payload['type'] = {'id' => type_id}
      elsif !options[:no_prompt]
        if available_types.empty?
          raise_command_error "No system types found."
        else
          print cyan, "Available System Types\n", reset
          available_types.each do |t|
            print "  #{t['id']}) #{t['name']}#{t['code'] ? " (#{t['code']})" : ''}\n"
          end
          selected = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'text', 'fieldLabel' => 'System Type ID', 'required' => true}], options[:options], @api_client, {})['type']
          type_id = available_types.find { |t| t['id'].to_s == selected.to_s }&.dig('id')
          raise_command_error "Invalid system type id: #{selected}" unless type_id
          system_payload['type'] = {'id' => type_id}
        end
      end

      # Layout
      available_layouts = system_layouts_for_dropdown(system_payload.dig('type', 'id'))
      layout_val = params['layout']
      if layout_val
        layout_id = layout_val =~ /\A\d+\Z/ ? layout_val.to_i : available_layouts.find { |l| l['name'] == layout_val || l['code'] == layout_val }&.dig('id')
        raise_command_error "System layout not found: #{layout_val}" unless layout_id
        system_payload['layout'] = {'id' => layout_id}
      elsif !options[:no_prompt]
        if available_layouts.empty?
          raise_command_error "No system layouts found for selected type."
        else
          print cyan, "Available System Layouts\n", reset
          available_layouts.each do |l|
            print "  #{l['id']}) #{l['name']}#{l['code'] ? " (#{l['code']})" : ''}\n"
          end
          selected = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'text', 'fieldLabel' => 'System Layout ID', 'required' => true}], options[:options], @api_client, {})['layout']
          layout_id = available_layouts.find { |l| l['id'].to_s == selected.to_s }&.dig('id')
          raise_command_error "Invalid system layout id: #{selected}" unless layout_id
          system_payload['layout'] = {'id' => layout_id}
        end
      end

      payload = {rest_object_key => system_payload}
    end

    if options[:dry_run]
      print_dry_run rest_interface.dry.create(payload)
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.create(payload)
    render_response(json_response, options, rest_object_key) do
      system_id = json_response['id'] || json_response.dig(rest_object_key, 'id')
      print_green_success "System created"
      get([system_id.to_s] + (options[:remote] ? ['-r', options[:remote]] : [])) if system_id
    end
  end

  def add_uninitialized(args)
    options = {}
    params = {}
    components = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name NAME', String, "System Name") do |val|
        params['name'] = val.to_s
      end
      opts.on('--description [TEXT]', String, "Description") do |val|
        params['description'] = val.to_s
      end
      opts.on('--type TYPE', String, "System Type ID or name") do |val|
        params['type'] = val
      end
      opts.on('--layout LAYOUT', String, "System Layout ID or name") do |val|
        params['layout'] = val
      end
      opts.on('--config JSON', String, "System config JSON") do |val|
        params['config'] = JSON.parse(val)
      end
      opts.on('--externalId ID', String, "External ID") do |val|
        params['externalId'] = val.to_s
      end
      opts.on('--component JSON', String, "Component JSON (can be repeated). e.g. '{\"typeCode\":\"compute-node\",\"name\":\"CN-1\",\"config\":{\"ip\":\"10.0.0.1\"}}'") do |val|
        components << JSON.parse(val)
      end
      opts.on('--components JSON', String, "Components JSON array") do |val|
        components.concat(JSON.parse(val))
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new system in an uninitialized state.
This creates a skeleton system with components but does not invoke provider initialization.
[name] is optional and can be passed as the first argument.
EOT
    end
    optparse.parse!(args)
    connect(options)

    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload[rest_object_key] ||= {}
      payload[rest_object_key].deep_merge!(params) unless params.empty?
      payload[rest_object_key]['name'] ||= args[0] if args[0]
      payload[rest_object_key]['components'] = components unless components.empty?
    else
      system_payload = {}

      # Name
      system_payload['name'] = params['name'] || args[0]
      if !system_payload['name'] && !options[:no_prompt]
        system_payload['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options], @api_client, {})['name']
      end
      raise_command_error "Name is required.\n#{optparse}" if system_payload['name'].to_s.empty?

      # Description
      if !params['description'] && !options[:no_prompt]
        system_payload['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false}], options[:options], @api_client, {})['description']
      else
        system_payload['description'] = params['description']
      end

      # Type
      available_types = system_types_for_dropdown
      type_val = params['type']
      if type_val
        type_id = type_val =~ /\A\d+\Z/ ? type_val.to_i : available_types.find { |t| t['name'] == type_val || t['code'] == type_val }&.dig('id')
        raise_command_error "System type not found: #{type_val}" unless type_id
        system_payload['type'] = {'id' => type_id}
      elsif !options[:no_prompt]
        if available_types.empty?
          raise_command_error "No system types found."
        else
          print cyan, "Available System Types\n", reset
          available_types.each do |t|
            print "  #{t['id']}) #{t['name']}#{t['code'] ? " (#{t['code']})" : ''}\n"
          end
          selected = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'text', 'fieldLabel' => 'System Type ID', 'required' => true}], options[:options], @api_client, {})['type']
          type_id = available_types.find { |t| t['id'].to_s == selected.to_s }&.dig('id')
          raise_command_error "Invalid system type id: #{selected}" unless type_id
          system_payload['type'] = {'id' => type_id}
        end
      end

      # Layout
      available_layouts = system_layouts_for_dropdown(system_payload.dig('type', 'id'))
      selected_layout = nil
      layout_val = params['layout']
      if layout_val
        layout_id = layout_val =~ /\A\d+\Z/ ? layout_val.to_i : available_layouts.find { |l| l['name'] == layout_val || l['code'] == layout_val }&.dig('id')
        raise_command_error "System layout not found: #{layout_val}" unless layout_id
        system_payload['layout'] = {'id' => layout_id}
        selected_layout = available_layouts.find { |l| l['id'].to_i == layout_id.to_i }
      elsif !options[:no_prompt]
        if available_layouts.empty?
          raise_command_error "No system layouts found for selected type."
        else
          print cyan, "Available System Layouts\n", reset
          available_layouts.each do |l|
            print "  #{l['id']}) #{l['name']}#{l['code'] ? " (#{l['code']})" : ''}\n"
          end
          selected = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'text', 'fieldLabel' => 'System Layout ID', 'required' => true}], options[:options], @api_client, {})['layout']
          selected_layout = available_layouts.find { |l| l['id'].to_s == selected.to_s }
          raise_command_error "Invalid system layout id: #{selected}" unless selected_layout
          system_payload['layout'] = {'id' => selected_layout['id']}
        end
      end

      # Config
      system_payload['config'] = params['config'] if params['config']

      # External ID
      system_payload['externalId'] = params['externalId'] if params['externalId']

      # Components — prompt interactively if none provided via flags
      if components.empty? && !options[:no_prompt] && selected_layout
        available_component_types = selected_layout['componentTypes'] || []
        if available_component_types.any?
          print cyan, "\nAvailable Component Types for layout '#{selected_layout['name']}':\n", reset
          available_component_types.each do |ct|
            print "  #{ct['code']}#{ct['category'] ? " [#{ct['category']}]" : ''} - #{ct['name']}\n"
          end
          print "\n"
          add_more = true
          while add_more
            add_component = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'addComponent', 'type' => 'text', 'fieldLabel' => 'Add a component? (yes/no)', 'required' => true, 'defaultValue' => 'yes'}], options[:options], @api_client, {})['addComponent']
            if add_component.to_s.downcase =~ /^(y|yes)$/
              # Component type selection
              print cyan, "Component Types:\n", reset
              available_component_types.each_with_index do |ct, idx|
                print "  #{idx + 1}) #{ct['name']} (#{ct['code']})\n"
              end
              selected_ct = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'componentType', 'type' => 'text', 'fieldLabel' => 'Component Type (number or code)', 'required' => true}], options[:options], @api_client, {})['componentType']
              component_type = nil
              if selected_ct =~ /\A\d+\Z/
                idx = selected_ct.to_i - 1
                component_type = available_component_types[idx] if idx >= 0 && idx < available_component_types.size
              else
                component_type = available_component_types.find { |ct| ct['code'] == selected_ct }
              end
              if component_type.nil?
                print_red_alert "Invalid component type: #{selected_ct}"
                next
              end
              # Component name
              default_name = component_type['name']
              comp_name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'componentName', 'type' => 'text', 'fieldLabel' => 'Component Name', 'required' => false, 'defaultValue' => default_name}], options[:options], @api_client, {})['componentName']
              comp = {'typeCode' => component_type['code'], 'name' => comp_name || default_name}
              # Component config
              comp_config = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'componentConfig', 'type' => 'text', 'fieldLabel' => 'Component Config JSON (optional)', 'required' => false}], options[:options], @api_client, {})['componentConfig']
              if comp_config && !comp_config.to_s.empty?
                begin
                  comp['config'] = JSON.parse(comp_config)
                rescue JSON::ParserError => e
                  print_red_alert "Invalid JSON: #{e.message}"
                  next
                end
              end
              components << comp
              print_green_success "Added component: #{comp['name']} (#{comp['typeCode']})"
            else
              add_more = false
            end
          end
        end
      end
      system_payload['components'] = components unless components.empty?

      payload = {rest_object_key => system_payload}
    end

    if options[:dry_run]
      print_dry_run rest_interface.dry.save_uninitialized(payload)
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.save_uninitialized(payload)
    render_response(json_response, options, rest_object_key) do
      system_id = json_response['id'] || json_response.dig(rest_object_key, 'id')
      print_green_success "Uninitialized system created"
      get([system_id.to_s] + (options[:remote] ? ['-r', options[:remote]] : [])) if system_id
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing system.
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

    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the system #{system['name']}?")
      return 9, "aborted"
    end

    if options[:dry_run]
      print_dry_run rest_interface.dry.destroy(system['id'])
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.destroy(system['id'])
    render_response(json_response, options) do
      print_green_success "System #{system['name']} removed"
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

  def system_types_for_dropdown
    result = @api_client.system_types.list({'max' => 100})
    items = result ? (result['systemTypes'] || result[:systemTypes] || result['types'] || result[:types] || []) : []
    items.map { |t| {'id' => t['id'] || t[:id], 'name' => t['name'] || t[:name], 'value' => (t['id'] || t[:id]).to_s, 'code' => t['code'] || t[:code]} }
  end

  def system_layouts_for_dropdown(type_id = nil)
    return [] if type_id.nil?
    result = @api_client.system_types.list_layouts(type_id, {'max' => 100})
    items = result ? (result['systemTypeLayouts'] || result[:systemTypeLayouts] || result['layouts'] || result[:layouts] || []) : []
    items.map { |l| {'id' => l['id'] || l[:id], 'name' => l['name'] || l[:name], 'value' => (l['id'] || l[:id]).to_s, 'code' => l['code'] || l[:code], 'componentTypes' => l['componentTypes'] || l[:componentTypes] || []} }
  end
end
