require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworksCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :networks

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'types' => :list_types
  register_subcommands :'get-type' => :get_type

  #register_subcommands :list_subnets, # :get_subnet, :add_subnet, :update_subnet, :remove_subnet
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @networks_interface = @api_client.networks
    @network_types_interface = @api_client.network_types
    @subnets_interface = @api_client.subnets
    @subnet_types_interface = @api_client.subnet_types
    @groups_interface = @api_client.groups
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
      opts.on( '-c', '--cloud CLOUD', "Filter by Cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on('--cidr VALUE', String, "Filter by cidr, matches beginning of value.") do |val|
        params['cidr'] = val
      end
      opts.on('-a', '--all', "Display all data, including subnets.") do
        options[:show_subnets] = true
      end
      opts.on('--subnets', '--subnets', "Display subnets as rows under each network found.") do
        options[:show_subnets] = true
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List networks."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      cloud = nil
      if options[:cloud]
        cloud = find_cloud_by_name_or_id(options[:cloud])
        return 1 if cloud.nil?
        params['zoneId'] = cloud['id']
      end
      @networks_interface.setopts(options)
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
      if cloud
        subtitles << "Cloud: #{cloud['id']}"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if networks.empty?
        print cyan,"No networks found.",reset,"\n"
      else
        rows = []
        networks.each do |network|
          row = {
            id: network['id'],
            name: network['name'],
            type: network['type'] ? network['type']['name'] : '',
            group: network['group'] ? network['group']['name'] : 'Shared',
            cloud: network['zone'] ? network['zone']['name'] : '',
            cidr: network['cidr'],
            pool: network['pool'] ? network['pool']['name'] : '',
            dhcp: network['dhcpServer'] ? 'Yes' : 'No',
            subnets: (network['subnets'].size rescue 'n/a'),
            visibility: network['visibility'].to_s.capitalize,
            active: format_boolean(network['active']),
            tenants: network['tenants'] ? network['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
          }
          rows << row
          if network['subnets'] && network['subnets'].size() > 0 && options[:show_subnets]
            network['subnets'].each do |subnet|
              subnet_row = {
                id: subnet['id'],
                name: "  #{subnet['name']}",
                # type: subnet['type'] ? subnet['type']['name'] : '',
                type: "Subnet",
                group: network['group'] ? network['group']['name'] : 'Shared',
                cloud: network['zone'] ? network['zone']['name'] : '',
                cidr: subnet['cidr'],
                pool: subnet['pool'] ? subnet['pool']['name'] : '',
                dhcp: subnet['dhcpServer'] ? 'Yes' : 'No',
                visibility: subnet['visibility'].to_s.capitalize,
                active: format_boolean(network['active']),
                tenants: subnet['tenants'] ? subnet['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
              }
              rows << subnet_row
            end
          end
        end
        columns = [:id, :name, :type, :group, :cloud, :cidr, :pool, :dhcp, :subnets, :active, :visibility, :tenants]
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
      @networks_interface.setopts(options)
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
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : 'Shared' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "CIDR" => 'cidr',
        "Gateway" => 'gateway',
        "Netmask" => 'netmask',
        "Subnet" => 'subnetAddress',
        "Primary DNS" => 'dnsPrimary',
        "Secondary DNS" => 'dnsSecondary',
        "Pool" => lambda {|it| it['pool'] ? it['pool']['name'] : '' },
        "VPC" => lambda {|it| it['zonePool'] ? it['zonePool']['name'] : '' },
        "DHCP" => lambda {|it| it['dhcpServer'] ? 'Yes' : 'No' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Allow IP Override" => lambda {|it| it['allowStaticOverride'] ? 'Yes' : 'No' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
      }
      print_description_list(description_cols, network)

      if network["group"]
        # Group Access is n/a unless network is_a? Shared (no group)
      elsif network['resourcePermission'].nil?
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

      # if options[:show_subnets]
      # subnets data is limited, use /networks/:id/subnets to fetch it all.
      subnets = network['subnets']
      if subnets and subnets.size > 0
        print_h2 "Subnets", options
        rows = []
        subnet_rows = subnets.collect { |subnet|
          {
            id: subnet['id'],
            name: "  #{subnet['name']}",
            # type: subnet['type'] ? subnet['type']['name'] : '',
            type: "Subnet",
            cloud: network['zone'] ? network['zone']['name'] : '',
            cidr: subnet['cidr'],
            pool: subnet['pool'] ? subnet['pool']['name'] : '',
            dhcp: subnet['dhcpServer'] ? 'Yes' : 'No',
            visibility: subnet['visibility'].to_s.capitalize,
            active: format_boolean(subnet['active']),
            tenants: subnet['tenants'] ? subnet['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
          }
        }
        columns = [:id, :name, :cidr, :dhcp, :active, :visibility]
        print cyan
        print as_pretty_table(subnet_rows, columns, options)
        print reset
        print_results_pagination({'meta'=>{'total'=>subnet_rows.size,'size'=>subnet_rows.size}}, {:label => "subnet", :n_label => "subnets"})
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
      opts.on( '-g', '--group GROUP', "Group Name or ID. Default is Shared." ) do |val|
        options[:group] = val
      end
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
        options['dhcpServer'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--allow-ip-override [on|off]', String, "Allow IP Override") do |val|
        options['allowStaticOverride'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--domain VALUE', String, "Network Domain ID") do |val|
        options['domain'] = val
      end
      opts.on('--scan [on|off]', String, "Scan Network") do |val|
        options['scanNetwork'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--proxy VALUE', String, "Network Proxy ID") do |val|
        options['proxy'] = val
      end
      opts.on('--proxy-bypass [on|off]', String, "Bypass Proxy for Appliance URL") do |val|
        options['applianceUrlProxyBypass'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--no-proxy LIST', String, "No Proxy Addresses") do |val|
        options['noProxy'] = val
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
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

        # Group
        group = nil
        if options[:group]
          group = find_group_by_name_or_id(options[:group])
          return 1 if group.nil?
        else
          group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'optionSource' => 'groups', 'required' => false, 'description' => 'Select Group.'}],options,@api_client,{})
          group_id = group_prompt['group']
          if group_id.to_s != '' && group_id.to_s != 'shared'
            group = find_group_by_name_or_id(group_id)
            return 1 if group.nil?
          end
        end
        if group
          payload['network']['site'] = {'id' => group['id']}
        else
          # shared
        end

        # Cloud
        cloud = nil
        if group
          if options[:cloud]
            cloud = group["clouds"].find {|it| it["id"].to_s == options[:cloud].to_s || it["name"].to_s == options[:cloud]}
            if cloud.nil?
              print_red_alert "Cloud not found by id #{id}"
              return 1
            end
          else
            api_params = {groupId:group['id']}
            cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'cloudsForNetworks', 'required' => true, 'description' => 'Select Cloud.'}],options,@api_client,api_params)
            cloud_id = cloud_prompt['cloud']
            cloud = find_cloud_by_name_or_id(cloud_id) if cloud_id
            return 1 if cloud.nil?
          end
        else
          if options[:cloud]
            cloud = find_cloud_by_name_or_id(options[:cloud])
            # meh, should validate cloud is in the cloudsForNetworks dropdown..
            return 1 if cloud.nil?
          else
            api_params = {}
            cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'cloudsForNetworks', 'required' => true, 'description' => 'Select Cloud.'}],options,@api_client,api_params)
            cloud_id = cloud_prompt['cloud']
            cloud = find_cloud_by_name_or_id(cloud_id) if cloud_id
            return 1 if cloud.nil?
          end
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

        network_type = nil
        json_response = @network_types_interface.get(network_type_id)
        if json_response["networkType"]
          network_type = json_response["networkType"]
        else
          print_red_alert "Network Type not found by id '#{network_type_id}'"
          return 1
        end
        network_type_option_types = network_type['optionTypes']
        if network_type_option_types && network_type_option_types.size > 0
          # prompt for option types
          # JD: 3.6.2 has fieldContext: 'domain' , which is wrong
          network_type_option_types.each do |option_type|
            # if option_type['fieldContext'] == 'domain'
            #   option_type['fieldContext'] = 'network'
            # end
            #option_type['fieldContext'] = nil
          end
          network_type_params = Morpheus::Cli::OptionTypes.prompt(network_type_option_types,options[:options],@api_client, {zoneId: cloud['id']})
          # network context options belong at network level and not network.network
          network_context_params = network_type_params.delete('network')
          payload['network'].deep_merge!(network_context_params) if network_context_params
          payload['network'].deep_merge!(network_type_params)

        #todo: special handling of type: 'aciVxlan'

        else
          # DEFAULT INPUTS

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

        end

        ## IPAM Options

        # Network Pool
        if options['pool']
          payload['network']['pool'] = options['pool'].to_i
        else
          # todo: select dropdown
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'select', 'optionSource' => 'networkPools', 'required' => false, 'description' => ''}], options, @api_client, {zoneId: cloud['id']})
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pool', 'fieldLabel' => 'Network Pool', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['network']['pool'] = v_prompt['pool'].to_i if v_prompt['pool']
        end
        
        ## Advanced Options

        # Network Domain
        if options['domain']
          payload['network']['networkDomain'] = {'id' => options['domain'].to_i}
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'domain', 'fieldLabel' => 'Network Domain', 'type' => 'select', 'optionSource' => 'networkDomains', 'required' => false, 'description' => ''}], options, @api_client)
          payload['network']['networkDomain'] = {'id' => v_prompt['domain'].to_i} unless v_prompt['domain'].to_s.empty?
        end

        # Scan Network
        if options['scanNetwork'] != nil
          payload['network']['scanNetwork'] = options['scanNetwork']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scanNetwork', 'fieldLabel' => 'Scan Network', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => false}], options)
          payload['network']['scanNetwork'] = v_prompt['scanNetwork']
        end

        # Proxy
        if options['networkProxy']
          payload['network']['networkProxy'] = {'id' => options['networkProxy'].to_i}
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkProxy', 'fieldLabel' => 'Network Proxy', 'type' => 'select', 'optionSource' => 'networkProxies', 'required' => false, 'description' => ''}], options, @api_client)
          payload['network']['networkProxy'] = {'id' => v_prompt['networkProxy'].to_i} unless v_prompt['networkProxy'].to_s.empty?
        end

        # ByPass Proxy for Appliance URL 
        if options['applianceUrlProxyBypass'] != nil
          payload['network']['applianceUrlProxyBypass'] = options['applianceUrlProxyBypass']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'applianceUrlProxyBypass', 'fieldLabel' => 'Bypass Proxy for Appliance URL', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => true}], options)
          payload['network']['applianceUrlProxyBypass'] = v_prompt['applianceUrlProxyBypass']
        end

        # No Proxy
        if options['noProxy']
          payload['network']['noProxy'] = options['noProxy']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'noProxy', 'fieldLabel' => 'No Proxy', 'type' => 'text', 'required' => false, 'description' => 'List of ip addresses or name servers to exclude proxy traversal for. Typically locally routable servers are excluded.'}], options)
          payload['network']['noProxy'] = v_prompt['noProxy']
        end

        # Group Access
        # Group Access (default is All)
        if group_access_all.nil?
          if payload['resourcePermissions'].nil?
            payload['resourcePermissions'] ||= {}
            payload['resourcePermissions']['all'] = true
          end
        else
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

      @networks_interface.setopts(options)
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
        get_args = [network['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        get(get_args)
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
        options['dhcpServer'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--allow-ip-override [on|off]', String, "Allow IP Override") do |val|
        options['allowStaticOverride'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--domain VALUE', String, "Network Domain ID") do |val|
        options['domain'] = val
      end
      opts.on('--scan [on|off]', String, "Scan Network") do |val|
        options['scanNetwork'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--proxy VALUE', String, "Network Proxy ID") do |val|
        options['proxy'] = val
      end
      opts.on('--proxy-bypass [on|off]', String, "Bypass Proxy for Appliance URL") do |val|
        options['applianceUrlProxyBypass'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--no-proxy LIST', String, "No Proxy Addresses") do |val|
        options['noProxy'] = val
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
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
        
        # Network Domain
        if options['domain']
          payload['network']['networkDomain'] = {'id' => options['domain'].to_i}
        else
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'domain', 'fieldLabel' => 'Network Domain', 'type' => 'select', 'optionSource' => 'networkDomains', 'required' => false, 'description' => ''}], options, @api_client)
          #payload['network']['networkDomain'] = {'id' => v_prompt['domain'].to_i} unless v_prompt['domain'].to_s.empty?
        end

        # Scan Network
        if options['scanNetwork'] != nil
          payload['network']['scanNetwork'] = options['scanNetwork']
        else
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scanNetwork', 'fieldLabel' => 'Scan Network', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => false}], options)
          #payload['network']['scanNetwork'] = v_prompt['scanNetwork']
        end

        # Proxy
        if options['networkProxy']
          payload['network']['networkProxy'] = {'id' => options['networkProxy'].to_i}
        else
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkProxy', 'fieldLabel' => 'Network Proxy', 'type' => 'select', 'optionSource' => 'networkProxies', 'required' => false, 'description' => ''}], options, @api_client)
          #payload['network']['networkProxy'] = {'id' => v_prompt['networkProxy'].to_i} unless v_prompt['networkProxy'].to_s.empty?
        end

        # ByPass Proxy for Appliance URL 
        if options['applianceUrlProxyBypass'] != nil
          payload['network']['applianceUrlProxyBypass'] = options['applianceUrlProxyBypass']
        else
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'applianceUrlProxyBypass', 'fieldLabel' => 'Bypass Proxy for Appliance URL', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => true}], options)
          #payload['network']['applianceUrlProxyBypass'] = v_prompt['applianceUrlProxyBypass']
        end

        # No Proxy
        if options['noProxy']
          payload['network']['noProxy'] = options['noProxy']
        else
          #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'noProxy', 'fieldLabel' => 'No Proxy', 'type' => 'text', 'required' => false, 'description' => 'List of ip addresses or name servers to exclude proxy traversal for. Typically locally routable servers are excluded.'}], options)
          #payload['network']['noProxy'] = v_prompt['noProxy']
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
      @networks_interface.setopts(options)
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
        get_args = [network['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        get(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.on( '-f', '--force', "Force Delete" ) do
        params[:force] = 'true'
      end
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
      @networks_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @networks_interface.dry.destroy(network['id'], params)
        return 0
      end
      json_response = @networks_interface.destroy(network['id'], params)
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

  def list_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:cloud]
        #return network_types_for_cloud(options[:cloud], options)
        zone = find_zone_by_name_or_id(nil, options[:cloud])
        #params["zoneTypeId"] = zone['zoneTypeId']
        params["zoneId"] = zone['id']
        params["creatable"] = true
      end
      @network_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_types_interface.dry.list(params)
        return
      end
      json_response = @network_types_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'networkTypes')
      return 0 if render_result

      network_types = json_response['networkTypes']

      title = "Morpheus Network Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if options[:cloud]
        subtitles << "Cloud: #{options[:cloud]}"
      end
      print_h1 title, subtitles
      if network_types.empty?
        print cyan,"No network types found.",reset,"\n"
      else
        rows = network_types.collect do |network_type|
          {
            id: network_type['id'],
            code: network_type['code'],
            name: network_type['name']
          }
        end
        columns = [:id, :name, :code]
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

  def get_type(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network type.\n" +
                    "[type] is required. This is the id or name of a network type."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      @network_types_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_types_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_types_interface.dry.list({name:args[0]})
        end
        return
      end

      network_type = find_network_type_by_name_or_id(args[0])
      return 1 if network_type.nil?
      json_response = {'networkType' => network_type}  # skip redundant request
      # json_response = @networks_interface.get(network_type['id'])
      
      render_result = render_with_format(json_response, options, 'networkType')
      return 0 if render_result

      network_type = json_response['networkType']

      title = "Morpheus Network Type"
      
      print_h1 "Morpheus Network Type", [], options
      
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'name',
        "Description" => 'description',
        # lots more here
        "Createable" => lambda {|it| format_boolean(it['creatable']) },
        "Deletable" => lambda {|it| format_boolean(it['deleteable']) },
      }
      print_description_list(description_cols, network_type)


      option_types = network_type['optionTypes'] || []
      option_types = option_types.sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      if !option_types.empty?
        print_h2 "Config Option Types", [], options
        option_type_cols = {
          "Name" => lambda {|it| it['fieldContext'].to_s != '' ? "#{it['fieldContext']}.#{it['fieldName']}" : it['fieldName'] },
          "Label" => lambda {|it| it['fieldLabel'] },
          "Type" => lambda {|it| it['type'] },
        }
        print cyan
        print as_pretty_table(option_types, option_type_cols)
      end
      
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_subnets(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List subnets under a network." + "\n" +
                    "[network] is required. This is the name or id of a network."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network = find_network_by_name_or_id(args[0])
      return 1 if network.nil?
      params['networkId'] = network['id']
      params.merge!(parse_list_options(options))
      @subnets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnets_interface.dry.list(params)
        return
      end
      json_response = @subnets_interface.list(params)
      subnets = json_response["subnets"]
      if options[:json]
        puts as_json(json_response, options, "subnets")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "subnets")
        return 0
      elsif options[:csv]
        puts records_as_csv(subnets, options)
        return 0
      end
      title = "Morpheus Subnets"
      subtitles = []
      subtitles << "Network: #{network['name']}"
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      
      if subnets.empty?
        print cyan,"No subnets found.",reset,"\n"
      else
        subnet_columns = {
          "ID" => 'id',
          "Name" => 'name',
          #"Description" => 'description',
          "Type" => lambda {|it| it['type']['name'] rescue it['type'] },
          "CIDR" => lambda {|it| it['cidr'] },
          "Active" => lambda {|it| format_boolean(it['active']) },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        }
        print cyan
        print as_pretty_table(subnets, subnet_columns)
      end
      print reset,"\n"
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

end
