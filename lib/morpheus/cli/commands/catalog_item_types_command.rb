require 'morpheus/cli/cli_command'

# CLI command Catalog Item Types
# UI is Library > Blueprints > Catalog Items
# API is /api/catalog-item-types and returns catalogItemTypes
class Morpheus::Cli::CatalogItemTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'catalog-item-types'
  set_command_description "View and manage catalog item types"

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands({:'update-logo' => :update_logo, :'update-dark-logo' => :update_dark_logo})
  
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
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      opts.on('--code CODE', String, "Filter by code" ) do |val|
        params[:code] = val
      end
      opts.on('-c', '--category CATEGORY', String, "Filter by category") do |val|
        add_query_parameter(params, 'category', val)
      end
      build_standard_list_options(opts, options)
      opts.footer = "List catalog item types."
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
      print_h1 "Morpheus Catalog Item Types", parse_list_subtitles(options), options
      if catalog_item_types.empty?
        print cyan,"No catalog item types found.",reset,"\n"
      else
        list_columns = catalog_item_type_list_column_definitions.upcase_keys!
        #list_columns["Config"] = lambda {|it| truncate_string(it['config'], 100) }
        print as_pretty_table(catalog_item_types, list_columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if catalog_item_types.empty?
      return 1, "no catalog item types found"
    else
      return 0, nil
    end
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      opts.on( '-c', '--config', "Display raw config only." ) do
        options[:show_config] = true
      end
      # opts.on('--no-config', "Do not display Config YAML." ) do
      #   options[:no_config] = true
      # end
      opts.on('--no-content', "Do not display Content." ) do
        options[:no_content] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific catalog item type.
[type] is required. This is the name or id of a catalog item type.
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
    # export just the config as json or yaml (default)
    if options[:show_config]
      if catalog_item_type['instanceSpec']
        puts catalog_item_type['instanceSpec']
        # print reset
        return 0, nil
      end
      unless options[:json] || options[:yaml] || options[:csv]
        options[:json] = true
      end
      return render_with_format(catalog_item_type['config'] || {}, options)
    end
    render_response(json_response, options, catalog_item_type_object_key) do
      print_h1 "Catalog Item Type Details", [], options
      print cyan
      show_columns = catalog_item_type_column_definitions
      show_columns.delete("Form") unless catalog_item_type['form']
      show_columns.delete("Blueprint") unless catalog_item_type['blueprint']
      show_columns.delete("Workflow") unless catalog_item_type['workflow']
      show_columns.delete("Context") unless catalog_item_type['context'] # workflow context
      print_description_list(show_columns, catalog_item_type)

      option_type_form = catalog_item_type['form']
      if option_type_form
        print_h2 "Form Inputs"
        form_inputs = (option_type_form['options'] || [])
        if option_type_form['fieldGroups']
          option_type_form['fieldGroups'].each { |field_group| form_inputs += (field_group['options'] || []) }
        end
        # print format_simple_option_types_table(form_inputs, options)
        print format_option_types_table(form_inputs, options, 'config.customOptions')
        print reset,"\n"
      else
        # print cyan,"No form inputs found for this catalog item.","\n",reset
      end

      if catalog_item_type['optionTypes'] && catalog_item_type['optionTypes'].size > 0
        print_h2 "Inputs"
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

      item_type_code = catalog_item_type['type'].to_s.downcase
      if options[:no_config] != true
        if item_type_code == 'instance'
          print_h2 "Config JSON"
          
            #print reset,(JSON.pretty_generate(config) rescue config),"\n",reset
            #print reset,(as_yaml(config, options) rescue config),"\n",reset
            config_string = catalog_item_type['instanceSpec'] || (as_json(catalog_item_type['config'], options) rescue "")
            config_lines = config_string.split("\n")
            config_line_count = config_lines.size
            max_lines = 10
            if config_lines.size > max_lines
              config_string = config_lines.first(max_lines).join("\n")
              config_string << "\n\n"
              config_string << "#{dark}(#{(config_line_count - max_lines)} more lines were not shown, use -c to show the config)#{reset}"
              #config_string << "\n"
            end
            # strip --- yaml header
            if config_string[0..3] == "---\n"
              config_string = config_string[4..-1]
            end
            print reset,config_string.chomp("\n"),"\n",reset
          
        elsif item_type_code == 'blueprint' || item_type_code == 'apptemplate' || item_type_code == 'app'
          print_h2 "App Spec"
          if catalog_item_type['appSpec']
            #print reset,(JSON.pretty_generate(config) rescue config),"\n",reset
            #print reset,(as_yaml(config, options) rescue config),"\n",reset
            config_string = catalog_item_type['appSpec'] || ""
            config_lines = config_string.split("\n")
            config_line_count = config_lines.size
            max_lines = 10
            if config_lines.size > max_lines
              config_string = config_lines.first(max_lines).join("\n")
              config_string << "\n\n"
              config_string << "#{dark}(#{(config_line_count - max_lines)} more lines were not shown, use -c to show the config)#{reset}"
              #config_string << "\n"
            end
            # strip --- yaml header
            if config_string[0..3] == "---\n"
              config_string = config_string[4..-1]
            end
            print reset,config_string.chomp("\n"),"\n",reset
          else
            print reset,"(blank)","\n",reset
          end
        elsif item_type_code == 'workflow' || item_type_code == 'operationalworkflow' || item_type_code == 'taskset'
          print_h2 "Workflow Config"
          if catalog_item_type['workflowConfig']
            #print reset,(JSON.pretty_generate(config) rescue config),"\n",reset
            #print reset,(as_yaml(config, options) rescue config),"\n",reset
            config_string = catalog_item_type['workflowConfig'] || ""
            config_lines = config_string.split("\n")
            config_line_count = config_lines.size
            max_lines = 10
            if config_lines.size > max_lines
              config_string = config_lines.first(max_lines).join("\n")
              config_string << "\n\n"
              config_string << "#{dark}(#{(config_line_count - max_lines)} more lines were not shown, use -c to show the config)#{reset}"
            end
            print reset,config_string.chomp("\n"),"\n",reset
          else
            print reset,"(blank)","\n",reset
          end
        end
      end

      # Content (Wiki Page)
      if !catalog_item_type["content"].to_s.empty? && options[:no_content] != true
        print_h2 "Content"
        print reset,catalog_item_type["content"].chomp("\n"),"\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {:option_types => add_catalog_item_type_option_types}
    params = {}
    logo_file = nil
    dark_logo_file = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      # opts.on('-t', '--type [instance|blueprint|workflow]', "Item Type, default is instance.") do |val|
      #   # params['type'] = val.to_s.downcase
      #   options[:options]['type'] = val.to_s.downcase
      # end
      build_option_type_options(opts, options, add_catalog_item_type_option_types)
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--logo FILE', String, "Upload a custom logo icon") do |val|
        filename = val
        logo_file = nil
        if filename == 'null'
          logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          logo_file = File.new(filename, 'rb')
        end
      end
      opts.on('--dark-logo FILE', String, "Upload a custom dark logo icon") do |val|
        filename = val
        dark_logo_file = nil
        if filename == 'null'
          dark_logo_file = 'null' # clear it
        else
          filename = File.expand_path(filename)
          if !File.exist?(filename)
            raise_command_error "File not found: #{filename}"
          end
          dark_logo_file = File.new(filename, 'rb')
        end
      end
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exist?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          params['config'] = file_content
          Morpheus::Logging::DarkPrinter.puts "Failed to parse config as JSON or YAML. Defaulting to String."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--form-type form|optionTypes', String, "Form Type determines if input comes from a Form or list of Option Types") do |val|
        params['formType'] = val
      end
      opts.on('--form FORM', String, "Form Name or ID") do |val|
        params['form'] = val
      end
      opts.on('--option-types [x,y,z]', Array, "List of Option Type IDs") do |val|
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
      # Type prompt first
      #params['type'] = Morpheus::Cli::OptionTypes.no_prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Blueprint', 'value' => 'blueprint'}, {'name' => 'Workflow', 'value' => 'workflow'}], 'defaultValue' => 'instance', 'required' => true}], options[:options], @api_client, options[:params])['type']
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_catalog_item_type_option_types(), options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_catalog_item_type_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # convert type to refType until api accepts type
      # if params['type'] && !params['refType']
      #   if params['type'].to_s.downcase == 'instance'
      #     params['refType'] = 'InstanceType'
      #   elsif params['type'].to_s.downcase == 'blueprint'
      #     params['refType'] = 'AppTemplate'
      #   elsif params['type'].to_s.downcase == 'workflow'
      #     params['refType'] = 'OperationalWorkflow'
      #   end
      # end
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          params['config'] = config
          Morpheus::Logging::DarkPrinter.puts "Failed to parse config as JSON or YAML. Defaulting to String."
        else
          params['config'] = config_map
        end
      end
      # massage association params a bit
      params['workflow'] = {'id' => params['workflow']}  if params['workflow'] && !params['workflow'].is_a?(Hash)
      params['blueprint'] = {'id' => params['blueprint']}  if params['blueprint'] && !params['blueprint'].is_a?(Hash)
      if params['formType'].to_s.empty?
        params['formType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'formType', 'fieldLabel' => 'Form Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Form', 'value' => 'form'}, {'name' => 'Inputs', 'value' => 'optionTypes'}], 'defaultValue' => 'optionTypes', 'required' => true}], options[:options], @api_client, options[:params])['formType']
      end
      if params['formType'] == 'form'
        # using formType = 'form'
        # prompt for Form
        options[:options]['form'] = params['form'] if params['form']
        form_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'form', 'fieldLabel' => 'Form', 'type' => 'select', 'optionSource' => 'forms', 'required' => true}], options[:options], @api_client, options[:params])['form']
        params['form'] = {'id' => form_id}
      else
        # using formType = 'optionTypes'
        # prompt for Option Types
        prompt_results = prompt_for_option_types(params, options, @api_client)
        if prompt_results[:success]
          params['optionTypes'] = prompt_results[:data] unless prompt_results[:data].nil?
        else
          return 1, "failed to parse optionTypes"
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
    if json_response['success']
      if logo_file || dark_logo_file
        begin
          @catalog_item_types_interface.update_logo(json_response['catalogItemType']['id'], logo_file, dark_logo_file)
        rescue RestClient::Exception => e
          print_red_alert "Failed to save logo!"
          print_rest_exception(e, options)
        end
      end
    end
    catalog_item_type = json_response[catalog_item_type_object_key]
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Added catalog item type #{catalog_item_type['name']}"
      return _get(catalog_item_type["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    logo_file = nil
    dark_logo_file = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type] [options]")
      build_option_type_options(opts, options, update_catalog_item_type_option_types)
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exist?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          params['config'] = file_content
          Morpheus::Logging::DarkPrinter.puts "Failed to parse config as JSON or YAML. Defaulting to String."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on('--form-type form|optionTypes', String, "Form Type determines if input comes from a Form or list of Option Types") do |val|
        params['formType'] = val
      end
      opts.on('--form FORM', String, "Form Name or ID") do |val|
        params['form'] = val
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
[type] is required. This is the name or id of a catalog item type.
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
      
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          params['config'] = config
          Morpheus::Logging::DarkPrinter.puts "Failed to parse config as JSON or YAML. Defaulting to String."
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
          return 1, "failed to parse optionTypes"
        end
      end
      # massage association params a bit
      params['workflow'] = {'id' => params['workflow']}  if params['workflow'] && !params['workflow'].is_a?(Hash)
      params['blueprint'] = {'id' => params['blueprint']}  if params['blueprint'] && !params['blueprint'].is_a?(Hash)
      payload.deep_merge!({catalog_item_type_object_key => params})
      if payload[catalog_item_type_object_key].empty? && (!logo_file && !dark_logo_file)# || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.update(catalog_item_type['id'], payload)
      return
    end
    json_response = @catalog_item_types_interface.update(catalog_item_type['id'], payload)
    if json_response['success']
      if logo_file || dark_logo_file
        begin
          @catalog_item_types_interface.update_logo(json_response['catalogItemType']['id'], logo_file, dark_logo_file)
        rescue RestClient::Exception => e
          print_red_alert "Failed to save logo!"
          print_rest_exception(e, options)
        end
      end
    end
    catalog_item_type = json_response[catalog_item_type_object_key]
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Updated catalog item type #{catalog_item_type['name']}"
      return _get(catalog_item_type["id"], {}, options)
    end
    return 0, nil
  end

  def update_logo(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[type] [file]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update the logo for a catalog item type." + "\n" +
                    "[type] is required. This is the name or id of a catalog item type." + "\n" +
                    "[file] is required. This is the path of the logo file"
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    catalog_item_type = find_catalog_item_type_by_name_or_id(args[0])
    return 1 if catalog_item_type.nil?
    filename = args[1]
    logo_file = nil
    if filename == 'null'
      logo_file = 'null' # clear it
    else
      filename = File.expand_path(filename)
      if !File.exist?(filename)
        raise_command_error "File not found: #{filename}"
      end
      logo_file = File.new(filename, 'rb')
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.update_logo(catalog_item_type['id'], logo_file)
      return
    end
    json_response = @catalog_item_types_interface.update_logo(catalog_item_type['id'], logo_file)
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Updated catalog item type #{catalog_item_type['name']} logo"
      return _get(catalog_item_type["id"], {}, options)
    end
  end

  def update_dark_logo(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[type] [file]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update the dark logo for a catalog item type." + "\n" +
                    "[type] is required. This is the name or id of a catalog item type." + "\n" +
                    "[file] is required. This is the path of the dark logo file"
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    catalog_item_type = find_catalog_item_type_by_name_or_id(args[0])
    return 1 if catalog_item_type.nil?
    filename = args[1]
    dark_logo_file = nil
    if filename == 'null'
      dark_logo_file = 'null' # clear it
    else
      filename = File.expand_path(filename)
      if !File.exist?(filename)
        raise_command_error "File not found: #{filename}"
      end
      dark_logo_file = File.new(filename, 'rb')
    end
    @catalog_item_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @catalog_item_types_interface.dry.update_logo(catalog_item_type['id'], nil, dark_logo_file)
      return
    end
    json_response = @catalog_item_types_interface.update_logo(catalog_item_type['id'], nil, dark_logo_file)
    render_response(json_response, options, catalog_item_type_object_key) do
      print_green_success "Updated catalog item type #{catalog_item_type['name']} logo"
      return _get(catalog_item_type["id"], {}, options)
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a catalog item type.
[type] is required. This is the name or id of a catalog item type.
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
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the catalog item type #{catalog_item_type['name']}?")
      return 9, "aborted command"
    end
    json_response = @catalog_item_types_interface.destroy(catalog_item_type['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed catalog item type #{catalog_item_type['name']}"
    end
    return 0, nil
  end

  private

  def catalog_item_type_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Category" => 'category',
      "Labels" => lambda {|it| format_list(it['labels'], '', 3) },
      "Description" => 'description',
      "Type" => lambda {|it| format_catalog_type(it) },
      "Visibility" => 'visibility',
      #"Layout Code" => 'layoutCode',
      "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : nil },
      "Workflow" => lambda {|it| it['workflow'] ? it['workflow']['name'] : nil },
      # "Context" => lambda {|it| it['context'] },
      # "Content" => lambda {|it| it['content'] },
      "Form Type" => lambda {|it| it['formType'] == 'form' ? "Form" : "Inputs" },
      "Form" => lambda {|it| it['form'] ? it['form']['name'] : nil }, 
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Featured" => lambda {|it| format_boolean(it['featured']) },
      #"Config" => lambda {|it| it['config'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def catalog_item_type_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Labels" => lambda {|it| format_list(it['labels']) },
      "Description" => 'description',
      "Code" => 'code',
      "Category" => 'category',
      "Type" => lambda {|it| format_catalog_type(it) },
      "Visibility" => 'visibility',
      "Layout Code" => 'layoutCode',
      "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : nil },
      "Workflow" => lambda {|it| it['workflow'] ? it['workflow']['name'] : nil },
      "Context" => lambda {|it| it['context'] },
      # "Content" => lambda {|it| it['content'] },
      "Form Type" => lambda {|it| it['formType'] == 'form' ? "Form" : "Inputs" },
      "Form" => lambda {|it| it['form'] ? it['form']['name'] : nil }, 
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Featured" => lambda {|it| format_boolean(it['featured']) },
      "Allow Quantity" => lambda {|it| format_boolean(it['allowQuantity']) },
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
      # refType is not returned
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

  def add_catalog_item_type_option_types
    [
      {'code' => 'catalogItemType.type', 'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Blueprint', 'value' => 'blueprint'}, {'name' => 'Workflow', 'value' => 'workflow'}], 'defaultValue' => 'instance', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'displayOrder' => 3},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'displayOrder' => 3.5},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 4},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true, 'displayOrder' => 5},
      {'fieldName' => 'featured', 'fieldLabel' => 'Featured', 'type' => 'checkbox', 'defaultValue' => false, 'displayOrder' => 6},
      {'fieldName' => 'allowQuantity', 'fieldLabel' => 'Allow Quantity', 'type' => 'checkbox', 'defaultValue' => false, 'displayOrder' => 7},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'required' => true, 'displayOrder' => 8},
      {'fieldName' => 'layoutCode', 'fieldLabel' => 'Layout Code', 'type' => 'text', 'required' => false, 'displayOrder' => 9},
      {'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => 'iconList', 'displayOrder' => 10},
      #{'fieldName' => 'optionTypes', 'fieldLabel' => 'Option Types', 'type' => 'text', 'description' => 'Option Types to include, comma separated list of names or IDs.', 'displayOrder' => 8},
      {'dependsOnCode' => 'catalogItemType.type:instance', 'fieldName' => 'config', 'fieldLabel' => 'Config', 'type' => 'code-editor', 'description' => 'JSON or YAML', 'required' => true, 'displayOrder' => 11},
      {'dependsOnCode' => 'catalogItemType.type:workflow', 'fieldName' => 'workflowConfig', 'fieldLabel' => 'Config', 'type' => 'textarea', 'description' => 'Enter configuration for the Workflow', 'required' => false, 'noParse' => true, 'displayOrder' => 11},
      {'dependsOnCode' => 'catalogItemType.type:blueprint', 'fieldName' => 'blueprint', 'fieldLabel' => 'Blueprint', 'type' => 'select', 'optionSource' => 'blueprints', 'description' => 'Choose a blueprint to apply to the catalog item.', 'required' => true, 'noParams' => true, 'displayOrder' => 12},
      {'dependsOnCode' => 'catalogItemType.type:blueprint', 'fieldName' => 'appSpec', 'fieldLabel' => 'App Spec', 'type' => 'code-editor', 'description' => 'Enter a spec in the for the App, the Scribe YAML format', 'required' => true, 'displayOrder' => 13},
      {'dependsOnCode' => 'catalogItemType.type:workflow', 'fieldName' => 'workflow', 'fieldLabel' => 'Workflow', 'type' => 'select', 'optionSource' => 'operationWorkflows', 'description' => 'Enter a spec in the for the App, the Scribe YAML format', 'required' => true, 'noParams' => true, 'displayOrder' => 14},
      {'dependsOnCode' => 'catalogItemType.type:workflow', 'fieldName' => 'context', 'fieldLabel' => 'Context Type', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        [{'name' => "Select", 'value' => ""}, {'name' => "None", 'value' => "appliance"}, {'name' => "Instance", 'value' => "instance"}, {'name' => "Server", 'value' => "server"}]
        }, 'description' => 'Context for operational workflow, determines target type', 'defaultValue' => 'Select', 'required' => false},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'code-editor', 'description' => 'Wiki Page Content describing the catalog item', 'displayOrder' => 15}
    ]
  end

  def add_catalog_item_type_advanced_option_types
    []
  end

  def update_catalog_item_type_option_types
    list = add_catalog_item_type_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def update_catalog_item_type_advanced_option_types
    add_catalog_item_type_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def catalog_item_type_object_key
    'catalogItemType'
  end

  def catalog_item_type_list_key
    'catalogItemTypes'
  end

  def find_catalog_item_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_catalog_item_type_by_id(val)
    else
      return find_catalog_item_type_by_name(val)
    end
  end

  def find_catalog_item_type_by_id(id)
    begin
      json_response = @catalog_item_types_interface.get(id.to_i)
      return json_response[catalog_item_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "catalog item type not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_catalog_item_type_by_name(name)
    json_response = @catalog_item_types_interface.list({name: name.to_s})
    catalog_item_types = json_response[catalog_item_type_list_key]
    if catalog_item_types.empty?
      print_red_alert "catalog item type not found by name '#{name}'"
      return nil
    elsif catalog_item_types.size > 1
      print_red_alert "#{catalog_item_types.size} catalog item types found by name '#{name}'"
      puts_error as_pretty_table(catalog_item_types, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return catalog_item_types[0]
    end
  end

end
