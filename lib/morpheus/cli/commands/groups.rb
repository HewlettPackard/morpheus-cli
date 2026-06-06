require 'morpheus/cli/cli_command'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::OptionSourceHelper

  register_subcommands :list, :get, :add, :update, :use, :unuse, :add_cloud, :remove_cloud, :remove, :current => :print_current
  alias_subcommand :details, :get
  register_subcommands :wiki, :update_wiki
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @groups_interface = @api_client.groups
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
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
      opts.on('--include-tenants','--include-tenants', "Include sub tenant groups") do
        options[:include_tenants] = true
        params['includeTenants'] = true
      end
      opts.on('--tenant TENANT', String, "Tenant Name or ID" ) do |val|
        options[:tenant] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List groups."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    if options[:tenant]
      if options[:tenant].to_s !~ /\A\d{1,}\Z/
        account = find_account_by_name_or_id(options[:tenant])
        if account.nil?
          return 1, "Tenant not found by name: #{options[:tenant]}"
        else
          params['tenantId'] = account['id']
        end
      else
        params['tenantId'] = options[:tenant]
      end
    end
    params.merge!(parse_list_options(options))
    @groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @groups_interface.list(params)
      return 0, nil
    end
    json_response = @groups_interface.list(params)
    exit_code, err = 0, nil
    render_response(json_response, options, "groups") do
      groups = json_response['groups']
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Groups", subtitles, options
      if groups.empty?
        print cyan,"No groups found.",reset,"\n"
      else
        print_groups_table(groups, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return exit_code, err
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--include-tenants','--include-tenants', "Include sub tenant groups when finding group by name") do
        options[:include_tenants] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a group.
[name] is required. This is the name or id of a group. Supports 1-N arguments.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options={})
    params = {}
    group = nil
    if id.to_s !~ /\A\d{1,}\Z/
      group = find_group_by_name_or_id(id, options[:include_tenants])
      id = group['id']
    end
    @groups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @groups_interface.dry.get(id.to_i, params)
      return
    end
    json_response = @groups_interface.get(id.to_i, params)
    render_response(json_response, options, 'group') do
      group = json_response['group']
      group_stats = group['stats']
      # serverCounts moved to zone.stats.serverCounts
      server_counts = nil
      instance_counts = nil
      if group_stats
        instance_counts = group_stats['instanceCounts']
        server_counts = group_stats['serverCounts']
      end
      is_active = @active_group_id && (@active_group_id == group['id'])
      print_h1 "Group Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'code',
        "Location" => 'location',
        "Labels" => lambda {|it| format_list(it['labels'], '') rescue '' },
        "Clouds" => lambda {|it| it['zones'].collect {|z| z['name'] }.join(', ') },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        #"Instances" => lambda {|it| it['stats']['instanceCounts']['all'] rescue '' },
        # "Hosts" => lambda {|it| it['stats']['serverCounts']['host'] rescue it['serverCount'] },
        # "VMs" => lambda {|it| it['stats']['serverCounts']['vm'] rescue '' },
        # "Bare Metal" => lambda {|it| it['stats']['serverCounts']['baremetal'] rescue '' },
      }
      print_description_list(description_cols, group)

      if server_counts
        print_h2 "Group Stats"
        print cyan
        print "Clouds: #{group['zones'].size}".center(20)
        print "Instances: #{instance_counts['all']}".center(20) if instance_counts
        print "Hosts: #{server_counts['host']}".center(20)
        #print "Container Hosts: #{server_counts['containerHost']}".center(20)
        #print "Hypervisors: #{server_counts['hypervisor']}".center(20)
        print "Virtual Machines: #{server_counts['vm']}".center(20)
        print "Bare Metal: #{server_counts['baremetal']}".center(20)
        #print "Unmanaged: #{server_counts['unmanaged']}".center(20)
        print "\n"
      end
      # puts "ID: #{group['id']}"
      # puts "Name: #{group['name']}"
      # puts "Code: #{group['code']}"
      # puts "Location: #{group['location']}"
      # puts "Clouds: #{group['zones'].collect {|it| it['name'] }.join(', ')}"
      # puts "Hosts: #{group['serverCount']}"
      if is_active
        print "\n"
        print cyan, "=> This is the active group", reset, "\n" # remove me...
      end
      print reset,"\n"
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, add_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end
      opts.on( '--use', '--use', "Make this the current active group" ) do
        use_it = true
      end
      build_standard_add_options(opts, options)
      opts.footer = "Create a new group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    connect(options)
    begin
      # group = {name: args[0], location: params[:location]}
      # payload = {group: group}
      group_payload = {}
      if args[0]
        group_payload[:name] = args[0]
        options[:options]['name'] = args[0] # to skip prompt
      end
      if params[:location]
        group_payload[:name] = params[:location]
        options[:options]['location'] = params[:location] # to skip prompt
      end
      all_option_types = add_group_option_types()
      params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {})
      group_payload.merge!(params)
      payload = {group: group_payload}
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.create(payload)
        return
      end
      json_response = @groups_interface.create(payload)
      group = json_response['group']
      if use_it
        ::Morpheus::Cli::Groups.set_active_group(@appliance_name, group['id'])
      end
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added group #{group['name']}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end
      build_standard_update_options(opts, options)
      opts.footer = "Update a group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      group_payload = {}

      #params = Morpheus::Cli::OptionTypes.prompt(update_group_option_types, options[:options], @api_client, {})
      params = options[:options] || {}

      if params.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end

      if params.key?('labels')
        params['labels'] = parse_labels(params['labels'])
      end
      group_payload.merge!(params)

      payload = {group: group_payload}
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update(group['id'], payload)
        return
      end
      json_response = @groups_interface.update(group['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        #list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_cloud(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "CLOUD")
      build_standard_update_options(opts, options)
      opts.footer = "Add a cloud to a group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      cloud = find_cloud_by_name_or_id(args[1])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if found_zone
        print_red_alert "Cloud #{cloud['name']} is already in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones + [{'id' => cloud['id']}]
      payload = {group: {id: group["id"], zones: new_zones}}
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_zones(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_zones(group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added cloud #{cloud["name"]} to group #{group['name']}"
        #list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_cloud(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [cloud]")
      build_standard_update_options(opts, options)
      opts.footer = "Remove a cloud from a group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      cloud = find_cloud_by_name_or_id(args[1])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if !found_zone
        print_red_alert "Cloud #{cloud['name']} is not in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones.reject {|it| it["id"] == cloud["id"] }
      payload = {group: {id: group["id"], zones: new_zones}}
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_zones(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_zones(group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed cloud #{cloud['name']} from group #{group['name']}"
        # list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete a group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the group #{group['name']}?")
        exit
      end
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.destroy(group['id'])
        return
      end
      json_response = @groups_interface.destroy(group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed group #{group['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.footer = <<-EOT
This sets the active group.
The active group will be auto-selected for use during provisioning.
[name] is required. This is the name or id of a group.
EOT
      build_common_options(opts, options, [:quiet, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    group = find_group_option(args[0]) #uses /api/options
    if !group
      raise_command_error "Group not found by name #{args[0]}"
    end
    exit_code, err = 0, nil
    is_already_active = @active_group_id == group['id']
    if is_already_active
      unless options[:quiet]
        print reset,"Already using the group #{group['name']}","\n",reset
      end
    else
      ::Morpheus::Cli::Groups.set_active_group(@appliance_name, group['id'])
      # ::Morpheus::Cli::Groups.save_groups(@active_groups)
      unless options[:quiet]
        print cyan,"Switched active group to #{group['name']}","\n",reset
      end
      #list([])
    end
    if is_already_active
      print_green_success "Group #{group['name']} is still active"
    else
      print_green_success "Group #{group['name']} is now active"
    end
    return 0


  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "This will clear the current active group.\n" +
        "You will be prompted for a Group during provisioning."
      build_common_options(opts, options, [:quiet, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options.merge({:skip_verify_access_token => true, :skip_login => true}))
    exit_code, err = 0, nil
    if @active_group_id
      ::Morpheus::Cli::Groups.clear_active_group(@appliance_name)
      # print_green_success "Group #{@active_group_id} is no longer active."
      print_green_success "Group is no longer active."
      return 0, nil
    else
      # print reset,"You are not using any group for appliance #{@appliance_name}",reset,"\n"
      print reset,"You are not using any group",reset,"\n"
      # exit_code = 1
    end
    return exit_code, err
  end

  def print_current(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:remote])
      opts.footer = "Print the name of the current active group"
    end
    optparse.parse!(args)
    connect(options)

    group = @active_group_id ? find_group_by_name_or_id(@active_group_id) : nil
    if group
      print cyan,group['name'].to_s,"\n",reset
    else
      print yellow,"No active group. See `groups use`","\n",reset
      return false
    end
  end

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[group]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for an group." + "\n" +
                    "[group] is required. This is the name or id of an group."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?


      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.wiki(group["id"], params)
        return
      end
      json_response = @groups_interface.wiki(group["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Group Wiki Page: #{group['name']}"
        # print_h1 "Wiki Page Details"
        print cyan

        print_description_list({
          "Page ID" => 'id',
          "Name" => 'name',
          #"Category" => 'category',
          #"Ref Type" => 'refType',
          #"Ref ID" => 'refId',
          #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
          "Updated By" => lambda {|it| it['updatedBy'] ? it['updatedBy']['username'] : '' }
        }, page)
        print reset,"\n"

        print_h2 "Page Content"
        print cyan, page['content'], reset, "\n"

      else
        print "\n"
        print cyan, "No wiki page found.", reset, "\n"
      end
      print reset,"\n"

      if open_wiki_link
        return view_wiki([args[0]])
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_wiki(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View group wiki page in a web browser" + "\n" +
                    "[group] is required. This is the name or id of an group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/groups/#{group['id']}#!wiki"

      if options[:dry_run]
        puts Morpheus::Util.open_url_command(link)
        return 0
      end
      return Morpheus::Util.open_url(link)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_wiki(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[group] [options]")
      build_option_type_options(opts, options, update_wiki_page_option_types)
      opts.on('--file FILE', "File containing the wiki content. This can be used instead of --content") do |filename|
        full_filename = File.expand_path(filename)
        if File.exist?(full_filename)
          params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      opts.on(nil, '--clear', "Clear current page content") do |val|
        params['content'] = ""
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'page' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_wiki_page_option_types, options[:options], @api_client, options[:params])
        #params = passed_options
        params.deep_merge!(passed_options)

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload.deep_merge!({'page' => params}) unless params.empty?
      end
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_wiki(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_wiki(group["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for group #{group['name']}"
        wiki([group['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  protected

  def print_groups_table(groups, options={})
    table_color = options[:color] || cyan
    active_group = @active_group_id ? groups.find {|group| group['id'] == @active_group_id } : nil
    rows = groups.collect do |group|
      {
        id: active_group ? (((@active_group_id && (@active_group_id == group['id'])) ? "=> " : "   ") + group['id'].to_s) : group['id'],
        name: group['name'],
        tenant: group['account'] ? group['account']['name'] : '',
        labels: group['labels'],
        location: group['location'],
        cloud_count: group['zones'] ? group['zones'].size : 0,
        instance_count: (group['stats']['instanceCounts']['all'] rescue ''),
        host_count: (group['stats']['serverCounts']['host'] rescue group['serverCount']),
        vm_count: (group['stats']['serverCounts']['vm'] rescue ''),
        baremetal_count: (group['stats']['serverCounts']['baremetal'] rescue '')
      }
    end
    columns = [
      #{:active => {:display_name => ""}},
      {:id => {:display_name => (active_group ? "   ID" : "ID")}},
      {:name => {:width => 64}},
      options[:include_tenants] || options[:tenant] ? {:tenant => {:width => 32}} : nil,
      {:location => {:width => 32}},
      {:labels => {:display_method => lambda {|it| format_list(it[:labels], '', 3) rescue '' }}},
      {:cloud_count => {:display_name => "CLOUDS"}},
      {:instance_count => {:display_name => "INSTANCES"}},
      {:host_count => {:display_name => "HOSTS"}},
      {:vm_count => {:display_name => "VMS"}},
      {:baremetal_count => {:display_name => "BARE METAL"}},
  ].compact
    print as_pretty_table(rows, columns, options)
  end

  def add_group_option_types()
    tmp_option_types = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'shorthand' => '-l', 'optionalValue' => true, 'fieldName' => 'labels', 'fieldLabel' => 'Labels', 'type' => 'text', 'required' => false, 'processValue' => lambda {|val| parse_labels(val) }, 'displayOrder' => 3},
      {'fieldName' => 'location', 'fieldLabel' => 'Location', 'type' => 'text', 'required' => false, 'displayOrder' => 4},
    ]

    # Advanced Options
    # TODO: Service Registry

    return tmp_option_types
  end

  def update_group_option_types()
    add_group_option_types().collect {|it| it['required'] = false; it }
  end

  # todo: This belongs elsewhere, like module Morpheus::Cli::ActiveGroups

public
  
  @@groups = nil

  class << self
    include Term::ANSIColor
    # Provides the current active group information
    def active_groups_map
      @@groups ||= load_group_file || {}
    end

    def active_groups
      active_groups_map
    end

    # Provides the current active group information (just the ID right now)
    def active_group(appliance_name=nil)
      if appliance_name == nil
        appliance_name, appliance_url = Morpheus::Cli::Remote.active_appliance
      end
      if !appliance_name
        return nil
      end
      return active_groups_map[appliance_name.to_sym]
    end

    # alias (unused)
    def active_group_id(appliance_name=nil)
      active_group(appliance_name)
    end

    def set_active_group(appliance_name, group_id)
      the_groups = active_groups_map
      the_groups[appliance_name.to_sym] = group_id
      save_groups(the_groups)
    end

    def clear_active_group(appliance_name)
      the_groups = active_groups_map
      the_groups.delete(appliance_name.to_sym)
      save_groups(the_groups)
    end

    def load_group_file
      fn = groups_file_path
      if File.exist? fn
        #Morpheus::Logging::DarkPrinter.puts "loading groups file #{fn}" if Morpheus::Logging.debug?
        return YAML.load_file(fn)
      else
        {}
      end
    end

    def groups_file_path
      return File.join(Morpheus::Cli.home_directory, "groups")
    end

    def save_groups(groups_map)
      fn = groups_file_path
      if !Dir.exist?(File.dirname(fn))
        FileUtils.mkdir_p(File.dirname(fn))
      end
      File.open(fn, 'w') {|f| f.write groups_map.to_yaml } #Store
      FileUtils.chmod(0600, fn)
      @@groups = groups_map
    end

  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end
end
