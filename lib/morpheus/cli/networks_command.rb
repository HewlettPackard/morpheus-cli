require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworksCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :networks

  register_subcommands :list, :get, :add, :update, :remove #, :generate_pool
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @networks_interface = @api_client.networks
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--cidr VALUE', String, "Filter by cidr, matches beginning of value.") do |val|
        params['cidr'] = val
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List networks."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @networks_interface.dry.list(params)
        return
      end
      json_response = @networks_interface.list(params)
      networks = json_response["networks"]
      if options[:json]
        puts as_json(json_response, options, "networks")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networks")
        return 0
      elsif options[:csv]
        puts records_as_csv(networks, options)
        return 0
      end
      title = "Morpheus Networks"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if networks.empty?
        print cyan,"No networks found.",reset,"\n"
      else
        rows = networks.collect {|network| 
          row = {
            id: network['id'],
            name: network['name'],
            type: network['type'] ? network['type']['name'] : '',
            cloud: network['zone'] ? network['zone']['name'] : '',
            cidr: network['cidr'],
            pool: network['pool'] ? network['pool']['name'] : '',
            dhcp: network['dhcpServer'] ? 'Yes' : 'No',
            visibility: network['visibility'].to_s.capitalize,
            tenants: network['tenants'] ? network['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
          }
          row
        }
        columns = [:id, :name, :type, :cloud, :cidr, :pool, :dhcp, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network", :n_label => "networks"})
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
      opts.banner = subcommand_usage("[network]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network." + "\n" +
                    "[network] is required. This is the name or id of a network."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @networks_interface.dry.get(args[0].to_i)
        else
          print_dry_run @networks_interface.dry.list({name:args[0]})
        end
        return
      end
      network = find_network_by_name_or_id(args[0])
      return 1 if network.nil?
      json_response = {'network' => network}  # skip redundant request
      # json_response = @networks_interface.get(network['id'])
      network = json_response['network']
      if options[:json]
        puts as_json(json_response, options, "network")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "network")
        return 0
      elsif options[:csv]
        puts records_as_csv([network], options)
        return 0
      end
      print_h1 "Network Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "CIDR" => 'cidr',
        "Gateway" => 'gateway',
        "Netmask" => 'netmask',
        "Subnet" => 'subnetAddress',
        "Primary DNS" => 'dnsPrimary',
        "Secondary DNS" => 'dnsSecondary',
        "Pool" => lambda {|it| it['pool'] ? it['pool']['name'] : '' },
        "DHCP" => lambda {|it| it['dhcpServer'] ? 'Yes' : 'No' },
        "Allow IP Override" => lambda {|it| it['allowStaticOverride'] ? 'Yes' : 'No' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, network)

      if network['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if network['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if network['resourcePermission']['sites']
          network['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          {group: site['name'], default: site['default'] ? 'Yes' : ''}
        end
        columns = [:group, :default]
        print cyan
        print as_pretty_table(rows, columns)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    network_type_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("-t TYPE")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on('-t', '--type ID', "Network Type Name or ID") do |val|
        options['type'] = val
      end
      opts.on('--name VALUE', String, "Name for this network") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of network") do |val|
        options['description'] = val
      end
      opts.on('--gateway VALUE', String, "Gateway") do |val|
        options['gateway'] = val
      end
      opts.on('--dns-primary VALUE', String, "DNS Primary") do |val|
        options['dnsPrimary'] = val
      end
      opts.on('--dns-secondary VALUE', String, "DNS Secondary") do |val|
        options['dnsSecondary'] = val
      end
      opts.on('--cidr VALUE', String, "CIDR") do |val|
        options['cidr'] = val
      end
      opts.on('--vlan-id VALUE', String, "VLAN ID") do |val|
        options['vlanId'] = val.to_i
      end
      opts.on('--pool ID', String, "Network Pool") do |val|
        options['pool'] = val.to_i
      end
      opts.on('--dhcp-server [on|off]', String, "DHCP Server") do |val|
        options['dhcpServer'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--allow-ip-override [on|off]', String, "Allow IP Override") do |val|
        options['allowStaticOverride'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a network") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # support [name] as first argument
      if args[0]
        options['name'] = args[0]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'network' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['network'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Cloud
        cloud = nil
        if options[:cloud]
          cloud = find_cloud_by_name_or_id(options[:cloud])
          # meh, should validate cloud is in the cloudsForNetworks dropdown..
          return 1 if cloud.nil?
        else
          # print_red_alert "Cloud not specified!"
          # exit 1
          cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'cloudsForNetworks', 'required' => true, 'description' => 'Select Cloud.'}],options,@api_client,{})
          cloud_id = cloud_prompt['cloud']
          cloud = find_cloud_by_name_or_id(cloud_id) if cloud_id
          return 1 if cloud.nil?
        end
        payload['network']['zone'] = {'id' => cloud['id']}

        # Network Type
        network_type_id = nil
        api_params = {"network.zone.id" => cloud['id']} #{network:{zone:{id: cloud['id']}}}
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Network Type', 'type' => 'select', 'optionSource' => 'networkTypesForCloud', 'required' => true, 'description' => 'Choose a network type.'}], options, @api_client, api_params)
        network_type_id = v_prompt['type']
        if network_type_id.nil? || network_type_id.to_s.empty?
          print_red_alert "Network Type not found by id '#{options['type']}'"
          return 1
        end
        payload['network']['type'] = {'id' => network_type_id.to_i }

        # Name
        if options['name']
          payload['network']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network.'}], options)
          payload['network']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['network']['description'] = options['description']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of network.'}], options)
          payload['network']['description'] = v_prompt['description']
        end

        # Gateway
        if options['gateway']
          payload['network']['gateway'] = options['gateway']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'gateway', 'fieldLabel' => 'Gateway', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['gateway'] = v_prompt['gateway']
        end

        # DNS Primary
        if options['dnsPrimary']
          payload['network']['dnsPrimary'] = options['dnsPrimary']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dnsPrimary', 'fieldLabel' => 'DNS Primary', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['dnsPrimary'] = v_prompt['dnsPrimary']
        end

        # DNS Secondary
        if options['dnsSecondary']
          payload['network']['dnsSecondary'] = options['dnsSecondary']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dnsSecondary', 'fieldLabel' => 'DNS Secondary', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['dnsSecondary'] = v_prompt['dnsSecondary']
        end

        # CIDR
        if options['cidr']
          payload['network']['cidr'] = options['cidr']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cidr', 'fieldLabel' => 'CIDR', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['cidr'] = v_prompt['cidr']
        end

        # VLAN ID
        if options['vlanId']
          payload['network']['vlanId'] = options['vlanId']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'vlanId', 'fieldLabel' => 'VLAN ID', 'type' => 'number', 'required' => false, 'description' => ''}], options)
          payload['network']['vlanId'] = v_prompt['vlanId']
        end

        # Network Pool
        if options['pool']
          payload['network']['pool'] = options['pool'].to_i
        else
          # todo: select dropdown
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'select', 'optionSource' => 'networkPools', 'required' => false, 'description' => ''}], options, @api_client, {zoneId: cloud['id']})
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['pool'] = v_prompt['pool'].to_i if v_prompt['pool']
        end

        # DHCP Server
        if options['dhcpServer'] != nil
          payload['network']['dhcpServer'] = options['dhcpServer']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dhcpServer', 'fieldLabel' => 'DHCP Server', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          payload['network']['dhcpServer'] = v_prompt['dhcpServer']
        end

        # Allow IP Override
        if options['allowStaticOverride'] != nil
          payload['network']['allowStaticOverride'] = options['allowStaticOverride']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allowStaticOverride', 'fieldLabel' => 'Allow IP Override', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          payload['network']['allowStaticOverride'] = v_prompt['allowStaticOverride']
        end
      
        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['network']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['network']['visibility'] = options['visibility']
        end

      end

      
      if options[:dry_run]
        print_dry_run @networks_interface.dry.create(payload)
        return
      end
      json_response = @networks_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network = json_response['network']
        print_green_success "Added network #{network['name']}"
        get([network['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    # network_type_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network] [options]")
      # opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
      #   options[:cloud] = val
      # end
      # opts.on('-t', '--type ID', "Network Type Name or ID") do |val|
      #   options['type'] = val
      # end
      opts.on('--name VALUE', String, "Name for this network") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of network") do |val|
        options['description'] = val
      end
      opts.on('--gateway VALUE', String, "Gateway") do |val|
        options['gateway'] = val
      end
      opts.on('--dns-primary VALUE', String, "DNS Primary") do |val|
        options['dnsPrimary'] = val
      end
      opts.on('--dns-secondary VALUE', String, "DNS Secondary") do |val|
        options['dnsSecondary'] = val
      end
      opts.on('--cidr VALUE', String, "CIDR") do |val|
        options['cidr'] = val
      end
      opts.on('--vlan-id VALUE', String, "VLAN ID") do |val|
        options['vlanId'] = val.to_i
      end
      opts.on('--pool ID', String, "Network Pool") do |val|
        options['pool'] = val.to_i
      end
      opts.on('--dhcp-server [on|off]', String, "DHCP Server") do |val|
        options['dhcpServer'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--allow-ip-override [on|off]', String, "Allow IP Override") do |val|
        options['allowStaticOverride'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a network") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network." + "\n" +
                    "[network] is required. This is the id of a network."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network = find_network_by_name_or_id(args[0])
      return 1 if network.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'network' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['network'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # # Cloud
        # cloud = nil
        # if options[:cloud]
        #   cloud = find_cloud_by_name_or_id(options[:cloud])
        #   # meh, should validate cloud is in the cloudsForNetworks dropdown..
        #   return 1 if cloud.nil?
        # else
        #   # print_red_alert "Cloud not specified!"
        #   # exit 1
        #   cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'cloudsForNetworks', 'required' => true, 'description' => 'Select Cloud.'}],options,@api_client,{})
        #   cloud_id = cloud_prompt['cloud']
        #   cloud = find_cloud_by_name_or_id(cloud_id) if cloud_id
        #   return 1 if cloud.nil?
        # end

        # # Network Type
        # network_type_id = nil
        # api_params = {"network.zone.id" => cloud['id']} #{network:{zone:{id: cloud['id']}}}
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Network Type', 'type' => 'select', 'optionSource' => 'networkTypesForCloud', 'required' => true, 'description' => 'Choose a network type.'}], options, @api_client, api_params)
        # network_type_id = v_prompt['type']
        # if network_type_id.nil? || network_type_id.to_s.empty?
        #   print_red_alert "Network Type not found by id '#{options['type']}'"
        #   return 1
        # end
        # payload['network']['type'] = {'id' => network_type_id.to_i }

        # Name
        if options['name']
          payload['network']['name'] = options['name']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network.'}], options)
          # payload['network']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['network']['description'] = options['description']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of network.'}], options)
          # payload['network']['description'] = v_prompt['description']
        end

        # Gateway
        if options['gateway']
          payload['network']['gateway'] = options['gateway']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'gateway', 'fieldLabel' => 'Gateway', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['network']['gateway'] = v_prompt['gateway']
        end

        # DNS Primary
        if options['dnsPrimary']
          payload['network']['dnsPrimary'] = options['dnsPrimary']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dnsPrimary', 'fieldLabel' => 'DNS Primary', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['network']['dnsPrimary'] = v_prompt['dnsPrimary']
        end

        # DNS Secondary
        if options['dnsSecondary']
          payload['network']['dnsSecondary'] = options['dnsSecondary']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dnsSecondary', 'fieldLabel' => 'DNS Secondary', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['network']['dnsSecondary'] = v_prompt['dnsSecondary']
        end

        # CIDR
        if options['cidr']
          payload['network']['cidr'] = options['cidr']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cidr', 'fieldLabel' => 'CIDR', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['network']['cidr'] = v_prompt['cidr']
        end

        # VLAN ID
        if options['vlanId']
          payload['network']['vlanId'] = options['vlanId']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'vlanId', 'fieldLabel' => 'VLAN ID', 'type' => 'number', 'required' => false, 'description' => ''}], options)
          # payload['network']['vlanId'] = v_prompt['vlanId']
        end

        # Network Pool
        if options['pool']
          payload['network']['pool'] = options['pool'].to_i
        else
          # todo: select dropdown
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'select', 'optionSource' => 'networkPools', 'required' => false, 'description' => ''}], options, @api_client, {zoneId: cloud['id']})
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['network']['pool'] = v_prompt['pool'].to_i if v_prompt['pool']
        end

        # DHCP Server
        if options['dhcpServer'] != nil
          payload['network']['dhcpServer'] = options['dhcpServer']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dhcpServer', 'fieldLabel' => 'DHCP Server', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          # payload['network']['dhcpServer'] = v_prompt['dhcpServer']
        end

        # Allow IP Override
        if options['allowStaticOverride'] != nil
          payload['network']['allowStaticOverride'] = options['allowStaticOverride']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allowStaticOverride', 'fieldLabel' => 'Allow IP Override', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          # payload['network']['allowStaticOverride'] = v_prompt['allowStaticOverride']
        end
      
        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['network']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['network']['visibility'] = options['visibility']
        end

      end

      if options[:dry_run]
        print_dry_run @networks_interface.dry.update(network["id"], payload)
        return
      end
      json_response = @networks_interface.update(network["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network = json_response['network']
        print_green_success "Updated network #{network['name']}"
        get([network['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network." + "\n" +
                    "[network] is required. This is the name or id of a network."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network = find_network_by_name_or_id(args[0])
      return 1 if network.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network: #{network['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @networks_interface.dry.destroy(network['id'])
        return 0
      end
      json_response = @networks_interface.destroy(network['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network #{network['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


 def find_network_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_by_id(val)
    else
      return find_network_by_name(val)
    end
  end

  def find_network_by_id(id)
    begin
      json_response = @networks_interface.get(id.to_i)
      return json_response['network']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_by_name(name)
    json_response = @networks_interface.list({name: name.to_s})
    networks = json_response['networks']
    if networks.empty?
      print_red_alert "Network not found by name #{name}"
      return nil
    elsif networks.size > 1
      print_red_alert "#{networks.size} networks found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = networks.collect do |network|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      network = networks[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][network['id']]
        network['tenants'] = json_response['tenants'][network['id']]
      end
      return network
    end
  end

end
