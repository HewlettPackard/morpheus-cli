# SecondaryRestCommand is a mixin for Morpheus::Cli command classes.
# for resources that are secondary to some parent resource.
# Provides basic CRUD commands: list, get, add, update, remove
# The parent resource is specified as the first argument for all the comments.
#
# Example of a SecondaryRestCommand for `morpheus load-balancer-virtual-servers`.
#
# class Morpheus::Cli::LoadBalancerVirtualServers
#
#   include Morpheus::Cli::CliCommand
#   include Morpheus::Cli::RestCommand
#   include Morpheus::Cli::SecondaryRestCommand
#   include Morpheus::Cli::LoadBalancersHelper
# 
#   set_command_name :'load-balancer-virtual-servers'
#   register_subcommands :list, :get, :add, :update, :remove
#
#   register_interfaces :load_balancer_virtual_servers,
#                       :load_balancers, :load_balancer_types
#
#   set_rest_parent_name :load_balancers
#
# end
#
module Morpheus::Cli::SecondaryRestCommand
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods

    ## duplicated the rest_* settings with rest_parent_*, for defining the parent resource

    # rest_parent_name is the rest_name for the parent
    def rest_parent_name
      @rest_parent_name || default_rest_parent_name
    end

    def default_rest_parent_name
      words = rest_name.split("_")
      if words.size > 1
        words.pop
        return words.join("_") + "s"
      else
        # this wont happen, default wont make sense in this scenario
        # "parent_" + rest_name
        raise "Unable to determine default_rest_parent_name for rest_name: #{rest_name}, class: #{self}"
      end
    end

    def rest_parent_name=(v)
      @rest_parent_name = v.to_s
    end

    alias :set_rest_parent_name :rest_parent_name=
    alias :set_rest_parent :rest_parent_name=
    #alias :rest_parent= :rest_parent_name=

    # rest_parent_key is the singular name of the resource eg. "neat_thing"
    def rest_parent_key
      @rest_parent_key || default_rest_parent_key
    end

    def default_rest_parent_key
      rest_parent_name.chomp("s")
    end

    def rest_parent_key=(v)
      @rest_parent_key = v.to_s
    end

    alias :set_rest_parent_key :rest_parent_key=

    def rest_parent_arg
      @rest_parent_arg || default_rest_parent_arg
    end

    def default_rest_parent_arg
      rest_parent_key.to_s.gsub("_", " ")
    end

    def rest_parent_arg=(v)
      @rest_parent_arg = v.to_s
    end

    alias :set_rest_parent_arg :rest_parent_arg=

    # rest_parent_label is the capitalized resource label eg. "Neat Thing"    
    def rest_parent_label
      @rest_parent_label || default_rest_parent_label
    end

    def default_rest_parent_label
      rest_parent_key.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
    end

    def rest_parent_label=(v)
      @rest_parent_label = v.to_s
    end

    alias :set_rest_parent_label :rest_parent_label=

    # the plural version of the label eg. "Neat Things"
    def rest_parent_label_plural
      @rest_parent_label_plural || default_rest_parent_label_plural
    end
    
    def default_rest_parent_label_plural
      #rest_parent_name.to_s.split("_").collect {|it| it.to_s.capitalize }.join(" ")
      rest_parent_label.to_s.pluralize
    end

    def rest_parent_label_plural=(v)
      @rest_parent_label_plural = v.to_s
    end
    
    alias :set_rest_parent_label_plural :rest_parent_label_plural=

    # the name of the default interface, matches the rest name eg. "neat_things"
    def rest_parent_interface_name
      @rest_parent_interface_name || default_rest_parent_interface_name
    end

    def default_rest_parent_interface_name
      rest_parent_name
    end

    def rest_parent_interface_name=(v)
      @rest_parent_interface_name = v.to_s
    end

    alias :set_rest_parent_interface_name :rest_parent_interface_name=

  end

  ## duplicated the rest_* settings with rest_parent, for the parents resource
  
  def rest_parent_name
    self.class.rest_parent_name
  end

  def rest_parent_key
    self.class.rest_parent_key
  end

  def rest_parent_arg
    self.class.rest_parent_arg
  end

  def rest_parent_label
    self.class.rest_parent_label
  end

  def rest_parent_label_plural
    self.class.rest_parent_label_plural
  end

  def rest_parent_interface_name
    self.class.rest_parent_interface_name # || "@#{rest_parent_name}_interface"
  end

  def rest_parent_interface
    instance_variable_get("@#{rest_parent_interface_name}_interface")
  end

  def rest_parent_object_key
    self.send("#{rest_parent_key}_object_key")
  end

  def rest_parent_list_key
    self.send("#{rest_parent_key}_list_key")
  end

  def rest_parent_column_definitions
    self.send("#{rest_parent_key}_column_definitions")
  end

  def rest_parent_list_column_definitions
    self.send("#{rest_parent_key}_list_column_definitions")
  end

  def rest_parent_find_by_name_or_id(name)
    return self.send("find_#{rest_parent_key}_by_name_or_id", name)
  end

  def registered_interfaces
    self.class.registered_interfaces
  end

  def list(args)
    parent_id, parent_record = nil, nil
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List #{rest_label_plural.downcase}.
[#{rest_parent_arg}] is required. This is the name or id of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    parent_id = args[0]
    if args[1] # && rest_has_name
      record_name = args[1]
    end
    verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 1
      options[:phrase] = args[1..-1].join(" ")
    end
    connect(options)
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      raise_command_error "#{rest_parent_label} not found for '#{parent_id}'.\n#{optparse}"
    end
    parent_id = parent_record['id']
    params.merge!(parse_list_options(options))
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.list(parent_id, params)
      return
    end
    json_response = rest_interface.list(parent_id, params)
    render_response(json_response, options, rest_list_key) do
      records = json_response[rest_list_key]
      print_h1 "Morpheus #{rest_label_plural}"
      if records.nil? || records.empty?
        print cyan,"No #{rest_label_plural.downcase} found.",reset,"\n"
      else
        print as_pretty_table(records, rest_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about #{a_or_an(rest_label)} #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the name or id of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    parent_id = args[0]
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      raise_command_error "#{rest_parent_label} not found for '#{parent_id}'.\n#{optparse}"
    end
    parent_id = parent_record['id']
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args[1..-1])
    return run_command_for_each_arg(id_list) do |arg|
      _get(parent_id, arg, params, options)
    end
  end

  def _get(parent_id, id, params, options)
    if id !~ /\A\d{1,}\Z/
      record = rest_find_by_name_or_id(id)
      if record.nil?
        raise_command_error "#{rest_label} not found for name '#{id}'"
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
      print_description_list(rest_column_definitions, record, options)
      # show config settings...
      if record['optionTypes'] && record['optionTypes'].size > 0
        print_h2 "Option Types", options
        print format_option_types_table(record['optionTypes'], options, rest_object_key)
      end
      print reset,"\n"
    end
  end

  def add(args)
    parent_id, parent_record = nil, nil
    record_type_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      if rest_has_type
        opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}] -t TYPE")
        opts.on( '-t', "--#{rest_type_arg} TYPE", "#{rest_type_label}" ) do |val|
          record_type_id = val
        end
      else
        opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      end
      # if defined?(add_#{rest_key}_option_types)
      #   build_option_type_options(opts, options, add_#{rest_key}_option_types)
      # end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the name or id of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the name of the new #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max: 2)
    # todo: make supporting args[0] optional and more flexible
    # for now args[0] is assumed to be the 'name'
    record_name = nil
    parent_id = args[0]
    if args[1] # && rest_has_name
      record_name = args[1]
    end
    # todo: maybe need a flag to make this required, it could be an option type too, so
    if rest_has_type
      if record_type_id.nil?
        raise_command_error "#{rest_type_label} is required.\n#{optparse}"
      end
    end
    connect(options)
    if rest_has_type
      record_type = rest_type_find_by_name_or_id(record_type_id)
      if record_type.nil?
        raise_command_error "#{rest_type_label} not found for '#{record_type_id}'.\n#{optparse}"
      end
    end
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      raise_command_error "#{rest_parent_label} not found for '#{parent_id}'.\n#{optparse}"
    end
    parent_id = parent_record['id']
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options})
    else
      record_payload = {}
      if record_name
        record_payload['name'] = record_name
        options[:options]['name'] = record_name # injected for prompt
      end
      if rest_has_type && record_type
        # record_payload['type'] = {'code' => record_type['code']}
        record_payload['type'] = record_type['code']
        options[:options]['type'] = record_type['code'] # injected for prompt
      end
      record_payload.deep_merge!(passed_options)
      # options by type
      my_option_types = record_type ? record_type['optionTypes'] : nil
      if my_option_types && !my_option_types.empty?
        # remove redundant fieldContext
        my_option_types.each do |option_type| 
          if option_type['fieldContext'] == rest_object_key
            option_type['fieldContext'] = nil
          end
        end
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        record_payload.deep_merge!(v_prompt)
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.create(parent_id, payload)
      return
    end
    json_response = rest_interface.create(parent_id, payload)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_green_success "Added #{rest_label.downcase} #{record['name'] || record['id']}"
      return _get(parent_id, record["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    parent_id = args[0]
    id = args[1]
    options = {}
    params = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}] [options]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the name or id of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      raise_command_error "#{rest_parent_label} not found for '#{parent_id}'.\n#{optparse}"
    end
    parent_id = parent_record['id']
    connect(options)
    record = rest_find_by_name_or_id(id)
    passed_options = parse_passed_options(options)
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options}) unless passed_options.empty?
    else
      record_payload = passed_options
      if record_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.update(parent_id, record['id'], payload)
      return
    end
    json_response = rest_interface.update(parent_id, record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated #{rest_label.downcase} #{record['name'] || record['id']}"
      _get(parent_id, record["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    parent_id = args[0]
    id = args[1]
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [#{rest_arg}]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an existing #{rest_label.downcase}.
[#{rest_parent_arg}] is required. This is the name or id of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[#{rest_arg}] is required. This is the name or id of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    parent_record = rest_parent_find_by_name_or_id(parent_id)
    if parent_record.nil?
      raise_command_error "#{rest_parent_label} not found for '#{parent_id}'.\n#{optparse}"
    end
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the #{rest_label.downcase} #{record['name'] || record['id']}?")
      return 9, "aborted"
    end
    params.merge!(parse_query_options(options))
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.destroy(parent_id, record['id'])
      return 0, nil
    end
    json_response = rest_interface.destroy(parent_id, record['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed #{rest_label.downcase} #{record['name'] || record['id']}"
    end
    return 0, nil
  end

end

