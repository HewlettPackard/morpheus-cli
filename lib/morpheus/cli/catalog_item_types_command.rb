require 'morpheus/cli/cli_command'

# CLI command self service
# UI is Tools: Self Service - Catalog Items
# API is /catalog-item-types and returns catalogItemTypes
class Morpheus::Cli::CatalogItemTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::CatalogHelper
  include Morpheus::Cli::LibraryHelper
  include Morpheus::Cli::OptionSourceHelper

  # hide until 5.1 when update api is fixed and service-catalog endpoints are available
  set_command_hidden  
  set_command_name :'catalog-types'

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @catalog_item_types_interface = @api_client.catalog_item_types
    @option_types_interface = @api_client.option_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on( '--enabled [on|off]', String, "Filter by enabled" ) do |val|
        params['enabled'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on( '--featured [on|off]', String, "Filter by featured" ) do |val|
        params['featured'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      build_standard_list_options(opts, options)
      opts.footer = "List catalog items."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.list(params)
      return
    end
    json_response = @catalog_item_types_interface.list(params)
    catalog_item_types = json_response[catalog_item_type_list_key]
    render_response(json_response, options, catalog_item_type_list_key) do
      print_h1 "Morpheus Catalog Items", parse_list_subtitles(options), options
      if catalog_item_types.empty?
        print cyan,"No catalog items found.",reset,"\n"
      else
        list_columns = catalog_item_type_column_definitions.upcase_keys!
        #list_columns["Config"] = lambda {|it| truncate_string(it['config'], 100) }
        print as_pretty_table(catalog_item_types, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if catalog_item_types.empty?
      return 1, "no catalog items found"
    else
      return 0, nil
    end
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[catalog item type]")
      opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
        options[:show_config] = true
      end
      # opts.on('--no-config', "Do not display config content." ) do
      #   options[:no_config] = true
      # end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific catalog item type.
[catalog item type] is required. This is the name or id of a catalog item type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    catalog_item_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      catalog_item_type = find_catalog_item_type_by_name(id)
      return 1, "catalog item type not found for #{id}" if catalog_item_type.nil?
      id = catalog_item_type['id']
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.get(id, params)
      return
    end
    # skip extra query, list has same data as show right now
    if catalog_item_type
      json_response = {catalog_item_type_object_key => catalog_item_type}
    else
      json_response = @catalog_item_types_interface.get(id, params)
    end
    catalog_item_type = json_response[catalog_item_type_object_key]
    config = catalog_item_type['config'] || {}
    # export just the config as json or yaml (default)
    if options[:show_config]
      unless options[:json] || options[:yaml] || options[:csv]
        options[:yaml] = true
      end
      return render_with_format(config, options)
    end
    render_response(json_response, options, catalog_item_type_object_key) do
      print_h1 "Catalog Item Type Details", [], options
      print cyan
      show_columns = catalog_item_type_column_definitions
      show_columns.delete("Blueprint") unless catalog_item_type['blueprint']
      print_description_list(show_columns, catalog_item_type)

      if catalog_item_type['optionTypes'] && catalog_item_type['optionTypes'].size > 0
        print_h2 "Option Types"
        opt_columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"FIELD NAME" => lambda {|it| it['fieldName'] } },
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
        ]
        print as_pretty_table(catalog_item_type['optionTypes'], opt_columns)
      else
        # print cyan,"No option types found for this catalog item.","\n",reset
      end

      if config && options[:no_config] != true
        print_h2 "Config YAML"
        #print reset,(JSON.pretty_generate(config) rescue config),"\n",reset
        #print reset,(as_yaml(config, options) rescue config),"\n",reset
        config_string = as_yaml(config, options) rescue config
        config_lines = config_string.split("\n")
        config_line_count = config_lines.size
        max_lines = 10
        if config_lines.size > max_lines
          config_string = config_lines.first(max_lines).join("\n")
          config_string << "\n\n"
          config_string << "(#{(config_line_count - max_lines)} more lines were not shown, use -c to show the config)"
          #config_string << "\n"
        end
        # strip --- yaml header
        if config_string[0..3] == "---\n"
          config_string = config_string[4..-1]
        end
        print reset,config_string.chomp("\n"),"\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_catalog_item_type_option_types)
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--optionTypes [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.add_hidden_option('--optionTypes')
      build_option_type_options(opts, options, add_catalog_item_type_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new catalog item type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({catalog_item_type_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({catalog_item_type_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_catalog_item_type_option_types(), options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_catalog_item_type_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # convert type to refType until api accepts type
      if params['type'] && !params['refType']
        if params['type'].to_s.downcase == 'blueprint'
          params['refType'] = 'AppTemplate'
        else
          params['refType'] = 'InstanceType'
        end
      end
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
        end
      end
      if params['optionTypes']
        # todo: move to optionSource, so it will be /api/options/optionTypes  lol
        prompt_results = prompt_for_option_types(params, options, @api_client)
        if prompt_results[:success]
          params['optionTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1
        end
      end
      payload[catalog_item_type_object_key].deep_merge!(params)
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @catalog_item_types_interface.create(payload)
    catalog_item_type = json_response[catalog_item_type_object_key]
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Added catalog item #{catalog_item_type['name']}"
      return _get(catalog_item_type["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[catalog item type] [options]")
      build_option_type_options(opts, options, update_catalog_item_type_option_types)
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--optionTypes [x,y,z]', Array, "List of Option Type IDs") do |list|
        if list.nil?
          params['optionTypes'] = []
        else
          params['optionTypes'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.add_hidden_option('--optionTypes')
      build_option_type_options(opts, options, update_catalog_item_type_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a catalog item type.
[catalog item type] is required. This is the name or id of a catalog item type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    catalog_item_type = find_catalog_item_type_by_name_or_id(args[0])
    return 1 if catalog_item_type.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({catalog_item_type_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({catalog_item_type_object_key => parse_passed_options(options)})
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_catalog_item_type_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_catalog_item_type_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # convert type to refType until api accepts type
      if params['type'] && !params['refType']
        if params['type'].to_s.downcase == 'blueprint'
          params['refType'] = 'AppTemplate'
        else
          params['refType'] = 'InstanceType'
        end
      end
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
        end
      end
      payload.deep_merge!({catalog_item_type_object_key => params})
      if payload[catalog_item_type_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.update(catalog_item_type['id'], payload)
      return
    end
    json_response = @catalog_item_types_interface.update(catalog_item_type['id'], payload)
    catalog_item_type = json_response[catalog_item_type_object_key]
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Updated catalog item #{catalog_item_type['name']}"
      return _get(catalog_item_type["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[catalog item type] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a catalog_item_type.
[catalog item type] is required. This is the name or id of a catalog item type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    catalog_item_type = find_catalog_item_type_by_name_or_id(args[0])
    return 1 if catalog_item_type.nil?
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.destroy(catalog_item_type['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the catalog item #{catalog_item_type['name']}?")
      return 9, "aborted command"
    end
    json_response = @catalog_item_types_interface.destroy(catalog_item_type['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed catalog item #{catalog_item_type['name']}"
    end
    return 0, nil
  end

  private

  def catalog_item_type_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| format_catalog_type(it) },
      "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : nil },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Featured" => lambda {|it| format_boolean(it['featured']) },
      #"Config" => lambda {|it| it['config'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def format_catalog_type(catalog_item_type)
    out = ""
    # api "blueprint": {"name":my blueprint"} }
    # instead of cryptic refType
    if catalog_item_type['type']
      if catalog_item_type['type'].is_a?(String)
        out << catalog_item_type['type'].to_s.capitalize
      else
        out << (catalog_item_type['type']['name'] || catalog_item_type['type']['code']) rescue catalog_item_type['type'].to_s
      end
    else
      ref_type = catalog_item_type['refType']
      if ref_type == 'InstanceType'
        out << "Instance"
      elsif ref_type == 'AppTemplate'
        out << "Blueprint"
      elsif ref_type
        out << ref_type
      else
        "(none)"
      end
    end
    out
  end

  # this is not so simple, need to first choose select instance, host or provider
  def add_catalog_item_type_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Blueprint', 'value' => 'blueprint'}], 'defaultValue' => 'instance'},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true},
      {'fieldName' => 'featured', 'fieldLabel' => 'Featured', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'required' => true},
      {'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => 'iconList'},
      #{'fieldName' => 'optionTypes', 'fieldLabel' => 'Option Types', 'type' => 'text', 'description' => 'Option Types to include, comma separated list of names or IDs.'},
      {'fieldName' => 'config', 'fieldLabel' => 'Config', 'type' => 'code-editor', 'required' => true, 'description' => 'JSON or YAML'}
    ]
  end

  def add_catalog_item_type_advanced_option_types
    []
  end

  def update_catalog_item_type_option_types
    add_catalog_item_type_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_catalog_item_type_advanced_option_types
    add_catalog_item_type_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

end
