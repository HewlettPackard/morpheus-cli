require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
# Mixin for Morpheus::Cli command classes
# Provides common methods for provisioning instances
module Morpheus::Cli::ProvisioningHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def api_client
    raise "#{self.class} has not defined @api_client" if @api_client.nil?
    @api_client
  end

  def instances_interface
    @api_client.instances
  end

  def apps_interface
    @api_client.apps
  end

  def servers_interface
    @api_client.servers
  end

  def options_interface
    @api_client.options
  end

  def instance_types_interface
    @api_client.instance_types
  end

  def instance_type_layouts_interface
    @api_client.library_layouts
  end

  def provision_types_interface
    api_client.provision_types
  end

  def clouds_interface
    @api_client.clouds
  end

  def cloud_datastores_interface
    @api_client.cloud_datastores
  end

  def datastores_interface
    @api_client.datastores
  end

  def accounts_interface
    @api_client.accounts
  end

  def datastores_interface
    @api_client.datastores
  end

  def get_available_groups(params = {}, refresh=false)
    if !@available_groups || refresh
      option_results = options_interface.options_for_source('groups', params)
      @available_groups = option_results['data'].collect {|it|
        {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
      }
    end
    #puts "get_available_groups() rtn: #{@available_groups.inspect}"
    return @available_groups
  end

  def get_available_clouds(group_id, params = {}, refresh=false)
    if !group_id
      option_results = options_interface.options_for_source('clouds', params.merge({'default' => 'false'}))
      return option_results['data'].collect {|it|
        {"id" => it["value"], "name" => it["name"], "value" => it["value"], "zoneTypeId" => it["zoneTypeId"]}
      }
    end
    group = find_group_by_id_for_provisioning(group_id)
    if !group
      return []
    end
    if !group["clouds"] || refresh
      option_results = options_interface.options_for_source('clouds', params.merge({groupId: group_id}))
      group["clouds"] = option_results['data'].collect {|it|
        {"id" => it["value"], "name" => it["name"], "value" => it["value"], "zoneTypeId" => it["zoneTypeId"]}
      }
    end
    return group["clouds"]
  end

  def get_available_accounts(refresh=false)
    if !@available_accounts || refresh
      # @available_accounts = accounts_interface.list()['accounts']
      @available_accounts = options_interface.options_for_source("allTenants", {})['data'].collect {|it|
        {"name" => it["name"], "value" => it["value"], "id" => it["value"]}
      }
    end
    @available_accounts
  end

  def get_available_plans(refresh=false)
    if !@available_plans || refresh
      @available_plans = instances_interface.search_plans['searchPlans'].collect {|it|
        {"name" => it["name"], "value" => it["id"]}
      }
    end
    @available_plans
  end

  def find_group_by_id_for_provisioning(val)
    groups = get_available_groups()
    group = groups.find {|it| it["id"].to_s == val.to_s }
    if !group
      print_red_alert "Group not found by id #{val}"
      exit 1
    end
    return group
  end

  def find_group_by_name_for_provisioning(val)
    groups = get_available_groups()
    group = groups.find {|it| it["name"].to_s.downcase == val.to_s.downcase }
    if !group
      print_red_alert "Group not found by name #{val}"
      exit 1
    end
    return group
  end

  def find_group_by_name_or_id_for_provisioning(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_group_by_id_for_provisioning(val)
    else
      return find_group_by_name_for_provisioning(val)
    end
  end

  def find_cloud_by_id_for_provisioning(group_id, val)
    clouds = get_available_clouds(group_id)
    cloud = clouds.find {|it| it["id"].to_s == val.to_s }
    if !cloud
      print_red_alert "Cloud not found by id #{val}"
      exit 1
    end
    return cloud
  end

  def find_cloud_by_name_for_provisioning(group_id, val)
    clouds = get_available_clouds(group_id)
    cloud = clouds.find {|it| it["name"].to_s.downcase == val.to_s.downcase }
    if !cloud
      print_red_alert "Cloud not found by name #{val}"
      exit 1
    end
    return cloud
  end

  def find_cloud_by_name_or_id_for_provisioning(group_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_cloud_by_id_for_provisioning(group_id, val)
    else
      return find_cloud_by_name_for_provisioning(group_id, val)
    end
  end

  def find_instance_type_by_id(id)
    begin
      json_response = instance_types_interface.get(id.to_i)
      return json_response['instanceType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_instance_type_by_code(code)
    results = instance_types_interface.list({code: code})
    instance_types = results['instanceTypes']
    if instance_types.empty?
      print_red_alert "Instance Type not found by code #{code}"
      return nil
    end
    if instance_types.size() > 1
      print as_pretty_table(instance_types, [:id,:name,:code], {color:red})
      print_red_alert "Try using ID instead"
      return nil
    end
    # return instance_types[0]
    # fetch by ID to get full details
    # could also use ?details-true with search
    return find_instance_type_by_id(instance_types[0]['id'])
  end

  def find_instance_type_by_name(name)
    results = instance_types_interface.list({name: name})
    instance_types = results['instanceTypes']
    if instance_types.empty?
      print_red_alert "Instance Type not found by name #{name}"
      return nil
    end
    if instance_types.size() > 1
      print as_pretty_table(instance_types, [:id,:name,:code], {color:red})
      print_red_alert "Try using ID instead"
      return nil
    end
    # return instance_types[0]
    # fetch by ID to get full details
    # could also use ?details-true with search
    return find_instance_type_by_id(instance_types[0]['id'])
  end

  def find_instance_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_type_by_id(val)
    else
      return find_instance_type_by_name(val)
    end
  end

  def find_instance_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_by_id(val)
    else
      return find_instance_by_name(val)
    end
  end

  def find_instance_by_id(id)
    begin
      json_response = instances_interface.get(id.to_i)
      return json_response['instance']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_instance_by_name(name)
    json_results = instances_interface.list({name: name.to_s})
    if json_results['instances'].empty?
      print_red_alert "Instance not found by name #{name}"
      exit 1
    end
    instance = json_results['instances'][0]
    return instance
  end

  def parse_instance_id_list(id_list)
    parse_id_list(id_list).collect do |instance_id|
      find_instance_by_name_or_id(instance_id)['id']
    end
  end

  ## resources

  # todo: crud and /api/options for resources

  def parse_resource_id_list(id_list)
    parse_id_list(id_list).collect do |resource_id|
      #find_resource_by_name_or_id(resource_id)['id']
      resource_id
    end
  end

  ## apps

  def find_app_by_id(id)
    app_results = apps_interface.get(id.to_i)
    if app_results['app'].empty?
      print_red_alert "App not found by id #{id}"
      exit 1
    end
    return app_results['app']
  end

  def find_app_by_name(name)
    app_results = apps_interface.list({name: name})
    apps = app_results['apps']
    if apps.empty?
      print_red_alert "App not found by name #{name}"
      exit 1
    elsif apps.size > 1
      print_red_alert "#{apps.size} apps exist with the name #{name}. Try using id instead"
      exit 1
    end

    return app_results['apps'][0]
  end

  def find_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_app_by_id(val)
    else
      return find_app_by_name(val)
    end
  end

  ## servers

  def find_server_by_id(id)
    begin
      json_response = servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Server not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_server_by_name(name)
    results = servers_interface.list({name: name})
    if results['servers'].empty?
      print_red_alert "Server not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple Servers exist with the name '#{name}'"
      puts_error as_pretty_table(results['servers'], [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      exit 1
    end
    return results['servers'][0]
  end

  def find_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_server_by_id(val)
    else
      return find_server_by_name(val)
    end
  end

  def parse_server_id_list(id_list)
    parse_id_list(id_list).collect do |server_id|
      find_server_by_name_or_id(server_id)['id']
    end
  end

  ## hosts is the same as servers, just says 'Host' instead of 'Server'

  def find_host_by_id(id)
    begin
      json_response = servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Host not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_host_by_name(name)
    results = servers_interface.list({name: name})
    if results['servers'].empty?
      print_red_alert "Host not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "#{results['servers'].size} hosts exist with the name #{name}. Try using id instead"
      exit 1
    end
    return results['servers'][0]
  end

  def find_host_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_host_by_id(val)
    else
      return find_host_by_name(val)
    end
  end

  def parse_host_id_list(id_list)
    parse_id_list(id_list).collect do |host_id|
      find_host_by_name_or_id(host_id)['id']
    end
  end

  def find_instance_type_layout_by_id(layout_id, id)
    json_results = instance_type_layouts_interface.get(layout_id, id)
    if json_results['instanceTypeLayout'].empty?
      print_red_alert "Instance type layout not found by id #{id}"
      exit 1
    end
    json_results['instanceTypeLayout']
  end

  def find_workflow_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_workflow_by_id(val)
    else
      return find_workflow_by_name(val)
    end
  end

  def find_workflow_by_id(id)
    begin
      json_response = @task_sets_interface.get(id.to_i)
      return json_response['taskSet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Workflow not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_workflow_by_name(name)
    workflows = @task_sets_interface.get({name: name.to_s})['taskSets']
    if workflows.empty?
      print_red_alert "Workflow not found by name #{name}"
      return nil
    elsif workflows.size > 1
      print_red_alert "#{workflows.size} workflows by name #{name}"
      print_workflows_table(workflows, {color: red})
      print reset,"\n\n"
      return nil
    else
      return workflows[0]
    end
  end

  def find_cloud_resource_pool_by_name_or_id(cloud_id, val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cloud_resource_pool_by_id(cloud_id, val) : find_cloud_resource_pool_by_name(cloud_id, val)
  end

  def get_provision_type_for_zone_type(zone_type_id)
    clouds_interface.cloud_type(zone_type_id)['zoneType']['provisionTypes'].first rescue nil
  end

  # prompts user for all the configuartion options for a particular instance
  # returns payload of data for a new instance
  def prompt_new_instance(options={})
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    #puts "prompt_new_instance() #{options}"
    print reset # clear colors
    options[:options] ||= {}
    # provisioning with blueprint can lock fields
    locked_fields = options[:locked_fields] || []
    # Group
    default_group = find_group_by_name_or_id_for_provisioning(options[:default_group] || @active_group_id) if options[:default_group] || @active_group_id

    group_id = nil
    group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
    if group
      group_id = group["id"]
    else
      # print_red_alert "Group not found or specified!"
      # exit 1
      group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => true, 'description' => 'Select Group.', 'defaultValue' => (default_group ? default_group['name'] : nil)}],options[:options],api_client,{})
      group_id = group_prompt['group']
    end

    # Cloud
    cloud_id = nil
    cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
    if cloud
      cloud_id = cloud["id"]
    else
      # print_red_alert "Cloud not specified!"
      # exit 1
      available_clouds = get_available_clouds(group_id)
      cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => get_available_clouds(group_id), 'required' => true, 'description' => 'Select Cloud.', 'defaultValue' => options[:default_cloud] ? options[:default_cloud] : nil}],options[:options],api_client,{groupId: group_id})
      cloud_id = cloud_prompt['cloud']
      cloud = available_clouds.find {|it| it['value'] == cloud_id}
    end

    cloud_type = clouds_interface.cloud_type(cloud['zoneTypeId'])

    # Instance Type
    instance_type_code = nil
    if options[:instance_type_code]
      instance_type_code = options[:instance_type_code]
    else
      instance_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Type', 'optionSource' => 'instanceTypes', 'required' => true, 'description' => 'Select Instance Type.'}],options[:options],api_client,{groupId: group_id, cloudId: cloud_id, restrictProvisionType:true}, no_prompt, true)
      instance_type_code = instance_type_prompt['type']
    end
    if instance_type_code.to_s =~ /\A\d{1,}\Z/
      instance_type = find_instance_type_by_id(instance_type_code)
    else
      instance_type = find_instance_type_by_code(instance_type_code)
    end
    exit 1 if !instance_type

    # Instance Name
    instance_name = nil
    if options[:instance_name]
      options[:options]['name'] = options[:instance_name]
    elsif options[:options]['instance'] && options[:options]['instance']['name']
      options[:options]['name'] = options[:options]['instance']['name']
    end

    while instance_name.nil? do
      name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Instance Name', 'type' => 'text', 'required' => options[:name_required], 'defaultValue' => options[:default_name]}], options[:options])
      name = name_prompt['name']
      if name.nil? && !options[:name_required]
        break
      else
        if instances_interface.list({name: name})['instances'].empty?
          instance_name = name
        else
          print_red_alert "Name must be unique, #{name} already exists"
          options[:options].delete('name')
          exit 1 if no_prompt
          if options[:default_name] == name
            options[:default_name] += '-2'
          end
        end
      end
    end

    # config
    config = {}
=begin
    if cloud_type['code'] == 'amazon' && (cloud['config'] || {})['isVpc'] == 'false' && (cloud['config'] || {})['vpc'] == ''
      config['isEC2'] = true
    else
      config['isEC2'] = false
      if cloud_type['code'] == 'amazon' && (cloud['config'] || {})['isVpc'] == 'true' && (cloud['config'] || {})['vpc'] != ''
        config['isVpcSelectable'] = false
        config['resourcePoolId'] = cloud['config']['vpc']
      else
        config['isVpcSelectable'] = true
      end
    end
=end

    payload = {
      'zoneId' => cloud_id,
      # 'siteId' => siteId,
      'instance' => {
        'name' => instance_name,
        'cloud' => cloud['name'],
        'site' => {
          'id' => group_id
        },
        'type' => instance_type_code,
        'instanceType' => {
          'code' => instance_type_code
        }
      },
      'config' => config
    }

    # allow arbitrary -O values passed by the user
    if options[:options]
      arbitrary_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      # remove some things that are being prompted for
      arbitrary_options.delete('group')
      arbitrary_options.delete('cloud')
      arbitrary_options.delete('type')
      arbitrary_options.delete('name')
      #arbitrary_options.delete('version')
      arbitrary_options.delete('layout')
      arbitrary_options.delete('servicePlan')
      arbitrary_options.delete('description')
      arbitrary_options.delete('environment')
      arbitrary_options.delete('instanceContext')
      arbitrary_options.delete('tags')
      # these are used by prompt_network_interfaces
      arbitrary_options.delete('networkInterface')
      (2..10).each {|i| arbitrary_options.delete('networkInterface' + i.to_s) }
      # these are used by prompt_volumes
      arbitrary_options.delete('rootVolume')
      arbitrary_options.delete('dataVolume')
      (2..10).each {|i| arbitrary_options.delete('dataVolume' + i.to_s) }
      arbitrary_options.delete('lockedFields')
      # arbitrary_options.delete('ports')
      arbitrary_options.delete('marketplacePublisher')
      arbitrary_options.delete('marketplaceOffer')
      arbitrary_options.delete('marketplaceSku')
      arbitrary_options.delete('marketplaceVersion')
      payload.deep_merge!(arbitrary_options)
    end

    # Description
    if options[:description]
      options[:options]['description'] = options[:description]
    end
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'defaultValue' => options[:default_description]}], options[:options])
    payload['instance']['description'] = v_prompt['description'] if !v_prompt['description'].empty?

    # Environment
    if options[:environment]
      options[:options]['environment'] = options[:environment]
    elsif options[:options]['instanceContext'] && !options[:options]['environment']
      options[:options]['environment'] = options[:options]['instanceContext']
    end
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'select', 'required' => false, 'selectOptions' => get_available_environments(), 'defaultValue' => options[:default_environment]}], options[:options])
    payload['instance']['instanceContext'] = v_prompt['environment'] if !v_prompt['environment'].empty?

    # Labels (used to be called tags)
    unless options[:skip_labels_prompt]
      if options[:labels]
        payload['instance']['labels'] = options[:labels].is_a?(Array) ? options[:labels] : options[:labels].to_s.split(',').collect {|it| it.to_s.strip }.compact.uniq
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'labels', 'fieldLabel' => 'Labels', 'type' => 'text', 'required' => false, 'defaultValue' => options[:default_labels]}], options[:options])
        payload['instance']['labels'] = v_prompt['labels'].split(',').collect {|it| it.to_s.strip }.compact.uniq if !v_prompt['labels'].empty?
      end
    end

    # Version and Layout
    layout_id = nil
    if locked_fields.include?('instance.layout.id')
      layout_id = options[:options]['instance']['layout'] rescue  options[:options]['layout']
      if layout_id.is_a?(Hash)
        layout_id = layout_id['id'] || layout_id['code'] || layout_id['name']
      end
    else
      layout_id = nil
      if options[:layout]
        layout_id = options[:layout]
      # elsif options[:options]['layout']
      #   layout_id = options[:options]['layout']
      end
      if layout_id.is_a?(Hash)
        layout_id = layout_id['id'] || layout_id['code'] || layout_id['name']
      end
      if layout_id.nil?
        version_value = nil
        default_layout_value = nil
        if options[:version]
          version_value = options[:version]
        elsif options[:options]['version']
          version_value = options[:options]['version']
        else
          available_versions = options_interface.options_for_source('instanceVersions',{groupId: group_id, cloudId: cloud_id, instanceTypeId: instance_type['id']})['data']
          # filter versions with no layouts.. api should probably do that too eh?
          available_versions.reject! { |available_version| available_version["layouts"].nil? || available_version["layouts"].empty? }
          default_version_value = payload['instance']['version'] ? payload['instance']['version'] : payload['version']
          #default_layout_value = options[:layout]
          if default_layout_value.nil?
            default_layout_value = payload['instance']['layout'] ? payload['instance']['layout'] : payload['layout']
          end
          if default_layout_value && default_layout_value.is_a?(Hash)
            default_layout_value = default_layout_value['id']
          end
          # JD: version is always nil because it is not stored in the blueprint or config !!
          # so for now, infer the version from the layout
          # requires api 3.6.2 to get "layouts" from /options/versions
          if default_layout_value && default_version_value.to_s.empty?
            available_versions.each do |available_version|
              if available_version["layouts"]
                selected_layout = available_version["layouts"].find {|it| it["value"].to_s == default_layout_value.to_s || it["id"].to_s == default_layout_value.to_s || it["code"].to_s == default_layout_value.to_s }
                if selected_layout
                  default_version_value = available_version["value"]
                  break
                end
              end
            end
          end

          # do not require version if a layout is passed
          version_value = default_version_value
          version_is_required = default_layout_value.nil?
          if default_layout_value.nil? && options[:options]["layout"].nil? && options[:always_prompt] != true
            version_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'version', 'type' => 'select', 'fieldLabel' => 'Version', 'selectOptions' => available_versions, 'required' => version_is_required, 'skipSingleOption' => true, 'autoPickOption' => true, 'description' => 'Select which version of the instance type to be provisioned.', 'defaultValue' => default_version_value}],options[:options],api_client,{groupId: group_id, cloudId: cloud_id, instanceTypeId: instance_type['id']})
            version_value = version_prompt['version']
          end
        end
        layout_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'select', 'fieldLabel' => 'Layout', 'optionSource' => 'layoutsForCloud', 'required' => true, 'description' => 'Select which configuration of the instance type to be provisioned.', 'defaultValue' => default_layout_value}],options[:options],api_client,{groupId: group_id, cloudId: cloud_id, instanceTypeId: instance_type['id'], version: version_value, creatable: true}, no_prompt, true)['layout']
      end
    end

    # determine layout and provision_type

    # layout = find_instance_type_layout_by_id(instance_type['id'], layout_id.to_i)
    layout = (instance_type['instanceTypeLayouts'] || []).find {|it| 
      it['id'].to_s == layout_id.to_s || it['code'].to_s == layout_id.to_s || it['name'].to_s == layout_id.to_s
    }
    if !layout
      print_red_alert "Layout not found by id #{layout_id}"
      exit 1
    end
    layout_id = layout['id']
    payload['instance']['layout'] = {'id' => layout['id'], 'code' => layout['code']}

    # need to GET provision type for optionTypes, and other settings...
    provision_type_code = layout['provisionTypeCode'] || layout['provisionType']['code']
    provision_type = nil
    if provision_type_code
      provision_type = provision_types_interface.list({code:provision_type_code})['provisionTypes'][0]
      if provision_type.nil?
        print_red_alert "Provision Type not found by code #{provision_type_code}"
        exit 1
      end
    else
      provision_type = get_provision_type_for_zone_type(cloud['zoneType']['id'])
    end

    # build config option types
    option_type_list = []
    if !layout['optionTypes'].nil? && !layout['optionTypes'].empty?
      option_type_list += layout['optionTypes']
    end
    if !instance_type['optionTypes'].nil? && !instance_type['optionTypes'].empty?
      option_type_list += instance_type['optionTypes']
    end

    api_params = {groupId: group_id, cloudId: cloud_id, zoneId: cloud_id, instanceTypeId: instance_type['id'], version: version_value}

    pool_id = nil
    resource_pool = nil
    service_plan = nil

    prompt_service_plan = -> {
      service_plans_json = instances_interface.service_plans({zoneId: cloud_id, layoutId: layout['id'], siteId: group_id}.merge(resource_pool.nil? ? {} : {'poolId' => resource_pool['id'], 'resourcePoolId' => resource_pool['id']}))
      service_plans = service_plans_json["plans"]
      if locked_fields.include?('plan.id')
        plan_id = options[:options]['plan']['id'] rescue nil
        if plan_id.nil?
          plan_id = options[:options]['instance']['plan']['id'] rescue nil
        end
        service_plan = service_plans.find {|sp| sp['id'] == plan_id }
      else
        service_plan = service_plans.find {|sp| sp['id'] == options[:service_plan].to_i} if options[:service_plan]

        if !service_plan
          service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"], 'code' => sp['code']} } # already sorted
          default_plan = nil
          if payload['plan']
            default_plan = payload['plan']
          elsif payload['instance'] && payload['instance']['plan']
            default_plan = payload['instance']['plan']
          end

          if options[:default_plan] && service_plans_dropdown.find {|sp| [sp["name"], sp["value"].to_s, sp["code"]].include?(options[:default_plan].to_s)}
            default_plan_value = options[:default_plan]
          else
            default_plan_value = options[:default_plan] || (default_plan.is_a?(Hash) ? default_plan['id'] : default_plan)
          end
          plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance', 'defaultValue' => default_plan_value}],options[:options], api_client, {}, no_prompt, true)
          plan_id = plan_prompt['servicePlan']
          service_plan = service_plans.find {|sp| sp["id"] == plan_id.to_i }
          if !service_plan
            print_red_alert "Plan not found by id #{plan_id}"
            exit 1
          end
        end
        #todo: consolidate these, instances api looks for instance.plan.id and apps looks for plan.id
        if options[:for_app]
          payload['plan'] = {'id' => service_plan["id"], 'code' => service_plan["code"], 'name' => service_plan["name"]}
        else
          payload['instance']['plan'] = {'id' => service_plan["id"], 'code' => service_plan["code"], 'name' => service_plan["name"]}
        end
      end
    }

    prompt_resource_pool = -> {
      # prompt for resource pool
      if locked_fields.include?('config.resourcePoolId')
        pool_id = payload['config']['resourcePoolId'] rescue nil
      elsif locked_fields.include?('config.resourcePool')
        pool_id = payload['config']['resourcePool'] rescue nil
      elsif locked_fields.include?('config.azureResourceGroupId')
        pool_id = payload['config']['azureResourceGroupId'] rescue nil
      else
        has_zone_pools = provision_type && provision_type["id"] && provision_type["hasZonePools"]
        if has_zone_pools
          # pluck out the resourcePoolId option type to prompt for
          resource_pool_option_type = option_type_list.find {|opt| ['poolId','resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
          option_type_list = option_type_list.reject {|opt| ['poolId','resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }

          resource_pool_options = options_interface.options_for_source('zonePools', {groupId: group_id, siteId: group_id, zoneId: cloud_id, cloudId: cloud_id, instanceTypeId: instance_type['id'], layoutId: layout["id"]}.merge(service_plan.nil? ? {} : {planId: service_plan["id"]}))['data']
          if options[:resource_pool]
            resource_pool = resource_pool_options.find {|opt| opt['value'] == options[:resource_pool].to_s || opt['value'] == "pool-#{options[:resource_pool]}"}
          end
          pool_required = provision_type["zonePoolRequired"]
          # Should pool_id have the pool-,poolGroup- prefix or not?
          use_pool_prefix = resource_pool_options.find {|opt| opt['value'].to_s.include?("pool") }
          if resource_pool
            pool_id = resource_pool['id'] # id or value?
          else
            if options[:default_resource_pool]
              default_resource_pool = resource_pool_options.find {|rp| rp['id'] == options[:default_resource_pool]}
            end
            if use_pool_prefix && options[:options]['config'] && options[:options]['config']['resourcePoolId'] && !options[:options]['config']['resourcePoolId'].to_s.include?("pool")
              options[:options]['config']['resourcePoolId'] = "pool-" + options[:options]['config']['resourcePoolId'].to_s
            end
            resource_pool_option_type ||= {'fieldContext' => 'config', 'fieldName' => 'resourcePoolId', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'selectOptions' => resource_pool_options, 'required' => pool_required, 'skipSingleOption' => true, 'description' => 'Select resource pool.', 'defaultValue' => default_resource_pool ? default_resource_pool['name'] : nil}
            resource_pool_prompt = Morpheus::Cli::OptionTypes.prompt([resource_pool_option_type],options[:options],api_client,{}, no_prompt, true)
            resource_pool_prompt.deep_compact!
            payload.deep_merge!(resource_pool_prompt)
            # this results in the layout, not the resourcePool for some reason...
            #resource_pool = Morpheus::Cli::OptionTypes.get_last_select() 
            if resource_pool_option_type['fieldContext'] && resource_pool_prompt[resource_pool_option_type['fieldContext']]
              pool_id = resource_pool_prompt[resource_pool_option_type['fieldContext']][resource_pool_option_type['fieldName']]
            elsif resource_pool_prompt[resource_pool_option_type['fieldName']]
              pool_id = resource_pool_prompt[resource_pool_option_type['fieldName']]
            end
            resource_pool ||= resource_pool_options.find {|it| it['value'].to_s == pool_id.to_s}
          end
        end
      end
    }

    prompt_provision_options = -> {
      if !provision_type.nil? && !provision_type['optionTypes'].nil? && !provision_type['optionTypes'].empty?
        option_type_list += provision_type['optionTypes'].reject {|it| (it['fieldGroup'] || '').downcase == 'provisiontype'}
        provision_config_payload = Morpheus::Cli::OptionTypes.prompt(provision_type['optionTypes'].reject {|it| (it['fieldGroup'] || '').downcase != 'provisiontype'}, options[:options], @api_client, api_params, no_prompt, true)
        payload.deep_merge!(provision_config_payload)
      end
    }

    if ['openstack', 'huawei', 'opentelekom'].include?(cloud_type['zoneType']['code'])
      prompt_resource_pool.call
      prompt_provision_options.call
      prompt_service_plan.call
    else
      prompt_service_plan.call
      prompt_provision_options.call
      prompt_resource_pool.call
    end

    # remove host selection for kubernetes
    if resource_pool
      payload['config']['poolProviderType'] = resource_pool['providerType'] if resource_pool['providerType']
      if resource_pool['providerType'] == 'kubernetes'
        option_type_list = option_type_list.reject {|opt| ['provisionServerId'].include?(opt['fieldName'])}
      end

      # add selectable datastores
      # no longer use the plan datastores info, always load from data-stores api instead
      # note: this modifies service_plan in place with 'datastores' and 'autoOptions'
      if options[:select_datastore]
        if provision_type['hasDatastore']
          datastore_params = {'zoneId' => cloud_id, 'siteId' => group_id, 'resourcePoolId' => resource_pool['id']}
          load_service_plan_datastores(service_plan, provision_type, datastore_params)
        end
      end
    end

    # plan_info has this property already..
    # has_datastore = provision_type && provision_type["id"] && provision_type["hasDatastore"]
    # service_plan['hasDatastore'] = has_datastore

    # set root volume name if has mounts
    mounts = (layout['mounts'] || []).reject {|it| !it['canPersist']}
    if mounts.count > 0
      options[:root_volume_name] = mounts[0]['shortName']
    end

    # prompt for volumes
    if locked_fields.include?('volumes')
      payload['volumes'] = options[:options]['volumes'] if options[:options]['volumes']
    else
      volumes = prompt_volumes(service_plan, provision_type, options, api_client, {zoneId: cloud_id, layoutId: layout['id'], siteId: group_id})
      if !volumes.empty?
        payload['volumes'] = volumes
      end
    end

    # plan customizations
    plan_opts = prompt_service_plan_options(service_plan, options, api_client, {zoneId: cloud_id, layoutId: layout['id'], siteId: group_id})
    if plan_opts && !plan_opts.empty?
      payload['servicePlanOptions'] = plan_opts
    end

    # prompt networks
    if locked_fields.include?('networks')
      # payload['networkInterfaces'] = options[:options]['networkInterfaces'] if options[:options]['networkInterfaces']
    else
      if provision_type && provision_type["hasNetworks"]
        # prompt for network interfaces (if supported)
        begin
          network_interfaces = prompt_network_interfaces(cloud_id, provision_type["id"], pool_id, options.merge({:api_params => payload['config']}))
          if !network_interfaces.empty?
            payload['networkInterfaces'] = network_interfaces
          end
        rescue RestClient::Exception => e
          print yellow,"Unable to load network options. Proceeding...",reset,"\n"
          print_rest_exception(e, options) if Morpheus::Logging.debug?
        end
      end
    end

    # Security Groups
    # look for securityGroups option type... this is old and goofy
    sg_option_type = option_type_list.find {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['fieldName'] == 'securityId' || opt['name'] == 'securityId')) }
    option_type_list = option_type_list.reject {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['fieldName'] == 'securityId' || opt['name'] == 'securityId')) }
    if locked_fields.include?('securityGroups')
      # payload['securityGroups'] = options[:options]['securityGroups'] if options[:options]['securityGroups']
    else
      # prompt for multiple security groups
      # ok.. seed data has changed and serverTypes do not have this optionType anymore...
      if sg_option_type.nil?
        if provision_type && (provision_type["code"] == 'amazon')
            sg_option_type = {'fieldContext' => 'config', 'fieldName' => 'securityId', 'type' => 'select', 'fieldLabel' => 'Security Group', 'optionSource' => 'amazonSecurityGroup', 'optionSourceType' => 'amazon', 'required' => true, 'description' => 'Select security group.', 'defaultValue' => options[:default_security_group]}
        end
      end
      sg_api_params = {zoneId: cloud_id, poolId: pool_id}
      # The amazon plugin uses a new optionSource options/amazon/awsPluginEc2SecurityGroup 
      # which expects parameter config.resourcePoolId=pool-ID
      if sg_option_type
        if sg_option_type['optionSource'] == 'awsPluginEc2SecurityGroup'
          if pool_id
            sg_api_params[:config] ||= {}
            sg_api_params[:config][:resourcePoolId] = pool_id
          end
          # convert multiSelect to select to make prompt_security_groups() work
          # though we should should be able to skip the prompt_security_groups and use multiSelect instead
          sg_option_type['type'] = 'select' if sg_option_type['type'] == 'multiSelect'
          sg_option_type['type'] = 'typeahead' if sg_option_type['type'] == 'multiTypeahead'
          sg_option_type['fieldLabel'] = 'Security Group' if sg_option_type['fieldLabel'] == 'Security Groups'
          sg_option_type['required'] = true
        end
      end
      has_security_groups = !!sg_option_type
      if options[:security_groups]
        available_security_groups = []
        if sg_option_type && sg_option_type['optionSource']
          sg_option_results = options_interface.options_for_source(sg_option_type['optionSource'], sg_api_params, sg_option_type['optionSourceType'])
          available_security_groups = sg_option_results['data'].collect do |it|
            {"id" => it["value"] || it["id"], "name" => it["name"], "value" => it["value"] || it["id"]}
          end
        end
        # work with id or names, API expects ids though.
        payload['securityGroups'] = options[:security_groups].collect {|sg_id| 
          found_sg = available_security_groups.find {|it| sg_id && (sg_id.to_s == it['id'].to_s || sg_id.to_s == it['name'].to_s) }
          if found_sg.nil?
            print_red_alert "Security group not found by name or id '#{sg_id}'"
            exit 1
          end
          {'id' => found_sg['id']}
        }

      elsif has_security_groups
        do_prompt_sg = true
        if options[:default_security_groups]
          payload['securityGroups'] = options[:default_security_groups]
          security_groups_value = options[:default_security_groups].collect {|sg| sg['id'] }.join(',') rescue options[:default_security_groups]
          # do_prompt_sg = (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Modify security groups? (#{security_groups_value})", {:default => false}))
          do_prompt_sg = (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Modify security groups?", {:default => false}))
        end
        if do_prompt_sg
          security_groups_array = prompt_security_groups(sg_option_type, sg_api_params, options)
          if !security_groups_array.empty?
            payload['securityGroups'] = security_groups_array.collect {|sg_id| {'id' => sg_id} }
          end
        end
      end
    end

    # prompt for option types
    api_params['config'] = payload['config'] if payload['config']
    api_params['poolId'] = payload['config']['resourcePoolId'] if payload['config'] && payload['config']['resourcePoolId']
    api_params['resourcePoolId'] = api_params['poolId']
    # some option sources expect networkIntefaces passed as networkInterfaceIds[] eg. oraclecloudAvailabilityDomains
    if payload['networkInterfaces']
      begin
        api_params['networkInterfaceIds[]'] = payload['networkInterfaces'].collect {|it| it['network']['id'] }
      rescue => netex
        Morpheus::Logging::DarkPrinter.puts "Unable to parse networkInterfaces parameter" if Morpheus::Logging.debug?
      end
    end

    # set option type defaults from config
    if options[:default_config]
      options[:default_config].each do |k,v|
        if v && !(v.kind_of?(Array) && v.empty?)
          option_type = option_type_list.find {|ot| ot['fieldContext'] == 'config' && ot['fieldName'] == k}
          option_type['defaultValue'] = v if option_type
        end
      end
    end

    option_type_list += [
      {'fieldName' => 'userGroup.id', 'fieldLabel' => 'User Group', 'fieldGroup' => 'User Config', 'type' => 'select', 'optionSource' => 'userGroups', 'displayOrder' => 0, 'fieldContext' => 'instance'},
      {'fieldName' => 'hostName', 'fieldLabel' => 'Hostname', 'fieldGroup' => 'Advanced', 'type' => 'string', 'displayOrder' => 1},
      {'fieldName' => 'networkDomain.id', 'fieldLabel' => 'Domain', 'fieldGroup' => 'Advanced', 'type' => 'select', 'optionSource' => 'networkDomains', 'displayOrder' => 2, 'fieldContext' => 'instance'},
      {'fieldName' => 'timezone', 'fieldLabel' => 'Time Zone', 'fieldGroup' => 'Advanced', 'type' => 'select', 'optionSource' => 'timezones', 'displayOrder' => 3, 'fieldContext' => 'config'}
    ]

    if instance_type['hasAutoScale']
      option_type_list += [
        {'fieldName' => 'layoutSize', 'fieldLabel' => 'Scale Factor', 'fieldGroup' => 'Advanced', 'type' => 'number', 'defaultValue' => 1, 'displayOrder' => 0},
      ]
    end

    instance_config_payload = Morpheus::Cli::OptionTypes.prompt(option_type_list.reject {|ot| ot['type'] == 'exposedPorts'}, options[:options], @api_client, api_params, no_prompt, true)
    payload.deep_merge!(instance_config_payload)

    # prompt for exposed ports
    if payload['ports'].nil?
      # need a way to know if the instanceType even supports this.
      # the default ports come from the node type, under layout['containerTypes']
      ports = prompt_exposed_ports(options)
      if !ports.empty?
        payload['ports'] = ports
      end
    end

    # prompt for environment variables
    evars = prompt_evars(options)
    if !evars.empty?
      payload['evars'] = evars
    end

    # metadata tags
    # metadata_tag_key = 'metadata'
    metadata_tag_key = 'tags'
    if !options[:metadata]
      if options[:options]['metadata'].is_a?(Array)
        options[:metadata] = options[:options]['metadata']
      end
      if options[:options]['tags'].is_a?(Array)
        options[:metadata] = options[:options]['tags']
      end
    end
    if options[:metadata]
      metadata = []
      if options[:metadata] == "[]" || options[:metadata] == "null"
        metadata = []
      elsif options[:metadata].is_a?(Array)
        metadata = options[:metadata]
      else
        # parse string into format name:value, name:value
        # merge IDs from current metadata
        # todo: should allow quoted semicolons..
        metadata = options[:metadata].split(",").select {|it| !it.to_s.empty? }
        metadata = metadata.collect do |it|
          metadata_pair = it.split(":")
          if metadata_pair.size < 2 && it.include?("=")
            metadata_pair = it.split("=")
          end
          row = {}
          row['name'] = metadata_pair[0].to_s.strip
          row['value'] = metadata_pair[1].to_s.strip
          row
        end
      end
      payload[metadata_tag_key] = metadata
    else
      # prompt for metadata tags
      metadata = prompt_metadata(options)
      if !metadata.empty?
        payload[metadata_tag_key] = metadata
      end
    end

    return payload
  end

  # This recreates the behavior of multi_disk.js
  # returns array of volumes based on service plan options (plan_info)
  def prompt_volumes(plan_info, provision_type, options={}, api_client=nil, api_params={})
    #puts "Configure Volumes:"
    # return [] if plan_info['noDisks']

    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    volumes = []
    plan_size = 0
    if plan_info['maxStorage'].to_i > 0
      plan_size = plan_info['maxStorage'].to_i / (1024 * 1024 * 1024)
    end
    root_storage_types = []
    if plan_info['rootStorageTypes']
      plan_info['rootStorageTypes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }.each do |opt|
        if !opt.nil?
          root_storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    storage_types = []
    if plan_info['storageTypes']
      plan_info['storageTypes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }.each do |opt|
        if !opt.nil?
          storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    datastore_options = []
    if plan_info['supportsAutoDatastore']
      if plan_info['autoOptions']
        plan_info['autoOptions'].each do |opt|
          if !opt.nil?
            datastore_options << {'name' => opt['name'], 'value' => opt['id']}
          end
        end
      end
    end
    if plan_info['datastores']
      plan_info['datastores'].each do |k, v|
        v.each do |opt|
          if !opt.nil?
            k = 'datastores' if k == 'store'
            k = 'clusters' if k == 'cluster'
            datastore_options << {'name' => "#{k}: #{opt['name']}", 'value' => opt['id']}
          end
        end
      end
    end
    # api does not always return datastores, so go get them if needed..
    if plan_info['hasDatastore'] && datastore_options.empty?
      option_results = options_interface.options_for_source('datastores', api_params)
      option_results['data'].each do |it|
          datastore_options << {"id" => it["value"] || it["id"], "name" => it["name"], "value" => it["value"] || it["id"]}
      end
    end

    #puts "Configure Root Volume"

    field_context = "rootVolume"

    volume_label = options[:root_volume_name] || 'root'
    volume = {
      'id' => -1,
      'rootVolume' => true,
      'name' => volume_label,
      'size' => plan_size,
      'sizeId' => nil,
      'storageType' => nil,
      'datastoreId' => nil
    }
    if options[:options] && options[:options]['volumes'] && options[:options]['volumes'][0]
      volume = options[:options]['volumes'][0]
    end

    if root_storage_types.empty?
      # this means there's no configuration, just send a single root volume to the server
      storage_type_id = nil
      storage_type = nil
    else
      default_storage_type = root_storage_types.find {|t| t['value'].to_s == (volume['typeId'] || volume['storageType']).to_s}
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => 'Root Storage Type', 'selectOptions' => root_storage_types, 'required' => true, 'defaultFirstOption' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.', 'defaultValue' => default_storage_type ? default_storage_type['name'] : volume['storageType']}], options[:options])
      storage_type_id = v_prompt[field_context]['storageType']
      storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
      volume['storageType'] = storage_type_id
    end

    # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
    root_custom_size_options = []
    if plan_info['rootCustomSizeOptions'] && plan_info['rootCustomSizeOptions'][storage_type_id.to_s]
      plan_info['rootCustomSizeOptions'][storage_type_id.to_s].each do |opt|
        if !opt.nil?
          root_custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
        end
      end
    end

    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customLabel']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Root Volume Label', 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
      volume['name'] = v_prompt[field_context]['name']
    end
    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customSize']
      # provision_type['rootDiskSizeKnown'] == false means size cannot be changed
      if provision_type['rootDiskSizeKnown'] == false
        # volume['size'] = plan_size if plan_size.to_i != 0
      else
        if root_custom_size_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => 'Root Volume Size (GB)', 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
          volume['size'] = v_prompt[field_context]['size']
          volume['sizeId'] = nil #volume.delete('sizeId')
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => 'Root Volume Size', 'selectOptions' => root_custom_size_options, 'required' => true, 'description' => 'Choose a volume size.', 'defaultValue' => volume['sizeId']}], options[:options])
          volume['sizeId'] = v_prompt[field_context]['sizeId']
          volume['size'] = nil #volume.delete('size')
        end
      end
      # root volume storage controller mount input is disabled in the UI.
      # if plan_info['customizeVolume'] # && storage_type['customStorageController']
      #   cmp = prompt_volume_controller_mount_point(volumes, field_context, volume_index, volume, plan_info, provision_type, options, server)
      #   volume['controllerMountPoint'] = cmp if !cmp.to_s.empty?
      # end
    else
      # might need different logic here ? =o
      #volume['size'] = plan_size
      #volume['sizeId'] = nil #volume.delete('sizeId')
    end

    if !datastore_options.empty? && !provision_type['disableRootDatastore']
      default_datastore = datastore_options.find {|ds| ds['value'].to_s == volume['datastoreId'].to_s}
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => 'Root Datastore', 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.', 'defaultValue' => default_datastore ? default_datastore['name'] : volume['datastoreId']}], options[:options])
      volume['datastoreId'] = v_prompt[field_context]['datastoreId']
    end

    volumes << volume

    if plan_info['addVolumes']
      volume_index = 1
      has_another_volume = (options[:options] && options[:options]["dataVolume#{volume_index}"]) || (options[:options] && options[:options]['volumes'] && options[:options]['volumes'][volume_index])
      add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add data volume?", {:default => (options[:defaultAddFirstDataVolume] == true && volume_index == 1)}))
      while add_another_volume do
        #puts "Configure Data #{volume_index} Volume"

        field_context = "dataVolume#{volume_index}"

        #volume_label = (volume_index == 1 ? 'data' : "data #{volume_index}")
        volume_label = "data-#{volume_index}"
        volume = {
          #'id' => -1,
          'rootVolume' => false,
          'name' => volume_label,
          'size' => plan_size,
          'sizeId' => nil,
          'storageType' => nil,
          'datastoreId' => nil
        }
        if options[:options] && options[:options]['volumes'] && options[:options]['volumes'][volume_index]
          volume = options[:options]['volumes'][volume_index]
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'defaultFirstOption' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.', 'defaultValue' => volume['storageType']}], options[:options])
        storage_type_id = v_prompt[field_context]['storageType']
        volume['storageType'] = storage_type_id
        storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }

        # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
        custom_size_options = []
        if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
          plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
            if !opt.nil?
              custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
            end
          end
        end

        if plan_info['customizeVolume'] && storage_type['customLabel']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
          volume['name'] = v_prompt[field_context]['name']
        end
        if plan_info['customizeVolume'] && storage_type['customSize']
          if custom_size_options.empty?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
            volume['size'] = v_prompt[field_context]['size']
            volume['sizeId'] = nil #volume.delete('sizeId')
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.', 'defaultValue' => volume['sizeId']}], options[:options])
            volume['sizeId'] = v_prompt[field_context]['sizeId']
            volume['size'] = nil #volume.delete('size')
          end
        else
          # might need different logic here ? =o
          volume['size'] = plan_size
          volume['sizeId'] = nil #volume.delete('sizeId')
        end
        #todo: Pass in virtual_image to prompt based on its storage_controllers (and volume configuration)
        if plan_info['customizeVolume'] # && storage_type['customStorageController']
          cmp = prompt_volume_controller_mount_point(volumes, field_context, volume_index, volume, plan_info, provision_type, options, nil)
          volume['controllerMountPoint'] = cmp if !cmp.to_s.empty?
        end
        if !datastore_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.', 'defaultValue' => volume['datastoreId']}], options[:options])
          volume['datastoreId'] = v_prompt[field_context]['datastoreId']
        end

        volumes << volume

        volume_index += 1
        if options[:options] && options[:options]['volumes'] && options[:options]['volumes'][volume_index]
          add_another_volume = true
        elsif plan_info['maxDisk'] && volume_index >= plan_info['maxDisk']
          # todo: should maxDisk check consider the root volume too?
          add_another_volume = false
        else
          has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
          add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another data volume?", {:default => false}))
        end

      end

    end

    return volumes
  end


  # This recreates the behavior of multi_disk.js
  # returns array of volumes based on service plan options (plan_info)
  def prompt_resize_volumes(current_volumes, plan_info, provision_type, options={}, server=nil)
    #puts "Configure Volumes:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))

    current_root_volume = current_volumes[0]

    volumes = []

    plan_size = nil
    if plan_info['maxStorage'].to_i > 0
      plan_size = plan_info['maxStorage'].to_i / (1024 * 1024 * 1024)
    end

    root_storage_types = []
    if plan_info['rootStorageTypes']
      plan_info['rootStorageTypes'].each do |opt|
        if !opt.nil?
          root_storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    storage_types = []
    if plan_info['storageTypes']
      plan_info['storageTypes'].each do |opt|
        if !opt.nil?
          storage_types << {'name' => opt['name'], 'value' => opt['id']}
        end
      end
    end

    # no longer use the plan datastores info, always load from data-stores api instead
    # note: this modifies service_plan in place with 'datastores' and 'autoOptions'
    group_id = cloud_id = options['siteId']
    cloud_id = options['zoneId']
    server_resource_pool_id = server ? (server['resourcePoolId'] || (server['resourcePool'] ? server['resourcePool']['id'] : nil)) : nil
    resource_pool_id = options['resourcePoolId'] || server_resource_pool_id
    if provision_type['hasDatastore']
      datastore_params = {'zoneId' => cloud_id, 'siteId' => group_id, 'resourcePoolId' => resource_pool_id}
      load_service_plan_datastores(plan_info, provision_type, datastore_params)
    end
    datastore_options = []
    if plan_info['supportsAutoDatastore']
      if plan_info['autoOptions']
        plan_info['autoOptions'].each do |opt|
          if !opt.nil?
            datastore_options << {'name' => opt['name'], 'value' => opt['id']}
          end
        end
      end
    end
    if plan_info['datastores']
      plan_info['datastores'].each do |k, v|
        v.each do |opt|
          if !opt.nil?
            datastore_options << {'name' => "#{k}: #{opt['name']}", 'value' => opt['id']}
          end
        end
      end
    end

    #puts "Configure Root Volume"

    field_context = "rootVolume"
    storage_type = nil
    storage_type_id = nil
    if root_storage_types.empty?
      # this means there's no configuration, just send a single root volume to the server
      storage_type_id = nil
      storage_type = nil
    else
      #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => 'Root Storage Type', 'selectOptions' => root_storage_types, 'required' => true, 'defaultFirstOption' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
      #storage_type_id = v_prompt[field_context]['storageType']
      storage_type_id = (current_root_volume['typeId'] || current_root_volume['storageType'] || (current_root_volume['type']['id'] rescue nil))
      storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
    end

    # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
    root_custom_size_options = []
    if plan_info['rootCustomSizeOptions'] && plan_info['rootCustomSizeOptions'][storage_type_id.to_s]
      plan_info['rootCustomSizeOptions'][storage_type_id.to_s].each do |opt|
        if !opt.nil?
          root_custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
        end
      end
    end
    volume = {
      'id' => current_root_volume['id'],
      'rootVolume' => true,
      'name' => current_root_volume['name'],
      'size' => get_volume_size(current_root_volume) || plan_size,
      'sizeId' => nil,
      'storageType' => storage_type_id,
      'datastoreId' => current_root_volume['datastoreId']
    }
    if !current_root_volume['controllerMountPoint'].to_s.empty?
      volume['controllerMountPoint'] = current_root_volume['controllerMountPoint']
    end
    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customLabel']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Root Volume Label', 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
      volume['name'] = v_prompt[field_context]['name']
    end
    if plan_info['rootDiskCustomizable'] && storage_type && storage_type['customSize']
      # provision_type['rootDiskSizeKnown'] == false means size cannot be changed
      if provision_type['rootDiskSizeKnown'] == false
        # volume['size'] = plan_size if plan_size.to_i != 0
      else
        if root_custom_size_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => 'Root Volume Size (GB)', 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
          volume['size'] = v_prompt[field_context]['size']
          volume['sizeId'] = nil #volume.delete('sizeId')
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => 'Root Volume Size', 'selectOptions' => root_custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
          volume['sizeId'] = v_prompt[field_context]['sizeId']
          volume['size'] = nil #volume.delete('size')
        end
      end
    else
      # might need different logic here ? =o
      # volume['size'] = plan_size
      # volume['sizeId'] = nil #volume.delete('sizeId')
    end
    # if !datastore_options.empty?
    #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => 'Root Datastore', 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
    #   volume['datastoreId'] = v_prompt[field_context]['datastoreId']
    # end

    volumes << volume

    # modify or delete existing data volumes
    (1..(current_volumes.size-1)).each do |volume_index|
      current_volume = current_volumes[volume_index]
      if current_volume

        field_context = "dataVolume#{volume_index}"

        action_options = [{'name' => 'Modify', 'value' => 'modify'}, {'name' => 'Keep', 'value' => 'keep'}, {'name' => 'Delete', 'value' => 'delete'}]
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'action', 'type' => 'select', 'fieldLabel' => "Modify/Keep/Delete volume '#{current_volume['name']}'", 'selectOptions' => action_options, 'required' => true, 'defaultValue' => 'keep', 'description' => 'Modify, Keep or Delete existing data volume?'}], options[:options])
        volume_action = v_prompt[field_context]['action']

        if volume_action == 'delete'
          # deleted volume is just excluded from post params
          next
        elsif volume_action == 'keep'
          volume = {
            'id' => current_volume['id'].to_i,
            'rootVolume' => false,
            'name' => current_volume['name'],
            'size' => get_volume_size(current_volume) || plan_size,
            'sizeId' => nil,
            'storageType' => (current_volume['typeId'] || current_volume['storageType'] || (current_volume['type']['id'] rescue nil)),
            'datastoreId' => current_volume['datastoreId']
          }
          if !current_volume['controllerMountPoint'].to_s.empty?
            volume['controllerMountPoint'] = current_volume['controllerMountPoint']
          end
          volumes << volume
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
          # storage_type_id = v_prompt[field_context]['storageType']
          storage_type_id = (current_volume['typeId'] || current_volume['storageType'] || (current_volume['type']['id'] rescue nil))
          storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }
          # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
          custom_size_options = []
          if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
            plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
              if !opt.nil?
                custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
              end
            end
          end

          volume = {
            'id' => current_volume['id'].to_i,
            'rootVolume' => false,
            'name' => current_volume['name'],
            'size' => get_volume_size(current_volume) || plan_size,
            'sizeId' => nil,
            'storageType' => (current_volume['typeId'] || current_volume['storageType'] || (current_volume['type']['id'] rescue current_volume['type'])),
            'datastoreId' => current_volume['datastoreId']
          }
          if !current_volume['controllerMountPoint'].to_s.empty?
            volume['controllerMountPoint'] = current_volume['controllerMountPoint']
          end
          
          if plan_info['customizeVolume'] && storage_type['customLabel']
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume['name']}], options[:options])
            volume['name'] = v_prompt[field_context]['name']
          end
          if plan_info['customizeVolume'] && storage_type['customSize']
            if custom_size_options.empty?
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
              volume['size'] = v_prompt[field_context]['size']
              volume['sizeId'] = nil #volume.delete('sizeId')
            else
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
              volume['sizeId'] = v_prompt[field_context]['sizeId']
              volume['size'] = nil #volume.delete('size')
            end
          else
            # might need different logic here ? =o
            # volume['size'] = plan_size
            # volume['sizeId'] = nil #volume.delete('sizeId')
          end
          # if plan_info['customizeVolume'] # && storage_type['customStorageController']
          #   cmp = prompt_volume_controller_mount_point(volumes, field_context, volume_index, volume, plan_info, provision_type, options, server)
          #   volume['controllerMountPoint'] = cmp if !cmp.to_s.empty?
          # end
          # if !datastore_options.empty?
          #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.'}], options[:options])
          #   volume['datastoreId'] = v_prompt[field_context]['datastoreId']
          # end

          volumes << volume

        end

      end
    end


    if plan_info['addVolumes']
      volume_index = current_volumes.size
      has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
      add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add data volume?", {:default => false}))
      while add_another_volume do
        #puts "Configure Data #{volume_index} Volume"
        previous_volume = volumes.last
        default_storage_type_id = (previous_volume['typeId'] || previous_volume['storageType'] || (previous_volume['type']['id'] rescue previous_volume['type']))
        storage_type_match = storage_types.find {|type| type['value'] == default_storage_type_id}
        default_storage_type = storage_type_match ? (storage_type_match['name'] || storage_type_match['value']) : nil
        field_context = "dataVolume#{volume_index}"
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'defaultValue' => default_storage_type, 'fieldContext' => field_context, 'fieldName' => 'storageType', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Type", 'selectOptions' => storage_types, 'required' => true, 'defaultFirstOption' => true, 'skipSingleOption' => true, 'description' => 'Choose a storage type.'}], options[:options])
        storage_type_id = v_prompt[field_context]['storageType']
        storage_type = plan_info['storageTypes'].find {|i| i['id'] == storage_type_id.to_i }

        # sometimes the user chooses sizeId from a list of size options (AccountPrice) and other times it is free form
        custom_size_options = []
        if plan_info['customSizeOptions'] && plan_info['customSizeOptions'][storage_type_id.to_s]
          plan_info['customSizeOptions'][storage_type_id.to_s].each do |opt|
            if !opt.nil?
              custom_size_options << {'name' => opt['value'], 'value' => opt['key']}
            end
          end
        end

        #volume_label = (volume_index == 1 ? 'data' : "data #{volume_index}")
        volume_label = "data-#{volume_index}"
        volume = {
          'id' => -1,
          'rootVolume' => false,
          'name' => volume_label,
          'size' => plan_size,
          'sizeId' => nil,
          'storageType' => storage_type_id,
          'datastoreId' => nil
        }

        if plan_info['customizeVolume'] && storage_type['customLabel']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "Disk #{volume_index} Volume Label", 'required' => true, 'description' => 'Enter a volume label.', 'defaultValue' => volume_label}], options[:options])
          volume['name'] = v_prompt[field_context]['name']
        end
        if plan_info['customizeVolume'] && storage_type['customSize']
          if custom_size_options.empty?
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Disk #{volume_index} Volume Size (GB)", 'required' => true, 'description' => 'Enter a volume size (GB).', 'defaultValue' => volume['size']}], options[:options])
            volume['size'] = v_prompt[field_context]['size']
            volume['sizeId'] = nil #volume.delete('sizeId')
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'sizeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Volume Size", 'selectOptions' => custom_size_options, 'required' => true, 'description' => 'Choose a volume size.'}], options[:options])
            volume['sizeId'] = v_prompt[field_context]['sizeId']
            volume['size'] = nil #volume.delete('size')
          end
        else
          # might need different logic here ? =o
          # volume['size'] = plan_size
          # volume['sizeId'] = nil #volume.delete('sizeId')
        end
        if plan_info['customizeVolume'] # && storage_type['customStorageController']
          cmp = prompt_volume_controller_mount_point(volumes, field_context, volume_index, volume, plan_info, provision_type, options, server)
          volume['controllerMountPoint'] = cmp if !cmp.to_s.empty?
        end
        if !datastore_options.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'datastoreId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Datastore", 'selectOptions' => datastore_options, 'required' => true, 'description' => 'Choose a datastore.', 'defaultValue' => current_root_volume['datastoreId']}], options[:options])
          volume['datastoreId'] = v_prompt[field_context]['datastoreId'] unless v_prompt[field_context]['datastoreId'].to_s.empty?
        end

        volumes << volume

        # todo: should maxDisk check consider the root volume too?
        if plan_info['maxDisk'] && volume_index >= plan_info['maxDisk']
          add_another_volume = false
        else
          volume_index += 1
          has_another_volume = options[:options] && options[:options]["dataVolume#{volume_index}"]
          add_another_volume = has_another_volume || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another data volume?", {default:false}))
        end

      end

    end

    return volumes
  end

  # loads datastores and modifies service_plan in place
  # populating datastores: {datastores: [],clusters: []}, supportsAutoDatastore: true, autoOptions: []
  def load_service_plan_datastores(service_plan, provision_type, params)
    begin
      selectable_datastores = datastores_interface.list(params)
      service_plan['datastores'] = {'clusters' => [], 'datastores' => []}
      ['clusters', 'datastores'].each do |type|
        service_plan['datastores'][type] ||= []
        selectable_datastores[type].reject { |ds| service_plan['datastores'][type].find {|it| it['id'] == ds['id']} }.each { |ds|
          service_plan['datastores'][type] << ds
        }
      end
    rescue => error
      Morpheus::Logging::DarkPrinter.puts "Unable to load available data-stores, using datastores option source instead." if Morpheus::Logging.debug?
    end
  
    if provision_type && provision_type['supportsAutoDatastore']
      service_plan['supportsAutoDatastore'] = true
      service_plan['autoOptions'] ||= []
      if service_plan['datastores'] && service_plan['datastores']['clusters']
        if service_plan['datastores']['clusters'].count > 0 && !service_plan['autoOptions'].find {|it| it['id'] == 'autoCluster'}
          service_plan['autoOptions'] << {'id' => 'autoCluster', 'name' => 'Auto - Cluster'}
        end
      else
        service_plan['autoOptions'] << {'id' => 'autoCluster', 'name' => 'Auto - Cluster'}
      end
      if service_plan['datastores'] && service_plan['datastores']['datastores']
        if service_plan['datastores']['datastores'].count > 0 && !service_plan['autoOptions'].find {|it| it['id'] == 'auto'}
          service_plan['autoOptions'] << {'id' => 'auto', 'name' => 'Auto - Datastore'}
        end
      else
        service_plan['autoOptions'] << {'id' => 'auto', 'name' => 'Auto - Datastore'}
      end
    end
    return service_plan
  end

  def get_volume_size(volume)
    if volume['size'].to_i > 0
      volume['size']
    elsif volume['maxStorage'].to_i > 0
      volume['maxStorage'].to_i / (1024**3)
    else
      nil  
    end
  end

  def prompt_volume_controller_mount_point(volumes, field_context, volume_index, volume, plan_info, provision_type, options={}, server=nil)
    begin
      # The /api/provision-types has always returned all the controllerTypes, yay
      # It did not return hasStorageControllers: true|false though, so fallback to checking if controllerTypes.size > 0.
      # has_storage_controllers = provision_type['hasStorageControllers'] || ['vmware'].include?(provision_type['code'])
      # storage_controller_types = has_storage_controllers ? options_interface.options_for_source('storageControllerTypes',{provisionTypeId:provision_type['id']})['data'] : []
      storage_controller_types = provision_type['controllerTypes']
      has_storage_controllers = provision_type['hasStorageControllers'] || (storage_controller_types && !storage_controller_types.empty?)
      storage_controllers = server ? server['controllers'] : []
      if has_storage_controllers
        # existing storage controllers from server
        storage_controller_options = []
        storage_controller_options.push({'name' => 'Auto', 'value' => 'auto'})
        storage_controller_options.push({'name' => 'New', 'value' => -1})
        storage_controllers.each_with_index do |sc, index|
          # storage_controller_options.push({'name' => sc['name'], 'value' => sc['id']})
          # API did not always return controller busNumber so extract from the volume mountPoint if needed
          if sc['busNumber'].nil?
            matching_volume = volumes.find {|v| v['controllerMountPoint'] && v['controllerMountPoint'].split(':')[0] == sc['id'].to_s }
            if matching_volume
              sc['busNumber'] = matching_volume['controllerMountPoint'].split(":")[1]
            end
          end
          sct = storage_controller_types.find { |t| t['id'] == sc['type']['id'] }
          storage_controller_options.push({'name' => "#{sct['category'].to_s.upcase rescue ''} #{sc['busNumber'] || index}", 'value' => sc['id']})
        end if storage_controllers
        # The controller mount point specification for this volume in the format: `id:busNumber:typeId:unitNumber"`
        # For new storage controllers the id is passed as -1, so an example value would be: `"-1:1:6:0"` which translates to id: -1 (new), busNumber: 1, storage controller type id: 6 (SCSI VMware Paravirtual), unit number: 0.
        # Split -O dataVolume1.controllerMountPoint="-1:1:6:0" into its components.
        controller_mount_point = ""
        controller_id, bus_number, controller_type_id, unit_number = nil, nil, nil, nil
        if options[:options][field_context] && options[:options][field_context]['controllerMountPoint']
          parts = options[:options][field_context]['controllerMountPoint'].split(":").collect {|it| it.to_s.strip }
          controller_id, bus_number, controller_type_id, unit_number = parts[0],parts[1],parts[2],parts[3]
          # if we dont have every part then clear the options value so it prompt down below
          if controller_id.to_s.empty? || bus_number.to_s.empty? || controller_type_id.to_s.empty? || unit_number.to_s.empty?
            options[:options][field_context].delete('controllerMountPoint')
          end
        end
        # Select Storage Controller, auto, new or existing
        # Choose Existing or Add a new controller which requires selecting type selecting type.
        if !controller_id.to_s.empty?
          controller_id = controller_id
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'controllerId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Controller #{volume_index}", 'selectOptions' => storage_controller_options, 'required' => true, 'description' => 'Choose a storage controller.', 'defaultValue' => (volume['controllerId'] || 'auto') }], options[:options])
          controller_id = v_prompt[field_context]['controllerId']
        end
        skip_controller_mount_point = false
        if controller_id.to_s == 'auto'
          # auto just means omit controllerMountPoint
          skip_controller_mount_point = true
        elsif controller_id.to_i < 1
          # -1 (or anything but a positive integer) means new controller
          controller_id = -1
        elsif controller_id
          controller_id = controller_id.to_i
        end
        if skip_controller_mount_point
          # skip mount point parameter
          # volume.delete('controllerMountPoint')
          # volume.delete('controllerId')
          return nil
        else
          storage_controller_type = nil
          storage_controller = nil
          # New Controller?
          if controller_id == -1
            #[field_context]['controllerTypeId'] controller_type_id = unless controller_type_id.to_s.empty?
            storage_controller_type_options = storage_controller_types.sort {|a,b| a['displayOrder'].to_i <=> b['displayOrder'].to_i}.collect {|it| {"name" => it["name"], "value" => it["id"]}}
            if !controller_type_id.to_s.empty?
              options[:options][field_context]['controllerTypeId'] = controller_type_id
            end
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'controllerTypeId', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Storage Controller Type", 'selectOptions' => storage_controller_type_options, 'required' => true, 'description' => 'Choose a storage controller type.'}], options[:options])
            controller_type_id = v_prompt[field_context]['controllerTypeId']
            # find the selected controller type
            storage_controller_type = storage_controller_types.find {|it| it['id'] == controller_type_id }
            if storage_controller_type.nil?
              raise_command_error("Storage controller type not found for id #{controller_type_id}")
            end
            storage_controller = {'id' => -1, 'type' => {'id' => storage_controller_type['id']}}
            max_devices = storage_controller_type['maxDevices'] || 1
            reserved_bus_numbers = storage_controllers.select {|it| it['category'] == storage_controller_type['category'] }.collect {|it| it['busNumber'].to_s}.uniq
            bus_number = bus_number.to_i || 0
            while true
              if !reserved_bus_numbers.include?(bus_number.to_s)
                break
              else
                next_bus_number = bus_number + 1
                if next_bus_number >= max_devices
                  Morpheus::Logging::DarkPrinter.puts "Failed to find an available bus number!"
                  break
                end
                bus_number = next_bus_number
              end
            end
            storage_controller['busNumber'] = bus_number.to_s
            storage_controller['name'] = "#{storage_controller_type['category'].to_s.upcase} #{bus_number}"
            # storage_controller['unitNumber'] = "null"
            # add new controller to the list
            storage_controllers.push(storage_controller)
          else
            # existing controller
            # controller_type_id = controller_type_id
            # find the selected controller type
            storage_controller = storage_controllers.find {|it| it['id'] == controller_id.to_i }
            if storage_controller.nil?
              raise_command_error("Storage controller type not found for id #{controller_type_id}")
            end
          end
          # Choose Controller Mount Point
          mount_point_options = []
          controller_list = storage_controllers
          # only show the selected controller
          controller_list = [storage_controller]
          controller_list.each do |sc|
            sct = storage_controller_types.find { |t| t['id'] == sc['type']['id'] }
            category = sct['category']
            max_devices = sct['maxDevices'] || 1
            matching_type_ids = storage_controller_types.select { |t| t['category'] == category }.collect {|t| t['id'] }
            # find available unit numbers by reversing the controllerMountPoint to find matching types, blarghhh
            reserved_unit_numbers = (volumes || []).collect {|v| 
              if !v['controllerMountPoint'].to_s.empty?
                parts = v['controllerMountPoint'].split(":")
                vol_controller_id = parts[0]
                vol_bus_number = parts[1]
                vol_sct_id = parts[2]
                vol_unit_number = parts[3]
                if matching_type_ids.include?(vol_sct_id.to_i)
                  vol_unit_number.to_i
                else
                  nil
                end
              else
                nil
              end
            }.compact.uniq
            (0..(max_devices - 1)).each do |index|
              cmp_value = [sc['id'],sc['busNumber'],sct['id'],index].join(":")
              if reserved_unit_numbers.include?(index)
                #mount_point_options << {'name' => "#{category.to_s.upcase} #{sc['busNumber']}:#{index}", 'value' => cmp_value}
              else
                mount_point_options << {'name' => "#{category.to_s.upcase} #{sc['busNumber']}:#{index}", 'value' => cmp_value}
              end
            end
          end
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'controllerMountPoint', 'type' => 'select', 'fieldLabel' => "Disk #{volume_index} Controller Mount Point", 'selectOptions' => mount_point_options, 'required' => true, 'description' => 'Choose a storage controller mount point.'}], options[:options])
          controller_mount_point = v_prompt[field_context]['controllerMountPoint']
          # build controllerMountPoint parameter as "id:busNumber:typeId:unitNumber"
          #controller_mount_point = [controller_id, bus_number, controller_type_id, unit_number].collect {|it| it.to_s.strip}.join(":")
          # volume['controllerMountPoint'] = controller_mount_point
          return controller_mount_point
        end
      else
        # storage controllers not supported, carry on then
      end
    rescue => e
      raise e
      Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) if Morpheus::Logging.debug?
      Morpheus::Logging::DarkPrinter.puts "Failed to prompt for storage controller. Proceeding..."
    end
  end

  # This recreates the behavior of multi_networks.js
  # This is used by both `instances add` and `hosts add`
  # returns array of networkInterfaces based on provision type and cloud settings
  def prompt_network_interfaces(zone_id, provision_type_id, pool_id, options={})
    #puts "Configure Networks:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    network_interfaces = []
    api_params = {zoneId: zone_id, provisionTypeId: provision_type_id}.merge(options[:api_params] || {})
    if pool_id
      api_params[:poolId] = pool_id 
    end

    zone_network_options_json = api_client.options.options_for_source('zoneNetworkOptions', api_params)
    # puts "zoneNetworkOptions JSON"
    # puts JSON.pretty_generate(zone_network_options_json)
    zone_network_data = zone_network_options_json['data'] || {}
    networks = zone_network_data['networks']
    network_groups = zone_network_data['networkGroups']
    if network_groups
      networks = network_groups + networks
    end
    network_subnets = zone_network_data['networkSubnets']
    if network_subnets
      networks += network_subnets
    end
    network_interface_types = (zone_network_data['networkTypes'] || []).sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
    enable_network_type_selection = (zone_network_data['enableNetworkTypeSelection'] == 'on' || zone_network_data['enableNetworkTypeSelection'] == true)
    has_networks = zone_network_data["hasNetworks"] == true
    max_networks = (zone_network_data["maxNetworks"].to_i > 0) ? zone_network_data["maxNetworks"].to_i : nil

    # skip unless provision type supports networks
    if !has_networks
      return nil
    end

    # no networks available, shouldn't happen
    if networks.empty?
      return network_interfaces
    end

    network_options = []
    networks.each do |opt|
      if !opt.nil?
        network_options << {'name' => opt['name'], 'value' => opt['id']}
      end
    end

    network_interface_type_options = []
    network_interface_types.each do |opt|
      if !opt.nil?
        network_interface_type_options << {'name' => opt['name'], 'value' => opt['id']}
      end
    end

    interface_index = 0
    add_another_interface = true
    while add_another_interface do
      # if !no_prompt
      #   if interface_index == 0
      #     puts "Configure Network Interface"
      #   else
      #     puts "Configure Network Interface #{interface_index+1}"
      #   end
      # end

      # networkInterfaces may be passed as objects from blueprints or via -O networkInterfaces='[]'
      field_context = interface_index == 0 ? "networkInterface" : "networkInterface#{interface_index+1}"
      network_interface = {}
      if options[:options] && options[:options]['networkInterfaces'] && options[:options]['networkInterfaces'][interface_index]
        network_interface = options[:options]['networkInterfaces'][interface_index]
      end

      default_network_id = network_interface['networkId'] || network_interface['id']
      if default_network_id.nil? && network_interface['network'].is_a?(Hash) && network_interface['network']['id']
        default_network_id = network_interface['network']['id']
      end
      # JD: this for cluster or server prompting perhaps?
      # because zoneNetworkOptions already returns foramt like "id": "network-1"
      if !default_network_id || !default_network_id.to_s.include?("-")
        if network_interface['network'] && network_interface['network']['id']
          if network_interface['network']['subnet']
            default_network_id = "subnet-#{network_interface['network']['subnet']}"
          elsif network_interface['network']['group']
            default_network_id = "networkGroup-#{network_interface['network']['group']}"
          else
            default_network_id = "network-#{network_interface['network']['id']}"
          end
        end
      end

      default_network_value = (network_options.find {|n| n['value'] == default_network_id} || {})['name']

      # choose network
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'networkId', 'type' => 'select', 'fieldLabel' => "Network", 'selectOptions' => network_options, 'required' => true, 'skipSingleOption' => false, 'description' => 'Choose a network for this interface.', 'defaultValue' => default_network_value}], options[:options], api_client, {}, no_prompt, true)
      network_interface['network'] = {}
      network_interface['network']['id'] = v_prompt[field_context]['networkId'].to_s
      selected_network = networks.find {|it| it["id"].to_s == network_interface['network']['id'] }
      #network_options.reject! {|it| it['value'] == v_prompt[field_context]['networkId']}

      if !selected_network
        print_red_alert "Network not found by id #{network_interface['network']['id']}!"
        exit 1
      end

      # choose network interface type
      if enable_network_type_selection && !network_interface_type_options.empty?
        default_interface_type_value = (network_interface_type_options.find {|t| t['value'].to_s == network_interface['networkInterfaceTypeId'].to_s} || {})['name']
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'networkInterfaceTypeId', 'type' => 'select', 'fieldLabel' => "Network Interface Type", 'selectOptions' => network_interface_type_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a network interface type.', 'defaultValue' => default_interface_type_value}], options[:options])
        network_interface['networkInterfaceTypeId'] = v_prompt[field_context]['networkInterfaceTypeId'].to_i
        selected_network_interface_type = network_interface_types.find {|it| it["id"] == network_interface['networkInterfaceTypeId']}
      end

      # determine if IP can/should be specified for selected network
      ip_flags = determine_ip_requirements(selected_network)
      ip_available = ip_flags[:ip_available]
      ip_required = ip_flags[:ip_required]

      # Prompt for IP input when static assignment is allowed or an IP is explicitly required
      if ip_available || ip_required
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'ipAddress', 'type' => 'text', 'fieldLabel' => "IP Address", 'required' => ip_required, 'description' => 'Enter an IP for this network interface. x.x.x.x', 'defaultValue' => network_interface['ipAddress']}], options[:options])
        if v_prompt[field_context] && !v_prompt[field_context]['ipAddress'].to_s.empty?
          network_interface['ipAddress'] = v_prompt[field_context]['ipAddress']
        end
      end

      if ip_required == false && network_interface['ipAddress'] == nil && selected_network['dhcpServer'] == true
        network_interface['ipMode'] = 'dhcp'
      elsif network_interface['ipAddress']
        network_interface['ipMode'] = 'static'
      end

      # prompt for virtual interfaces if supported by the selected network interface type
      virtual_interfaces = build_virtual_interfaces(
        selected_network_interface_type,
        networks,
        network_options,
        field_context,
        interface_index,
        options,
        no_prompt
      )
      virtual_interfaces ||= []
      network_interface['networkInterfaces'] = virtual_interfaces unless virtual_interfaces.empty?

      # append the interface
      network_interfaces << network_interface
      interface_index += 1
      if options[:options] && options[:options]['networkInterfaces'] && options[:options]['networkInterfaces'][interface_index]
        add_another_interface = true
      elsif (max_networks && network_interfaces.size >= max_networks) || network_options.count == 0
        add_another_interface = false
      else
        has_another_interface = options[:options] && options[:options]["networkInterface#{interface_index+1}"]
        add_another_interface = has_another_interface || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another network interface?", {:default => false}))
      end

    end

    return network_interfaces

  end

  # determine if IP can/should be specified for selected network
  def determine_ip_requirements(selected_network)
    ip_available = selected_network['allowStaticOverride'] != false
    ip_required = true
    if selected_network['id'].to_s.include?('networkGroup')
      ip_available = false
      ip_required = false
    elsif selected_network['pool']
      ip_required = false
    elsif selected_network['dhcpServer']
      ip_required = false
    end
    {ip_available: ip_available, ip_required: ip_required}
  end

  # utility to build virtual interfaces
  def build_virtual_interfaces(selected_network_interface_type, networks, network_options, field_context, interface_index, options, no_prompt)
    return [] unless selected_network_interface_type && selected_network_interface_type['hasVirtualInterfaces']

    virtual_interfaces = []
    vi_index = 0

    # gather virtual interface types for the selected network interface type
    vi_interface_types = selected_network_interface_type['virtualInterfaces'] || []
    vi_type_options = []
    vi_interface_types.each do |opt|
      next if opt.nil?
      vi_type_options << {'name' => opt['name'], 'value' => opt['id']}
    end

    preconfigured_vi_inputs = []
    if options[:options]
      if options[:options]['networkInterfaces'] &&
         options[:options]['networkInterfaces'][interface_index] &&
         options[:options]['networkInterfaces'][interface_index]['virtualInterfaces'].is_a?(Array)
        options[:options]['networkInterfaces'][interface_index]['virtualInterfaces'].each do |raw_vi|
          preconfigured_vi_inputs << raw_vi if raw_vi.is_a?(Hash)
        end
      end
    end

    # validate preconfigured virtual interfaces
    preconfigured_vi_inputs.each do |raw_vi|
      net_id = raw_vi['networkId'] ||
               (raw_vi['network'] && raw_vi['network']['id']) ||
               raw_vi['id']

      next if net_id.to_s.empty?

      vi_type_id = raw_vi['interfaceTypeId'] || raw_vi['networkInterfaceTypeId']
      vi_type_id = vi_type_id.to_i if vi_type_id
      if vi_type_id && !vi_type_options.find {|t| t['value'].to_i == vi_type_id }
        raise_command_error("Invalid virtual interfaceTypeId=#{vi_type_id} for virtual interface networkId=#{net_id}.")
      end

      selected_vif_network = networks.find {|it| it["id"].to_s == net_id.to_s }
      next unless selected_vif_network
      vif_ip_flags = determine_ip_requirements(selected_vif_network)

      # deep cloning the raw input
      vi_record = raw_vi.is_a?(Hash) ? Marshal.load(Marshal.dump(raw_vi)) : {}
      vi_record['network'] = {}
      vi_record['network']['id'] = net_id.to_s
      vi_record['networkInterfaceTypeId'] = vi_type_id

      if raw_vi['ipAddress']
        vi_record['ipMode'] = 'static'
      elsif vif_ip_flags[:ip_available] == false && vif_ip_flags[:ip_required] == false && selected_vif_network['dhcpServer'] == true
        vi_record['ipMode'] = 'dhcp'
      end

      virtual_interfaces << vi_record
      vi_index += 1
    end

    # Interactive addition (if allowed) after preconfigured ones
    confirm_message = virtual_interfaces.empty? ? "Add virtual network interface for 'interface-#{interface_index}'?" :
                        "Add another virtual network interface for 'interface-#{interface_index}'?"
    add_another_vi = !vi_type_options.empty? && !no_prompt && Morpheus::Cli::OptionTypes.confirm(confirm_message, {default: false})
    while add_another_vi
      vi_field_context = "#{field_context}_virtualInterface#{vi_index+1}"
      vi_prompt = Morpheus::Cli::OptionTypes.prompt(
        [
          {'fieldContext' => vi_field_context, 'fieldName' => 'networkId', 'type' => 'select', 'fieldLabel' => "Virtual Network", 'selectOptions' => network_options, 'required' => true, 'description' => 'Choose a virtual interface network name.'},
          {'fieldContext' => vi_field_context, 'fieldName' => 'interfaceTypeId', 'type' => 'select', 'fieldLabel' => "Virtual Network Interface Type", 'selectOptions' => vi_type_options, 'required' => true, 'description' => 'Choose a virtual interface type.'}
        ],
        options[:options]
      )

      vi_record = {
        'network' => {'id' => vi_prompt[vi_field_context]['networkId'].to_s},
        'networkInterfaceTypeId' => vi_prompt[vi_field_context]['interfaceTypeId'].to_s
      }
      selected_vif_network_id = vi_prompt[vi_field_context]['networkId'].to_s
      selected_vif_network = networks.find {|it| it["id"].to_s == selected_vif_network_id }

      vif_ip_flags = determine_ip_requirements(selected_vif_network)
      vif_ip_available = vif_ip_flags[:ip_available]
      vif_ip_required = vif_ip_flags[:ip_required]

      if vif_ip_available || vif_ip_required
        ip_prompt = Morpheus::Cli::OptionTypes.prompt(
          [
            {'fieldContext' => vi_field_context, 'fieldName' => 'ipAddress', 'type' => 'text',
             'fieldLabel' => "IP Address", 'required' => vif_ip_required,
             'description' => 'Enter an IP for this virtual interface. x.x.x.x',
             'defaultValue' => vi_record['ipAddress']}
          ],
          options[:options]
        )
        if ip_prompt[vi_field_context] && !ip_prompt[vi_field_context]['ipAddress'].to_s.empty?
          vi_record['ipAddress'] = ip_prompt[vi_field_context]['ipAddress']
        end
      end

      if vif_ip_required == false && vi_record['ipAddress'].nil? && selected_vif_network['dhcpServer'] == true
        vi_record['ipMode'] = 'dhcp'
      elsif vi_record['ipAddress']
        vi_record['ipMode'] = 'static'
      end

      virtual_interfaces << vi_record
      vi_index += 1
      add_another_vi = !no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another virtual network interface for 'interface-#{interface_index}'?", {default: false})
    end

    virtual_interfaces
  end

  # This recreates the behavior of multi_networks.js

  # Prompts user for environment variables for new instance
  # returns array of evar objects {id: null, name: "VAR", value: "somevalue"}
  def prompt_evars(options={})
    #puts "Configure Environment Variables:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    evars = []
    evar_index = 0
    has_another_evar = options[:options] && options[:options]["evar#{evar_index}"]
    add_another_evar = has_another_evar || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add an environment variable?", {default: false}))
    while add_another_evar do
      field_context = "evar#{evar_index}"
      evar = {}
      evar['id'] = nil
      evar_label = evar_index == 0 ? "ENV" : "ENV [#{evar_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{evar_label} Name", 'required' => true, 'description' => 'Environment Variable Name.', 'defaultValue' => evar['name']}], options[:options])
      evar['name'] = v_prompt[field_context]['name']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => "#{evar_label} Value", 'required' => true, 'description' => 'Environment Variable Value', 'defaultValue' => evar['value']}], options[:options])
      evar['value'] = v_prompt[field_context]['value']
      evars << evar
      evar_index += 1
      has_another_evar = options[:options] && options[:options]["evar#{evar_index}"]
      add_another_evar = has_another_evar || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another environment variable?", {default: false}))
    end

    return evars
  end

  # Converts metadata tags array into a string like "name:value, foo:bar"
  def format_metadata(tags)
    if tags.nil? || tags.empty?
      ""
    elsif tags.instance_of?(Array)
      tags.collect {|tag| "#{tag['name']}: #{tag['value']}" }.sort.join(", ")
    elsif tags.instance_of?(Hash)
      tags.collect {|k,v| "#{k}: #{v}" }.sort.join(", ")
    else
      tags.to_s
    end
  end

  # Parses metadata tags object (string) into an array
  def parse_metadata(val)
    metadata = nil
    if val
      if val == "[]" || val == "null"
        metadata = []
      elsif val.is_a?(Array)
        metadata = val
      else
        # parse string into format name:value, name:value
        # merge IDs from current metadata
        # todo: should allow quoted semicolons..
        metadata_list = val.to_s.split(",").select {|it| !it.to_s.empty? }
        metadata_list = metadata_list.collect do |it|
          metadata_pair = it.include?(":") ? it.split(":") : it.split("=")
          row = {}
          row['name'] = metadata_pair[0].to_s.strip
          row['value'] = metadata_pair[1].to_s.strip
          # hacky way to set masked flag to true of false to (masked) in the value itself
          if(row['value'].include?("(masked)"))
            row['value'] = row['value'].gsub("(masked)", "").strip
            row['masked'] = true
          end
          if(row['value'].include?("(unmasked)"))
            row['value'] = row['value'].gsub("(unmasked)", "").strip
            row['masked'] = false
          end
          row
        end
        metadata = metadata_list
      end
    end
    return metadata
  end

  # Prompts user for environment variables for new instance
  # returns array of metadata objects {id: null, name: "MYTAG", value: "myvalue"}
  def prompt_metadata(options={})
    #puts "Configure Environment Variables:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    metadata_array = []
    metadata_index = 0
    # Keep Current Tags (foo:bar,hello:world)
    # this is used by clone()
    if options[:current_tags] && !options[:current_tags].empty?
      current_tags_string = options[:current_tags].collect { |tag| tag['name'].to_s + '=' + tag['value'].to_s }.join(', ')
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'keepExistingTags', 'type' => 'checkbox', 'fieldLabel' => "Keep existing metadata tags (#{current_tags_string}) ?", 'required' => true, 'description' => 'Whether or not to keep existing metadata tags', 'defaultValue' => true}], options[:options])
      if ['on','true','1',''].include?(v_prompt['keepExistingTags'].to_s.downcase)
        options[:current_tags].each do |tag|
          current_tag = tag.clone
          current_tag.delete('id')
          metadata_array << current_tag
        end
      end
    end
    has_another_metadata = options[:options] && options[:options]["metadata#{metadata_index}"]
    add_another_metadata = has_another_metadata || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add a metadata tag?", {default: false}))
    while add_another_metadata do
      field_context = "metadata#{metadata_index}"
      metadata = {}
      #metadata['id'] = nil
      metadata_label = metadata_index == 0 ? "Metadata Tag" : "Metadata Tag [#{metadata_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{metadata_label} Name", 'required' => true, 'description' => 'Metadata Tag Name.', 'defaultValue' => metadata['name']}], options[:options])
      # todo: metadata.type ?
      metadata['name'] = v_prompt[field_context]['name']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'value', 'type' => 'text', 'fieldLabel' => "#{metadata_label} Value", 'required' => true, 'description' => 'Metadata Tag Value', 'defaultValue' => metadata['value']}], options[:options])
      metadata['value'] = v_prompt[field_context]['value']
      metadata_array << metadata
      metadata_index += 1
      has_another_metadata = options[:options] && options[:options]["metadata#{metadata_index}"]
      add_another_metadata = has_another_metadata || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another metadata tag?", {default: false}))
    end

    return metadata_array
  end

  def prompt_security_groups(sg_option_type, api_params, options)
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    security_groups_array = []
    sg_required = sg_option_type['required']
    sg_index = 0
    add_another_sg = sg_required || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add a security group?", {default: false}))
    while add_another_sg do
      cur_sg_option_type = sg_option_type.merge({'required' => (sg_index == 0 ? sg_required : false)})
      if sg_index == 0 && !options[:default_security_group].nil?
        cur_sg_option_type['defaultValue'] = options[:default_security_group]
      end
      field_context = cur_sg_option_type['fieldContext']
      field_name = cur_sg_option_type['fieldName']
      v_prompt = Morpheus::Cli::OptionTypes.prompt([cur_sg_option_type], options[:options], api_client, api_params)
      has_another_sg = false
      if field_context
        if v_prompt[field_context] && !v_prompt[field_context][field_name].to_s.empty?
          security_groups_array << v_prompt[field_context][field_name]
        end
        has_another_sg = options[:options] && options[:options][field_context] && options[:options][field_context]["#{field_name}#{sg_index+2}"]
      else
        if !v_prompt[field_name].to_s.empty?
          security_groups_array << v_prompt[field_name]
        end
        has_another_sg = options[:options] && options[:options]["#{field_name}#{sg_index+2}"]
      end
      add_another_sg = has_another_sg || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another security group?", {default: false}))
      sg_index += 1
    end

    return security_groups_array
  end

  # Prompts user for load balancer settings
  # returns Hash of parameters like {loadBalancerId: "-1", etc}
  def prompt_instance_load_balancer(instance, default_lb_id, options)
    #puts "Configure Environment Variables:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    payload = {}
    api_params = {}
    if instance['id']
      api_params['instanceId'] = instance['id']
    end
    if instance['zone']
      api_params['zoneId'] = instance['zone']['id']
    elsif instance['cloud']
      api_params['zoneId'] = instance['cloud']['id']
    end
    if instance['group']
      api_params['siteId'] = instance['group']['id']
    elsif instance['site']
      api_params['siteId'] = instance['site']['id']
    end
    if instance['plan']
      api_params['planId'] = instance['plan']['id']
    end
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'loadBalancerId', 'type' => 'select', 'fieldLabel' => "Load Balancer", 'optionSource' => 'loadBalancers', 'required' => true, 'description' => 'Select Load Balancer for instance', 'defaultValue' => default_lb_id || ''}], options[:options], api_client, api_params)
    lb_id = v_prompt['loadBalancerId']
    payload['loadBalancerId'] = lb_id

    # todo: finish implmenting this

    # loadBalancerId
    # loadBalancerProxyProtocol
    # loadBalancerName
    # loadBalancerDescription
    # loadBalancerSslCert
    # loadBalancerScheme
    
    return payload
  end

  def prompt_cluster_load_balancer(cluster, options, can_use_kubevip)
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'loadBalancerTypeId', 'type' => 'select', 'fieldLabel' => "Load Balancer", 'optionSource' => 'loadBalancerTypes', 'required' => false, 'description' => 'Select Load Balancer for Cluster', 'defaultValue' => '', 'excludeKubevip' => !can_use_kubevip}], options[:options], api_client, cluster)
    lb_type_id = v_prompt['loadBalancerTypeId']

    if lb_type_id.empty?
      return false
    end

    return lb_type_id
  end


  # reject old option types that now come from the selected service plan
  # these will eventually get removed from the associated optionTypes
  def reject_service_plan_option_types(option_types)
    option_types.reject {|opt|
      ['cpuCount', 'memorySize', 'memory'].include?(opt['fieldName'])
    }
  end

  def get_available_environments(refresh=false)
    if !@available_environments || refresh
      begin
        option_results = options_interface.options_for_source('environments',{})
        @available_environments = option_results['data'].collect {|it|
          {"code" => (it["code"] || it["value"]), "name" => it["name"], "value" => it["value"]}
        }
      rescue RestClient::Exception => e
        # if e.response && e.response.code == 404
          Morpheus::Logging::DarkPrinter.puts "Unable to determine available environments, using default options" if Morpheus::Logging.debug?
          @available_environments = get_static_environments()
        # else
        #   raise e
        # end
      end
    end
    return @available_environments
  end

  def get_static_environments
    [{'name' => 'Dev', 'value' => 'dev'}, {'name' => 'Test', 'value' => 'qa'}, {'name' => 'Staging', 'value' => 'staging'}, {'name' => 'Production', 'value' => 'production'}]
  end

  def add_perms_options(opts, options, excludes = [])
    if !excludes.include?('groups')
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        options[:groupAccessAll] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options[:groupAccessList] = []
        else
          options[:groupAccessList] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      if !excludes.include?('groupDefaults')
        opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
          if list.size == 1 && list[0] == 'null' # hacky way to clear it
            options[:groupDefaultsList] = []
          else
            options[:groupDefaultsList] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          end
        end
      end
    end

    if !excludes.include?('plans')
      opts.on('--plan-access-all [on|off]', String, "Toggle Access for all service plans.") do |val|
        options[:planAccessAll] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--plan-access LIST', Array, "Service Plan Access, comma separated list of plan IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options[:planAccessList] = []
        else
          options[:planAccessList] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--plan-defaults LIST', Array, "Plan Default Selection, comma separated list of plan IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options[:planDefaultsList] = []
        else
          options[:planDefaultsList] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
    end

    if !excludes.include?('visibility')
      opts.on('--visibility VISIBILITY', String, "Visibility [private|public]") do |val|
        options[:visibility] = val
      end
    end

    if !excludes.include?('tenants')
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options[:tenants] = []
        else
          options[:tenants] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
    end
  end

  def prompt_permissions(options, excludes = [])
    all_groups = nil
    group_access = nil
    all_plans = nil
    plan_access = nil
    permissions = {}

    # Group Access
    unless excludes.include?('groups')
      if !options[:groupAccessAll].nil?
        all_groups = options[:groupAccessAll]
      end

      if !options[:groupAccessList].empty?
        group_access = options[:groupAccessList].collect {|site_id| 
          found_group = find_group_by_name_or_id_for_provisioning(site_id)
          return 1, "group not found by #{site_id}" if found_group.nil?
          {'id' => found_group['id']}
        } || []
      elsif !options[:no_prompt] && !all_groups
        available_groups = options[:available_groups] || get_available_groups

        if available_groups.empty?
          #print_red_alert "No available groups"
          #exit 1
        elsif available_groups.count > 1
          available_groups.unshift({"id" => '0', "name" => "All", "value" => "all"})

          # default to all
          group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group Access', 'selectOptions' => available_groups, 'required' => false, 'description' => 'Add Group Access.'}], options[:options], @api_client, {})['group']

          if !group_id.nil?
            if group_id == 'all'
              all_groups = true
            else
              group_access = (excludes.include?('groupDefaults') ? [{'id' => group_id}] : [{'id' => group_id, 'default' => Morpheus::Cli::OptionTypes.confirm("Set '#{available_groups.find{|it| it['value'] == group_id}['name']}' as default?", {:default => false})}])
            end
            available_groups = available_groups.reject {|it| it['value'] == group_id}

            while !group_id.nil? && !available_groups.empty? && Morpheus::Cli::OptionTypes.confirm("Add another group access?", {:default => false})
              group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group Access', 'selectOptions' => available_groups, 'required' => false, 'description' => 'Add Group Access.'}], options[:options], @api_client, {})['group']

              if !group_id.nil?
                if group_id == 'all'
                  all_groups = true
                else
                  group_access ||= []
                  group_access << (excludes.include?('groupDefaults') ? {'id' => group_id} : {'id' => group_id, 'default' => Morpheus::Cli::OptionTypes.confirm("Set '#{available_groups.find{|it| it['value'] == group_id}['name']}' as default?", {:default => false})})
                end
                available_groups = available_groups.reject {|it| it['value'] == group_id}
              end
            end
          end
        end
      end
    end

    # Plan Access
    unless excludes.include?('plans')
      if !options[:planAccessAll].nil?
        all_plans = options[:planAccessAll]
      end

      if !options[:planAccessList].empty?
        plan_access = options[:planAccessList].collect {|plan_id| {'id' => plan_id.to_i}}
      elsif !options[:no_prompt]
        available_plans = options[:available_plans] || get_available_plans

        if available_plans.empty?
          #print_red_alert "No available plans"
          #exit 1
        elsif !available_plans.empty? && !options[:no_prompt]
          available_plans.unshift({"id" => '0', "name" => "All", "value" => "all"})

          # default to all
          plan_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Service Plan Access', 'selectOptions' => available_plans, 'required' => false, 'description' => 'Add Service Plan Access.'}], options[:options], @api_client, {})['plan']

          if !plan_id.nil?
            if plan_id == 'all'
              all_plans = true
            else
              plan_access = [{'id' => plan_id, 'default' => Morpheus::Cli::OptionTypes.confirm("Set '#{available_plans.find{|it| it['value'] == plan_id}['name']}' as default?", {:default => false})}]
            end

            available_plans = available_plans.reject {|it| it['value'] == plan_id}

            while !plan_id.nil? && !available_plans.empty? && Morpheus::Cli::OptionTypes.confirm("Add another service plan access?", {:default => false})
              plan_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Service Plan Access', 'selectOptions' => available_plans, 'required' => false, 'description' => 'Add Service Plan Access.'}], options[:options], @api_client, {})['plan']

              if !plan_id.nil?
                if plan_id == 'all'
                  all_plans = true
                else
                  plan_access ||= []
                  plan_access << {'id' => plan_id, 'default' => Morpheus::Cli::OptionTypes.confirm("Set '#{available_plans.find{|it| it['value'] == plan_id}['name']}' as default?", {:default => false})}
                end
                available_plans = available_plans.reject {|it| it['value'] == plan_id}
              end
            end
          end
        end
      end
    end

    unless excludes.include?('resource')
      resource_perms = {}
      resource_perms['all'] = all_groups if !all_groups.nil?
      resource_perms['sites'] = group_access if !group_access.nil?
      resource_perms['allPlans'] = all_plans if !all_plans.nil?
      resource_perms['plans'] = plan_access if !plan_access.nil?
      permissions['resourcePermissions'] = resource_perms
    end

    available_accounts = get_available_accounts() #.collect {|it| {'name' => it['name'], 'value' => it['id']}}
    accounts = []

    # Prompts for multi tenant
    if available_accounts.count > 1
      visibility = options[:visibility]
      unless excludes.include?('visibility')
        if !visibility && !options[:no_prompt]
          visibility = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Tenant Permissions Visibility', 'type' => 'select', 'defaultValue' => 'private', 'required' => true, 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}]}], options[:options], @api_client, {})['visibility']
        end
        permissions['resourcePool'] = {'visibility' => visibility} if visibility
      end

      # Tenants
      default_stores = []
      default_targets = []
      unless excludes.include?('tenants')
        if !options[:tenants].nil?
          accounts = options[:tenants].collect {|id| id.to_i}
        elsif !options[:no_prompt]
          account_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'account', 'type' => 'select', 'fieldLabel' => 'Add Tenant', 'selectOptions' => available_accounts, 'required' => false, 'description' => 'Add Tenant Permissions.'}], options[:options], @api_client, {})['account']

          unless account_id.nil?
            accounts << account_id
            available_accounts = available_accounts.reject {|it| it['value'] == account_id}

            # Prompt default store / target
            if options[:for_datastore]
              if Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultTarget', 'type' => 'checkbox', 'fieldLabel' => 'Default', 'required' => false, 'description' => 'Designate as Default Store.', 'defaultValue' => false}], options[:options].merge({:checkbox_as_boolean => true}), @api_client, {})['defaultTarget']
                default_targets << account_id
              end
              if Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultStore', 'type' => 'checkbox', 'fieldLabel' => 'Image Target', 'required' => false, 'description' => 'Designate as Image Target.', 'defaultValue' => false}], options[:options].merge({:checkbox_as_boolean => true}), @api_client, {})['defaultStore']
                default_stores << account_id
              end
            end

            while !available_accounts.empty? && (account_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'account', 'type' => 'select', 'fieldLabel' => 'Add Another Tenant', 'selectOptions' => available_accounts, 'required' => false, 'description' => 'Add Tenant Permissions.'}], options[:options], @api_client, {})['account'])
              if !account_id.nil?
                accounts << account_id
                available_accounts = available_accounts.reject {|it| it['value'] == account_id}

                # Prompt default store / target
                if options[:for_datastore]
                  if Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultTarget', 'type' => 'checkbox', 'fieldLabel' => 'Default', 'required' => false, 'description' => 'Designate as Default Store.', 'defaultValue' => false}], options[:options].merge({:checkbox_as_boolean => true}), @api_client, {})['defaultTarget']
                    default_targets << account_id
                  end
                  if Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultStore', 'type' => 'checkbox', 'fieldLabel' => 'Image Target', 'required' => false, 'description' => 'Designate as Image Target.', 'defaultValue' => false}], options[:options].merge({:checkbox_as_boolean => true}), @api_client, {})['defaultStore']
                    default_stores << account_id
                  end
                end
              end
            end
          end
        end
        if options[:for_datastore]
          permissions['tenantPermissions'] = accounts.collect {|it| {'id' => it, 'defaultStore' => default_stores.include?(it), 'defaultTarget' => default_targets.include?(it)}}
        else
          permissions['tenantPermissions'] = {'accounts' => accounts}
        end
      end
    end
    permissions
  end

  def prompt_permissions_v2(options, excludes = [])
    perms = prompt_permissions(options, excludes)
    rtn = {}
    rtn['visibility'] = perms['resourcePool']['visibility'] if !perms['resourcePool'].nil? && !excludes.include?('visibility')
    rtn['tenants'] = ((perms['tenantPermissions'] || {})['accounts'] || []).collect {|it| {'id' => it}}
    rtn
  end

  def print_permissions(permissions, excludes = [])
    if permissions.nil?
      print_h2 "Permissions"
      print yellow,"No permissions found.",reset,"\n"
    else
      if !permissions['resourcePermissions'].nil?
        if !excludes.include?('groups')
          print_h2 "Group Access"

          if excludes.include?('groupDefaults')
            groups = []
            groups << 'All' if permissions['resourcePermissions']['all']
            groups += permissions['resourcePermissions']['sites'].collect {|it| it['name']} if permissions['resourcePermissions']['sites']

            if groups.count > 0
              print cyan,"#{groups.join(', ')}".center(20)
            else
              print yellow,"No group access",reset,"\n"
            end
            print "\n"
          else
            rows = []
            if permissions['resourcePermissions']['all']
              rows.push({group: 'All'})
            end
            if permissions['resourcePermissions']['sites']
              permissions['resourcePermissions']['sites'].each do |site|
                rows.push({group: site['name'], default: site['default'] ? 'Yes' : ''})
              end
            end
            if rows.empty?
              print yellow,"No group access",reset,"\n"
            else
              columns = [:group, :default]
              print cyan
              print as_pretty_table(rows, columns)
            end
          end
        end

        if !excludes.include?('plans')
          print_h2 "Plan Access"
          rows = []
          if permissions['resourcePermissions']['allPlans']
            rows.push({plan: 'All'})
          end
          if permissions['resourcePermissions']['plans']
            permissions['resourcePermissions']['plans'].each do |plan|
              rows.push({plan: plan['name'], default: plan['default'] ? 'Yes' : ''})
            end
          end
          if rows.empty?
            print yellow,"No plan access",reset,"\n"
          else
            columns = [:plan, :default]
            print cyan
            print as_pretty_table(rows, columns)
          end
        end

        if !excludes.include?('tenants')
          if !permissions['tenantPermissions'].nil?
            print_h2 "Tenant Permissions"
            if !permissions['resourcePool'].nil?
              print cyan
              print "Visibility: #{permissions['resourcePool']['visibility'].to_s.capitalize}".center(20)
              print "\n"
            end
            if !permissions['tenantPermissions'].nil?
              print cyan
              print "Accounts: #{permissions['tenantPermissions']['accounts'].join(', ')}".center(20)
              print "\n"
            end
          end
        end
        print "\n"
      end
    end
  end


  ## Exposed Ports component

  def load_balance_protocols_dropdown
    [
      {'name' => 'None', 'value' => ''},
      {'name' => 'HTTP', 'value' => 'HTTP'},
      {'name' => 'HTTPS', 'value' => 'HTTPS'},
      {'name' => 'TCP', 'value' => 'TCP'}
    ]
  end

  # Prompts user for ports array
  # returns array of port objects
  def prompt_exposed_ports(options={}, api_client=nil, api_params={})
    #puts "Configure ports:"
    passed_ports = ((options[:options] && options[:options]["ports"]) ? options[:options]["ports"] : nil)
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    # skip prompting?
    if no_prompt
      return passed_ports
    end
    # value already given
    if passed_ports.is_a?(Array)
      return passed_ports
    end

    # prompt for ports
    ports = []
    port_index = 0
    has_another_port = options[:options] && options[:options]["ports"]
    add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add an exposed port?", {default:false}))
    while add_another_port do
      field_context = port_index == 0 ? "ports" : "ports#{port_index}"

      port = {}
      port_label = port_index == 0 ? "Port" : "Port [#{port_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{port_label} Name", 'required' => false, 'description' => 'Choose a name for this port.', 'defaultValue' => port['name']}], options[:options])
      port['name'] = v_prompt[field_context]['name']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'port', 'type' => 'number', 'fieldLabel' => "#{port_label} Number", 'required' => true, 'description' => 'A port number. eg. 8001', 'defaultValue' => (port['port'] ? port['port'].to_i : nil)}], options[:options])
      port['port'] = v_prompt[field_context]['port']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'lb', 'type' => 'select', 'fieldLabel' => "#{port_label} LB", 'required' => false, 'selectOptions' => load_balance_protocols_dropdown, 'description' => 'Choose a load balance protocol.', 'defaultValue' => port['lb']}], options[:options])
      # port['loadBalanceProtocol'] = v_prompt[field_context]['lb']
      port['lb'] = v_prompt[field_context]['lb']

      ports << port
      port_index += 1
      has_another_port = options[:options] && options[:options]["ports#{port_index}"]
      add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another exposed port?", {default:false}))
    end


    return ports
  end

  def prompt_service_plan_options(plan_info, options={}, api_client=nil, api_params={}, instance=nil)
    plan_opts = {}
    # provisioning with blueprint can lock fields
    locked_fields = options[:locked_fields] || []
    if options[:options]['servicePlanOptions']
      plan_opts = options[:options]['servicePlanOptions']
    end
    default_max_cores = plan_info['maxCores'].to_i != 0 ? plan_info['maxCores'] : 1
    default_cores_per_socket = plan_info['coresPerSocket'].to_i != 0 ? plan_info['coresPerSocket'] : 1
    default_max_memory = plan_info['maxMemory'].to_i != 0 ? plan_info['maxMemory'] : nil
    # use defaults from the instance/server
    if instance
      default_max_cores = instance["maxCores"] if instance["maxCores"]
      default_cores_per_socket = instance["coresPerSocket"] if instance["coresPerSocket"]
      default_max_memory = instance["maxMemory"] if instance["maxMemory"]
    end
    # Core Count
    if plan_info["customCores"]
      if locked_fields.include?('servicePlanOptions.maxCores')
        if options[:options]['servicePlanOptions'] && options[:options]['servicePlanOptions']['maxCores']
          plan_opts['maxCores'] = options[:options]['servicePlanOptions']['maxCores'].to_i
        end
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'servicePlanOptions', 'fieldName' => 'maxCores', 'type' => 'number', 'fieldLabel' => "Core Count", 'required' => true, 'defaultValue' => default_max_cores, 'description' => "Customize service plan options Core Count"}], options[:options])
        if v_prompt['servicePlanOptions'] && v_prompt['servicePlanOptions']['maxCores']
          plan_opts['maxCores'] = v_prompt['servicePlanOptions']['maxCores'].to_i
        end
      end
    end
    # Cores Per Socket
    if plan_info["customCoresPerSocket"]
      if locked_fields.include?('servicePlanOptions.coresPerSocket')
        if options[:options]['servicePlanOptions'] && options[:options]['servicePlanOptions']['coresPerSocket']
          plan_opts['coresPerSocket'] = options[:options]['servicePlanOptions']['coresPerSocket'].to_i
        end
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'servicePlanOptions', 'fieldName' => 'coresPerSocket', 'type' => 'number', 'fieldLabel' => "Cores Per Socket", 'required' => true, 'defaultValue' => default_cores_per_socket, 'description' => "Customize service plan options Cores Per Socket"}], options[:options])
        if v_prompt['servicePlanOptions'] && v_prompt['servicePlanOptions']['coresPerSocket']
          plan_opts['coresPerSocket'] = v_prompt['servicePlanOptions']['coresPerSocket'].to_i
        end
      end
    end
    # Memory
    if plan_info["customMaxMemory"]
      if locked_fields.include?('servicePlanOptions.maxMemory')
        if options[:options]['servicePlanOptions'] && options[:options]['servicePlanOptions']['maxMemory']
          plan_opts['maxMemory'] = options[:options]['servicePlanOptions']['maxMemory'].to_i
        end
      else
        if options[:options]['servicePlanOptions'] && options[:options]['servicePlanOptions']['maxMemory']
          plan_opts['maxMemory'] = options[:options]['servicePlanOptions']['maxMemory'].to_i
        else
          # prompt for "memoryMB" field as MB or "memoryGB" in GB
          # always convert maxMemory to bytes
          if plan_info["memorySizeType"] == "MB" || options[:options]["memoryMB"]
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memoryMB', 'type' => 'text', 'fieldLabel' => "Memory (MB)", 'required' => true, 'defaultValue' => default_max_memory ? (default_max_memory / (1024 * 1024)) : nil, 'description' => "Customize service plan options Memory (MB). Value is in megabytes."}], options[:options])
            if v_prompt['memoryMB'].to_s != ""
              plan_opts['maxMemory'] = v_prompt['memoryMB'].to_i * 1024 * 1024
            end
          else
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memoryGB', 'type' => 'text', 'fieldLabel' => "Memory (GB)", 'required' => true, 'defaultValue' => default_max_memory ? (default_max_memory / (1024 * 1024 * 1024)) : nil, 'description' => "Customize service plan options Memory (GB). Value is in gigabytes."}], options[:options])
            if v_prompt['memoryGB'].to_s != ""
              plan_opts['maxMemory'] = v_prompt['memoryGB'].to_i * 1024 * 1024 * 1024
            end
          end
          # remove transient memory field just used for prompting for MB or GB
          plan_opts.delete("memoryMB")
          plan_opts.delete("memoryGB")
        end
      end
    end
    return plan_opts
  end

  def format_instance_status(instance, return_color=cyan)
    out = ""
    status_string = instance['status'].to_s
    if status_string == 'running'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'provisioning'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_instance_connection_string(instance)
    if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
      connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
    end
  end

  def format_app_status(app, return_color=cyan)
    out = ""
    status_string = app['status'] || app['appStatus'] || ''
    if status_string == 'running'
      out = "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'provisioning'
      out = "#{cyan}#{status_string.upcase}#{cyan}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out = "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out = "#{yellow}#{status_string.upcase}#{return_color}"
    elsif status_string == 'warning' && app['instanceCount'].to_i == 0
      # show this instead of WARNING
      out =  "#{cyan}EMPTY#{return_color}"
    else
      out =  "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end
  
  def format_container_status(container, return_color=cyan)
    out = ""
    status_string = container['status'].to_s
    if status_string == 'running'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'provisioning'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_container_connection_string(container)
    if !container['ports'].nil? && container['ports'].empty? == false
      connection_string = "#{container['ip']}:#{container['ports'][0]['external']}"
    else
      # eh? more logic needed here i think, see taglib morph:containerLocationMenu
      connection_string = "#{container['ip']}"
    end
  end
  
  def format_instance_container_display_name(instance, plural=false)
    #<span class="info-label">${[null,'docker'].contains(instance.layout?.provisionType?.code) ? 'Containers' : 'Virtual Machines'}:</span> <span class="info-value">${instance.containers?.size()}</span>
    v = plural ? "Containers" : "Container"
    if instance && instance['layout'] && instance['layout'].key?("provisionTypeCode")
      if [nil, 'docker'].include?(instance['layout']["provisionTypeCode"])
        v = plural ? "Virtual Machines" : "Virtual Machine"
      end
    end
    return v
  end

  def format_blueprint_type(type_code)
    return type_code.to_s # just show it as is
    if type_code.to_s.empty?
      type_code = "morpheus"
    end
    if type_code.to_s.downcase == "arm"
      "ARM"
    else
      return type_code.to_s.capitalize
    end
  end

  def parse_blueprint_type(type_code)
    return type_code.to_s # just use it as is
    # if type_code.to_s.empty?
    #   type_code = "morpheus"
    # end
    if type_code.to_s.downcase == "arm"
      "arm"
    elsif type_code.to_s.downcase == "cloudformation"
      type_code = "cloudFormation"
    else
      return type_code.to_s.downcase
    end
  end

  def format_snapshot_status(snapshot, return_color=cyan)
    out = ""
    status_string = snapshot['status'].to_s
    if status_string == 'complete'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'creating'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end
end
