require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
# Mixin for Morpheus::Cli command classes
# Provides common methods for library management commands
module Morpheus::Cli::LibraryHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def api_client
    raise "#{self.class} has not defined @api_client" if @api_client.nil?
    @api_client
  end

  def find_instance_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_instance_type_by_id(val)
    else
      return find_instance_type_by_name(val)
    end
  end

  def find_instance_type_by_id(id)
    begin
      json_response = @library_instance_types_interface.get(id.to_i)
      return json_response['instanceType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance Type not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_instance_type_by_name(name)
    json_response = @library_instance_types_interface.list({name: name.to_s})
    instance_types = json_response['instanceTypes']
    if instance_types.empty?
      print_red_alert "Instance Type not found by name #{name}"
      return nil
    elsif instance_types.size > 1
      print_red_alert "#{instance_types.size} instance types found by name #{name}"
      print_instance_types_table(instance_types, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return instance_types[0]
    end
  end

  def print_instance_types_table(instance_types, opts={})
    columns = [
      {"ID" => lambda {|instance_type| instance_type['id'] } },
      {"NAME" => lambda {|instance_type| instance_type['name'] } },
      {"CODE" => lambda {|instance_type| instance_type['code'] } },
      {"TECHNOLOGY" => lambda {|instance_type| format_instance_type_technology(instance_type) } },
      {"CATEGORY" => lambda {|instance_type| instance_type['category'].to_s.capitalize } },
      {"FEATURED" => lambda {|instance_type| format_boolean instance_type['featured'] } },
      {"OWNER" => lambda {|instance_type| instance_type['account'] ? instance_type['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(instance_types, columns, opts)
  end

  def format_instance_type_technology(instance_type)
    if instance_type
      instance_type['provisionTypeCode'].to_s.capitalize
    else
      ""
    end
  end

  def load_balance_protocols_dropdown
    [
      {'name' => 'None', 'value' => ''},
      {'name' => 'HTTP', 'value' => 'HTTP'},
      {'name' => 'HTTPS', 'value' => 'HTTPS'},
      {'name' => 'TCP', 'value' => 'TCP'}
    ]
  end

  # Prompts user for exposed ports array
  # returns array of port objects
  def prompt_exposed_ports(options={}, api_client=nil, api_params={})
    #puts "Configure ports:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))

    ports = []
    port_index = 0
    has_another_port = options[:options] && options[:options]["exposedPort#{port_index}"]
    add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add an exposed port?"))
    while add_another_port do
      field_context = "exposedPort#{port_index}"

      port = {}
      #port['name'] ||= "Port #{port_index}"
      port_label = port_index == 0 ? "Port" : "Port [#{port_index+1}]"
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => "#{port_label} Name", 'required' => false, 'description' => 'Choose a name for this port.', 'defaultValue' => port['name']}], options[:options])
      port['name'] = v_prompt[field_context]['name']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'port', 'type' => 'number', 'fieldLabel' => "#{port_label} Number", 'required' => true, 'description' => 'A port number. eg. 8001', 'defaultValue' => (port['port'] ? port['port'].to_i : nil)}], options[:options])
      port['port'] = v_prompt[field_context]['port']

      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => field_context, 'fieldName' => 'loadBalanceProtocol', 'type' => 'select', 'fieldLabel' => "#{port_label} LB", 'selectOptions' => load_balance_protocols_dropdown, 'required' => false, 'skipSingleOption' => true, 'description' => 'Choose a load balance protocol.', 'defaultValue' => port['loadBalanceProtocol']}], options[:options])
      port['loadBalanceProtocol'] = v_prompt[field_context]['loadBalanceProtocol']

      ports << port
      port_index += 1
      has_another_port = options[:options] && options[:options]["exposedPort#{port_index}"]
      add_another_port = has_another_port || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another exposed port?"))

    end


    return ports
  end

  ## Spec Template helper methods

  def find_spec_template_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_spec_template_by_id(val)
    else
      return find_spec_template_by_name(val)
    end
  end

  def find_spec_template_by_id(id)
    begin
      json_response = @spec_templates_interface.get(id.to_i)
      return json_response['specTemplate']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Spec Template not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_spec_template_by_name(name)
    resource_specs = @spec_templates_interface.list({name: name.to_s})['specTemplates']
    if resource_specs.empty?
      print_red_alert "Spec Template not found by name #{name}"
      return nil
    elsif resource_specs.size > 1
      print_red_alert "#{resource_specs.size} spec templates found by name #{name}"
      print_resource_specs_table(resource_specs, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return resource_specs[0]
    end
  end

  def print_resource_specs_table(resource_specs, opts={})
    columns = [
      {"ID" => lambda {|resource_spec| resource_spec['id'] } },
      {"NAME" => lambda {|resource_spec| resource_spec['name'] } },
      #{"OWNER" => lambda {|resource_spec| resource_spec['account'] ? resource_spec['account']['name'] : '' } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(resource_specs, columns, opts)
  end

  def find_spec_template_type_by_id(id)
    begin
      json_response = @spec_template_types_interface.get(id.to_i)
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

  # def find_spec_template_type_by_name(name)
  #   json_response = @spec_template_types_interface.list({name: name.to_s})
  #   spec_template_types = json_response['networkTypes']
  #   if spec_template_types.empty?
  #     print_red_alert "Network Type not found by name #{name}"
  #     return spec_template_types
  #   elsif spec_template_types.size > 1
  #     print_red_alert "#{spec_template_types.size} network types found by name #{name}"
  #     rows = spec_template_types.collect do |it|
  #       {id: it['id'], name: it['name']}
  #     end
  #     puts as_pretty_table(rows, [:id, :name], {color:red})
  #     return nil
  #   else
  #     return spec_template_types[0]
  #   end
  # end

  def find_spec_template_type_by_name_or_code(name)
    spec_template_types = get_all_spec_template_types().select { |it| name && it['code'] == name || it['name'] == name }
    if spec_template_types.empty?
      print_red_alert "Spec Template Type not found by code #{name}"
      return nil
    elsif spec_template_types.size > 1
      print_red_alert "#{spec_template_types.size} spec template types found by code #{name}"
      rows = spec_template_types.collect do |it|
        {id: it['id'], code: it['code'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :code, :name], {color:red})
      return nil
    else
      return spec_template_types[0]
    end
  end

  def find_spec_template_type_by_name_or_code_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_subnet_by_id(val)
    else
      return find_spec_template_type_by_name_or_code(val)
    end
  end

  def get_all_spec_template_types
    @all_spec_template_types ||= @spec_template_types_interface.list({max: 1000})['specTemplateTypes'] || []
  end

  def prompt_for_spec_templates(params, options={}, api_client=nil, api_params={})
    # spec_templates
    spec_template_list = nil
    spec_template_ids = nil
    still_prompting = true
    if params['specTemplates'].nil?
      still_prompting = true
      while still_prompting do
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'specTemplates', 'type' => 'text', 'fieldLabel' => 'Spec Templates', 'required' => false, 'description' => 'Spec Templates to include, comma separated list of names or IDs.'}], options[:options])
        unless v_prompt['specTemplates'].to_s.empty?
          spec_template_list = v_prompt['specTemplates'].split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
        spec_template_ids = []
        bad_ids = []
        if spec_template_list && spec_template_list.size > 0
          spec_template_list.each do |it|
            found_spec_template = nil
            begin
              found_spec_template = find_spec_template_by_name_or_id(it)
            rescue SystemExit => cmdexit
            end
            if found_spec_template
              spec_template_ids << found_spec_template['id']
            else
              bad_ids << it
            end
          end
        end
        still_prompting = bad_ids.empty? ? false : true
      end
    else
      spec_template_list = params['specTemplates']
      still_prompting = false
      spec_template_ids = []
      bad_ids = []
      if spec_template_list && spec_template_list.size > 0
        spec_template_list.each do |it|
          found_spec_template = nil
          begin
            found_spec_template = find_spec_template_by_name_or_id(it)
          rescue SystemExit => cmdexit
          end
          if found_spec_template
            spec_template_ids << found_spec_template['id']
          else
            bad_ids << it
          end
        end
      end
      if !bad_ids.empty?
        return {success:false, msg:"Spec Templates not found: #{bad_ids}"}
      end
    end
    return {success:true, data: spec_template_ids}
  end

end
