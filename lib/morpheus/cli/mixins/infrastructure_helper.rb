require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for infrastructure management
module Morpheus::Cli::InfrastructureHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def groups_interface
    # @api_client.groups
    raise "#{self.class} has not defined @groups_interface" if @groups_interface.nil?
    @groups_interface
  end

  def clouds_interface
    # @api_client.clouds
    raise "#{self.class} has not defined @clouds_interface" if @clouds_interface.nil?
    @clouds_interface
  end

  def networks_interface
    # @api_client.networks
    raise "#{self.class} has not defined @networks_interface" if @networks_interface.nil?
    @networks_interface
  end

  def subnets_interface
    # @api_client.subnets
    raise "#{self.class} has not defined @subnets_interface" if @subnets_interface.nil?
    @subnets_interface
  end

  def network_groups_interface
    # @api_client.network_groups
    raise "#{self.class} has not defined @network_groups_interface" if @network_groups_interface.nil?
    @network_groups_interface
  end

  def resource_pool_groups_interface
    # @api_client.resource_pool_groups
    raise "#{self.class} has not defined @resource_pool_groups_interface" if @resource_pool_groups_interface.nil?
    @resource_pool_groups_interface
  end

  def resource_pools_interface
    # @api_client.resource_pool_groups
    raise "#{self.class} has not defined @cloud_resource_pools_interface" if @cloud_resource_pools_interface.nil?
    @cloud_resource_pools_interface
  end

  def network_types_interface
    # @api_client.network_types
    raise "#{self.class} has not defined @network_types_interface" if @network_types_interface.nil?
    @network_types_interface
  end
  
  def subnet_types_interface
    # @api_client.subnet_types
    raise "#{self.class} has not defined @subnet_types_interface" if @subnet_types_interface.nil?
    @subnet_types_interface
  end

  def find_group_by_name_or_id(val, include_tenants=true)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_group_by_id(val)
    else
      return find_group_by_name(val, include_tenants)
    end
  end

  def find_group_by_id(id)
    begin
      json_response = groups_interface.get(id.to_i)
      return json_response['group']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Group not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_group_by_name(name, include_tenants=false)
    params = {name: name}
    params['includeTenants'] = true if include_tenants
    groups = groups_interface.list(params)['groups']
    if groups.empty?
      print_red_alert "Group not found by name #{name}"
      exit 1
    elsif groups.size > 1
      print_red_alert "Multiple groups exist with the name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(groups, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      exit 1
    end
    return groups[0]
  end

  def find_cloud_by_name_or_id(val, include_tenants=false)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_cloud_by_id(val)
    else
      return find_cloud_by_name(val, include_tenants)
    end
  end

  def find_cloud_by_id(id)
    json_results = clouds_interface.get(id.to_i)
    if json_results['zone'].empty?
      print_red_alert "Cloud not found by id #{id}"
      exit 1
    end
    cloud = json_results['zone']
    return cloud
  end

  def find_cloud_by_name(name, include_tenants=false)
    params = {name: name}
    params['includeTenants'] = true if include_tenants
    clouds = clouds_interface.list(params)['zones']
    if clouds.empty?
      print_red_alert "Cloud not found by name #{name}"
      exit 1
    elsif clouds.size > 1
      print_red_alert "Multiple clouds exist with the name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(clouds, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      exit 1
    end
    return clouds[0]
  end

  def get_available_cloud_types(refresh=false, params = {})
    if !@available_cloud_types || refresh
      @available_cloud_types = clouds_interface.cloud_types({max:1000}.deep_merge(params))['zoneTypes']
    end
    return @available_cloud_types
  end

  def cloud_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return cloud_type_for_id(val)
    else
      return cloud_type_for_name(val)
    end
  end

  def cloud_type_for_id(id)
    return get_available_cloud_types().find { |z| z['id'].to_i == id.to_i}
  end

  def cloud_type_for_name(name)
    types = get_available_cloud_types(true, {'name' => name})
    return types.find { |z| z['code'].downcase == name.downcase} || types.find { |z| z['name'].downcase == name.downcase}
  end


  # Networks

  def find_network_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_by_id(val)
    else
      return find_network_by_name(val)
    end
  end

  def find_network_by_id(id)
    begin
      json_response = networks_interface.get(id.to_i)
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
    json_response = networks_interface.list({name: name.to_s})
    networks = json_response['networks']
    if networks.empty?
      print_red_alert "Network not found by name #{name}"
      return nil
    elsif networks.size > 1
      print_red_alert "#{networks.size} networks found by name #{name}"
      rows = networks.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
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

  def find_network_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_type_by_id(val)
    else
      return find_network_type_by_name(val)
    end
  end

  def find_network_type_by_id(id)
    begin
      json_response = network_types_interface.get(id.to_i)
      return json_response['networkType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_type_by_name(name)
    json_response = network_types_interface.list({name: name.to_s})
    network_types = json_response['networkTypes']
    if network_types.empty?
      print_red_alert "Network Type not found by name #{name}"
      return network_types
    elsif network_types.size > 1
      print_red_alert "#{network_types.size} network types found by name #{name}"
      rows = network_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_types[0]
    end
  end

  def find_subnet_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_subnet_by_id(val)
    else
      return find_subnet_by_name(val)
    end
  end

  def find_subnet_by_id(id)
    begin
      json_response = subnets_interface.get(id.to_i)
      return json_response['subnet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Subnet not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_subnet_by_name(name)
    json_response = subnets_interface.list({name: name.to_s})
    subnets = json_response['subnets']
    if subnets.empty?
      print_red_alert "Subnet not found by name #{name}"
      return nil
    elsif subnets.size > 1
      print_red_alert "#{subnets.size} subnets found by name #{name}"
      rows = subnets.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return subnets[0]
    end
  end

  def find_subnet_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_subnet_type_by_id(val)
    else
      return find_subnet_type_by_name(val)
    end
  end

  def find_subnet_type_by_id(id)
    begin
      json_response = subnet_types_interface.get(id.to_i)
      return json_response['subnetType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Subnet Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_subnet_type_by_name(name)
    json_response = subnet_types_interface.list({name: name.to_s})
    subnet_types = json_response['subnetTypes']
    if subnet_types.empty?
      print_red_alert "Subnet Type not found by name #{name}"
      return subnet_types
    elsif subnet_types.size > 1
      print_red_alert "#{subnet_types.size} subnet types found by name #{name}"
      rows = subnet_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return subnet_types[0]
    end
  end

  def find_network_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_group_by_id(val)
    else
      return find_network_group_by_name(val)
    end
  end

  def find_network_group_by_id(id)
    begin
      json_response = network_groups_interface.get(id.to_i)
      return json_response['networkGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_group_by_name(name)
    json_response = network_groups_interface.list({name: name.to_s})
    network_groups = json_response['networkGroups']
    if network_groups.empty?
      print_red_alert "Network Group not found by name #{name}"
      return nil
    elsif network_groups.size > 1
      print_red_alert "#{network_groups.size} network groups found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_groups[0]
    end
  end

  def find_resource_pool_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_resource_pool_by_id(val)
    else
      return find_resource_pool_by_name(val)
    end
  end

  def find_resource_pool_by_id(id)
    begin
      json_response = resource_pools_interface.get_without_cloud(id.to_i)
      return json_response['resourcePool']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Resource Pool not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_resource_pool_by_name(name)
    json_response = resource_pools_interface.list_without_cloud({name: name.to_s})
    resource_pools = json_response['resourcePools']
    if resource_pools.empty?
      print_red_alert "Resource Pool not found by name #{name}"
      return nil
    elsif resource_pools.size > 1
      print_red_alert "#{resource_pools.size} resource pools found by name #{name}"
      rows = resource_pools.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return resource_pools[0]
    end
  end

  def find_resource_pool_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_resource_pool_group_by_id(val)
    else
      return find_resource_pool_group_by_name(val)
    end
  end

  def find_resource_pool_group_by_id(id)
    begin
      json_response = resource_pool_groups_interface.get(id.to_i)
      return json_response['resourcePoolGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Resource Pool Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_resource_pool_group_by_name(name)
    json_response = resource_pool_groups_interface.list({name: name.to_s})
    resource_pool_groups = json_response['resourcePoolGroups']
    if resource_pool_groups.empty?
      print_red_alert "Resource Pool Group not found by name #{name}"
      return nil
    elsif resource_pool_groups.size > 1
      print_red_alert "#{resource_pool_groups.size} resource pool groups found by name #{name}"
      rows = resource_pool_groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return resource_pool_groups[0]
    end
  end

  def prompt_for_network(network_id, options={}, required=true, field_name='network', field_label='Network')
    # Prompt for a Network, text input that searches by name or id
    network = nil
    still_prompting = true
    while still_prompting do
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => field_name, 'type' => 'text', 'fieldLabel' => field_label, 'required' => required, 'description' => 'Network name or ID.'}], network_id ? {(field_name) => network_id} : {})
      network_id = v_prompt['network']
      begin
        network = find_network_by_name_or_id(network_id)
      rescue SystemExit => cmdexit
      end
      if options[:no_prompt]
        still_prompting = false
      else
        still_prompting = network ? false : true
      end
      if still_prompting
        network_id = nil
      end
    end
    return {success:!!network, network: network}
  end

  def prompt_for_networks(params, options={}, api_client=nil, api_params={})
    # Networks
    network_list = nil
    network_ids = nil
    still_prompting = true
    if params['networks'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networks', 'type' => 'text', 'fieldLabel' => 'Networks', 'required' => false, 'description' => 'Networks to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['networks'].to_s.empty?
          network_list = v_prompt['networks'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        network_ids = []
        bad_ids = []
        if network_list && network_list.size > 0
          network_list.each do |it|
            found_network = nil
            begin
              found_network = find_network_by_name_or_id(it)
            rescue SystemExit => cmdexit
            end
            if found_network
              network_ids << found_network['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      network_list = params['networks']
      still_prompting = false
      network_ids = []
      bad_ids = []
      if network_list && network_list.size > 0
        network_list.each do |it|
          found_network = nil
          begin
            found_network = find_network_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_network
            network_ids << found_network['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Networks not found: #{bad_ids}"}
      end
    end
    return {success:true, data: network_ids}
  end

  def prompt_for_subnets(params, options={}, api_client=nil, api_params={})
    # todo: make this a generic method now please.
    # Subnets
    record_list = nil
    record_ids = nil
    still_prompting = true
    if params['subnets'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'subnets', 'type' => 'text', 'fieldLabel' => 'Subnets', 'required' => false, 'description' => 'Subnets to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['subnets'].to_s.empty?
          record_list = v_prompt['subnets'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        record_ids = []
        bad_ids = []
        if record_list && record_list.size > 0
          record_list.each do |it|
            found_record = nil
            begin
              found_record = find_subnet_by_name_or_id(it)
            rescue SystemExit => cmdexit
            end
            if found_record
              record_ids << found_record['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      record_list = params['subnets']
      still_prompting = false
      record_ids = []
      bad_ids = []
      if record_list && record_list.size > 0
        record_list.each do |it|
          found_subnet = nil
          begin
            found_subnet = find_subnet_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_subnet
            record_ids << found_subnet['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Subnets not found: #{bad_ids}"}
      end
    end
    return {success:true, data: record_ids}
  end

  def prompt_for_pools(params, options={}, api_client=nil, api_params={})
    # Pools
    pool_list = nil
    pool_ids = nil
    still_prompting = true
    if params['pools'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'pools', 'type' => 'text', 'fieldLabel' => 'Pools', 'required' => false, 'description' => 'Pools to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['pools'].to_s.empty?
          pool_list = v_prompt['pools'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        pool_ids = []
        bad_ids = []
        if pool_list && pool_list.size > 0
          pool_list.each do |it|
            found_pool = nil
            begin
              found_pool = find_resource_pool_by_name_or_id(it) 
            rescue SystemExit => cmdexit
            end
            if found_pool
              pool_ids << found_pool['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      pool_list = params['pools']
      still_prompting = false
      pool_ids = []
      bad_ids = []
      if pool_list && pool_list.size > 0
        pool_list.each do |it|
          found_pool = nil
          begin
            found_pool = find_resource_pool_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_pool
            pool_ids << found_pool['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Pools not found: #{bad_ids}"}
      end
    end
    return {success:true, data: pool_ids}
  end

  def network_pool_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_network_pool_server_status(it) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def network_pool_server_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "App ID" => lambda {|it| it['config'] ? it['config']['appId'] : nil },
      "Credentials" => lambda {|it| it['credential'] ? (it['credential']['type'] == 'local' ? '(Local)' : it['credential']['name']) : nil },
      "Username" => lambda {|it| it['serviceUsername'] },
      "Password" => lambda {|it| it['servicePassword'] },
      "Throttle Rate" => lambda {|it| it['serviceThrottleRate'] },
      "Disable SSL SNI" => lambda {|it| format_boolean it['ignoreSsl'] },
      "Inventory Existing" => lambda {|it| format_boolean(it['config'] ? it['config']['inventoryExisting'] : nil) },
      "IP Mode" => lambda {|it| it['serviceMode'] },
      "Network Filter" => lambda {|it| it['networkFilter'] },
      "Zone Filter" => lambda {|it| it['zoneFilter'] },
      "Tenant Match" => lambda {|it| it['tenantMatch'] },
      "Extra Attributes" => lambda {|it| it['config'] ? it['config']['extraAttributes'] : nil },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_network_pool_server_status(it) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def format_network_pool_server_status(network_pool_server, return_color=cyan)
    out = ""
    status_string = network_pool_server['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{network_pool_server['statusMessage'] ? "#{return_color} - #{network_pool_server['statusMessage']}" : ''}#{return_color}"
    # elsif network_pool_server['enabled'] == false
    #   out << "#{red}DISABLED#{network_pool_server['statusMessage'] ? "#{return_color} - #{network_pool_server['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error' || status_string == 'offline'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{network_pool_server['statusMessage'] ? "#{return_color} - #{network_pool_server['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def network_pool_server_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def network_pool_server_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      # "Integration Code" => 'integrationCode',
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Selectable" => lambda {|it| format_boolean(it['selectable']) },
      "Plugin" => lambda {|it| format_boolean(it['isPlugin']) },
      "Embedded" => lambda {|it| format_boolean(it['isEmbedded']) },
    }
  end

  def find_network_server_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_server_type_by_id(val)
    else
      # always find by code too
      #return find_network_server_type_by_name(val)
      return find_network_server_type_by_name_or_code(val)
    end
  end

  def find_network_server_type_by_id(id)
    begin
      json_response = @network_server_types_interface.get(id.to_i)
      return json_response['networkServerType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Server Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_server_type_by_name(name)
    json_response = @network_server_types_interface.list({name: name.to_s})
    network_server_types = json_response['networkServerTypes']
    if network_server_types.empty?
      print_red_alert "Network Server Type not found by name #{name}"
      return nil
    elsif network_server_types.size > 1
      print_red_alert "#{network_server_types.size} network server types found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_server_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :code, :name], {color:red})
      return nil
    else
      return network_server_types[0]
    end
  end

  def find_network_server_type_by_name_or_code(name)
    json_response = @network_server_types_interface.list({phrase: name.to_s, max: 100})
    downcase_name = name.to_s.downcase
    network_server_types = json_response['networkServerTypes'].select { |it| 
        it['code'].to_s.downcase == downcase_name || it['name'].to_s.downcase == downcase_name 
    }
    if network_server_types.empty?
      print_red_alert "Network Server Type not found by name or code '#{name}'"
      return nil
    elsif network_server_types.size > 1
      print_red_alert "#{network_server_types.size} network server types found with name or code '#{name}'"
      # print_networks_table(networks, {color: red})
      rows = network_server_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :code, :name], {color:red})
      return nil
    else
      return network_server_types[0]
    end
  end

  def network_server_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) }
    }
  end

  def network_server_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Selectable" => lambda {|it| format_boolean(it['selectable']) },
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
      "Plugin" => lambda {|it| format_boolean(it['isPlugin']) },
      "Embedded" => lambda {|it| format_boolean(it['isEmbedded']) },
      #"Integration Code" => lambda {|it| it['integrationCode'] },
      "Networks" => lambda {|it| format_boolean(it['hasNetworks']) },
      "Gateways" => lambda {|it| format_boolean(it['hasGateways']) },
      "DHCP Servers" => lambda {|it| format_boolean(it['hasDhcpServers']) },
      "DHCP Relays" => lambda {|it| format_boolean(it['hasDhcpRelays']) },
      # "Route Tables" => lambda {|it| format_boolean(it['hasRouteTables']) },
      "Routers" => lambda {|it| format_boolean(it['hasRouters']) },
      "Switches" => lambda {|it| format_boolean(it['hasSwitches']) },
      "Firewall" => lambda {|it| format_boolean(it['hasFirewall']) },
      "Security Groups" => lambda {|it| format_boolean(it['hasSecurityGroups']) },
      "Load Balancers" => lambda {|it| format_boolean(it['hasLoadBalancers']) },
      "Floating Ips" => lambda {|it| format_boolean it['hasFloatingIps']},
      # "Security Code" => lambda {|it| it['securityCode'] },
      # "User Visible" => lambda {|it| format_boolean(it['userVisible']) },
    }
  end

end
