require 'morpheus/cli/cli_command'
  
class Morpheus::Cli::LibraryOptionListsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-option-lists'
  register_subcommands :list, :get, :list_items, :add, :update, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_instance_types_interface = @api_client.library_instance_types
    @provision_types_interface = @api_client.provision_types
    @option_types_interface = @api_client.option_types
    @option_type_lists_interface = @api_client.option_type_lists
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_standard_list_options(opts, options)
      opts.footer = "List option lists."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      
      params.merge!(parse_list_options(options))
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.list(params)
        return
      end

      json_response = @option_type_lists_interface.list(params)
      render_result = render_with_format(json_response, options, 'optionTypeLists')
      return 0 if render_result

      option_type_lists = json_response['optionTypeLists']
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Option Lists", subtitles, options
      if option_type_lists.empty?
        print cyan,"No option lists found.",reset,"\n"
      else
        rows = option_type_lists.collect do |option_type_list|
          {
            id: option_type_list['id'],
            name: option_type_list['name'],
            labels: option_type_list['labels'],
            description: option_type_list['description'],
            type: ((option_type_list['type'] == 'api') ? "#{option_type_list['type']} (#{option_type_list['apiType']})" : option_type_list['type'])
          }
        end
          columns = [
          :id,
          :name,
          {:labels => {:display_method => lambda {|it| format_list(it[:labels], '', 3) rescue '' }}},
          :description,
          :type
        ]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_get_options(opts, options)
      opts.on(nil,'--items', "Load and display option list items") do |val|
        options[:list_items] = true
      end
      opts.footer = "Get details about an option list.\n" + 
                    "[name] is required. This is the name or id of an option list. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end
  
  def _get(id, options)
    params = {}
    params.merge!(parse_query_options(options))
    begin
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        if id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @option_type_lists_interface.dry.get(id.to_i, params)
        else
          print_dry_run @option_type_lists_interface.dry.list(params.merge({name: id}))
        end
        return
      end
      option_type_list = find_option_type_list_by_name_or_id(id)
      return 1 if option_type_list.nil?
      list_items = nil
      if options[:list_items]
        list_items = option_type_list['listItems']
        if list_items.nil?
          begin
            list_items = @option_type_lists_interface.list_items(option_type_list['id'])['listItems']
          rescue => e
            puts_error "Failed to load option list items: #{e.message}"
          end
        end
      end
      json_response = {'optionTypeList' => option_type_list}
      render_result = render_with_format(json_response, options, 'optionTypeList')
      return 0 if render_result

      print_h1 "Option List Details", options
      print cyan
      if option_type_list['type'] == 'manual'
        print_description_list({
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Labels" => lambda {|it| format_list(it['labels']) },
          "Type" => lambda {|it| it['type'].to_s.capitalize },
        }, option_type_list)
        # print_h2 "Initial Dataset"
        # print reset,"#{option_type_list['initialDataset']}","\n",reset
      else
        option_list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Labels" => lambda {|it| format_list(it['labels']) },
          "Type" => lambda {|it| it['type'] },
          "API Type" => lambda {|it| it['apiType'] },
          "Source URL" => 'sourceUrl',
          "Real Time" => lambda {|it| format_boolean it['realTime'] },
          "Ignore SSL Errors" => lambda {|it| format_boolean it['ignoreSSLErrors'] },
          "Source Method" => lambda {|it| it['sourceMethod'].to_s.upcase },
          "Credentials" => lambda {|it| it['credential'] ? (it['credential']['type'] == 'local' ? '(Local)' : it['credential']['name']) : nil },
          "Username" => 'serviceUsername',
          "Password" => 'servicePassword',
          "Inject System Auth Header" => lambda {|it| format_boolean it['injectExecutionLeaseAuth'] },
          "Use Owner Authorization"   => lambda {|it| format_boolean it['useOwnerAuth'] },
          "Inject System Auth Header" => lambda {|it| format_boolean it['injectExecutionLeaseAuth'] },
          "Use Owner Authorization" => lambda {|it| format_boolean it['useOwnerAuth'] },
        }
        option_list_columns.delete("API Type") if option_type_list['type'] != 'api'
        option_list_columns.delete("Credentials") if !['rest','ldap'].include?(option_type_list['type']) # || !(option_type_list['credential'] && option_type_list['credential']['id'])
        option_list_columns.delete("Username") if !['rest','ldap'].include?(option_type_list['type']) || !(option_type_list['serviceUsername'])
        option_list_columns.delete("Password") if !['rest','ldap'].include?(option_type_list['type']) || !(option_type_list['servicePassword'])
        option_list_columns.delete("Inject System Auth Header") if option_type_list['type'] != 'rest'
        option_list_columns.delete("Use Owner Authorization")   if option_type_list['type'] != 'rest'
        option_list_columns.delete("Inject System Auth Header") if option_type_list['type'] != 'rest'
        option_list_columns.delete("Use Owner Authorization") if option_type_list['type'] != 'rest'
        source_headers = []
        if option_type_list['config'] && option_type_list['config']['sourceHeaders']
          source_headers = option_type_list['config']['sourceHeaders'].collect do |header|
            {name: header['name'], value: header['value'], masked: format_boolean(header['masked'])}
          end
          #option_list_columns["Source Headers"] = lambda {|it| source_headers.collect {|it| "#{it[:name]} #{it[:value]}"}.join("\n") }
        end
        print_description_list(option_list_columns, option_type_list)
        if source_headers && !source_headers.empty?
          print cyan
          print_h2 "Source Headers"
          print as_pretty_table(source_headers, [:name, :value, :masked], options)
        end
        if !option_type_list['initialDataset'].empty?
          print_h2 "Initial Dataset"
          print reset,"#{option_type_list['initialDataset']}","\n",reset
        end
        if !option_type_list['translationScript'].empty?
          print_h2 "Translation Script"
          print reset,"#{option_type_list['translationScript']}","\n",reset
        end
        if !option_type_list['requestScript'].empty?
          print_h2 "Request Script"
          print reset,"#{option_type_list['requestScript']}","\n",reset
        end
      end
      if options[:list_items]
        print_h2 "List Items"
        if list_items && list_items.size > 0
          print as_pretty_table(list_items, [:name, :value], options)
          print_results_pagination({size: list_items.size, total: list_items.size})
        else
          print cyan,"No list items found.",reset,"\n"
        end
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_items(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_get_options(opts, options)
      opts.footer = "List items for an option list.\n" + 
                    "[name] is required. This is the name or id of an option list."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    option_type_list = find_option_type_list_by_name_or_id(args[0])
    return 1 if option_type_list.nil?

    params.merge!(parse_list_options(options))
    @option_type_lists_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @option_type_lists_interface.dry.list_items(option_type_list['id'], params)
      return
    end
    json_response = @option_type_lists_interface.list_items(option_type_list['id'], params)
    list_items = json_response['listItems']
    render_response(json_response, options, "listItems") do
      print_h2 "List Items"
      if list_items && list_items.size > 0
        print as_pretty_table(list_items, [:name, :value], options)
        print_results_pagination({size: list_items.size, total: list_items.size})
      else
        print cyan,"No list items found.",reset,"\n"
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    my_option_types = nil
    list_type = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, new_option_type_list_option_types())
      build_standard_add_options(opts, options)
      opts.footer = "Create a new option list."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    if args.count == 1
      options[:options]['name'] = args[0]
    end

    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'optionTypeList' => parse_passed_options(options)})
      else
        payload = {}
        payload.deep_merge!({'optionTypeList' => parse_passed_options(options)})
        list_payload = Morpheus::Cli::OptionTypes.prompt(new_option_type_list_option_types(), options[:options], @api_client, options[:params])
        if list_payload['type'] == 'rest'
          # prompt for Source Headers
          if !(payload['optionTypeList']['config'] && payload['optionTypeList']['config']['sourceHeaders'])
            source_headers = prompt_source_headers(options)
            if !source_headers.empty?
              list_payload['config'] ||= {}
              list_payload['config']['sourceHeaders'] = source_headers
            end
          end
        end
        # tweak payload for API
        ['ignoreSSLErrors', 'realTime', 'injectExecutionLeaseAuth', 'useOwnerAuth'].each { |k|
          list_payload[k] = ['on','true'].include?(list_payload[k].to_s) if list_payload.key?(k)
        }
        payload.deep_merge!({'optionTypeList' => list_payload})
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.create(payload)
        return
      end
      json_response = @option_type_lists_interface.create(payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      option_type_list = json_response['optionTypeList']
      print_green_success "Added Option List #{option_type_list['name']}"
      get([option_type_list['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_option_type_list_option_types())
      build_standard_update_options(opts, options)
      opts.footer = "Update an option list.\n" +
                    "[name] is required. This is the name or id of an option list."
    end
    optparse.parse!(args)
    connect(options)
    begin
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'optionTypeList' => parse_passed_options(options)})
      else
        payload = {}
        payload.deep_merge!({'optionTypeList' => parse_passed_options(options)})
        list_payload = Morpheus::Cli::OptionTypes.no_prompt(update_option_type_list_option_types(), options[:options], @api_client)
        if list_payload['type'] == 'rest'
          # parse Source Headers
          if !(payload['optionTypeList']['config'] && payload['optionTypeList']['config']['sourceHeaders'])
            source_headers = prompt_source_headers(options.merge({no_prompt: true}))
            if !source_headers.empty?
              #params['config'] ||= option_type_list['config'] || {}
              params['config'] ||= {}
              params['config']['sourceHeaders'] = source_headers
            end
          end
        end
        # tweak payload for API
        ['ignoreSSLErrors', 'realTime', 'injectExecutionLeaseAuth', 'useOwnerAuth'].each { |k|
          list_payload[k] = ['on','true'].include?(list_payload[k].to_s) if list_payload.key?(k)
        }
        payload.deep_merge!({'optionTypeList' => list_payload})
        raise_command_error "Specify at least one option to update.\n#{optparse}" if payload['optionTypeList'].empty?
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.update(option_type_list['id'], payload)
        return
      end
      json_response = @option_type_lists_interface.update(option_type_list['id'], payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      print_green_success "Updated Option List #{list_payload['name']}"
      get([option_type_list['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete an option list.\n" +
                    "[name] is required. This is the name or id of an option list."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      option_type_list = find_option_type_list_by_name_or_id(args[0])
      exit 1 if option_type_list.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the option type #{option_type_list['name']}?", options)
        exit
      end
      @option_type_lists_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @option_type_lists_interface.dry.destroy(option_type_list['id'])
        return
      end
      json_response = @option_type_lists_interface.destroy(option_type_list['id'])
      render_result = render_with_format(json_response, options)
      return 0 if render_result

      print_green_success "Removed Option List #{option_type_list['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  # finders are in LibraryHelper

  def get_available_option_list_types
    [
      {'name' => 'REST', 'value' => 'rest'}, 
      {'name' => 'Morpheus Api', 'value' => 'api'}, 
      {'name' => 'LDAP', 'value' => 'ldap'}, 
      {'name' => 'Manual', 'value' => 'manual'}
    ]
  end

  def find_option_list_type(code)
     get_available_option_list_types.find {|it| code == it['value'] || code == it['name'] }
  end

  def new_option_type_list_option_types()
    [
        # rest
        {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
        {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
        {'shorthand' => '-l', 'optionalValue' => true, 'fieldName' => 'labels', 'fieldLabel' => 'Labels', 'type' => 'text', 'required' => false, 'noPrompt' => true, 'processValue' => lambda {|val| parse_labels(val) }, 'displayOrder' => 3},
        {'code' => 'optionTypeList.type', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_option_list_types, 'defaultValue' => 'rest', 'required' => true, 'description' => 'Option List Type. eg. rest, api, ldap, manual', 'displayOrder' => 4},
        {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 5},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'sourceUrl', 'fieldLabel' => 'Source Url', 'type' => 'text', 'required' => true, 'description' => "A REST URL can be used to fetch list data and is cached in the appliance database.", 'displayOrder' => 6},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'ignoreSSLErrors', 'fieldLabel' => 'Ignore SSL Errors', 'type' => 'checkbox', 'defaultValue' => false, 'displayOrder' => 7},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'realTime', 'fieldLabel' => 'Real Time', 'type' => 'checkbox', 'defaultValue' => false, 'displayOrder' => 8},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'injectExecutionLeaseAuth', 'switch' => 'inject-execution-lease-auth', 'fieldLabel' => 'Inject System Auth Header', 'type' => 'checkbox', 'defaultValue' => false, 'description' => 'Injects an authorization header using a system lease token when making the REST call.', 'displayOrder' => 21},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'useOwnerAuth', 'switch' => 'use-owner-auth', 'fieldLabel' => 'Use Owner Authorization', 'type' => 'checkbox', 'defaultValue' => false, 'description' => 'Uses the authorization credentials of the owner of the option list.', 'displayOrder' => 22},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'sourceMethod', 'fieldLabel' => 'Source Method', 'type' => 'select', 'selectOptions' => [{'name' => 'GET', 'value' => 'GET'}, {'name' => 'POST', 'value' => 'POST'}], 'defaultValue' => 'GET', 'required' => true, 'displayOrder' => 9},
        {'dependsOnCode' => 'optionTypeList.type:rest|ldap', 'fieldName' => 'credential', 'fieldLabel' => 'Credentials', 'type' => 'select', 'optionSource' => 'credentials', 'description' => 'Credential ID or use "local" to specify username and password', 'displayOrder' => 10, 'defaultValue' => "local", 'required' => true, :for_help_only => true}, # hacky way to render this but not prompt for it
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'serviceUsername', 'fieldLabel' => 'Username', 'type' => 'text', 'description' => "A Basic Auth Username for use when type is 'rest'.", 'displayOrder' => 11, "credentialFieldContext" => 'credential', "credentialFieldName" => 'username', "credentialType" => "username-password,oauth2"},
        {'dependsOnCode' => 'optionTypeList.type:rest', 'fieldName' => 'servicePassword', 'fieldLabel' => 'Password', 'type' => 'password', 'description' => "A Basic Auth Password for use when type is 'rest'.", 'displayOrder' => 12, "credentialFieldContext" => 'credential', "credentialFieldName" => 'password', "credentialType" => "username-password,oauth2"},
        # sourceHeaders component (is done afterwards manually)
        {'dependsOnCode' => 'optionTypeList.type:api', 'fieldName' => 'apiType', 'fieldLabel' => 'Option List', 'type' => 'select', 'optionSource' => 'apiOptionLists', 'required' => true, 'description' => 'The code of the api option list to use, eg. clouds, environments, groups, instances, instance-wiki, networks, servicePlans, resourcePools, securityGroups, servers, server-wiki', 'displayOrder' => 13},
        {'dependsOnCode' => 'optionTypeList.type:rest|ldap', 'fieldName' => 'credential', 'fieldLabel' => 'Credentials', 'type' => 'select', 'optionSource' => 'credentials', 'description' => 'Credential ID or use "local" to specify username and password', 'displayOrder' => 14, 'defaultValue' => "local", 'required' => true, :for_help_only => true}, # hacky way to render this but not prompt for it
        {'dependsOnCode' => 'optionTypeList.type:ldap', 'fieldName' => 'serviceUsername', 'fieldLabel' => 'Username', 'type' => 'text', 'description' => "An LDAP Username for use when type is 'ldap'.", 'displayOrder' => 15, "credentialFieldContext" => 'credential', "credentialFieldName" => 'username', "credentialType" => "username-password"},
        {'dependsOnCode' => 'optionTypeList.type:ldap', 'fieldName' => 'servicePassword', 'fieldLabel' => 'Password', 'type' => 'password', 'description' => "An LDAP Password for use when type is 'ldap'.", 'displayOrder' => 16, "credentialFieldContext" => 'credential', "credentialFieldName" => 'password', "credentialType" => "username-password"},
        {'dependsOnCode' => 'optionTypeList.type:ldap', 'fieldName' => 'ldapQuery', 'fieldLabel' => 'LDAP Query', 'type' => 'text', 'description' => "LDAP Queries are standard LDAP formatted queries where different objects can be searched. Dependent parameters can be loaded into the query using the <%=phrase%> syntax.", 'displayOrder' => 17},
        {'dependsOnCode' => 'optionTypeList.type:rest|api|manual', 'fieldName' => 'initialDataset', 'fieldLabel' => 'Initial Dataset', 'type' => 'code-editor', 'description' => "Create an initial json dataset to be used as the collection for this option list. It should be a list containing objects with properties 'name', and 'value'. However, if there is a translation script, that will also be passed through.", 'displayOrder' => 18, 'dataType' => 'string'},
        {'dependsOnCode' => 'optionTypeList.type:rest|api|ldap', 'fieldName' => 'translationScript', 'fieldLabel' => 'Translation Script', 'type' => 'code-editor', 'description' => "Create a js script to translate the result data object into an Array containing objects with properties name, and value. The input data is provided as data and the result should be put on the global variable results.", 'displayOrder' => 19, 'dataType' => 'string'},
        {'dependsOnCode' => 'optionTypeList.type:rest|api', 'fieldName' => 'requestScript', 'fieldLabel' => 'Request Script', 'type' => 'code-editor', 'description' => "Create a js script to prepare the request. Return a data object as the body for a post, and return an array containing properties name and value for a get. The input data is provided as data and the result should be put on the global variable results.", 'displayOrder' => 20, 'dataType' => 'string'},
      ]

  end

  def update_option_type_list_option_types()
    list = new_option_type_list_option_types()
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    list
  end

  # returns array of header objects {name: "Auth", value: "somevalue", masked: false}
  def prompt_source_headers(options={})
    #puts "Source Headers:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    source_headers = []
    source_header_index = 0
    has_another_source_header = options[:options] && options[:options]["sourceHeader#{source_header_index}"]
    add_another_source_header = has_another_source_header || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add a Source Header?", {default: false}))
    while add_another_source_header do
      field_context = "sourceHeader#{source_header_index}"
      source_header = {}
      source_header['id'] = nil
      source_header_label = source_header_index == 0 ? "Header" : "Header [#{source_header_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{source_header_label} Name", 'required' => true, 'description' => 'HTTP Header Name.', 'defaultValue' => source_header['name']}], options[:options])
      source_header['name'] = v_prompt[field_context]['name']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => "#{source_header_label} Value", 'required' => true, 'description' => 'HTTP Header Value', 'defaultValue' => source_header['value']}], options[:options])
      source_header['value'] = v_prompt[field_context]['value']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'masked', 'type' => 'checkbox', 'fieldLabel' => "#{source_header_label} Masked", 'required' => true, 'description' => 'Header value is secret and should not be displayed', 'defaultValue' => source_header['masked'] ? 'yes' : 'no'}], options[:options])
      source_header['masked'] = v_prompt[field_context]['masked'] if !v_prompt[field_context]['masked'].nil?
      source_headers << source_header
      source_header_index += 1
      has_another_source_header = options[:options] && options[:options]["sourceHeader#{source_header_index}"]
      add_another_source_header = has_another_source_header || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another Source Header?", {default: false}))
    end

    return source_headers
  end

end
