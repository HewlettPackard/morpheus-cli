require 'morpheus/cli/cli_command'

class Morpheus::Cli::Clouds
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  register_subcommands :list, :count, :get, :add, :update, :remove, :refresh, :security_groups, :apply_security_groups
  register_subcommands :types, :type
  alias_subcommand :'list-types', :types
  alias_subcommand :'get-type', :type
  register_subcommands :wiki, :update_wiki
  register_subcommands({:'update-logo' => :update_logo,:'update-dark-logo' => :update_dark_logo})
  register_subcommands :list_affinity_groups, :get_affinity_group, :update_affinity_group, :add_affinity_group, :remove_affinity_group
  #register_subcommands :firewall_disable, :firewall_enable
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clouds_interface = @api_client.clouds
    @groups_interface = @api_client.groups
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
        options[:group] = group
      end
      opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
        options[:zone_type] = val
      end
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_standard_list_options(opts, options)
      opts.footer = "List clouds."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    begin
      if options[:zone_type]
        cloud_type = cloud_type_for_name(options[:zone_type])
        params[:type] = cloud_type['code']
      end
      if !options[:group].nil?
        group = find_group_by_name(options[:group])
        if !group.nil?
          params['groupId'] = group['id']
        end
      end

      params.merge!(parse_list_options(options))
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.list(params)
        return 0
      end

      json_response = @clouds_interface.list(params)
      render_response(json_response, options, 'zones') do
        clouds = json_response['zones']
        title = "Morpheus Clouds"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud_type
          subtitles << "Type: #{cloud_type['name']}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if clouds.empty?
          print cyan,"No clouds found.",reset,"\n"
        else          
          columns = cloud_list_column_definitions(options).upcase_keys!
          print as_pretty_table(clouds, columns, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of clouds."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.list(params)
        return
      end
      json_response = @clouds_interface.list(params)
      # print number only
      if json_response['meta'] && json_response['meta']['total']
        print cyan, json_response['meta']['total'], reset, "\n"
      else
        print yellow, "unknown", reset, "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_standard_list_options(opts, options)
      opts.footer = "Get details about a cloud.\n" +
                    "[name] is required. This is the name or id of a cloud."
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

  def _get(id, params, options={})
    cloud = nil
    if id.to_s !~ /\A\d{1,}\Z/
      cloud = find_cloud_by_name_or_id(id)
      id = cloud['id']
    end
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.get(id.to_i, params)
      return
    end
    json_response = @clouds_interface.get(id, params)
    render_response(json_response, options, 'zone') do
      cloud = json_response['zone']
      cloud_stats = cloud['stats']
      # serverCounts moved to zone.stats.serverCounts
      server_counts = nil
      if cloud_stats
        server_counts = cloud_stats['serverCounts']
      else
        server_counts = json_response['serverCounts'] # legacy
      end
      #cloud_type = cloud_type_for_id(cloud['zoneTypeId'])
      print_h1 "Cloud Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        # "Type" => lambda {|it| cloud_type ? cloud_type['name'] : '' },
        "Type" => lambda {|it| it['zoneType'] ? it['zoneType']['name'] : '' },
        "Code" => 'code',
        "Location" => 'location',
        "Labels" => lambda {|it| format_list(it['labels'], '') rescue '' },
        "Region Code" => 'regionCode',
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Groups" => lambda {|it| it['groups'].collect {|g| g.instance_of?(Hash) ? g['name'] : g.to_s }.join(', ') },
        #"Owner" => lambda {|it| it['owner'].instance_of?(Hash) ? it['owner']['name'] : it['ownerId'] },
        "Tenant" => lambda {|it| it['account'].instance_of?(Hash) ? it['account']['name'] : it['accountId'] },
        "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        "Last Sync" => lambda {|it| format_local_dt(it['lastSync']) },
        "Sync Duration" => lambda {|it| format_duration_milliseconds(it['lastSyncDuration']).to_s },
        "Status" => lambda {|it| format_cloud_status(it) },
      }
      print_description_list(description_cols, cloud)

      print_h2 "Cloud Servers"
      print cyan
      if server_counts
        print "Container Hosts: #{server_counts['containerHost']}".center(20)
        print "Hypervisors: #{server_counts['hypervisor']}".center(20)
        print "Bare Metal: #{server_counts['baremetal']}".center(20)
        print "Virtual Machines: #{server_counts['vm']}".center(20)
        print "Unmanaged: #{server_counts['unmanaged']}".center(20)
        print "\n"
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --group GROUP --type TYPE")
      opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
        params[:group] = val
      end
      opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
        params[:zone_type] = val
      end
      opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
        params[:description] = desc
      end
      opts.on( '--certificate-provider CODE', String, "Certificate Provider. Default is 'internal'" ) do |val|
        params[:certificate_provider] = val
      end
      opts.on('--costing-mode VALUE', String, "Costing Mode can be off,costing,full, Default is off." ) do |val|
        options[:options]['costingMode'] = val
      end
      opts.on('--credential VALUE', String, "Credential ID or \"local\"" ) do |val|
        options[:options]['credential'] = val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end

      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    connect(options)

    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'zone' => parse_passed_options(options)})
      else
        cloud_payload = {name: args[0], description: params[:description]}
        cloud_payload.deep_merge!(parse_passed_options(options))
        # Group
        # use active group by default
        params[:group] ||= @active_group_id
        if options[:options]['group']
          params[:group] = options[:options]['group']
        end
        group_id = nil
        group = params[:group] ? find_group_by_name_or_id_for_provisioning(params[:group]) : nil
        if group
          group_id = group["id"]
        else
          # print_red_alert "Group not found or specified!"
          # exit 1
          #groups_dropdown = @groups_interface.list({})['groups'].collect {|it| {'name' => it["name"], 'value' => it["id"]} }
          group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'optionSource' => 'groups', 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
          group_id = group_prompt['group']
        end
        cloud_payload['groupId'] = group_id
        cloud_payload.delete('group')
        # todo: pass groups as an array instead

        # Cloud Name
        if args[0]
          cloud_payload['name'] = args[0]
          options[:options]['name'] = args[0] # to skip prompt
        end
        # name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
        # cloud_payload['name'] = name_prompt['name']

        # Cloud Type
        cloud_type = nil
        if params[:zone_type]
          cloud_type = cloud_type_for_name(params[:zone_type])
        else
          # print_red_alert "Cloud Type not found or specified!"
          # exit 1
          cloud_types_dropdown = cloud_types_for_dropdown
          cloud_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Cloud Type', 'selectOptions' => cloud_types_dropdown, 'required' => true, 'description' => 'Select Cloud Type.'}],options[:options],@api_client,{})
          cloud_type_code = cloud_type_prompt['type']
          cloud_type = cloud_type_for_name(cloud_type_code) # this does work
        end
        if !cloud_type
          print_red_alert "A cloud type is required."
          exit 1
        end
        cloud_payload.delete('type')
        cloud_payload['zoneType'] = {'code' => cloud_type['code']}

        cloud_payload['config'] ||= {}
        if params[:certificate_provider]
          cloud_payload['config']['certificateProvider'] = params[:certificate_provider]
        else
          cloud_payload['config']['certificateProvider'] = 'internal'
        end

        all_option_types = add_cloud_option_types(cloud_type)

        params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {zoneTypeId: cloud_type['id']})
        # some optionTypes have fieldContext='zone', so move those to the root level of the zone payload
        if params['zone'].is_a?(Hash)
          cloud_payload.deep_merge!(params.delete('zone'))
        end
        cloud_payload.deep_merge!(params)
        payload = {zone: cloud_payload}
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.create(payload)
        return
      end
      json_response = @clouds_interface.create(payload)
      cloud = json_response['zone']
      if options[:json]
        puts as_json(json_response, options)
      else
        get([cloud['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      # opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
      #   params[:group] = val
      # end
      # opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
      #   params[:zone_type] = val
      # end
      # opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
      #   params[:description] = desc
      # end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--costing-mode VALUE', String, "Costing Mode can be off, costing, or full. Default is off." ) do |val|
        options[:options]['costingMode'] = val
      end
      opts.on('--credential VALUE', String, "Credential ID or \"local\"" ) do |val|
        options[:options]['credential'] = val
      end
      opts.on('--default-cloud-logos', "Reset logos to default cloud logos, removing any custom logo and dark logo" ) do
        options[:options]['defaultCloudLogos'] = true
      end
      
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['zone'] ||= {}
          payload['zone'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        cloud_type = cloud_type_for_id(cloud['zoneTypeId'])
        cloud_payload = {}
        all_option_types = update_cloud_option_types(cloud_type)
        #params = Morpheus::Cli::OptionTypes.no_prompt(all_option_types, options[:options], @api_client, {zoneId: cloud['id'], zoneTypeId: cloud_type['id']})
        params = options[:options] || {}

        # Credentials (ideally only if value passed in and name can be parsed)
        if options[:options]['credential']
          credential_code = "credential"
          credential_option_type = {'code' => credential_code, 'fieldName' => credential_code, 'fieldLabel' => 'Credentials', 'type' => 'select', 'optionSource' => 'credentials', 'description' => 'Enter an existing credential ID or choose "local"', 'defaultValue' => "local", 'required' => true}
          # supported_credential_types = ['username-keypair', 'username-password', 'username-password-keypair'].compact.flatten.join(",").split(",").collect {|it| it.strip }
          credential_params = {"new" => false, "zoneId" => cloud['id']}
          credential_value = Morpheus::Cli::OptionTypes.select_prompt(credential_option_type, @api_client, credential_params, true, options[:options][credential_code])
          if !credential_value.to_s.empty?
            if credential_value == "local"
              params[credential_code] = {"type" => credential_value}
            elsif credential_value.to_s =~ /\A\d{1,}\Z/
              params[credential_code] = {"id" => credential_value.to_i}
            end
          end
        end
        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        # some optionTypes have fieldContext='zone', so move those to the root level of the zone payload
        if params['zone'].is_a?(Hash)
          cloud_payload.merge!(params.delete('zone'))
        end
        if params.key?('labels')
          params['labels'] = parse_labels(params['labels'])
        end
        cloud_payload.merge!(params)
        payload = {zone: cloud_payload}
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update(cloud['id'], payload)
        return
      end
      json_response = @clouds_interface.update(cloud['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        get([cloud['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--remove-resources [on|off]', ['on','off'], "Remove Associated Resources. Default is off.") do |val|
        query_params[:removeResources] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Remove" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cloud #{cloud['name']}?")
        exit
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.destroy(cloud['id'], query_params)
        return 0
      end
      json_response = @clouds_interface.destroy(cloud['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed cloud #{cloud['name']}"
        #list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def refresh(args)
    options = {}
    query_params = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [options]")
      opts.on( '-m', '--mode [daily|costing]', "Refresh Mode. Use this to run the daily or costing jobs instead of the default hourly refresh." ) do |val|
        query_params[:mode] = val
      end
      opts.on( '--rebuild [on|off]', "Rebuild invoices for period. Only applies to mode=costing." ) do |val|
        query_params[:rebuild] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on( '--period PERIOD', "Period in the format YYYYMM to process invoices for. Default is the current period. Only applies to mode=costing." ) do |val|
        query_params[:period] = val.to_s
      end
      opts.on( '-f', '--force', "Force refresh. Useful if the cloud is disabled." ) do
        query_params[:force] = 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Refresh a cloud." + "\n" +
                    "[cloud] is required. This is the name or id of a cloud."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        payload = {}
        payload.deep_merge!(passed_options) unless passed_options.empty?
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.refresh(cloud['id'], query_params, payload)
        return
      end
      json_response = @clouds_interface.refresh(cloud['id'], query_params, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Refreshing cloud #{cloud['name']}..."
        #get([cloud['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # not exposed yet, refresh should be all that's needed.
  def sync(args)
    options = {}
    query_params = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Sync a cloud." + "\n" +
                    "[cloud] is required. This is the name or id of a cloud."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        payload = {}
        payload.deep_merge!(passed_options) unless passed_options.empty?
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.sync(cloud['id'], query_params, payload)
        return
      end
      json_response = @clouds_interface.sync(cloud['id'], query_params, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Syncing cloud #{cloud['name']}..."
        #get([cloud['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.firewall_disable(cloud['id'])
        return
      end
      json_response = @clouds_interface.firewall_disable(cloud['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.firewall_enable(cloud['id'])
        return
      end
      json_response = @clouds_interface.firewall_enable(cloud['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      zone_id = cloud['id']
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.security_groups(zone_id)
        return
      end
      json_response = @clouds_interface.security_groups(zone_id)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Cloud: #{cloud['name']}"
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [-s] [--clear]")
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        options[:securityGroupIds] = []
        clear_or_secgroups_specified = true
      end
      opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        options[:securityGroupIds] = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.apply_security_groups(cloud['id'])
        return
      end
      json_response = @clouds_interface.apply_security_groups(cloud['id'], options)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def types(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List cloud types.
EOT
    end
    optparse.parse!(args)
    connect(options)

    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.cloud_types({})
      return 0
    end
    json_response = @clouds_interface.cloud_types(params)
      
    render_response(json_response, options, 'zoneTypes') do
      cloud_types = json_response['zoneTypes']
      subtitles = []        
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Cloud Types", subtitles, options
      if cloud_types.empty?
        print cyan,"No cloud types found.",reset,"\n"
      else
        print cyan
        cloud_types = cloud_types.select {|it| it['enabled'] }
        rows = cloud_types.collect do |cloud_type|
          {id: cloud_type['id'], name: cloud_type['name'], code: cloud_type['code']}
        end
        #print "\n"
        columns = [:id, :name, :code]
        columns = options[:include_fields] if options[:include_fields]
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
        print reset,"\n"
      end
    end
  end

  def type(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_standard_get_options(opts, options)
            opts.footer = <<-EOT
Get details about a cloud type.
[type] is required. This is the name or id of cloud type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # construct request
    params.merge!(parse_query_options(options))
    id = args[0]
    cloud_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      cloud_type = cloud_type_for_name_or_id(id)
      if cloud_type.nil?
        raise_command_error "cloud type not found for name or code '#{id}'"
      end
      id = cloud_type['id']
    end
    # execute request
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.cloud_type(id.to_i)
      return 0
    end
    json_response = @clouds_interface.cloud_type(id.to_i)
    # render response
    render_response(json_response, options, 'zoneType') do
      cloud_type = json_response['zoneType']
      print_h1 "Cloud Type", [], options
      print cyan
      #columns = rest_type_column_definitions(options)
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'code',
        "Enabled" => lambda {|it| format_boolean it['enabled'] },
        "Provision" => lambda {|it| format_boolean it['provision'] },
        "Auto Capacity" => lambda {|it| format_boolean it['autoCapacity'] },
        # "Migration Target" => lambda {|it| format_boolean it['migrationTarget'] },
        "Datastores" => lambda {|it| format_boolean it['hasDatastores'] },
        "Networks" => lambda {|it| format_boolean it['hasNetworks'] },
        "Resource Pools" => lambda {|it| format_boolean it['hasResourcePools'] },
        "Security Groups" => lambda {|it| format_boolean it['hasSecurityGroups'] },
        "Containers" => lambda {|it| format_boolean it['hasContainers'] },
        "Bare Metal" => lambda {|it| format_boolean it['hasBareMetal'] },
        "Services" => lambda {|it| format_boolean it['hasServices'] },
        "Functions" => lambda {|it| format_boolean it['hasFunctions'] },
        "Jobs" => lambda {|it| format_boolean it['hasJobs'] },
        "Discovery" => lambda {|it| format_boolean it['hasDiscovery'] },
        "Cloud Init" => lambda {|it| format_boolean it['hasCloudInit'] },
        "Folders" => lambda {|it| format_boolean it['hasFolders'] },
        # "Marketplace" => lambda {|it| format_boolean it['hasMarketplace'] },
        "Public Cloud" => lambda {|it| format_boolean(it['cloud'] == 'public') },
      }
      print_description_list(columns, cloud_type, options)
      # Option Types
      option_types = cloud_type['optionTypes']
      if option_types && option_types.size > 0
        print_h2 "Option Types", options
        print format_option_types_table(option_types, options, "zone")
      end
      print reset,"\n"
    end
  end

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for a cloud." + "\n" +
                    "[cloud] is required. This is the name or id of a cloud."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?


      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.wiki(cloud["id"], params)
        return
      end
      json_response = @clouds_interface.wiki(cloud["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Cloud Wiki Page: #{cloud['name']}"
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
      opts.footer = "View cloud wiki page in a web browser" + "\n" +
                    "[cloud] is required. This is the name or id of a cloud."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/clouds/#{cloud['id']}#!wiki"

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
      opts.banner = subcommand_usage("[cloud] [options]")
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
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
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
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update_wiki(cloud["id"], payload)
        return
      end
      json_response = @clouds_interface.update_wiki(cloud["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for cloud #{cloud['name']}"
        wiki([cloud['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_logo(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [file]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update the logo for a cloud.
[name] is required. This is the name or id of a cloud.
[file] is required. This is the path of the logo file
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    layout_id = args[0]
    filename = args[1]
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      logo_file = nil
      if filename == 'null'
        logo_file = 'null' # clear it
      else
        filename = File.expand_path(filename)
        if !File.exist?(filename)
          print_red_alert "File not found: #{filename}"
          exit 1
        end
        logo_file = File.new(filename, 'rb')
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update_logo(cloud['id'], logo_file)
        return
      end
      json_response = @clouds_interface.update_logo(cloud['id'], logo_file)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end
      print_green_success "Updated cloud #{cloud['name']} logo"
      _get(cloud['id'], params, options)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_dark_logo(args)
    options = {}
    params = {}
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [file]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update the logo for a cloud.
[name] is required. This is the name or id of a cloud.
[file] is required. This is the path of the dark logo file
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    layout_id = args[0]
    filename = args[1]
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      dark_logo_file = nil
      if filename == 'null'
        dark_logo_file = 'null' # clear it
      else
        filename = File.expand_path(filename)
        if !File.exist?(filename)
          print_red_alert "File not found: #{filename}"
          exit 1
        end
        dark_logo_file = File.new(filename, 'rb')
      end
      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update_logo(cloud['id'], nil, dark_logo_file)
        return
      end
      json_response = @clouds_interface.update_logo(cloud['id'], nil, dark_logo_file)
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end
      print_green_success "Updated cloud #{cloud['name']} dark logo"
      _get(cloud['id'], params, options)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_affinity_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cloud]")
      build_standard_list_options(opts, options)
      opts.footer = "List affinity groups for a cloud.\n" +
          "[cloud] is required. This is the name or id of an existing cloud."
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    cloud = find_cloud_by_name_or_id(args[0])
    return 1 if cloud.nil?
    params = {}
    params.merge!(parse_list_options(options))
    json_response = @clouds_interface.list_affinity_groups(cloud['id'], params)
    render_response(json_response, options, 'affinityGroups') do
      affinity_groups = json_response['affinityGroups']
      print_h1 "Morpheus Cloud Affinity Groups: #{cloud['name']}", parse_list_subtitles(options)
      if affinity_groups.empty?
        print cyan,"No affinity groups found.",reset,"\n"
      else          
        columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| format_affinity_type(it['affinityType']) },
          "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          # "Servers" => lambda {|it| it['serverCount'] },
          # "Source" => lambda {|it| it['source'] },
        }.upcase_keys!
        print as_pretty_table(affinity_groups, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cloud] [affinity group]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a cloud affinity group.\n" +
          "[cloud] is required. This is the name or id of an existing cloud.\n" +
          "[affinity group] is required. This is the name or id of an existing affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)

    cloud = find_cloud_by_name_or_id(args[0])
    return 1 if cloud.nil?
    # this finds the affinity group in the cloud api response, then fetches it by ID
    affinity_group = find_cloud_affinity_group_by_name_or_id(cloud['id'], args[1])
    if affinity_group.nil?
      print_red_alert "Affinity Group not found for '#{args[1]}'"
      exit 1
    end

    params = {}
    params.merge!(parse_query_options(options))
    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.get_affinity_group(cloud['id'], affinity_group['id'], params)
      return
    end
    json_response = @clouds_interface.get_affinity_group(cloud['id'], affinity_group['id'], params)
    render_response(json_response, options, 'affinityGroup') do
      affinity_group = json_response['affinityGroup']
      print_h1 "Affinity Group Details", [], options
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| format_affinity_type(it['affinityType']) },
        "Resource Pool" => lambda {|it| it['pool'] ? (it['pool']['name'] || it['pool']['id']) : '' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Servers" => lambda {|it| it['servers'].size() },
        "Source" => lambda {|it| it['source'] },
        "Active" => lambda {|it| format_boolean(it['active']) },
      }
      print_description_list(columns, affinity_group)
      if affinity_group['servers'].size > 0
        print_h2 "Servers", options
        print as_pretty_table(affinity_group['servers'], [:id, :name], options)
      end
      print reset,"\n"
    end
    return 0, nil
      
  end

  def add_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cloud] [name] [options]")
      build_option_type_options(opts, options, add_cloud_affinity_group_option_types)
      add_perms_options(opts, options, ['plans'])
      build_standard_add_options(opts, options)
      opts.footer = "Add affinity group to a cloud.\n" +
        "[cloud] is required. This is the name or id of an existing cloud.\n" +
        "[name] is required. This is the name of the new affinity group."
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:2)
    connect(options)

    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      if args[1]
        options[:options]['name']  = args[1]
      end
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload ||= {}
          payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        options[:params] ||= {}
        options[:params].merge!({:cloudId => cloud['id'],:zoneId => cloud['id']})
        option_types = add_cloud_affinity_group_option_types
        affinity_group = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client, options[:params])

        # affinity_group_type = find_affinity_group_type_by_code(affinity_group['affinityGroupType'])
        # affinity_group['affinityGroupType'] = {id:affinity_group_type['id']}

        # # affinity_group type options
        # unless affinity_group_type['optionTypes'].empty?
        #   affinity_group.merge!(Morpheus::Cli::OptionTypes.prompt(affinity_group_type['optionTypes'], options[:options].deep_merge({:context_map => {'domain' => ''}, :checkbox_as_boolean => true}), @api_client, options[:params]))
        # end

        # perms
        perms = prompt_permissions(options, is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])

        affinity_group['resourcePermissions'] = perms['resourcePermissions'] unless perms['resourcePermissions'].empty?
        affinity_group['tenants'] = perms['tenantPermissions'] unless perms['tenantPermissions'].empty? || perms['tenantPermissions']['accounts'].empty?
        affinity_group['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        payload = {'affinityGroup' => affinity_group}
      end

      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.create_affinity_group(cloud['id'], payload)
        return
      end
      json_response = @clouds_interface.create_affinity_group(cloud['id'], payload)
      if options[:json]
        puts as_json(json_response)
      else
        if json_response['success']
          if json_response['msg'] == nil
            print_green_success "Adding affinity group to cloud #{cloud['name']}"
          else
            print_green_success json_response['msg']
          end
          execution_id = json_response['executionId']
          if !options[:no_refresh] && execution_id
            wait_for_execution_request(json_response['executionId'], options.merge({waiting_status:['new', 'pending', 'executing']}))
          end
        else
          print_red_alert "Failed to create cloud affinity group #{json_response['msg']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_affinity_group(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[cloud] [affinity group] [options]")
      build_option_type_options(opts, options, update_cloud_affinity_group_option_types)
      add_perms_options(opts, options, ['plans'])
      build_standard_update_options(opts, options)
      opts.footer = "Update a cloud affinity group.\n" +
          "[cloud] is required. This is the name or id of an existing cloud.\n" +
          "[affinity group] is required. This is the name or id of an existing affinity group."
    end

    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      affinity_group = find_cloud_affinity_group_by_name_or_id(cloud['id'], args[1])
      if affinity_group.nil?
        print_red_alert "Affinity Group not found by '#{args[1]}'"
        exit 1
      end
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'affinityGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) }})
        end
      else
        payload = {'affinityGroup' => {}}
        options[:params] ||= {}
        options[:params].merge!({:cloudId => cloud['id'],:zoneId => cloud['id']})
        option_types = update_cloud_affinity_group_option_types
        v_prompt = Morpheus::Cli::OptionTypes.no_prompt(option_types, options[:options], @api_client, options[:params])
        v_prompt.deep_compact!.booleanize!
        payload.deep_merge!({'affinityGroup' => v_prompt})
        
        perms = prompt_permissions(options.merge({:no_prompt => true}), is_master_account ? ['plans'] : ['plans', 'visibility', 'tenants'])
        
        perms_payload = {}
        perms_payload['resourcePermissions'] = perms['resourcePermissions'] if !perms['resourcePermissions'].nil? && !perms['resourcePermissions'].empty?
        perms_payload['tenantPermissions'] = perms['tenantPermissions'] if !perms['tenantPermissions'].nil? && !perms['tenantPermissions']['accounts'].empty?
        
        payload['affinityGroup']['permissions'] = perms_payload if !perms_payload.empty?
        payload['affinityGroup']['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !perms['resourcePool']['visibility'].nil?

        # support -O OPTION switch on top of everything
        if options[:options]
          payload.deep_merge!({'affinityGroup' => options[:options].reject {|k,v| k.is_a?(Symbol) || payload['affinityGroup'].key?(k) }})
        end

        if payload['affinityGroup'].nil? || payload['affinityGroup'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @clouds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update_affinity_group(cloud['id'], affinity_group['id'], payload)
        return
      end
      json_response = @clouds_interface.update_affinity_group(cloud['id'], affinity_group['id'], payload)
      if options[:json]
        puts as_json(json_response)
      elsif !options[:quiet]
        affinity_group = json_response['affinityGroup']
        print_green_success "Updated affinity group #{affinity_group['name']}"
        #get_args = [cloud["id"], affinity_group["id"]] + (options[:remote] ? ["-r",options[:remote]] : [])
        #get_namespace(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_affinity_group(args)
    default_refresh_interval = 5
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [affinity group]")
      # opts.on( '-f', '--force', "Force Delete" ) do
      #   params[:force] = 'on'
      # end
      # opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
      #   options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      # end
      # opts.on(nil, '--no-refresh', "Do not refresh" ) do
      #   options[:no_refresh] = true
      # end
      build_standard_remove_options(opts, options)
      opts.footer = "Delete an affinity group from a cloud.\n" +
        "[cloud] is required. This is the name or id of an existing cloud.\n" +
        "[affinity group] is required. This is the name or id of an existing affinity group."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    params.merge!(parse_query_options(options))

    cloud = find_cloud_by_name_or_id(args[0])
    return 1 if cloud.nil?

    affinity_group_id = args[1]
    if affinity_group_id.empty?
      raise_command_error "missing required worker parameter"
    end

    affinity_group = find_cloud_affinity_group_by_name_or_id(cloud['id'], affinity_group_id)
    if affinity_group.nil?
      print_red_alert "Affinity Group not found for '#{affinity_group_id}'"
      return 1
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the cloud affinity group '#{affinity_group['name'] || affinity_group['id']}'?", options)
      return 9, "aborted command"
    end

    @clouds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clouds_interface.dry.destroy_affinity_group(cloud['id'], affinity_group['id'], params)
      return
    end
    json_response = @clouds_interface.destroy_affinity_group(cloud['id'], affinity_group['id'], params)
    if options[:json]
      puts as_json(json_response)
    else
      if json_response['success']
        print_green_success "Removed affinity group #{affinity_group['name']}"
        execution_id = json_response['executionId']
        if !options[:no_refresh] && execution_id
          wait_for_execution_request(execution_id, options.merge({waiting_status:['new', 'pending', 'executing']}))
        end
      else
        print_red_alert "Failed to remove cloud affinity group #{json_response['msg']}"
      end
    end
    return 0, nil
  end

  private

  def cloud_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['zoneType'] ? it['zoneType']['name'] : '' },
      "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
      "Location" => 'location',
      "Region Code" => lambda {|it| it['regionCode'] },
      "Groups" => lambda {|it| (it['groups'] || []).collect {|g| g.instance_of?(Hash) ? g['name'] : g.to_s }.join(', ') },
      "Servers" => lambda {|it| it['serverCount'] },
      "Status" => lambda {|it| format_cloud_status(it) },
    }
  end

  def add_cloud_option_types(cloud_type)
    # note: Type is selected before this
    tmp_option_types = [
      #{'fieldName' => 'zoneType.code', 'fieldLabel' => 'Image Type', 'type' => 'select', 'selectOptions' => cloud_types_for_dropdown, 'required' => true, 'description' => 'Cloud Type.', 'displayOrder' => 0},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'shorthand' => '-l', 'optionalValue' => true, 'fieldName' => 'labels', 'fieldLabel' => 'Labels', 'type' => 'text', 'required' => false, 'processValue' => lambda {|val| parse_labels(val) }, 'displayOrder' => 3},
      {'fieldName' => 'location', 'fieldLabel' => 'Location', 'type' => 'text', 'required' => false, 'displayOrder' => 4},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private', 'displayOrder' => 5},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true, 'displayOrder' => 6},
      {'fieldName' => 'autoRecoverPowerState', 'fieldLabel' => 'Automatically Power On VMs', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'displayOrder' => 7}
    ]

    # TODO: Account

    # Details (zoneType.optionTypes)

    if cloud_type && cloud_type['optionTypes'] && cloud_type['code'] != 'standard'
      if !cloud_type['optionTypes'].find {|opt| opt['type'] == 'credential'}
        tmp_option_types << {'fieldName' => 'type', 'fieldLabel' => 'Credentials', 'type' => 'credential', 'optionSource' => 'credentials', 'required' => true, 'defaultValue' => 'local', 'config' => {'credentialTypes' => get_cloud_type_credential_types(cloud_type['code'])}, 'displayOrder' => 7}
        cloud_type['optionTypes'].select {|opt| ['username', 'password', 'serviceUsername', 'servicePassword'].include?(opt['fieldName'])}.each {|opt| opt['localCredential'] = true}
      end
      # adjust displayOrder to put these at the end
      #tmp_option_types = tmp_option_types + cloud_type['optionTypes']
      cloud_type['optionTypes'].each do |opt|
        # temp fix for typo
        opt['optionSource'] = 'credentials' if opt['optionSource'] == 'credentials,'
        tmp_option_types << opt.merge({'displayOrder' => opt['displayOrder'].to_i + 100})
      end
    end

    # TODO:
    # Advanced Options
    ## (a whole bunch needed here)

    # Provisioning Options

    ## PROXY (dropdown)
    ## BYPASS PROXY FOR APPLIANCE URL (checkbox)
    ## USER DATA LINUX (code)

    return tmp_option_types
  end

  def update_cloud_option_types(cloud_type)
    add_cloud_option_types(cloud_type).collect {|it| it['required'] = false; it }
  end

  def cloud_types_for_dropdown
    @clouds_interface.cloud_types({max:1000, shallow:true})['zoneTypes'].select {|it| it['enabled'] }.collect {|it| {'name' => it['name'], 'value' => it['code']} }
  end

  def format_cloud_status(cloud, return_color=cyan)
    out = ""
    status_string = cloud['status']
    if cloud['enabled'] == false
      out << "#{red}DISABLED#{return_color}"
    elsif status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing' || status_string == 'initializing' || status_string == 'removing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{cloud['statusMessage'] ? "#{return_color} - #{cloud['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

  def get_cloud_type_credential_types(cloud_type_code)
    case cloud_type_code
    when "amazon", "alibaba"
      ['access-key-secret']
    when "azure","azurestack"
      ['client-id-secret']
    when "google"
      ['email-private-key']
    when "softlayer"
      ['username-api-key']
    when "digitalocean"
      ['username-api-key']
    else
      ['username-password']
    end
  end

  def find_cloud_affinity_group_by_name_or_id(cloud_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      @clouds_interface.get_affinity_group(cloud_id, val)['affinityGroup'] rescue nil
    else
      @clouds_interface.list_affinity_groups(cloud_id, {name: val})['affinityGroups'][0]
    end
  end

  def add_cloud_affinity_group_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'affinityType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Keep Separate', 'value' => 'KEEP_SEPARATE'}, {'name' => 'Keep Together', 'value' => 'KEEP_TOGETHER'}], 'description' => 'Choose affinity type.', 'required' => true, 'defaultValue' => 'KEEP_SEPARATE'},
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox', 'defaultValue' => true},
      {'fieldName' => 'pool.id', 'fieldLabel' => 'Cluster', 'type' => 'select', 'optionSourceType' => 'vmware', 'optionSource' => 'vmwareZonePoolClusters', 'description' => 'Select cluster for the affinity group.', 'required' => true},
      {'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'description' => 'Select servers to be in the affinity group.'},
    ]
  end

  def update_cloud_affinity_group_option_types
    [
      {'fieldName' => 'active', 'fieldLabel' => 'Active', 'type' => 'checkbox'},
      {'fieldName' => 'servers', 'fieldLabel' => 'Server', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'description' => 'Select servers to be in the affinity group.'},
    ]
  end

  def format_affinity_type(affinity_type)
    affinity_type == "KEEP_SEPARATE" ? "Keep Separate" : "Keep Together"
  end
    
end
