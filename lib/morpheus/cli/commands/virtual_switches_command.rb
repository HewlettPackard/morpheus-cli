require 'morpheus/cli/cli_command'

# CLI command Virtual Switch management
# UI is Tools: Virtual Switches
# API is /api/virtual-switches and returns virtualSwitches
class Morpheus::Cli::VirtualSwitchesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'virtual-switches'
  set_command_description "View and manage Virtual Switches"

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @virtual_switches_interface = @api_client.virtual_switches
    @clusters_interface = @api_client.clusters
    @networks_interface = @api_client.networks
    @options_interface = @api_client.options
    
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
      build_standard_list_options(opts, options)
      opts.footer = "List Virtual Switches."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @virtual_switches_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_switches_interface.dry.list(params)
      return
    end
    json_response = @virtual_switches_interface.list(params)
    render_response(json_response, options, virtual_switch_list_key) do
      virtual_switches = json_response[virtual_switch_list_key]
      print_h1 "Morpheus Virtual Switches", parse_list_subtitles(options), options
      if virtual_switches.empty?
        print cyan,"No Virtual Switches found.",reset,"\n"
      else
        columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type']['name'] rescue it['baseType'] },
          "NIC Count" => lambda {|it| it['nicCount'] },
          "Network Count" => lambda {|it| it['networkCount'] },
        }
        print as_pretty_table(virtual_switches, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[switch]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific Virtual Switch.
[switch] is required. This is the name or id of a Virtual Switch.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    virtual_switch = nil
    if id.to_s !~ /\A\d{1,}\Z/
      virtual_switch = find_virtual_switch_by_name(id)
      return 1, "Virtual Switch not found for #{id}" if virtual_switch.nil?
      id = virtual_switch['id']
    end
    @virtual_switches_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_switches_interface.dry.get(id, params)
      return
    end
    json_response = @virtual_switches_interface.get(id, params)
    virtual_switch = json_response[virtual_switch_object_key]
    render_response(json_response, options, virtual_switch_object_key) do
      print_h1 "Virtual Switch Details", [], options
      print cyan
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| it['type']['name'] rescue it['baseType'] },
        "NIC Count" => lambda {|it| it['nicCount'] },
        "Network Count" => lambda {|it| it['networkCount'] },
      }
      print_description_list(columns, virtual_switch, options)


      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_virtual_switch_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new Virtual Switch.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    if options[:options]['logo']
      options[:options]['iconPath'] = 'custom'
    end
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({virtual_switch_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # prompt for option types
      option_types = add_virtual_switch_option_types
      v_prompt = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      
      # massage association params a bit
      # params['apps'] = ...
      payload.deep_merge!({virtual_switch_object_key => params})
    end
    @virtual_switches_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_switches_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @virtual_switches_interface.create(payload)
    virtual_switch = json_response[virtual_switch_object_key]
    render_response(json_response, options, virtual_switch_object_key) do
      print_green_success "Added virtual switch #{virtual_switch['name']}"
      return _get(virtual_switch["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[switch] [options]")
      build_option_type_options(opts, options, update_virtual_switch_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a virtual switch.
[switch] is required. This is the name or id of a virtual switch.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    if options[:options]['logo']
      options[:options]['iconPath'] = 'custom'
    end
    connect(options)
    virtual_switch = find_virtual_switch_by_name_or_id(args[0])
    return 1 if virtual_switch.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({virtual_switch_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_virtual_switch_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # massage association params a bit
      
      # params['apps'] = ...
      payload.deep_merge!({virtual_switch_object_key => params})
      if payload[virtual_switch_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @virtual_switches_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_switches_interface.dry.update(virtual_switch['id'], payload)
      return
    end
    json_response = @virtual_switches_interface.update(virtual_switch['id'], payload)
    virtual_switch = json_response[virtual_switch_object_key]
    render_response(json_response, options, virtual_switch_object_key) do
      print_green_success "Updated virtual switch #{virtual_switch['name']}"
      return _get(virtual_switch["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[switch] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a virtual switch.
[switch] is required. This is the name or id of a virtual switch.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    virtual_switch = find_virtual_switch_by_name_or_id(args[0])
    return 1 if virtual_switch.nil?
    @virtual_switches_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_switches_interface.dry.destroy(virtual_switch['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual switch #{virtual_switch['name']}?")
      return 9, "aborted command"
    end
    json_response = @virtual_switches_interface.destroy(virtual_switch['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed virtual switch #{virtual_switch['name']}"
    end
    return 0, nil
  end

  private
  
  def add_virtual_switch_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Choose a unique name for the Virtual Switch'},
      #{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description'},
      {'switch' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'description' => 'Type of virtual switch', 'selectOptions' => [{'name' => 'VM Network', 'value' => 'general'}, {'name' => 'ISCSI', 'value' => 'iscsi'}, {'name' => 'NFS', 'value' => 'nfs'}, {'name' => 'Live Migration', 'value' => 'live_migration'}, {'name' => 'SDN', 'value' => 'sdn'}], 'required' => true},
    ]
  end

  def update_virtual_switch_option_types
    list = add_virtual_switch_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def find_virtual_switch_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_virtual_switch_by_id(val)
    else
      return find_virtual_switch_by_name(val)
    end
  end

  def find_virtual_switch_by_id(id)
    begin
      json_response = virtual_switches_interface.get(id.to_i)
      return json_response[virtual_switch_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Virtual Switch not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_virtual_switch_by_name(name)
    json_response = virtual_switches_interface.list({name: name.to_s})
    virtual_switches = json_response[virtual_switch_list_key]
    if virtual_switches.empty?
      print_red_alert "Virtual Switch not found by name '#{name}'"
      return nil
    elsif virtual_switches.size > 1
      print_red_alert "#{virtual_switches.size} Virtual Switches found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(virtual_switches, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return virtual_switches[0]
    end
  end

  def format_virtual_switch_status(virtual_switch, return_color=cyan)
    out = ""
    status_string = virtual_switch['status'].to_s.downcase
    if status_string
      if ['available','ok'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['unavailable','error'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{return_color}#{status_string.upcase}"
      end
    end
    out + return_color
  end


end
