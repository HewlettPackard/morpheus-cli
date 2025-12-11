require 'morpheus/cli/cli_command'

class Morpheus::Cli::Migrations
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::ProcessesHelper
  #include Morpheus::Cli::MigrationsHelper

  set_command_name :'migrations'
  set_command_description "View and manage migrations."
  register_subcommands :list, :get, :add, :update, :run, :remove, :history

  # RestCommand settings
  register_interfaces :migrations, :processes
  # set_rest_has_type false
  # set_rest_type :migration_types

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # show Migration Configuration
      # config = record['config']
      # if config && !config.empty?
      #   print_h2 "Virtual Machines"
      #   print_description_list(config.keys, config)
      # end
      # Datastores
      datastores = record['datastores']
      print_h2 "Datastores", options
      if datastores && datastores.size > 0
        columns = [
          {"Source" => lambda {|it| it['sourceDatastore'] ? "#{it['sourceDatastore']['name']} [#{it['sourceDatastore']['id']}]" : "" } },
          {"Destination" => lambda {|it| it['destinationDatastore'] ? "#{it['destinationDatastore']['name']} [#{it['destinationDatastore']['id']}]" : "" } },
        ]
        print as_pretty_table(datastores, columns, options)
      else
        print cyan,"No datatores in migration",reset,"\n"
      end
      # Networks
      print_h2 "Networks", options
      networks = record['networks']
      if networks && networks.size > 0
        columns = [
          {"Source" => lambda {|it| it['sourceNetwork'] ? "#{it['sourceNetwork']['name']} [#{it['sourceNetwork']['id']}]" : "" } },
          {"Destination" => lambda {|it| it['destinationNetwork'] ? "#{it['destinationNetwork']['name']} [#{it['destinationNetwork']['id']}]" : "" } },
        ]
        print as_pretty_table(networks, columns, options)
      else
        print cyan,"No networks found in migration",reset,"\n"
      end
      # Virtual Machines
      print_h2 "Virtual Machines", options
      servers = record['servers']
      if servers && servers.size > 0
        columns = [
          # {"ID" => lambda {|it| it['sourceServer'] ? it['sourceServer']['id'] : "" } },
          # {"Name" => lambda {|it| it['sourceServer'] ? it['sourceServer']['name'] : "" } },
          {"Source" => lambda {|it| it['sourceServer'] ? "#{it['sourceServer']['name']} [#{it['sourceServer']['id']}]" : "" } },
          {"Destination" => lambda {|it| it['destinationServer'] ? "#{it['destinationServer']['name']} [#{it['destinationServer']['id']}]" : "" } },
          {"Status" => lambda {|it| format_migration_server_status(it) } }
        ]
        print as_pretty_table(servers, columns, options)
      else
        print cyan,"No virtual machines found in migration",reset,"\n"
      end
      print reset,"\n"
    end
  end
  
  def history(args)
    handle_history_command(args, "migration", "Migration", "migrationPlan") do |id|
      record = rest_find_by_name_or_id(id)
      if record.nil?
        # raise_command_error "#{rest_name} not found for '#{id}'"
        return 1, "#{rest_name} not found for '#{id}'"
      end
      record
    end 
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_migration_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new migration plan.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # prompt for option types
      # skip config if using interactive prompt
      add_option_types = add_migration_option_types
      # handle some option types in a special way
      servers_option_type = add_option_types.find {|it| it['fieldName'] == 'servers' } # || {'switch' => 'servers', 'fieldName' => 'servers', 'fieldLabel' => 'Virtual Machines', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'required' => true, 'description' => 'Virtual Machines to be migrated, comma separated list of server names or IDs.'}
      add_option_types.reject! {|it| it['fieldName'] == 'servers' }
      # prompt
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!

      # prompt for servers
      server_ids = nil
      if params['sourceServerIds']
        server_ids = parse_id_list(params.delete('sourceServerIds'))
      elsif params['servers']
        server_ids = parse_id_list(params.delete('servers'))
      end
      
      if server_ids
        # lookup each value as an id or name and collect id
        # server_ids = server_ids.collect {|it| find_server_by_name_or_id(it)}.compact.collect {|it| it['id']}
        # available_servers = @api_client.options.options_for_source("searchServers", {'cloudId' => params['sourceCloudId'], 'max' => 1000})['data']
        available_servers = @api_client.migrations.source_servers({'sourceCloudId' => params['sourceCloudId'], 'max' => 5000})['sourceServers']
        bad_ids = []
        server_ids = server_ids.collect {|server_id| 
          found_option = available_servers.find {|it| it['id'].to_s == server_id.to_s || it['name'] == server_id.to_s }
          if found_option
            found_option['value'] || found_option['id']
          else
            bad_ids << server_id
          end
        }
        if bad_ids.size > 0
          raise_command_error "No such server found for: #{bad_ids.join(', ')}"
        end
      else
        # prompt for servers
        # servers_option_type = {'fieldName' => 'servers', 'fieldLabel' => 'Virtual Machines', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'description' => 'Select virtual machine servers to be migrated.', 'required' => true}
        api_params = {'cloudId' => params['sourceCloudId']}
        # server_ids = Morpheus::Cli::OptionTypes.prompt([servers_option_type], options[:options], @api_client, {'cloudId' => params['sourceCloudId'], 'max' => 1000})['servers']
        server_ids = Morpheus::Cli::OptionTypes.prompt([servers_option_type], options[:options], @api_client, {'sourceCloudId' => params['sourceCloudId'], 'max' => 5000})['servers']
        # todo: Add prompt for Add more servers?
        # while self.confirm("Add more #{servers_option_type['fieldLabel']}?", {:default => false}) do
        #   more_ids = Morpheus::Cli::OptionTypes.prompt([servers_option_type.merge({'required' => false})], {}, @api_client, api_params)['servers']
        #   server_ids += more_ids
        # end
      end
      server_ids.uniq!
      params['sourceServerIds'] = server_ids

      # prompt for datastores
      datastore_mappings = []
      source_datastores = @api_client.migrations.source_storage({'sourceCloudId' => params['sourceCloudId'], 'sourceServerIds' => params['sourceServerIds'].join(",")})['sourceStorage']
      source_datastores.each do |datastore|
        target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "datastore.#{datastore['id']}", 'fieldLabel' => "Datastore #{datastore['name']}", 'type' => 'select', 'required' => true, 'defaultFirstOption' => true, 'description' => "Datastore destination for datastore #{datastore['name']} [#{datastore['id']}]", 'optionSource' => lambda {|api_client, api_params| 
          api_client.migrations.target_storage(api_params)['targetStorage'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
        } }], options[:options], @api_client, {'targetCloudId' => params['targetCloudId'], 'targetPoolId' => params['targetPoolId']})["datastore"]["#{datastore['id']}"]
        datastore_mappings << {'sourceDatastore' => {'id' => datastore['id']}, 'destinationDatastore' => {'id' => target_id}}
      end
      params['datastores'] = datastore_mappings
      params.delete('datastore') # remove options passed in as -O datastore.id=

      # prompt for networks
      network_mappings = []
      source_networks = @api_client.migrations.source_networks({'sourceCloudId' => params['sourceCloudId'], 'sourceServerIds' => params['sourceServerIds'].join(",")})['sourceNetworks']
      source_networks.each do |network|
        target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => "network.#{network['id']}", 'fieldLabel' => "Network #{network['name']}", 'type' => 'select', 'required' => true, 'defaultFirstOption' => true, 'description' => "Network destination for network #{network['name']} [#{network['id']}]", 'optionSource' => lambda {|api_client, api_params| 
          api_client.migrations.target_networks(api_params)['targetNetworks'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
        } }], options[:options], @api_client, {'targetCloudId' => params['targetCloudId'], 'targetPoolId' => params['targetPoolId']})["network"]["#{network['id']}"]
        network_mappings << {'sourceNetwork' => {'id' => network['id']}, 'destinationNetwork' => {'id' => target_id}}
      end
      params['networks'] = network_mappings
      params.delete('network') # remove options passed in as -O network.id=

      payload.deep_merge!({rest_object_key => params})
    end
    @migrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @migrations_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @migrations_interface.create(payload)
    migration = json_response[rest_object_key]
    render_response(json_response, options, rest_object_key) do
      print_green_success "Added migration #{migration['name']}"
      return _get(migration["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[migration] [options]")
      build_option_type_options(opts, options, update_migration_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a migration plan.
[migration] is required. This is the name or id of a migration plan.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    migration = find_migration_by_name_or_id(args[0])
    return 1 if migration.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # prompt for option types
      # skip config if using interactive prompt
      update_option_types = update_migration_option_types
      # handle some option types in a special way
      servers_option_type = update_option_types.find {|it| it['fieldName'] == 'servers' } # || {'switch' => 'servers', 'fieldName' => 'servers', 'fieldLabel' => 'Virtual Machines', 'type' => 'multiSelect', 'optionSource' => 'searchServers', 'required' => true, 'description' => 'Virtual Machines to be migrated, comma separated list of server names or IDs.'}
      update_option_types.reject! {|it| it['fieldName'] == 'servers' }
      # prompt (edit uses no_prompt)
      # need these parameters for prompting..
      default_api_params = {}
      default_api_params['sourceCloudId'] = migration['sourceCloud']['id'] if migration['sourceCloud']
      default_api_params['targetCloudId'] = migration['targetCloud']['id'] if migration['targetCloud']
      default_api_params['targetGroupId'] = migration['targetGroup']['id'] if migration['targetGroup']
      default_api_params['targetPoolId'] = "pool-" + migration['targetPool']['id'].to_s if migration['targetPool']
      options[:params] = default_api_params.merge(options[:options])
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!

      # prompt for servers
      server_ids = nil
      if params['sourceServerIds']
        server_ids = parse_id_list(params.delete('sourceServerIds'))
      elsif params['servers']
        server_ids = parse_id_list(params.delete('servers'))
      end

      if server_ids
        # lookup each value as an id or name and collect id
        # server_ids = server_ids.collect {|it| find_server_by_name_or_id(it)}.compact.collect {|it| it['id']}
        # available_servers = @api_client.options.options_for_source("searchServers", {'cloudId' => params['sourceCloudId'], 'max' => 1000})['data']
        available_servers = @api_client.migrations.source_servers({'sourceCloudId' => params['sourceCloudId'], 'max' => 5000})['sourceServers']
        bad_ids = []
        server_ids = server_ids.collect {|server_id| 
          found_option = available_servers.find {|it| it['id'].to_s == server_id.to_s || it['name'] == server_id.to_s }
          if found_option
            found_option['value'] || found_option['id']
          else
            bad_ids << server_id
          end
        }
        if bad_ids.size > 0
          raise_command_error "No such server found for: #{bad_ids.join(', ')}"
        end
        server_ids.uniq!
        params['sourceServerIds'] = server_ids
      else
        # no prompt for update
      end
      
      source_server_ids = params['sourceServerIds'] || migration['servers'].collect {|it| it['sourceServer'] ? it['sourceServer']['id'] : nil }.compact
      source_cloud_id = params['sourceCloudId'] || (migration['sourceCloud'] ? migration['sourceCloud']['id'] : nil)
      target_cloud_id = params['targetCloudId'] || (migration['targetCloud'] ? migration['targetCloud']['id'] : nil)
      target_pool_id = params['targetPoolId'] || (migration['targetPool'] ? migration['targetPool']['id'] : nil)

      # prompt for datastores
      if options[:options]['datastore'].is_a?(Hash)
        datastore_mappings = []
        source_datastores = @api_client.migrations.source_storage({'sourceCloudId' => source_cloud_id, 'sourceServerIds' => source_server_ids.join(",")})['sourceStorage']
        source_datastores.each do |datastore|
          found_mapping = migration['datastores'].find {|it| it['sourceDatastore'] && it['sourceDatastore']['id'] == datastore['id'] }
          default_value = found_mapping && found_mapping['destinationDatastore'] ? found_mapping['destinationDatastore']['name'] : nil
          target_id = Morpheus::Cli::OptionTypes.no_prompt([{'fieldName' => "datastore.#{datastore['id']}", 'fieldLabel' => "Datastore #{datastore['name']}", 'type' => 'select', 'description' => "Datastore destination for datastore #{datastore['name']} [#{datastore['id']}]", 'defaultValue' => default_value, 'optionSource' => lambda {|api_client, api_params| 
            api_client.migrations.target_storage(api_params)['targetStorage'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
          } }], options[:options], @api_client, {'targetCloudId' => target_cloud_id, 'targetPoolId' => target_pool_id})["datastore"]["#{datastore['id']}"]
          datastore_mappings << {'sourceDatastore' => {'id' => datastore['id']}, 'destinationDatastore' => {'id' => target_id}}
        end
        params['datastores'] = datastore_mappings
        params.delete('datastore') # remove options passed in as -O datastore.id=
      end

      # prompt for networks
      if options[:options]['network'].is_a?(Hash)
        network_mappings = []
        source_networks = @api_client.migrations.source_networks({'sourceCloudId' => source_cloud_id, 'sourceServerIds' => source_server_ids.join(",")})['sourceNetworks']
        source_networks.each do |network|
          found_mapping = migration['networks'].find {|it| it['sourceNetwork'] && it['sourceNetwork']['id'] == network['id'] }
          default_value = found_mapping && found_mapping['destinationNetwork'] ? found_mapping['destinationNetwork']['name'] : nil
          target_id = Morpheus::Cli::OptionTypes.no_prompt([{'fieldName' => "network.#{network['id']}", 'fieldLabel' => "Network #{network['name']}", 'type' => 'select', 'description' => "Network destination for network #{network['name']} [#{network['id']}]", 'defaultValue' => default_value, 'optionSource' => lambda {|api_client, api_params| 
            api_client.migrations.target_networks(api_params)['targetNetworks'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
          } }], options[:options], @api_client, {'targetCloudId' => target_cloud_id, 'targetPoolId' => target_pool_id})["network"]["#{network['id']}"]
          network_mappings << {'sourceNetwork' => {'id' => network['id']}, 'destinationNetwork' => {'id' => target_id}}
        end
        params['networks'] = network_mappings
        params.delete('network') # remove options passed in as -O network.id=
      end

      if params.empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload.deep_merge!({rest_object_key => params})      
    end
    @migrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @migrations_interface.dry.update(migration['id'], payload)
      return
    end
    json_response = @migrations_interface.update(migration['id'], payload)
    migration = json_response[rest_object_key]
    render_response(json_response, options, rest_object_key) do
      print_green_success "Updated migration #{migration['name']}"
      return _get(migration["id"], {}, options)
    end
    return 0, nil
  end

  def run(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[migration]")
      build_standard_post_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Runs a migration plan to transition it from pending to scheduled for execution.
[migration] is required. This is the name or id of a migration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    migration = find_migration_by_name_or_id(args[0])
    return 1 if migration.nil?
    parse_payload(options) do |payload|
    end
    servers = migration['servers']
    print cyan, "The following #{servers.size == 1 ? 'server' : servers.size.to_s + ' servers'} will be migrated:", "\n"
    puts ""
    print as_pretty_table(servers, {"Virtual Machine" => lambda {|it| it['sourceServer'] ? "#{it['sourceServer']['name']} [#{it['sourceServer']['id']}]" : "" } }, options)
    puts ""
    confirm!("Are you sure you want to execute the migration plan?", options)
    execute_api(@migrations_interface, :run, [migration['id']], options, 'migration') do |json_response|
      print_green_success "Running migration #{migration['name']}"
    end
  end

  protected

  def migration_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "VMs" => lambda {|it| it['servers'] ? it['servers'].size : 0 },
      "Status" => lambda {|it| format_migration_status(it) },
    }
  end

  def migration_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Source Cloud" => lambda {|it| it['sourceCloud'] ? it['sourceCloud']['name'] : '' },
      "Destination Cloud" => lambda {|it| it['targetCloud'] ? it['targetCloud']['name'] : '' },
      "Resource Pool" => lambda {|it| it['targetPool'] ? it['targetPool']['name'] : '' },
      "Group" => lambda {|it| it['targetGroup'] ? it['targetGroup']['name'] : '' },
      "Skip Prechecks" => lambda {|it| format_boolean(it['skipPrechecks']) },
      "Install Guest Tools" => lambda {|it| format_boolean(it['installGuestTools']) },
      # "ReInitialize Server" => lambda {|it| format_boolean(it['reInitializeServerOnMigration']) },
      "VMs" => lambda {|it| it['servers'] ? it['servers'].size : 0 },
      "Status" => lambda {|it| format_migration_status(it) },
    }
  end

  def add_migration_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      # {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'switch' => 'source-cloud', 'fieldName' => 'sourceCloudId', 'fieldLabel' => 'Source Cloud', 'type' => 'select', 'required' => true, 'description' => 'Source Cloud', 'optionSource' => lambda {|api_client, api_params| 
        api_client.migrations.source_clouds(api_params)['sourceClouds'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
      } },
      {'switch' => 'cloud', 'fieldName' => 'targetCloudId', 'fieldLabel' => 'Destination Cloud', 'type' => 'select', 'required' => true, 'description' => 'Destination Cloud', 'optionSource' => lambda {|api_client, api_params| 
        api_client.migrations.target_clouds(api_params)['targetClouds'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
      } },
      {'switch' => 'group', 'fieldName' => 'targetGroupId', 'fieldLabel' => 'Group', 'type' => 'select', 'optionSource' => 'targetGroups', 'required' => true, 'defaultFirstOption' => true, 'description' => 'Destination Group'},
      {'switch' => 'pool', 'fieldName' => 'targetPoolId', 'fieldLabel' => 'Resource Pool', 'type' => 'select', 'required' => true, 'defaultFirstOption' => true, 'optionSource' => lambda {|api_client, api_params| 
        api_params = api_params.merge({'provisionTypeCode' => 'kvm', 'zoneId' => api_params['targetCloudId'], 'groupId' => api_params['targetGroupId']})
        api_client.options.options_for_source("zonePools", api_params)['data']
      } },
      {'switch' => 'servers', 'fieldName' => 'servers', 'fieldLabel' => 'Virtual Machines', 'type' => 'multiSelect', 'required' => true, 'description' => 'Virtual Machines to be migrated, comma separated list of server names or IDs.', 'optionSource' => lambda {|api_client, api_params| 
        api_client.migrations.source_servers(api_params)['sourceServers'].collect {|it| {'name' => it['name'], 'value' => it['id']} }
      } },
      {'fieldName' => 'skipPrechecks', 'fieldLabel' => 'Skip Prechecks', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false},
      {'fieldName' => 'installGuestTools', 'fieldLabel' => 'Install Guest Tools', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
    ]
  end

  def add_migration_advanced_option_types()
    [
      # {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'fieldGroup' => 'Advanced', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions'},
      # {'fieldName' => 'tenants', 'fieldLabel' => 'Tenants', 'fieldGroup' => 'Advanced', 'type' => 'multiSelect', 'optionSource' => lambda { |api_client, api_params| 
      #   api_client.options.options_for_source("allTenants", {})['data']
      # }},
    ]
  end

  def update_migration_option_types()
    add_migration_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it.delete('defaultFirstOption')
      it
    }
  end

  def update_migration_advanced_option_types()
    add_migration_advanced_option_types()
  end

  def format_migration_status(migration, return_color=cyan)
    # migration statuses: pending, scheduled, precheck, running, failed, completed
    out = ""
    status_string = migration['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'completed'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'pending' || status_string == 'scheduled' || status_string == 'precheck' || status_string == 'running'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{migration['statusMessage'] ? "#{return_color} - #{migration['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def format_migration_server_status(migration_server, return_color=cyan)
    return format_migration_status(migration_server, return_color)
  end
  
  def find_migration_by_name_or_id(arg)
    find_by_name_or_id(rest_key, arg)
  end

end
