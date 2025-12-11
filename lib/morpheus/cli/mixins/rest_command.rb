# RestCommand is a mixin for Morpheus::Cli command classes.
# Provides basic CRUD commands: list, get, add, update, remove
# Currently the command class must also include Morpheus::Cli::CliCommand
# The command class can define a few variables to dictate what the resource
# is called and the the api interface used to fetch the records. The command class 
# or helper must also provide several methods to provide the default behavior.
# In the example below, the command (helper) defines the following methods:
#  * load_balancer_object_key() - Key name of object returned by the "get" api endpoint.
#  * load_balancer_list_key() - Key name of array of records returned by the "list" api endpoint.
#  * load_balancer_column_definitions() - Column definitions for the "get" command display output.
#  * load_balancer_list_column_definitions() - Column definitions for the "list" command display output.
#
# Example of a RestCommand for `morpheus load-balancers`.
#
# class Morpheus::Cli::LoadBalancers
#
#   include Morpheus::Cli::CliCommand
#   include Morpheus::Cli::RestCommand
#   include Morpheus::Cli::LoadBalancersHelper
#
#   # All of the example settings below are redundant
#   # and would be the default values if not set.
#   set_rest_name :load_balancers
#   set_rest_label "Load Balancer"
#   set_rest_label_plural "Load Balancers"
#   set_rest_object_key "load_balancer"
#   set_rest_has_type true
#   set_rest_type "load_balancer_types"
#   register_interfaces :load_balancers, :load_balancer_types
#
# end
#
module Morpheus::Cli::RestCommand
  def self.included(base)
    #puts "including RestCommand for #{base}"
    #base.send :include, Morpheus::Cli::CliCommand
    base.extend ClassMethods
  end

  module ClassMethods

    # rest_name is the plural name of the resource eg. NeatThings would be "neat_things"
    # It is used to derive all other default rest settings key, label, etc.  
    # The default name the command name with underscores `_` instead of dashes `-`.
    def rest_name
      defined?(@rest_name) ? @rest_name : default_rest_name
    end

    def default_rest_name
      self.command_name.to_s.gsub("-", "_")
    end

    def rest_name=(v)
      @rest_name = v.to_s
    end

    alias :set_rest_name :rest_name=

    # rest_key is the singular name of the resource eg. "neat_thing"
    def rest_key
      defined?(@rest_key) ? @rest_key : default_rest_key
    end

    def default_rest_key
      rest_name.to_s.chomp("s")
    end

    def rest_key=(v)
      @rest_key = v.to_s
    end

    alias :set_rest_key :rest_key=

    # rest_arg is a label for the arg in the command usage eg. "thing" gets displayed as [thing]
    def rest_arg
      defined?(@rest_arg) ? @rest_arg : default_rest_arg
    end

    def default_rest_arg
      rest_key.gsub("_", " ") # "[" + rest_key.gsub("_", " ") + "]"
    end

    def rest_arg=(v)
      @rest_arg = v.to_s
    end

    alias :set_rest_arg :rest_arg=

    # rest_has_name indicates a resource has a name and can be retrieved by name or id
    # true by default, set to false for lookups by only id
    def rest_has_name
      defined?(@rest_has_name) ? @rest_has_name :  default_rest_has_name
    end

    def default_rest_has_name
      true
    end

    def rest_has_name=(v)
      @rest_has_name = !!v
    end

    alias :set_rest_has_name :rest_has_name=

    # rest_label is the capitalized resource label eg. "Neat Thing"    
    def rest_label
      defined?(@rest_label) ? @rest_label : default_rest_label
    end

    def default_rest_label
      rest_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_label=(v)
      @rest_label = v.to_s
    end

    alias :set_rest_label :rest_label=

    # the plural version of the label eg. "Neat Things"
    def rest_label_plural
      defined?(@rest_label_plural) ? @rest_label_plural : default_rest_label_plural
    end
    
    def default_rest_label_plural
      #rest_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_label.to_s.pluralize
    end

    def rest_label_plural=(v)
      @rest_label_plural = v.to_s
    end
    
    alias :set_rest_label_plural :rest_label_plural=

    # rest_interface_name is the interface name for the resource. eg. "neat_things"
    def rest_interface_name
      defined?(@rest_interface_name) ? @rest_interface_name : default_rest_interface_name
    end

    def default_rest_interface_name
      rest_name
    end

    def rest_interface_name=(v)
      @rest_interface_name = v.to_s
    end

    alias :set_rest_interface_name :rest_interface_name=

    # rest_perms_config enables and configures permissions prompt
    def rest_perms_config
      defined?(@rest_perms_config) ? @rest_perms_config : {}
    end

    def rest_perms_config=(v)
      @rest_perms_config = v
    end

    alias :set_rest_perms_config :rest_perms_config=

    # rest_option_context_map specifies context mapping during option prompt. default is domain => ''
    def rest_option_context_map
      defined?(@option_context_map) ? @option_context_map : {'domain' => ''}
    end

    def rest_option_context_map=(v)
      @option_context_map = v
    end

    alias :set_rest_option_context_map :rest_option_context_map=

    # rest_has_type indicates a resource has a type. default is false
    def rest_has_type
      defined?(@rest_has_type) && @rest_has_type
    end

    def default_rest_has_type
      false
    end

    def rest_has_type=(v)
      @rest_has_type = !!v
    end

    alias :set_rest_has_type :rest_has_type=

    ## duplicated the rest_* settings with rest_type, for the types resource

    # rest_type_name is the rest_name for the type, only applicable if rest_has_type
    def rest_type_name
      defined?(@rest_type_name) ? @rest_type_name : default_rest_type_name
    end

    def default_rest_type_name
      rest_key + "_types"
    end

    def rest_type_name=(v)
      @rest_type_name = v.to_s
    end

    alias :set_rest_type_name :rest_type_name=
    alias :set_rest_type :rest_type_name=
    #alias :rest_type= :rest_type_name=

    # rest_type_key is the singular name of the resource eg. "neat_thing"
    def rest_type_key
      defined?(@rest_type_key) ? @rest_type_key : default_rest_type_key
    end

    def default_rest_type_key
      rest_type_name.chomp("s")
    end

    def rest_type_key=(v)
      @rest_type_key = v.to_s
    end

    alias :set_rest_type_key :rest_type_key=

    def rest_type_arg
      defined?(@rest_type_arg) ? @rest_type_arg : default_rest_type_arg
    end

    def default_rest_type_arg
      # rest_type_key.gsub("_", " ") # "[" + rest_key.gsub("_", " ") + "]"
      "type" # [type]
    end

    def rest_type_arg=(v)
      @rest_type_arg = v.to_s
    end

    alias :set_rest_type_arg :rest_type_arg=

    # rest_type_label is the capitalized resource label eg. "Neat Thing"    
    def rest_type_label
      defined?(@rest_type_label) ? @rest_type_label : default_rest_type_label
    end

    def default_rest_type_label
      rest_type_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_type_label=(v)
      @rest_type_label = v.to_s
    end

    alias :set_rest_type_label :rest_type_label=

    # the plural version of the label eg. "Neat Things"
    def rest_type_label_plural
      defined?(@rest_type_label_plural) ? @rest_type_label_plural : default_rest_type_label_plural
    end
    
    def default_rest_type_label_plural
      #rest_type_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_type_label.to_s.pluralize
    end

    def rest_type_label_plural=(v)
      @rest_type_label_plural = v.to_s
    end
    
    alias :set_rest_type_label_plural :rest_type_label_plural=

    # the name of the default interface, matches the rest name eg. "neat_things"
    def rest_type_interface_name
      defined?(@rest_type_interface_name) ? @rest_type_interface_name : default_rest_type_interface_name
    end

    def default_rest_type_interface_name
      rest_type_name
    end

    def rest_type_interface_name=(v)
      @rest_type_interface_name = v.to_s
    end

    alias :set_rest_type_interface_name :rest_type_interface_name=

    # set or append to the list of interface names to register for this command
    # The registered interfaces will be pre-loaded into instance variables
    # eg. [:neat_things, :neat_thing_types] will instantiate @neat_things_interface and @neat_thing_types_interface
    def register_interfaces(*interfaces)
      @registered_interfaces ||= []
      interfaces.flatten.each do |it|
        @registered_interfaces << it.to_s
      end
      # put the default rest_interface first
      if rest_interface_name && !@registered_interfaces.include?(rest_interface_name)
        @registered_interfaces.unshift(rest_interface_name)
      end
      # and also the rest_type_interface
      if rest_has_type && !@registered_interfaces.include?(rest_type_interface_name)
        @registered_interfaces.unshift(rest_type_interface_name)
      end
    end

    alias :register_interface :register_interfaces

    # get list of interface names that are registered for this command
    # automatically includes the interface for the rest_name and rest_type_name if has_type
    def registered_interfaces
      @registered_interfaces ||= []
      # put the default rest_interface first
      if @registered_interfaces.empty?
        if rest_interface_name
          @registered_interfaces.unshift(rest_interface_name)
        end
        if rest_has_type
          @registered_interfaces.unshift(rest_type_interface_name)
        end
      end
      @registered_interfaces
    end

     # clear the list of registered interfaces, perhaps useful in a command subclass
    def clear_registered_interfaces()
      @registered_interfaces = []
    end

  end

  def rest_name
    self.class.rest_name
  end

  def rest_key
    self.class.rest_key
  end

  def rest_arg
    self.class.rest_arg
  end

  def rest_has_name
    self.class.rest_has_name
  end

  def rest_label
    self.class.rest_label
  end

  def rest_label_plural
    self.class.rest_label_plural
  end

  def rest_interface_name
    self.class.rest_interface_name
  end

  def rest_perms_config
    self.class.rest_perms_config
  end

  def rest_option_context_map
    self.class.rest_option_context_map
  end

  # returns the default rest interface, allows using rest_interface_name = "your"
  # or override this method to return @your_interface if needed
  def rest_interface
    instance_variable_get("@#{rest_interface_name}_interface")
  end

  def rest_object_key
    if respond_to?("#{rest_key}_object_key", true)
      send("#{rest_key}_object_key")
    else
      rest_name.camelcase.singularize
    end
  end

  def rest_list_key
    if respond_to?("#{rest_key}_list_key", true)
      send("#{rest_key}_list_key")
    else
      rest_name.camelcase
    end
  end

  def rest_column_definitions(options)
    send("#{rest_key}_column_definitions", options)
  end

  def rest_list_column_definitions(options)
    send("#{rest_key}_list_column_definitions", options)
  end

  def rest_find_by_name_or_id(val)
    # use explicitly defined finders
    # else default to new generic CliCommand method to find anything by type (singular underscore)
    if rest_has_name
      if respond_to?("find_#{rest_key}_by_name_or_id", true)
        send("find_#{rest_key}_by_name_or_id", val)
      else
        find_by_name_or_id(rest_key, val)
      end
    else
      if respond_to?("find_#{rest_key}_by_id", true)
        send("find_#{rest_key}_by_id", val)
      else
        find_by_id(rest_key, val)
      end
    end
  end

  def rest_has_type
    self.class.rest_has_type
  end

  ## duplicated the rest_* settings with rest_type, for the types resource

  def rest_type_name
    self.class.rest_type_name
  end

  def rest_type_key
    self.class.rest_type_key
  end

  def rest_type_arg
    self.class.rest_type_arg
  end

  def rest_type_label
    self.class.rest_type_label
  end

  def rest_type_label_plural
    self.class.rest_type_label_plural
  end

  def rest_type_interface_name
    self.class.rest_type_interface_name # || "@#{rest_type_name}_interface"
  end

  def rest_type_interface
    instance_variable_get("@#{rest_type_interface_name}_interface")
  end

  def rest_type_object_key
    if respond_to?("#{rest_type_key}_object_key", true)
      send("#{rest_type_key}_object_key")
    else
      rest_type_name.camelcase.singularize
    end
  end

  def rest_type_list_key
    if respond_to?("#{rest_type_key}_list_key", true)
      send("#{rest_type_key}_list_key")
    else
      rest_type_name.camelcase
    end
  end

  def rest_type_column_definitions(options)
    send("#{rest_type_key}_column_definitions", options)
  end

  def rest_type_list_column_definitions(options)
    send("#{rest_type_key}_list_column_definitions", options)
  end

  def rest_type_find_by_name_or_id(val)
    # use explicately defined finders
    # else default to new generic CliCommand method to find anything by type (singular underscore)
    if respond_to?("find_#{rest_type_key}_by_name_or_id", true)
      send("find_#{rest_type_key}_by_name_or_id", val)
    else
      find_by_name_or_id(rest_type_key, val)
    end
  end

  def registered_interfaces
    self.class.registered_interfaces
  end

  # standard connect method to establish @api_client
  # and @{name}_interface variables for each registered interface.
  def connect(options)
    @api_client = establish_remote_appliance_connection(options)
    self.class.registered_interfaces.each do |interface_name|
      if interface_name.is_a?(String) || interface_name.is_a?(Symbol)
        instance_variable_set("@#{interface_name}_interface", @api_client.send(interface_name))
      elsif interface_name.is_a?(Hash)
        interface_name.each do |k,v|
          instance_variable_set("#{k}_interface", @api_client.send(v))
        end
      end
    end
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_list_options(opts, options, params)
      opts.footer = <<-EOT
List #{rest_label_plural.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    connect(options)
    parse_list_options!(args, options, params)
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.list(params)
      return
    end
    json_response = rest_interface.list(params)
    render_response(json_response, options, rest_list_key) do
      records = json_response[rest_list_key]
      title = "Morpheus #{rest_label_plural}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if records.nil? || records.empty?
        print cyan,"No #{rest_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}]")
      build_get_options(opts, options, params)
      opts.footer = <<-EOT
Get details about #{a_or_an(rest_label)} #{rest_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    parse_get_options!(args, options, params)
    id = args.join(" ")
    _get(id, params, options)
  end

  def _get(id, params, options)
    if id.to_s !~ /\A\d{1,}\Z/ && rest_has_name
      record = rest_find_by_name_or_id(id)
      if record.nil?
        return 1, "#{rest_label} not found for '#{id}'"
      end
      id = record['id']
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.get(id, params)
      return
    end
    json_response = rest_interface.get(id, params)
    render_response_for_get(json_response, options)
    return 0, nil
  end

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # # could always show config eh? or maybe only with --config if that is nicer.
      # # config = record['config'].is_a?(Hash) && !record['config'].empty?
      # if config && !config.empty?
      #   print_h2 "Configuration"
      #   print_description_list(config.keys, config)
      # end
      # Option Types
      if record['optionTypes'] && record['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.size > 0
        print_h2 "Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

  def add(args)
    record_type = nil
    record_type_id = nil
    options = {:options => {:context_map => rest_option_context_map}}
    #respond_to?("#{rest_key}_option_context_map", true) ? send("#{rest_key}_option_context_map") : {'domain' => ''}}}
    option_types = respond_to?("add_#{rest_key}_option_types", true) ? send("add_#{rest_key}_option_types") : []
    advanced_option_types = respond_to?("add_#{rest_key}_advanced_option_types", true) ? send("add_#{rest_key}_advanced_option_types") : []
    type_option_type = option_types.find {|it| it['fieldName'] == 'type'} 
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      if rest_has_name
        opts.banner = subcommand_usage("[name]")
      else
        opts.banner = subcommand_usage()
      end
      if rest_has_type && type_option_type.nil?
        opts.on( '-t', "--#{rest_type_arg} TYPE", "#{rest_type_label}" ) do |val|
          record_type_id = val
        end
      end
      build_option_type_options(opts, options, option_types)
      build_option_type_options(opts, options, advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new #{rest_label.downcase}.
[name] is required. This is the name of the new #{rest_label.downcase}.
EOT
      opts.footer += send "add_#{rest_key}_footer_addn" if respond_to?("add_#{rest_key}_footer_addn", true)
    end
    optparse.parse!(args)
    # todo: make supporting args[0] optional and more flexible
    # for now args[0] is assumed to be the 'name'
    record_name = nil
    if rest_has_name
      if args.count > 0
        record_name = args.join(" ")
      end
      verify_args!(args:args, optparse:optparse, min:0, max: 1)
    else
      verify_args!(args:args, optparse:optparse, count: 0)
    end
    connect(options)
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options})
    else
      # load or prompt for type
      if rest_has_type && type_option_type.nil?
        if record_type_id.nil?
          #raise_command_error "#{rest_type_label} is required.\n#{optparse}"
          type_list = rest_type_interface.list({max:10000, creatable:true})[rest_type_list_key]
          type_dropdown_options = respond_to?("#{rest_key}_type_list_to_options", true) ? send("#{rest_key}_type_list_to_options", type_list) : type_list.collect {|it| {'name' => it['name'], 'value' => it['code']} }
          record_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => rest_type_label, 'type' => 'select', 'selectOptions' => type_dropdown_options, 'required' => true}], options[:options], @api_client)['type']
        end
        record_type = rest_type_find_by_name_or_id(record_type_id)
        if record_type.nil?
          return 1, "#{rest_type_label} not found for '#{record_type_id}"
        end
      end
      record_payload = {}
      if record_name
        record_payload['name'] = record_name
        options[:options]['name'] = record_name # injected for prompt
      end
      if rest_has_type && record_type
        # inject type to options for prompting
        record_payload['type'] = record_type['code']
        options[:options]['type'] = record_type['code']
        # initialize params for loading optionSource data
        options[:params] ||= {}
        options[:params]['type'] = record_type['code']
      end
      record_payload.deep_merge!(passed_options)
      if option_types && !option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # options by type
      if rest_has_type && record_type.nil?
        type_value = record_payload['type'].is_a?(Hash) ? record_payload['type']['id'] : record_payload['type']
        if type_value
          record_type = rest_type_find_by_name_or_id(type_value)
          if record_type.nil?
            return 1, "#{rest_type_label} not found for '#{type_value}"
          end
        end
        # reload the type by id to get all the details ie. optionTypes
        if record_type && record_type['optionTypes'].nil?
          record_type = rest_type_find_by_name_or_id(record_type['id'])
        end
      end
      my_option_types = nil
      if respond_to?("load_option_types_for_#{rest_key}", true)
        my_option_types = send("load_option_types_for_#{rest_key}", record_type, nil)
      else
        my_option_types = record_type ? record_type['optionTypes'] : nil
      end
      if my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
        end
        api_params = (options[:params] || {}).merge(record_payload)
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, api_params, false, true)
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # advanced options (uses no_prompt)
      if advanced_option_types && !advanced_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(advanced_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # permissions
      if rest_perms_config[:enabled]
        if rest_perms_config[:version] == 2
          perms = prompt_permissions_v2(options.deep_merge(rest_perms_config[:options] || {}), rest_perms_config[:excludes] || [])
        else
          perms = prompt_permissions(options.deep_merge(rest_perms_config[:options] || {}), rest_perms_config[:excludes] || [])
        end
        unless rest_perms_config[:name].nil?
          perms.transform_keys! {|k| k == 'resourcePermissions' ? rest_perms_config[:name] : k}
        end
        unless rest_perms_config[:context].nil?
          perms_context = {}
          perms_context[rest_perms_config[:context]] = perms
        end
        record_payload.merge!(perms)
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.create(payload)
      return
    end      
    json_response = rest_interface.create(payload)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_green_success "Added #{rest_label.downcase} #{record['name'] || record['id']}"
      return _get(record["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    record_type = nil
    record_type_id = nil
    options = {}
    option_types = respond_to?("update_#{rest_key}_option_types", true) ? send("update_#{rest_key}_option_types") : []
    advanced_option_types = respond_to?("update_#{rest_key}_advanced_option_types", true) ? send("update_#{rest_key}_advanced_option_types") : []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}] [options]")
      build_option_type_options(opts, options, option_types)
      build_option_type_options(opts, options, advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
      opts.footer += send "update_#{rest_key}_footer_addn" if respond_to?("update_#{rest_key}_footer_addn", true)
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    id = args[0]
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    # load type so we can prompt for those option types
    if rest_has_type
      record_type_id = record['type']['id']
      record_type = rest_type_find_by_name_or_id(record_type_id)
      if record_type.nil?
        return 1, "#{rest_type_label} not found for '#{record_type_id}"
      end
      # reload the type by id to get all the details ie. optionTypes
      if record_type['optionTypes'].nil?
        record_type = rest_type_find_by_name_or_id(record_type['id'])
      end
    end
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options}) unless passed_options.empty?
    else
      record_payload = passed_options
      if rest_has_type && record_type
        # inject type to options for prompting
        # record_payload['type'] = record_type['code']
        # options[:options]['type'] = record_type['code']
        # initialize params for loading optionSource data
        options[:params] ||= {}
        options[:params]['type'] = record_type['code']
      end
      # update options without prompting by default
      if option_types && !option_types.empty?
        api_params = (options[:params] || {}).merge(record_payload) # need to merge in values from record too, ughhh
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(option_types, options[:options], @api_client, api_params)
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # options by type
      my_option_types = nil
      if respond_to?("load_option_types_for_#{rest_key}", true)
        my_option_types = send("load_option_types_for_#{rest_key}", record_type, nil)
      else
        my_option_types = record_type ? record_type['optionTypes'] : nil
      end
      if my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        # make them optional for updates
        # todo: use current value as default instead of just making things optioanl
        # maybe new prompt() options like {:mode => :edit, :object => storage_server} or something
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
          option_type.delete('required')
          option_type.delete('defaultValue')
        end
        api_params = (options[:params] || {}).merge(record_payload) # need to merge in values from record too, ughhh
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(my_option_types, options[:options], @api_client, api_params)
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # advanced options
      if advanced_option_types && !advanced_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(advanced_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      # remove empty config, compact could hanlde this
      if record_payload['config'] && record_payload['config'].empty?
        record_payload.delete('config')
      end
      # prevent updating with empty payload
      if record_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.update(record['id'], payload)
      return
    end
    json_response = rest_interface.update(record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated #{rest_label.downcase} #{record['name'] || record['id']}"
      _get(record["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id = args[0]
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the #{rest_label.downcase} #{record['name'] || record['id']}?")
      return 9, "aborted"
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.destroy(record['id'], params)
      return 0, nil
    end
    json_response = rest_interface.destroy(record['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed #{rest_label.downcase} #{record['name'] || record['id']}"
    end
    return 0, nil
  end

  def list_types(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_list_options(opts, options, params)
      opts.footer = <<-EOT
List #{rest_type_label_plural.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    connect(options)
    parse_list_options!(args, options, params)
    rest_type_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_type_interface.dry.list(params)
      return
    end
    json_response = rest_type_interface.list(params)
    render_response(json_response, options, rest_type_list_key) do
      records = json_response[rest_type_list_key]
      title = "Morpheus #{rest_type_label_plural}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if records.nil? || records.empty?
        print cyan,"No #{rest_type_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_type_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_type(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_type_arg}]")
      build_get_options(opts, options, params)
      opts.footer = <<-EOT
Get details about #{a_or_an(rest_type_label)} #{rest_type_label.downcase}.
[#{rest_type_arg}] is required. This is the name or id of #{a_or_an(rest_type_label)} #{rest_type_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    parse_get_options!(args, options, params)
    id = args.join(" ")
    _get_type(id, params, options)
  end

  def _get_type(id, params, options)
    if id.to_s !~ /\A\d{1,}\Z/ # && rest_type_has_name
      record = rest_type_find_by_name_or_id(id)
      if record.nil?
        return 1, "#{rest_type_label} not found for '#{id}'"
      end
      id = record['id']
    end
    rest_type_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_type_interface.dry.get(id, params)
      return
    end
    json_response = rest_type_interface.get(id, params)
    render_response_for_get_type(json_response, options)
    return 0, nil
  end

  def render_response_for_get_type(json_response, options)
    render_response(json_response, options, rest_type_object_key) do
      record = json_response[rest_type_object_key]
      print_h1 rest_type_label, [], options
      print cyan
      print_description_list(rest_type_column_definitions(options), record, options)
      # # could always show config eh? or maybe only with --config if that is nicer.
      # # config = record['config'].is_a?(Hash) && !record['config'].empty?
      # if config && !config.empty?
      #   print_h2 "Configuration"
      #   print_description_list(config.keys, config)
      # end
      # Option Types
      if record['optionTypes'] && record['optionTypes'].size > 0
        print_h2 "Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

end

