require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::BackupsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_hidden # hide until ready
  
  set_command_name :'backups'

  register_subcommands :list, :get, :add, :update, :remove, :run, :restore
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @backups_interface = @api_client.backups
    @backup_jobs_interface = @api_client.backup_jobs
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
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
      build_standard_list_options(opts, options)
      opts.footer = "List backups."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @backups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backups_interface.dry.list(params)
      return
    end
    json_response = @backups_interface.list(params)
    backups = json_response['backups']
    render_response(json_response, options, 'backups') do
      print_h1 "Morpheus Backups", parse_list_subtitles(options), options
      if backups.empty?
        print cyan,"No backups found.",reset,"\n"
      else
        print as_pretty_table(backups, backup_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[backup]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    if id.to_s !~ /\A\d{1,}\Z/
      record = find_by_name(:backup, id)
      if record.nil?
        return 1, "Backup not found for '#{id}'"
      end
      id = record['id']
    end
    @backups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backups_interface.dry.get(id, params)
      return
    end
    json_response = @backups_interface.get(id, params)
    backup = json_response['backup']
    render_response(json_response, options, 'backup') do
      print_h1 "Backup Details", [], options
      print cyan
      columns = backup_column_definitions
      columns.delete("Instance") if backup['instance'].nil?
      columns.delete("Container ID") if backup['containerId'].nil?
      columns.delete("Host") if backup['server'].nil?
      print_description_list(columns, backup, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      # build_option_type_options(opts, options, add_backup_option_types)
      opts.on('--source VALUE', String, "Backup Source: instance, host or provider") do |val|
        options[:options]['source'] = val
      end
      opts.on('--instance VALUE', String, "Instance Name or ID") do |val|
        options[:options]['source'] = 'instance'
        options[:options]['instanceId'] = val
      end
      opts.on('--host VALUE', String, "Host Name or ID") do |val|
        options[:options]['source'] = 'server'
        options[:options]['serverId'] = val
      end
      opts.on('--server VALUE', String, "alias for --host") do |val|
        options[:options]['source'] = 'server'
        options[:options]['serverId'] = val
      end
      opts.add_hidden_option('--server')
      opts.on('--name VALUE', String, "Name") do |val|
        options[:options]['name'] = val
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'backup' => parse_passed_options(options)})
    else
      payload.deep_merge!({'backup' => parse_passed_options(options)})

      location_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'source', 'fieldLabel' => 'Source', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Host', 'value' => 'server'}, {'name' => 'Provider', 'value' => 'provider'}], 'defaultValue' => 'instance', 'required' => true, 'description' => 'Where is the backup located?'}], options[:options], @api_client)['source']
      params['locationType'] = location_type
      if location_type == 'instance'
        # Instance
        avail_instances = @instances_interface.list({max:10000})['instances'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        params['instanceId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instanceId', 'fieldLabel' => 'Instance', 'type' => 'select', 'selectOptions' => avail_instances, 'required' => true}], options[:options], @api_client)['instanceId']
        # Name
        params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Backup Name'}], options[:options], @api_client)['name']
      elsif location_type == 'server'
        # Server
        avail_servers = @servers_interface.list({max:10000, 'vmHypervisor' => nil, 'containerHypervisor' => nil})['servers'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
        params['serverId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'serverId', 'fieldLabel' => 'Host', 'type' => 'select', 'selectOptions' => avail_servers, 'required' => true}], options[:options], @api_client)['serverId']
        # Name
        params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Backup Name'}], options[:options], @api_client)['name']
      elsif location_type == 'provider'
        # todo: prompt for provider inputs
        # sourceProviderId
        # storageProvider
      end
      # POST to /create to get available option info for containers, backupTypes, backupProviderTypes, etc.
      payload['backup'].deep_merge!(params)
      create_results = @backups_interface.create_options(payload)

      if location_type == 'instance' || location_type == 'server'
        if location_type == 'instance'
          # Container
          avail_containers = (create_results['containers'] || []).collect {|it| {'name' => it['name'], 'value' => it['id']} }
          if avail_containers.empty?
            raise_command_error "No available containers found for selected instance"
          else
            params['containerId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'containerId', 'fieldLabel' => 'Container', 'type' => 'select', 'selectOptions' => avail_containers, 'defaultValue' => avail_containers[0] ? avail_containers[0]['name'] : nil, 'required' => true}], options[:options], @api_client)['containerId']
          end
        elsif location_type == 'server'
          
          
        end
        # Backup Type
        avail_backup_types = (create_results['backupTypes'] || []).collect {|it| {'name' => it['name'], 'value' => it['code']} }
        if avail_backup_types.empty?
          raise_command_error "No available backup types found"
        else
          params['backupType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'backupType', 'fieldLabel' => 'Backup Type', 'type' => 'select', 'selectOptions' => avail_backup_types, 'defaultValue' => avail_backup_types[0] ? avail_backup_types[0]['name'] : nil, 'required' => true}], options[:options], @api_client)['backupType']  
        end

        # Job / Schedule
        params['jobAction'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobAction', 'fieldLabel' => 'Backup Job Type', 'type' => 'select', 'optionSource' => 'backupJobActions', 'required' => true, 'defaultValue' => 'new'}], options[:options], @api_client)['jobAction']
        if params['jobAction'] == 'new'
          params['jobName'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobName', 'fieldLabel' => 'Job Name', 'type' => 'text', 'required' => false, 'defaultValue' => nil}], options[:options], @api_client)['jobName']
          default_retention_count = create_results['backup'] ? create_results['backup']['retentionCount'] : nil
          params['retentionCount'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'retentionCount', 'fieldLabel' => 'Retention Count', 'type' => 'number', 'required' => false, 'defaultValue' => default_retention_count}], options[:options], @api_client)['retentionCount']
          params['jobSchedule'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobSchedule', 'fieldLabel' => 'Backup Schedule', 'type' => 'select', 'optionSource' => 'executeSchedules', 'required' => true}], options[:options], @api_client)['jobSchedule']
        elsif params['jobAction'] == 'clone'
          params['jobId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
            @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
              {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
            }
          }, 'required' => true}], options[:options], @api_client)['jobId']
          params['jobName'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobName', 'fieldLabel' => 'Job Name', 'type' => 'text', 'required' => false, 'defaultValue' => nil}], options[:options], @api_client)['jobName']
        elsif params['jobAction'] == 'addTo'
          params['jobId'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
            @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
              {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
            }
          }, 'required' => true}], options[:options], @api_client)['jobId']
        end
      end

      payload['backup'].deep_merge!(params)
    end
    @backups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backups_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @backups_interface.create(payload)
    backup = json_response['backup']
    render_response(json_response, options, 'backup') do
      print_green_success "Added backup #{backup['name']}"
      return _get(backup["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [options]")
      build_option_type_options(opts, options, update_backup_option_types)
      build_option_type_options(opts, options, update_backup_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup = find_backup_by_name_or_id(args[0])
    return 1 if backup.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'backup' => parse_passed_options(options)})
    else
      payload.deep_merge!({'backup' => parse_passed_options(options)})
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_backup_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_backup_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      payload.deep_merge!({'backup' => params})
      if payload['backup'].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @backups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backups_interface.dry.update(backup['id'], payload)
      return
    end
    json_response = @backups_interface.update(backup['id'], payload)
    backup = json_response['backup']
    render_response(json_response, options, 'backup') do
      print_green_success "Updated backup #{backup['name']}"
      return _get(backup["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[backup] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a backup.
[backup] is required. This is the name or id of a backup.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    backup = find_backup_by_name_or_id(args[0])
    return 1 if backup.nil?
    @backups_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @backups_interface.dry.destroy(backup['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the backup #{backup['name']}?")
      return 9, "aborted command"
    end
    json_response = @backups_interface.destroy(backup['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed backup #{backup['name']}"
    end
    return 0, nil
  end

  private

  def backup_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Backup Job" => lambda {|it| it['job']['name'] rescue '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def backup_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Location Type" => lambda {|it| 
        if it['locationType'] == "instance"
          "Instance"
        elsif it['locationType'] == "server"
          "Host"
        elsif it['locationType'] == "storage"
          "Provider"
        end
      },
      "Instance" => lambda {|it| it['instance']['name'] rescue '' },
      "Container ID" => lambda {|it| it['containerId'] rescue '' },
      "Host" => lambda {|it| it['server']['name'] rescue '' },
      "Schedule" => lambda {|it| it['schedule']['name'] rescue '' },
      "Backup Job" => lambda {|it| it['job']['name'] rescue '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  # this is not so simple, need to first choose select instance, host or provider
  def add_backup_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'backupType', 'fieldLabel' => 'Backup Type', 'type' => 'select', 'optionSource' => 'backupTypes', 'required' => true},
      {'fieldName' => 'jobAction', 'fieldLabel' => 'Backup Job Type', 'type' => 'select', 'optionSource' => 'backupJobActions', 'required' => true},
      {'fieldName' => 'jobId', 'fieldLabel' => 'Backup Job', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        @backup_jobs_interface.list({max:10000})['jobs'].collect {|backup_job|
          {'name' => backup_job['name'], 'value' => backup_job['id'], 'id' => backup_job['id']}
        }
      }, 'required' => true},
    ]
  end

  def add_backup_advanced_option_types
    []
  end

  def update_backup_option_types
    add_backup_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def update_backup_advanced_option_types
    add_backup_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

end
