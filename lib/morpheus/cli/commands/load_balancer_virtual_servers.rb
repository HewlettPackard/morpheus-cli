require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerVirtualServers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_description "View and manage load balancer virtual servers."
  set_command_name :'load-balancer-virtual-servers'
  register_subcommands :list, :get, :add, :update, :remove

  register_interfaces :load_balancer_virtual_servers,
                      :load_balancers, :load_balancer_types

  set_rest_parent_name :load_balancers

  set_rest_arg 'vipName'

  # overridden to provide global list functionality without requiring parent argument
  def list(args)
    parent_id, parent_record = nil, nil
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_parent_arg}] [search]")
      if respond_to?("build_list_options_for_#{rest_key}", true)
        send("build_list_options_for_#{rest_key}", opts, options)
      else
        build_standard_list_options(opts, options)
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List #{rest_label_plural.downcase}.
[#{rest_parent_arg}] is optional. This is the #{rest_parent_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_parent_label)} #{rest_parent_label.downcase}.
[search] is optional. This is a search phrase to filter the results.
EOT
    end
    optparse.parse!(args)
    parent_id = args[0]
    verify_args!(args:args, optparse:optparse, min:0)
    if args.count > 1
      options[:phrase] = args[1..-1].join(" ")
    end
    connect(options)
    if parent_id
      parent_record = rest_parent_find_by_name_or_id(parent_id)
      if parent_record.nil?
        return 1, "#{rest_parent_label} not found for '#{parent_id}"
      end
      parent_id = parent_record['id']
    end
    if respond_to?("parse_list_options_for_#{rest_key}", true)
      # custom method to parse parameters for list request should return 0, nil if successful
      parse_result, parse_err = send("parse_list_options_for_#{rest_key}", options, params)
      if parse_result != 0
        return parse_result, parse_err
      end
    else
      params.merge!(parse_list_options(options))
    end
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
        print as_pretty_table(records, rest_list_column_definitions(options).upcase_keys!, options)
        print_results_pagination(json_response) if json_response['meta']
      end
      print reset,"\n"
    end
    return 0, nil
  end

  protected

  def build_list_options_for_load_balancer_virtual_server(opts, options)
    opts.on('--load-balancer LB', String, "Load Balancer Name or ID") do |val|
      options[:load_balancer] = val
    end
    build_standard_list_options(opts, options)
  end

  def parse_list_options_for_load_balancer_virtual_server(options, params)
    if options[:load_balancer]
      if options[:load_balancer].to_s !~ /\A\d{1,}\Z/
        load_balancer = find_by_name(:load_balancer, options[:load_balancer])
        if load_balancer.nil?
          return 1, "Load Balancer not found for '#{options[:load_balancer]}'"
        end
        params['loadBalancerId'] = load_balancer['id']
      else
        params['loadBalancerId'] = options[:load_balancer]
      end
    end
    params.merge!(parse_list_options(options))
    return 0, nil
  end

  def load_balancer_virtual_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'vipName',
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      # "Description" => 'description',
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : '(Unassigned)' },
      "Hostname" => lambda {|it| it['vipHostname'] },
      "VIP" => lambda {|it| it['vipAddress'] },
      "Protocol" => lambda {|it| it['vipProtocol'] },
      "Port" => lambda {|it| it['vipPort'] },
      "SSL" => lambda {|it| format_boolean(it['sslEnabled']) },
      "Status" => lambda {|it| format_virtual_server_status(it) },
    }
  end

  def load_balancer_virtual_server_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'vipName',
      "Description" => 'description',
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : '(Unassigned)' },
      "Hostname" => lambda {|it| it['vipHostname'] },
      "VIP" => lambda {|it| it['vipAddress'] },
      "Protocol" => lambda {|it| it['vipProtocol'] },
      "Port" => lambda {|it| it['vipPort'] },
      "SSL" => lambda {|it| format_boolean(it['sslEnabled']) },
      # todo: more properties to show here
      "Status" => lambda {|it| format_virtual_server_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def load_balancer_virtual_server_object_key
    'virtualServer'
  end

  def load_balancer_virtual_server_list_key
    'virtualServers'
  end

  def load_balancer_virtual_server_label
    'Virtual Server'
  end

  def load_balancer_virtual_server_label_plural
    'Virtual Servers'
  end

  def format_virtual_server_status(virtual_server, return_color=cyan)
    out = ""
    status_string = virtual_server['vipStatus'] || virtual_server['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'online'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{virtual_server['statusMessage'] ? "#{return_color} - #{virtual_server['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def load_option_types_for_load_balancer_virtual_server(type_record, parent_record)
    load_balancer = parent_record
    load_balancer_type_id = load_balancer['type']['id']
    load_balancer_type = find_by_id(:load_balancer_type, load_balancer_type_id)
    load_balancer_type['vipOptionTypes']
  end

  ## using CliCommand's generic find_by methods

end
