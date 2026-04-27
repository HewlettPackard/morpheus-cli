require 'morpheus/cli/cli_command'

class Morpheus::Cli::Systems
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_name :systems
  set_command_description "View and manage systems."
  register_subcommands :list, :get, :add, :update, :remove, :'add-uninitialized', {:'initialize' => 'exec_initialize'}, {:'validate' => 'exec_validate'},
                       {:'list-available-server-updates' => :list_available_server_updates},
                       {:'apply-server-update' => :apply_server_update},
                       {:'list-available-storage-updates' => :list_available_storage_updates},
				       {:'apply-storage-update' => :apply_storage_update},
				       {:'list-available-network-updates' => :list_available_network_updates},
				       {:'apply-network-update' => :apply_network_update},
                       {:'list-available-network-server-updates' => :list_available_network_server_updates},
			       {:'apply-network-server-update' => :apply_network_server_update},
			       {:'list-available-cluster-updates' => :list_available_cluster_updates},
			       {:'apply-cluster-update' => :apply_cluster_update}

  protected

  # Systems API uses lowercase keys in payloads.
  def system_object_key
    'system'
  end

  def system_list_key
    'systems'
  end

  # Required so find_by_name_or_id(:servers, id) resolves the lowercase 'server' key
  def server_object_key
    'server'
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
      components = record['components'] || []
      if components.any?
      	print_h2 "Components (#{components.size})", options
      	component_rows = components.collect do |component|
      		{
      			id: component['id'],
      			name: component['name'],
      			type_code: component.dig('type', 'code'),
      			type_name: component.dig('type', 'name'),
      			external_id: component['externalId']
      		}
      	end
      	print as_pretty_table(component_rows, [:id, :name, :type_code, :type_name, :external_id], options)
      end
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

  def exec_initialize(args)
    options = {}
    params = {}
    components = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system]")
      opts.on('--name NAME', String, "Update the system name before initializing") do |val|
        params['name'] = val.to_s
      end
      opts.on('--description [TEXT]', String, "Update the description before initializing") do |val|
        params['description'] = val.to_s
      end
      opts.on('--externalId ID', String, "Set the external ID before initializing") do |val|
        params['externalId'] = val.to_s
      end
      opts.on('--config JSON', String, "Set config JSON before initializing") do |val|
        params['config'] = JSON.parse(val)
      end
      opts.on('--component JSON', String, "Component update JSON (can be repeated). e.g. '{\"typeCode\":\"compute-node\",\"externalId\":\"ext-001\",\"config\":{\"ip\":\"10.0.0.1\"}}'") do |val|
        components << JSON.parse(val)
      end
      opts.on('--components JSON', String, "Component updates JSON array") do |val|
        components.concat(JSON.parse(val))
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Initialize an existing system that is in an uninitialized state.
This invokes the provider's prepare and initialize lifecycle methods.
[system] is required. This is the name or id of a system.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)

    system_record = nil
    if args[0].to_s =~ /\A\d{1,}\Z/
      json_response = rest_interface.get(args[0].to_i)
      system_record = json_response[rest_object_key] || json_response
    else
      system_record = find_by_name(rest_key, args[0])
    end
    return 1, "System not found for '#{args[0]}'" if system_record.nil?

    # Prompt for component updates if none provided via flags and not in no-prompt mode
    if components.empty? && !options[:no_prompt] && !options[:payload]
      existing_components = system_record['components'] || []
      if existing_components.any?
        print cyan, "\nExisting Components:\n", reset
        existing_components.each_with_index do |c, idx|
          type_code = c.dig('type', 'code') || 'unknown'
          print "  #{idx + 1}) #{c['name']} (#{type_code})#{c['externalId'] ? " externalId=#{c['externalId']}" : ''}\n"
        end
        print "\n"
        update_components = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'updateComponents', 'type' => 'text', 'fieldLabel' => 'Update any components? (yes/no)', 'required' => true, 'defaultValue' => 'no'}], options[:options], @api_client, {})['updateComponents']
        if update_components.to_s.downcase =~ /^(y|yes)$/
          existing_components.each do |c|
            type_code = c.dig('type', 'code') || 'unknown'
            print cyan, "\nComponent: #{c['name']} (#{type_code})\n", reset
            comp_update = {'typeCode' => type_code}

            ext_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'externalId', 'type' => 'text', 'fieldLabel' => "  External ID (current: #{c['externalId'] || 'none'})", 'required' => false}], options[:options], @api_client, {})['externalId']
            comp_update['externalId'] = ext_id unless ext_id.to_s.empty?

            comp_config = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'config', 'type' => 'text', 'fieldLabel' => '  Config JSON (optional)', 'required' => false}], options[:options], @api_client, {})['config']
            if comp_config && !comp_config.to_s.empty?
              begin
                comp_update['config'] = JSON.parse(comp_config)
              rescue JSON::ParserError => e
                print_red_alert "Invalid JSON for component config: #{e.message}"
              end
            end

            components << comp_update if comp_update.keys.length > 1
          end
        end
      end
    end

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload[rest_object_key] ||= {}
      payload[rest_object_key].deep_merge!(params) unless params.empty?
      payload[rest_object_key]['components'] = components unless components.empty?
    else
      params['components'] = components unless components.empty?
      payload = {rest_object_key => params}
    end

    if options[:dry_run]
      print_dry_run rest_interface.dry.initialize_system(system_record['id'], payload)
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.initialize_system(system_record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "System #{system_record['name']} initialized"
      get([system_record['id'].to_s] + (options[:remote] ? ['-r', options[:remote]] : []))
    end
  end

  def exec_validate(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Validate an existing system by running the provider's pre-check phase.
No state changes are made. Returns success if the provider's prepare check passes.
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

    if options[:dry_run]
      print_dry_run rest_interface.dry.validate_system(system['id'])
      return
    end

    rest_interface.setopts(options)
    json_response = rest_interface.validate_system(system['id'])
    render_response(json_response, options) do
      if json_response['success']
        print_green_success "System #{system['name']} validated successfully"
      else
        print_red_alert "System #{system['name']} validation failed: #{json_response['msg']}"
      end
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
    components = []
    components_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system]")
      opts.on("--name NAME", String, "Updates System Name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Updates System Description") do |val|
        params['description'] = val.to_s
      end
      opts.on('--enabled [on|off]', String, "Set whether the system is enabled") do |val|
        params['enabled'] = val.to_s
      end
      opts.on('--externalId ID', String, "Set the external ID") do |val|
        params['externalId'] = val.to_s
      end
      opts.on('--config JSON', String, "Set config JSON") do |val|
        params['config'] = JSON.parse(val)
      end
      opts.on('--component JSON', String, "Component JSON (can be repeated). Pass the full desired component set when using component updates.") do |val|
        components_specified = true
        components << JSON.parse(val)
      end
      opts.on('--components JSON', String, "Components JSON array. This should be the full desired final component list.") do |val|
        components_specified = true
        components.concat(JSON.parse(val))
      end
      build_standard_update_options(opts, options, [:find_by_name])
      opts.footer = <<-EOT
Update an existing system.
If system.components is supplied, it is authoritative: omitted components will be removed.
Omit the components key entirely to leave components unchanged.
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
    payload[rest_object_key] ||= {}
    payload[rest_object_key].deep_merge!(params) unless params.empty?
    payload[rest_object_key]['components'] = components if components_specified
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

  def list_available_server_updates(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [server]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List available update definitions for a compute server component of a system.
[system] is required. This is the name or id of a system.
[server] is required. This is the name or id of the compute server.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      server = find_by_name_or_id(:servers, args[1])
      return 1 if server.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.list_compute_server_update_definitions(system['id'], server['id'], params)
        return
      end
      json_response = @systems_interface.list_compute_server_update_definitions(system['id'], server['id'], params)
      update_definitions = json_response['updateDefinitions']
      render_response(json_response, options, 'updateDefinitions') do
        print_h1 "Available Server Updates: #{system['name']} / #{server['name']}", [], options
        if update_definitions.nil? || update_definitions.empty?
          print cyan, "No update definitions found.", reset, "\n"
        else
          columns = {
            "ID"          => 'id',
            "Name"        => 'name',
            "Version"     => 'updateVersion',
            "Severity"    => 'severity',
            "Type"        => 'type',
            "Reboot"      => lambda {|it| format_boolean(it['requiresReboot']) },
            "Rollback"    => lambda {|it| format_boolean(it['supportsRollback']) },
            "Released"    => lambda {|it| it['updateReleaseDate'] ? format_local_dt(it['updateReleaseDate']) : '' },
          }
          print cyan
          print as_pretty_table(update_definitions, columns.upcase_keys!, options)
          print_results_pagination({size: update_definitions.size, total: (json_response['meta'] ? json_response['meta']['total'] : update_definitions.size)})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_server_update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [server] [updateDefinitionId]")
      opts.on('--dry-run-update', "Execute as a dry run — passes dryRun:true to the server, no changes applied.") do
        options[:dry_run_update] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Apply an update definition to a compute server component of a system.
[system] is required. This is the name or id of a system.
[server] is required. This is the name or id of the compute server.
[updateDefinitionId] is required. This is the id of the update definition.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:3)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      server = find_by_name_or_id(:servers, args[1])
      return 1 if server.nil?
      update_definition_id = args[2]
      payload = {}
      payload['dryRun'] = true if options[:dry_run_update]
      payload.deep_merge!(parse_passed_options(options))
      params = {}
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.apply_compute_server_update_definition(system['id'], server['id'], update_definition_id, payload, params)
        return
      end
      json_response = @systems_interface.apply_compute_server_update_definition(system['id'], server['id'], update_definition_id, payload, params)
      render_response(json_response, options) do
        print_green_success "Update operation #{json_response['updateOperation']['id']} queued for server #{server['name']} on system #{system['name']}."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_available_storage_updates(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [storage-server]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List available update definitions for a storage server component of a system.
[system] is required. This is the name or id of a system.
[storage-server] is required. This is the name or id of the storage server.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      storage_server = find_by_name_or_id(:storage_servers, args[1])
      return 1 if storage_server.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.list_storage_server_update_definitions(system['id'], storage_server['id'], params)
        return
      end
      json_response = @systems_interface.list_storage_server_update_definitions(system['id'], storage_server['id'], params)
      update_definitions = json_response['updateDefinitions']
      render_response(json_response, options, 'updateDefinitions') do
        print_h1 "Available Storage Updates: #{system['name']} / #{storage_server['name']}", [], options
        if update_definitions.nil? || update_definitions.empty?
          print cyan, "No update definitions found.", reset, "\n"
        else
          columns = {
            "ID"          => 'id',
            "Name"        => 'name',
            "Version"     => 'updateVersion',
            "Severity"    => 'severity',
            "Type"        => 'type',
            "Reboot"      => lambda {|it| format_boolean(it['requiresReboot']) },
            "Rollback"    => lambda {|it| format_boolean(it['supportsRollback']) },
            "Released"    => lambda {|it| it['updateReleaseDate'] ? format_local_dt(it['updateReleaseDate']) : '' },
          }
          print cyan
          print as_pretty_table(update_definitions, columns.upcase_keys!, options)
          print_results_pagination({size: update_definitions.size, total: (json_response['meta'] ? json_response['meta']['total'] : update_definitions.size)})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_storage_update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [storage-server] [updateDefinitionId]")
      opts.on('--dry-run-update', "Execute as a dry run — passes dryRun:true to the server, no changes applied.") do
        options[:dry_run_update] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Apply an update definition to a storage server component of a system.
[system] is required. This is the name or id of a system.
[storage-server] is required. This is the name or id of the storage server.
[updateDefinitionId] is required. This is the id of the update definition.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:3)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      storage_server = find_by_name_or_id(:storage_servers, args[1])
      return 1 if storage_server.nil?
      update_definition_id = args[2]
      payload = {}
      payload['dryRun'] = true if options[:dry_run_update]
      payload.deep_merge!(parse_passed_options(options))
      params = {}
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.apply_storage_server_update_definition(system['id'], storage_server['id'], update_definition_id, payload, params)
        return
      end
      json_response = @systems_interface.apply_storage_server_update_definition(system['id'], storage_server['id'], update_definition_id, payload, params)
      render_response(json_response, options) do
        print_green_success "Update operation #{json_response['updateOperation']['id']} queued for storage server #{storage_server['name']} on system #{system['name']}."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_available_network_server_updates(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [network-server]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List available update definitions for a network server component of a system.
[system] is required. This is the name or id of a system.
[network-server] is required. This is the name or id of the network server.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      network_server = find_by_name_or_id(:network_servers, args[1])
      return 1 if network_server.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.list_network_server_update_definitions(system['id'], network_server['id'], params)
        return
      end
      json_response = @systems_interface.list_network_server_update_definitions(system['id'], network_server['id'], params)
      update_definitions = json_response['updateDefinitions']
      render_response(json_response, options, 'updateDefinitions') do
        print_h1 "Available Network Server Updates: #{system['name']} / #{network_server['name']}", [], options
        if update_definitions.nil? || update_definitions.empty?
          print cyan, "No update definitions found.", reset, "\n"
        else
          columns = {
            "ID"          => 'id',
            "Name"        => 'name',
            "Version"     => 'updateVersion',
            "Severity"    => 'severity',
            "Type"        => 'type',
            "Reboot"      => lambda {|it| format_boolean(it['requiresReboot']) },
            "Rollback"    => lambda {|it| format_boolean(it['supportsRollback']) },
            "Released"    => lambda {|it| it['updateReleaseDate'] ? format_local_dt(it['updateReleaseDate']) : '' },
          }
          print cyan
          print as_pretty_table(update_definitions, columns.upcase_keys!, options)
          print_results_pagination({size: update_definitions.size, total: (json_response['meta'] ? json_response['meta']['total'] : update_definitions.size)})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_available_network_updates(args)
    list_available_network_server_updates(args)
  end

  def apply_network_server_update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [network-server] [updateDefinitionId]")
      opts.on('--dry-run-update', "Execute as a dry run — passes dryRun:true to the server, no changes applied.") do
        options[:dry_run_update] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Apply an update definition to a network server component of a system.
[system] is required. This is the name or id of a system.
[network-server] is required. This is the name or id of the network server.
[updateDefinitionId] is required. This is the id of the update definition.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:3)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      network_server = find_by_name_or_id(:network_servers, args[1])
      return 1 if network_server.nil?
      update_definition_id = args[2]
      payload = {}
      payload['dryRun'] = true if options[:dry_run_update]
      payload.deep_merge!(parse_passed_options(options))
      params = {}
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.apply_network_server_update_definition(system['id'], network_server['id'], update_definition_id, payload, params)
        return
      end
      json_response = @systems_interface.apply_network_server_update_definition(system['id'], network_server['id'], update_definition_id, payload, params)
      render_response(json_response, options) do
        print_green_success "Update operation #{json_response['updateOperation']['id']} queued for network server #{network_server['name']} on system #{system['name']}."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_network_update(args)
    apply_network_server_update(args)
  end

  def list_available_cluster_updates(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [cluster]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List available update definitions for a cluster component of a system.
[system] is required. This is the name or id of a system.
[cluster] is required. This is the name or id of the cluster.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      cluster = find_cluster_by_name_or_id(args[1])
      return 1 if cluster.nil?
      params = {}
      params.merge!(parse_list_options(options))
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.list_cluster_update_definitions(system['id'], cluster['id'], params)
        return
      end
      json_response = @systems_interface.list_cluster_update_definitions(system['id'], cluster['id'], params)
      update_definitions = json_response['updateDefinitions']
      render_response(json_response, options, 'updateDefinitions') do
        print_h1 "Available Cluster Updates: #{system['name']} / #{cluster['name']}", [], options
        if update_definitions.nil? || update_definitions.empty?
          print cyan, "No update definitions found.", reset, "\n"
        else
          columns = {
            "ID"          => 'id',
            "Name"        => 'name',
            "Version"     => 'updateVersion',
            "Severity"    => 'severity',
            "Type"        => 'type',
            "Reboot"      => lambda {|it| format_boolean(it['requiresReboot']) },
            "Rollback"    => lambda {|it| format_boolean(it['supportsRollback']) },
            "Released"    => lambda {|it| it['updateReleaseDate'] ? format_local_dt(it['updateReleaseDate']) : '' },
          }
          print cyan
          print as_pretty_table(update_definitions, columns.upcase_keys!, options)
          print_results_pagination({size: update_definitions.size, total: (json_response['meta'] ? json_response['meta']['total'] : update_definitions.size)})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_cluster_update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[system] [cluster] [updateDefinitionId]")
      opts.on('--dry-run-update', "Execute as a dry run — passes dryRun:true to the server, no changes applied.") do
        options[:dry_run_update] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Apply an update definition to a cluster component of a system.
[system] is required. This is the name or id of a system.
[cluster] is required. This is the name or id of the cluster.
[updateDefinitionId] is required. This is the id of the update definition.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:3)
    connect(options)
    begin
      system = find_by_name_or_id(:systems, args[0])
      return 1 if system.nil?
      cluster = find_cluster_by_name_or_id(args[1])
      return 1 if cluster.nil?
      update_definition_id = args[2]
      payload = {}
      payload['dryRun'] = true if options[:dry_run_update]
      payload.deep_merge!(parse_passed_options(options))
      params = {}
      @systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @systems_interface.dry.apply_cluster_update_definition(system['id'], cluster['id'], update_definition_id, payload, params)
        return
      end
      json_response = @systems_interface.apply_cluster_update_definition(system['id'], cluster['id'], update_definition_id, payload, params)
      render_response(json_response, options) do
        print_green_success "Update operation #{json_response['updateOperation']['id']} queued for cluster #{cluster['name']} on system #{system['name']}."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_cluster_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      json_result = @api_client.clusters.get(val.to_i)
      cluster = json_result['cluster']
      if cluster.nil?
        print_red_alert "Cluster not found by id #{val}"
        return nil
      end
      cluster
    else
      json_result = @api_client.clusters.list({name: val})
      clusters = json_result['clusters']
      if clusters.nil? || clusters.empty?
        print_red_alert "Cluster not found by name '#{val}'"
        return nil
      elsif clusters.size > 1
        print_red_alert "#{clusters.size} clusters found by name '#{val}'. Use the id instead."
        return nil
      end
      clusters.first
    end
  end

end
