require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/mixins/processes_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::ProcessesHelper
  set_command_name :instances
  set_command_description "View and manage instances."
  register_subcommands :list, :count, :get, :add, :update, :update_notes, :remove, :logs, :history, {:'history-details' => :history_details}, {:'history-event' => :history_event_details}, :stats, :stop, :start, :restart, :actions, :action, :suspend, :eject, :backup, :backups, :stop_service, :start_service, :restart_service, :resize, :clone, :envs, :setenv, :delenv, :security_groups, :apply_security_groups, :firewall_enable, :firewall_disable, :run_workflow, :import_snapshot, :console, :status_check, {:containers => :list_containers}, :scaling, {:'scaling-update' => :scaling_update}
  register_subcommands :exec => :execution_request
  # register_subcommands {:'lb-update' => :load_balancer_update}
  alias_subcommand :details, :get
  set_default_subcommand :list
  
  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @users_interface = @api_client.users
    @instances_interface = @api_client.instances
    @task_sets_interface = @api_client.task_sets
    @logs_interface = @api_client.logs
    @tasks_interface = @api_client.tasks
    @instance_types_interface = @api_client.instance_types
    @clouds_interface = @api_client.clouds
    @servers_interface = @api_client.servers
    @provision_types_interface = @api_client.provision_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_group
    @execution_request_interface = @api_client.execution_request
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-H', '--host HOST', "Host Name or ID" ) do |val|
        options[:host] = val
      end
      opts.on( '--created-by USER', "Created By User Username or ID" ) do |val|
        options[:created_by] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List instances."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
      if group
        params['siteId'] = group['id']
      end

      # argh, this doesn't work because group_id is required for options/clouds
      # cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
      cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
      if cloud
        params['zoneId'] = cloud['id']
      end

      host = options[:host] ? find_host_by_name_or_id(options[:host]) : options[:host]
      if host
        params['serverId'] = host['id']
      end

      account = nil
      if options[:created_by]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:created_by])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
      end

      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return 0
      end
      json_response = @instances_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "instances")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instances")
        return 0
      elsif options[:csv]
        # merge stats to be nice here..
        if json_response['instances']
          all_stats = json_response['stats'] || {}
          if all_stats
            json_response['instances'].each do |it|
              it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
            end
          end
        end
        puts records_as_csv(json_response['instances'], options)
      else
        instances = json_response['instances']

        title = "Morpheus Instances"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud
          subtitles << "Cloud: #{cloud['name']}".strip
        end
        if host
          subtitles << "Host: #{host['name']}".strip
        end
        if options[:created_by]
          subtitles << "Created By: #{options[:created_by]}"
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if instances.empty?
          print yellow,"No instances found.",reset,"\n"
        else
          # print_instances_table(instances)
          # server returns stats in a separate key stats => {"id" => {} }
          # the id is a string right now..for some reason..
          all_stats = json_response['stats'] || {} 
          if all_stats
            instances.each do |it|
              if !it['stats']
                found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
                it['stats'] = found_stats # || {}
              end
            end
          end

          rows = instances.collect {|instance| 
            stats = instance['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            row = {
              id: instance['id'],
              name: instance['name'],
              connection: format_instance_connection_string(instance),
              environment: instance['instanceContext'],
              nodes: instance['containers'].count,
              status: format_instance_status(instance, cyan),
              type: instance['instanceType']['name'],
              group: !instance['group'].nil? ? instance['group']['name'] : nil,
              cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil,
              version: instance['instanceVersion'] ? instance['instanceVersion'] : '',
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan,
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, {:name => {:max_width => 50}}, :group, :cloud, :type, :version, :environment, :nodes, {:connection => {:max_width => 30}}, :status]
          term_width = current_terminal_width()
          if term_width > 190
            columns += [:cpu, :memory, :storage]
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
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
      opts.footer = "Get the number of instances."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return
      end
      json_response = @instances_interface.list(params)
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

  def add(args)
    options = {}
    options[:create_user] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      # opts.banner = subcommand_usage("[type] [name]")
      opts.banner = subcommand_usage("[name] -c CLOUD -t TYPE")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
        options[:instance_type_code] = val
      end
      opts.on( '--name NAME', "Instance Name" ) do |val|
        options[:instance_name] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on("--copies NUMBER", Integer, "Number of copies to provision") do |val|
        options[:copies] = val.to_i
      end
      opts.on("--layout-size NUMBER", Integer, "Apply a multiply factor of containers/vms within the instance") do |val|
        options[:layout_size] = val.to_i
      end
      opts.on("--workflow ID", String, "Automation: Workflow ID") do |val|
        options[:workflow_id] = val
      end
      # opts.on('-L', "--lb", "Enable Load Balancer") do
      #   options[:enable_load_balancer] = true
      # end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is on") do |val|
        options[:create_user] = !['false','off','0'].include?(val.to_s)
      end
      opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
        options[:user_group_id] = val
      end
      opts.on("--shutdown-days NUMBER", Integer, "Automation: Shutdown Days") do |val|
        options[:expire_days] = val.to_i
      end
      opts.on("--expire-days NUMBER", Integer, "Automation: Expiration Days") do |val|
        options[:expire_days] = val.to_i
      end
      opts.on("--create-backup [on|off]", String, "Automation: Create Backups.") do |val|
        options[:create_backup] = ['on','true','1',''].include?(val.to_s.downcase) ? 'on' : 'off'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new instance." + "\n" +
                    "[name] is required. This is the new instance name." + "\n" +
                    "The available options vary by --type."
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add has just 1 (optional) argument: [name].  Got #{args.count} arguments: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if args[0]
      options[:instance_name] = args[0]
    end

    # use active group by default
    options[:group] ||= @active_group_id

    options[:name_required] = true
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      else
        # prompt for all the instance configuration options
        # this provisioning helper method handles all (most) of the parsing and prompting
        # and it relies on the method to exit non-zero on error, like a bad CLOUD or TYPE value
        payload = prompt_new_instance(options)
        # clean payload of empty objects 
        # note: this is temporary and should be fixed upstream in OptionTypes.prompt()
        if payload['instance'].is_a?(Hash)
          payload['instance'].keys.each do |k|
            v = payload['instance'][k]
            payload['instance'].delete(k) if v.is_a?(Hash) && v.empty?
          end
        end
        if payload['config'].is_a?(Hash)
          payload['config'].keys.each do |k|
            v = payload['config'][k]
            payload['config'].delete(k) if v.is_a?(Hash) && v.empty?
          end
        end
      end
      payload['instance'] ||= {}
      if options[:instance_name]
        payload['instance']['name'] = options[:instance_name]
      end
      payload[:copies] = options[:copies] if options[:copies] && options[:copies] > 0
      payload[:layoutSize] = options[:layout_size] if options[:layout_size] && options[:layout_size] > 0 # aka Scale Factor
      payload[:createBackup] = options[:create_backup] if !options[:create_backup].nil?
      payload['instance']['expireDays'] = options[:expire_days] if options[:expire_days]
      payload['instance']['shutdownDays'] = options[:shutdown_days] if options[:shutdown_days]
      if options.key?(:create_user)
        payload['config'] ||= {}
        payload['config']['createUser'] = options[:create_user]
      end
      if options[:user_group_id]
        payload['instance']['userGroup'] = {'id' => options[:user_group_id] }
      end
      if options[:workflow_id]
        if options[:workflow_id].to_s =~ /\A\d{1,}\Z/
          payload['taskSetId'] = options[:workflow_id].to_i
        else
          payload['taskSetName'] = options[:workflow_id]
        end
      end
      if options[:enable_load_balancer]
        lb_payload = prompt_instance_load_balancer(payload['instance'], nil, options)
        payload.deep_merge!(lb_payload)
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create(payload)
        return 0
      end

      json_response = @instances_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        instance_id = json_response["instance"]["id"]
        instance_name = json_response["instance"]["name"]
        print_green_success "Provisioning instance [#{instance_id}] #{instance_name}"
        get([instance_id])
        #list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    usage = "Usage: morpheus instances update [name] [options]"
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['displayName'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--environment VALUE', String, "Environment") do |val|
        params['instanceContext'] = val
      end
      opts.on('--group GROUP', String, "Group Name or ID") do |val|
        options[:group] = val
      end
      opts.on('--metadata LIST', String, "Metadata in the format 'name:value, name:value'") do |val|
        options[:metadata] = val
      end
      opts.on('--tags LIST', String, "Tags") do |val|
        params['tags'] = val
        # params['tags'] = val.split(',').collect {|it| it.to_s.strip }.compact.uniq
      end
      opts.on('--power-schedule-type ID', String, "Power Schedule Type ID") do |val|
        params['powerScheduleType'] = val == "null" ? nil : val
      end
      opts.on('--created-by ID', String, "Created By User ID") do |val|
        params['createdById'] = val
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
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      new_group = nil
      if options[:group]
        new_group = find_group_by_name_or_id_for_provisioning(options[:group])
        return 1 if new_group.nil?
        params['site'] = {'id' => new_group['id']}
      end
      if options[:metadata]
        if options[:metadata] == "[]" || options[:metadata] == "null"
          params['metadata'] = []
        else
          # parse string into format name:value, name:value
          # merge IDs from current metadata
          # todo: should allow quoted semicolons..
          metadata_list = options[:metadata].split(",").select {|it| !it.to_s.empty? }
          metadata_list = metadata_list.collect do |it|
            metadata_pair = it.split(":")
            row = {}
            row['name'] = metadata_pair[0].to_s.strip
            row['value'] = metadata_pair[1].to_s.strip
            existing_metadata = (instance['metadata'] || []).find { |m| m['name'] == it['name'] }
            if existing_metadata
              row['id'] = existing_metadata['id']
            end
            row
          end
          params['metadata'] = metadata_list
        end
      end
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support args and option parameters on top of payload
        if !params.empty?
          payload['instance'] ||= {}
          payload['instance'].deep_merge!(params)
        end
      else
        if params.empty?
          print_red_alert "Specify atleast one option to update"
          puts optparse
          exit 1
        end
        payload = {}
        payload['instance'] = params
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated instance #{instance['name']}"
        #list([])
        get([instance['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_notes(args)
    usage = "Usage: morpheus instances update-notes [name] [options]"
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--notes VALUE', String, "Notes content (Markdown)") do |val|
        params['notes'] = val
      end
      opts.on('--file FILE', "File containing the notes content. This can be used instead of --notes") do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['notes'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      opts.on(nil, '--clear', "Clear current notes") do |val|
        params['notes'] = ""
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
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      new_group = nil
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support args and option parameters on top of payload
        if !params.empty?
          payload['instance'] ||= {}
          payload['instance'].deep_merge!(params)
        end
      else
        if params['notes'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'notes', 'type' => 'code-editor', 'fieldLabel' => 'Notes', 'required' => true, 'description' => 'Notes (Markdown)'}], options[:options])
          params['notes'] = v_prompt['notes']
        end
        payload = {}
        payload['instance'] = params
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_notes(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update_notes(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated notes for instance #{instance['name']}"
        #list([])
        get([instance['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def status_check(args)
    out = ""
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet, :json, :remote]) # no :dry_run, just do it man
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    # todo: just return status or maybe check if instance['status'] == args[0]
    instance = find_instance_by_name_or_id(args[0])
    exit_code = 0
    if instance['status'].to_s.downcase != (args[1] || "running").to_s.downcase
      exit_code = 1
    end
    if options[:json]
      mock_json = {status: instance['status'], exit: exit_code}
      out << as_json(mock_json, options)
      out << "\n"
    elsif !options[:quiet]
      out << cyan
      out << "Status: #{format_instance_status(instance)}"
      out << reset
      out << "\n"
    end
    print out unless options[:quiet]
    exit exit_code #return exit_code
  end

  def stats(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    ids = args
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _stats(arg, options)
    end
  end

  def _stats(arg, options)
    begin
      instance = find_instance_by_name_or_id(arg)
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get(instance['id'])
        return 0
      end
      json_response = @instances_interface.get(instance['id'])
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      end
      instance = json_response['instance']
      stats = instance['stats'] || json_response['stats'] || {}
      title = "Instance Stats: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      puts cyan + "Status: ".rjust(12) + format_instance_status(instance).to_s
      puts cyan + "Nodes: ".rjust(12) + (instance['containers'] ? instance['containers'].count : '').to_s
      # print "\n"
      #print_h2 "Instance Usage", options
      print_stats_usage(stats)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def console(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-n', '--node NODE_ID', "Scope console to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      build_common_options(opts, options, [:remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/terminal/#{instance['id']}"
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        link += "?containerId=#{options[:node_id]}"
      end

      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      build_common_options(opts, options, [:list, :query, :json, :csv, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        container_ids = [options[:node_id]]
      end
      params = {}
      params.merge!(parse_list_options(options))
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(container_ids, params)
        return
      end
      logs = @logs_interface.container_logs(container_ids, params)
      output = ""
      if options[:json]
        puts as_json(logs, options)
        return 0
      else
        title = "Instance Logs: #{instance['name']} (#{instance['instanceType'] ? instance['instanceType']['name'] : ''})"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        # todo: startMs, endMs, sorts insteaad of sort..etc
        print_h1 title, subtitles, options
        if logs['data'].empty?
          puts "#{cyan}No logs found.#{reset}"
        else
          logs['data'].reverse.each do |log_entry|
            log_level = ''
            case log_entry['level']
            when 'INFO'
              log_level = "#{blue}#{bold}INFO#{reset}"
            when 'DEBUG'
              log_level = "#{white}#{bold}DEBUG#{reset}"
            when 'WARN'
              log_level = "#{yellow}#{bold}WARN#{reset}"
            when 'ERROR'
              log_level = "#{red}#{bold}ERROR#{reset}"
            when 'FATAL'
              log_level = "#{red}#{bold}FATAL#{reset}"
            end
            puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}"
          end
          print output, reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( nil, '--containers', "Display Instance Containers" ) do
        options[:include_containers] = true
      end
      opts.on( nil, '--nodes', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      opts.on( nil, '--vms', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      opts.on( nil, '--scaling', "Display Instance Scaling Settings" ) do
        options[:include_scaling] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      # opts.on( nil, '--threshold', "Alias for --scaling" ) do
      #   options[:include_scaling] = true
      # end
      # opts.on( nil, '--lb', "Display Load Balancer Details" ) do
      #   options[:include_lb] = true
      # end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about an instance.\n" + 
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(arg, options={})
    begin
      if options[:dry_run]
        @instances_interface.setopts(options)
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @instances_interface.dry.get(arg.to_i)
        else
          print_dry_run @instances_interface.dry.get({name:arg})
        end
        return
      end
      instance = find_instance_by_name_or_id(arg)
      @instances_interface.setopts(options)
      json_response = @instances_interface.get(instance['id'])
      if options[:quiet]
        return 0
      end
      if options[:json]
        puts as_json(json_response, options, "instance")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instance")
        return 0
      end

      if options[:csv]
        puts records_as_csv([json_response['instance']], options)
        return 0
      end
      instance = json_response['instance']
      stats = instance['stats'] || json_response['stats'] || {}
      # load_balancers = json_response['loadBalancers'] || {}

      # containers are fetched via separate api call
      containers = nil
      if options[:include_containers]
        containers = @instances_interface.containers(instance['id'])['containers']
      end

      # threshold is fetched via separate api call too
      instance_threshold = nil
      if options[:include_scaling]
        instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold']
      end

      # loadBalancers is returned via show
      # parse the current api format of loadBalancers.first.lbs.first
      current_instance_lb = nil
      if instance["currentLoadBalancerInstances"]
        current_instance_lb = instance['currentLoadBalancerInstances'][0]
      end

      # support old format
      if !current_instance_lb && json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      print_h1 "Instance Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Type" => lambda {|it| it['instanceType']['name'] },
        "Layout" => lambda {|it| it['layout'] ? it['layout']['name'] : '' },
        "Version" => lambda {|it| it['instanceVersion'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Environment" => 'instanceContext',
        "Tags" => lambda {|it| it['tags'] ? it['tags'].join(',') : '' },
        "Metadata" => lambda {|it| it['metadata'] ? it['metadata'].collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        "Power Schedule" => lambda {|it| (it['powerSchedule'] && it['powerSchedule']['type']) ? it['powerSchedule']['type']['name'] : '' },
        "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['username'] || it['createdBy']['id']) : '' },
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].count : 0 },
        "Connection" => lambda {|it| format_instance_connection_string(it) },
        #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Status" => lambda {|it| format_instance_status(it) }
      }
      print_description_list(description_cols, instance)

      if instance['statusMessage']
        print_h2 "Status Message", options
        if instance['status'] == 'failed'
          print red, instance['statusMessage'], reset
        else
          print instance['statusMessage']
        end
        print "\n"
      end
      if instance['errorMessage']
        print_h2 "Error Message", options
        print red, instance['errorMessage'], reset, "\n"
      end
      if !instance['notes'].to_s.empty?
        print_h2 "Instance Notes", options
        print cyan, instance['notes'], reset, "\n"
      end
      if stats
        print_h2 "Instance Usage", options
        print_stats_usage(stats)
      end
      print reset, "\n"

      # if options[:include_lb]
      if current_instance_lb
        print_h2 "Load Balancer", options
        print cyan
        description_cols = {
          "LB ID" => lambda {|it| it['loadBalancer']['id'] },
          "Name" => lambda {|it| it['loadBalancer']['name'] },
          "Type" => lambda {|it| it['loadBalancer']['type'] ? it['loadBalancer']['type']['name'] : '' },
          "Host Name" => lambda {|it| it['vipHostname'] || instance['hostName'] },
          "Port" => lambda {|it| it['vipPort'] },
          "Protocol" => lambda {|it| it['vipProtocol'] || 'tcp' },
          "SSL Enabled" => lambda {|it| format_boolean(it['sslEnabled']) },
          "SSL Cert" => lambda {|it| (it['sslCert']) ? it['sslCert']['name'] : '' },
          "In" => lambda {|it| instance['currentLoadBalancerContainersIn'] },
          "Out" => lambda {|it| instance['currentLoadBalancerContainersOutrelo'] }
        }
        print_description_list(description_cols, current_instance_lb)
        print "\n", reset
      end
      # end

      if options[:include_containers]
        print_h2 "Instance Containers", options

        if containers.empty?
          print yellow,"No containers found for instance.",reset,"\n"
        else
          containers = containers.sort { |x,y| x['id'] <=> y['id'] }
          rows = containers.collect {|container| 
            stats = container['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            row = {
              id: container['id'],
              status: format_container_status(container),
              name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
              type: container['containerType'] ? container['containerType']['name'] : '',
              cloud: container['cloud'] ? container['cloud']['name'] : '',
              location: format_container_connection_string(container),
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan,
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, :status, :name, :type, :cloud, :location]
          term_width = current_terminal_width()
          if term_width > 190
            columns += [:cpu, :memory, :storage]
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          #print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
        end
        print reset,"\n"
      end

      if options[:include_scaling]
        print_h2 "Instance Scaling", options
        if instance_threshold.nil? || instance_threshold.empty?
          print yellow,"No scaling settings applied to this instance.",reset,"\n"
        else
          print cyan
          print_instance_threshold_description_list(instance_threshold)
          print reset,"\n"
        end
      end

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(instance['status'])
          print cyan, "Refreshing in #{options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_containers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _list_containers(arg, options)
    end
  end

  def _list_containers(arg, options)
    begin
      instance = find_instance_by_name_or_id(arg)
      return 1 if instance.nil?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.containers(instance['id'], params)
        return
      end
      json_response = @instances_interface.containers(instance['id'])
      if options[:json]
        puts as_json(json_response, options, "containers")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containers")
        return 0
      end

      if options[:csv]
        puts records_as_csv(json_response['containers'], options)
        return 0
      end
      

      containers = json_response['containers']
      containers = containers.sort { |x,y| x['id'] <=> y['id'] }
      title = "Instance Containers: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      if containers.empty?
        print yellow,"No containers found for instance.",reset,"\n"
      else

        rows = containers.collect {|container| 
          stats = container['stats']
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          row = {
            id: container['id'],
            status: format_container_status(container),
            name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
            type: container['containerType'] ? container['containerType']['name'] : '',
            cloud: container['cloud'] ? container['cloud']['name'] : '',
            location: format_container_connection_string(container),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, :status, :name, :type, :cloud, :location]
        term_width = current_terminal_width()
        if term_width > 190
          columns += [:cpu, :memory, :storage]
        end
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backups(instance['id'], params)
        return
      end
      json_response = @instances_interface.backups(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      
      if json_response['backups'] && json_response['backups'][0] && json_response['backups'][0]['backupResults']
        # new format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options


        backup = json_response['backups'][0]

        description_cols = {
          "Backup ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Type" => lambda {|it| it['backupType'] ? (it['backupType']['name'] || it['backupType']['code']) : '' },
          "Storage" => lambda {|it| it['storageProvider'] ? it['storageProvider']['name'] : '' },
          "Schedule" => lambda {|it| it['cronDescription'] || it['cronExpression'] }
        }
        print_description_list(description_cols, backup)

        backup_results = backup ? backup['backupResults'] : nil
        backup_rows = backup_results.collect {|it| 
          status_str = it['status'].to_s.upcase
          # 'START_REQUESTED' //START_REQUESTED, IN_PROGRESS, CANCEL_REQUESTED, CANCELLED, SUCCEEDED, FAILED
          if status_str == 'SUCCEEDED'
            status_str = "#{green}#{status_str.upcase}#{cyan}"
          elsif status_str == 'FAILED'
            status_str = "#{red}#{status_str.upcase}#{cyan}"
          else
            status_str = "#{cyan}#{status_str.upcase}#{cyan}"
          end
          {id: it['id'], startDate: format_local_dt(it['dateCreated']), duration: format_duration_milliseconds(it['durationMillis']), 
            size: format_bytes(it['sizeInMb'], 'MB'), status: status_str }
        }
        print_h1 "Backup Results", [], options
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          {:startDate => {:display_name => "Started"} },
          :duration,
          :size,
          :status
        ]
        print reset, "\n"
      elsif json_response['backups'].size == 0
        # no backup configured
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        print "#{yellow}No backups configured#{reset}\n\n"
      else
        # old format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        backups = json_response['backups']
        backup_rows = backups.collect {|r| 
          it = r['backup']
          {id: it['id'], name: it['name'], dateCreated: format_local_dt(it['dateCreated'])}
        }
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          :name,
          {:dateCreated => {:display_name => "Date Created"} }
        ]
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def clone(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -g GROUP")
      build_option_type_options(opts, options, clone_instance_option_types(false))
      opts.on( '-g', '--group GROUP', "Group Name or ID for the new instance" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID for the new instance" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    # if !options[:group]
    #   print_red_alert "GROUP is required."
    #   puts optparse
    #   exit 1
    # end
    connect(options)
    begin
      options[:options] ||= {}
      # use the -g GROUP or active group by default
      options[:options]['group'] ||= options[:group] || @active_group_id
      # support [new-name] 
      # if args[1]
      #   options[:options]['name'] = args[1]
      # end
      payload = {

      }
      params = Morpheus::Cli::OptionTypes.prompt(clone_instance_option_types, options[:options], @api_client, options[:params])
      group = find_group_by_name_or_id_for_provisioning(params.delete('group'))
      payload.merge!(params)
      payload['group'] = {id: group['id']}

      cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
      if cloud
        payload['cloud'] = {id: cloud['id']}
      end
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to clone the instance '#{instance['name']}'?", options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.clone(instance['id'], payload)
        return
      end
      json_response = @instances_interface.clone(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Cloning instance #{instance['name']} to '#{payload['name']}'"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def envs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get_envs(instance['id'])
        return
      end
      json_response = @instances_interface.get_envs(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      print_h1 "Instance Envs: #{instance['name']} (#{instance['instanceType']['name']})", [], options
      print cyan
      envs = json_response['envs'] || {}
      if json_response['readOnlyEnvs']
        envs += json_response['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
      end
      tp envs, :name, :value, :export
      print_h2 "Imported Envs", options
      imported_envs = json_response['importedEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value']}}
      tp imported_envs
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def setenv(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] VAR VALUE [-e]")
      opts.on( '-e', "Exportable" ) do |exportable|
        options[:export] = exportable
      end
      opts.on( '-M', "Masked" ) do |masked|
        options[:masked] = masked
      end
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count < 3
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
      payload = {envs: [evar]}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_env(instance['id'], payload)
        return
      end
      json_response = @instances_interface.create_env(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def delenv(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] VAR")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.del_env(instance['id'], args[1])
        return
      end
      json_response = @instances_interface.del_env(instance['id'], args[1])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    params = {'server' => true, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    params = {'server' => true, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def suspend(args)
    params = {'server' => true, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Suspend an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.suspend(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.suspend(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Suspended instance #{instances[0]['name']}"
        else
          print_green_success "Suspended #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def eject(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Eject an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.eject(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.eject(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Ejected instance #{instances[0]['name']}"
        else
          print_green_success "Ejected #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop_service(args)
    params = {'server' => false, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop service on an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start_service(args)
    params = {'server' => true} # server is true eh? so start-service is the same as start
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start service on an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart_service(args)
    params = {'server' => false, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart service on an instance.\n" +
                    "[name] is required. This is the name or id of an instance. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def actions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id or name list]")
      opts.footer = "This outputs the list of the actions available to specified instance(s)."
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} actions requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }
    begin
      # instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.available_actions(instance_ids)
        return 0
      end
      json_response = @instances_interface.available_actions(instance_ids)
      if options[:json]
        puts as_json(json_response, options)
      else
        title = "Instance Actions: #{anded_list(id_list)}"
        print_h1 title, [], options
        available_actions = json_response["actions"]
        if (available_actions && available_actions.size > 0)
          print as_pretty_table(available_actions, [:name, :code])
          print reset, "\n"
        else
          print "#{yellow}No available actions#{reset}\n\n"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def action(args)
    options = {}
    action_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list] -a CODE")
      opts.on('-a', '--action CODE', "Instance Action CODE to execute") do |val|
        action_id = val.to_s
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an action for one or many instances."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }

    # figure out what action to run
    available_actions = @instances_interface.available_actions(instance_ids, options)["actions"]
    if available_actions.empty?
      if instance_ids.size > 1
        print_red_alert "The specified instances have no available actions in common."
      else
        print_red_alert "The specified instance has no available actions."
      end
      return 1
    end
    instance_action = nil
    if action_id.nil?
      available_actions_dropdown = available_actions.collect {|act| {'name' => act["name"], 'value' => act["code"]} } # already sorted
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'select', 'fieldLabel' => 'Instance Action', 'selectOptions' => available_actions_dropdown, 'required' => true, 'description' => 'Choose the instance action to execute'}], options[:options])
      action_id = v_prompt['code']
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s }
    else
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s || act['name'].to_s.downcase == action_id.to_s.downcase }
      action_id = instance_action["code"] if instance_action
    end
    if !instance_action
      # for testing bogus actions..
      # instance_action = {"id" => action_id, "name" => "Unknown"}
      raise_command_error "Instance Action '#{action_id}' not found."
    end

    action_display_name = "#{instance_action['name']} [#{instance_action['code']}]"    
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to perform action #{action_display_name} on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end

    # return run_command_for_each_arg(containers) do |arg|
    #   _action(arg, action_id, options)
    # end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.action(instance_ids, action_id)
      return 0
    end
    json_response = @instances_interface.action(instance_ids, action_id)
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      # containers.each do |container|
      #   print green, "Action #{action_display_name} performed on container #{container['id']}", reset, "\n"
      # end
      print green, "Action #{action_display_name} performed on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}", reset, "\n"
    end
    return 0
  end

  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])

      group_id = instance['group']['id']
      cloud_id = instance['cloud']['id']
      layout_id = instance['layout']['id']

      plan_id = instance['plan']['id']
      payload = {
        :instance => {:id => instance["id"]}
      }

      # avoid 500 error
      # payload[:servicePlanOptions] = {}

      puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"

      # prompt for service plan
      service_plans_json = @instances_interface.service_plans({zoneId: cloud_id, siteId: group_id, layoutId: layout_id}, options)
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        if plan['value'] && plan['value'].to_i == plan_id.to_i
          plan['name'] = "#{plan['name']} (current)"
        end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
      new_plan_id = service_plan["id"]
      #payload[:servicePlan] = new_plan_id # ew, this api uses servicePlanId instead
      #payload[:servicePlanId] = new_plan_id
      payload[:instance][:plan] = {id: service_plan["id"]}

      volumes_response = @instances_interface.volumes(instance['id'], options)
      current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

      # prompt for volumes
      volumes = prompt_resize_volumes(current_volumes, service_plan, options)
      if !volumes.empty?
        payload[:volumes] = volumes
      end

      # only amazon supports this option
      # for now, always do this
      payload[:deleteOriginalVolumes] = true
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.resize(instance['id'], payload)
        return
      end
      json_response = @instances_interface.resize(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        print_green_success "Resizing instance #{instance['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backup(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to backup the instance '#{instance['name']}'?", options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backup(instance['id'])
        return
      end
      json_response = @instances_interface.backup(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        bad_results = []
        if json_response['results']
          json_response['results'].each do |result_id, result|
            if result['success'] != true
              bad_results << result['msg'] || "Failed to create backup for instance #{result_id}"
            end
          end
        end
        if bad_results.empty?
          print_green_success "Backup initiated."
          return 0
        else
          print_red_alert bad_results.join("\n")
          return 1
        end
      end
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
      opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off. Applies to certain types only.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on('--releaseEIPs [on|off]', ['on','off'], "Release EIPs. Default is on. Applies to Amazon only.") do |val|
        query_params[:releaseEIPs] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])

    end
    optparse.parse!(args)
    if args.count < 1
      puts "\n#{optparse}\n\n"
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
        exit 1
      end
      # JD: removeVolumes to maintain the old behavior with pre-3.5.2 appliances, remove me later
      if query_params[:preserveVolumes].nil?
        query_params[:removeVolumes] = 'on'
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.destroy(instance['id'],query_params)
        return
      end
      json_response = @instances_interface.destroy(instance['id'],query_params)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        print_green_success "Removing instance #{instance['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_disable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_disable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_enable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_enable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.security_groups(instance['id'])
        return
      end
      json_response = @instances_interface.security_groups(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Instance: #{instance['name']}", [], options
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      #print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
        print "\n"
      end
      print reset, "\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    security_group_ids = nil
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [-S] [-c]")
      opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        security_group_ids = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        security_group_ids = []
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      payload = {securityGroupIds: security_group_ids}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.apply_security_groups(instance['id'], payload)
        return
      end
      json_response = @instances_interface.apply_security_groups(instance['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      if !options[:quiet]
        security_groups([args[0]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def run_workflow(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [workflow] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 2
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 2 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    workflow = find_workflow_by_name(args[1])
    task_types = @tasks_interface.task_types()
    editable_options = []
    workflow['taskSetTasks'].sort{|a,b| a['taskOrder'] <=> b['taskOrder']}.each do |task_set_task|
      task_type_id = task_set_task['task']['taskType']['id']
      task_type = task_types['taskTypes'].find{ |current_task_type| current_task_type['id'] == task_type_id}
      task_opts = task_type['optionTypes'].select { |otype| otype['editable']}
      if !task_opts.nil? && !task_opts.empty?
        editable_options += task_opts.collect do |task_opt|
          new_task_opt = task_opt.clone
          new_task_opt['fieldContext'] = "#{task_set_task['id']}.#{new_task_opt['fieldContext']}"
        end
      end
    end
    params = {}
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # if params.empty? && !editable_options.empty?
    #   puts optparse
    #   option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
    #   puts "\nAvailable Options:\n#{option_lines}\n\n"
    #   exit 1
    # end

    workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
    begin
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.workflow(instance['id'],workflow['id'], workflow_payload)
        return
      end
      json_response = @instances_interface.workflow(instance['id'],workflow['id'], workflow_payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      else
        print_green_success "Running workflow #{workflow['name']} on instance #{instance['name']} ..."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def import_snapshot(args)
    options = {}
    storage_provider_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on("--storage-provider ID", String, "Optional storage provider") do |val|
        storage_provider_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to import a snapshot of the instance '#{instance['name']}'?", options)
        exit 1
      end

      payload = {}

      # Prompt for Storage Provider, use default value.
      begin
        options[:options] ||= {}
        options[:options]['storageProviderId'] = storage_provider_id if storage_provider_id
        storage_provider_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.'}], options[:options], @api_client, {})
        if !storage_provider_prompt['storageProviderId'].empty?
          payload['storageProviderId'] = storage_provider_prompt['storageProviderId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load storage providers"
        #print_rest_exception(e, options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.import_snapshot(instance['id'], payload)
        return
      end
      json_response = @instances_interface.import_snapshot(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot import initiated."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def scaling(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Show scaling threshold information for an instance."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} scaling requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _scaling(arg, options)
    end
  end

  def _scaling(arg, options)
    instance = find_instance_by_name_or_id(arg)
    return 1 if instance.nil?
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.threshold(instance['id'], params)
      return 0
    end
    json_response = @instances_interface.threshold(instance['id'], params)
    if options[:json]
      puts as_json(json_response, options, "instanceThreshold")
      return 0
    elsif options[:yaml]
      puts as_yaml(json_response, options, "instanceThreshold")
      return 0
    elsif options[:csv]
      puts records_as_csv([json_response['instanceThreshold']], options)
      return 0
    end

    instance_threshold = json_response['instanceThreshold']

    title = "Instance Scaling: [#{instance['id']}] #{instance['name']} (#{instance['instanceType']['name']})"
    print_h1 title, [], options
    if instance_threshold.empty?
      print yellow,"No scaling settings applied to this instance.",reset,"\n"
    else
      # print_h1 "Threshold Settings", [], options
      print cyan
      print_instance_threshold_description_list(instance_threshold)
    end
    print reset, "\n"
    return 0

  end

  def scaling_update(args)
    usage = "Usage: morpheus instances scaling-update [name] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, instance_scaling_option_types(nil))
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update scaling threshold information for an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} scaling-update requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold'] || {}
      my_option_types = instance_scaling_option_types(instance)

      # preserve current values by setting the prompt options defaultValue attribute
      # note: checkbox type converts true,false to 'on','off'
      my_option_types.each do |opt|
        field_key = opt['fieldName'] # .sub('instanceThreshold.', '')
        if instance_threshold[field_key] != nil
          opt['defaultValue'] = instance_threshold[field_key]
        end
      end
      
      # params = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, {})

      # ok, gotta split these inputs into sections with conditional logic
      params = {}

      option_types_group = my_option_types.select {|opt| ['autoUp', 'autoDown'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})

      option_types_group = my_option_types.select {|opt| ['zoneId'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['zoneId']
        if params['zoneId'] == '' || params['zoneId'] == 'null' || params['zoneId'].to_s == '0'
          params['zoneId'] = 0
        else
          params['zoneId'] = params['zoneId'].to_i
        end
      end

      option_types_group = my_option_types.select {|opt| ['minCount', 'maxCount'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})

      option_types_group = my_option_types.select {|opt| ['memoryEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['memoryEnabled'] == 'on' || params['memoryEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minMemory', 'maxMemory'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minMemory'] = nil
        params['maxMemory'] = nil
      end

      option_types_group = my_option_types.select {|opt| ['diskEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['diskEnabled'] == 'on' || params['diskEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minDisk', 'maxDisk'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minDisk'] = nil
        params['maxDisk'] = nil
      end

      option_types_group = my_option_types.select {|opt| ['cpuEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['cpuEnabled'] == 'on' || params['cpuEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minCpu', 'maxCpu'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minCpu'] = nil
        params['maxCpu'] = nil
      end

      # argh, convert on/off to true/false
      # this needs a global solution...
      params.each do |k,v|
        if v == 'on' || v == 'true' || v == 'yes'
          params[k] = true
        elsif v == 'off' || v == 'false' || v == 'no'
          params[k] = false
        end
      end      

      payload = {
        'instanceThreshold' => {}
      }
      payload['instanceThreshold'].merge!(params)

      # unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the scaling settings for instance '#{instance['name']}'?", options)
      #   return 9, "aborted command"
      # end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_threshold(instance['id'], payload)
        return
      end
      json_response = @instances_interface.update_threshold(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated scaling settings for instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def load_balancer_update(args)
    raise "Not Yet Implemented"
    usage = "Usage: morpheus instances lb-update [name] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      #build_option_type_options(opts, options, instance_load_balancer_option_types(nil))
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Assign a load balancer for an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-update requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # refetch to get loadBalancers from show()
      json_response = @instances_interface.get(instance['id'])

      current_instance_lb = nil
      # refetch to get current load balancer info from show()
      json_response = @instances_interface.get(instance['id'])
      #load_balancers = @instances_interface.threshold(instance['id'])['loadBalancers'] || {}
      if json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      #my_option_types = instance_load_balancer_option_types(instance)

      # todo...

      # Host Name
      # Load Balancer
      # Protocol
      # Port
      # SSL Cert
      # Scheme

      current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]

      params = {}
  
      payload = {
        'instance' => {},
        'networkLoadBalancer' => {}
      }

      cur_host_name = instance['hostName']
      #host_name = params = Morpheus::Cli::OptionTypes.prompt([{'fieldName'=>'hostName', 'label'=>'Host Name', 'defaultValue'=>cur_host_name}], options[:options], @api_client, {})
      payload['instance']['hostName'] = instance['hostName']

      #payload['loadBalancerId'] = params['loadBalancerId']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.update_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated scaling settings for instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def load_balancer_remove(args)
    usage = "Usage: morpheus instances lb-remove [name] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, instance_scaling_option_types(nil))
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove a load balancer from an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-remove requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      # re-fetch via show() get loadBalancers
      json_response = @instances_interface.get(instance['id'])
      load_balancers = json_response['instance']['loadBalancers']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      
      # no options here, just send DELETE request
      payload = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.remove_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Removed load balancer from instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history(args)
    raw_args = args.dup
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on( '-n', '--node NODE_ID', "Scope history to specific Container or VM" ) do |node_id|
      #   options[:node_id] = node_id.to_i
      # end
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on(nil, '--details', "Display more details. Shows everything, untruncated." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      opts.on('--process-id ID', String, "Display details about a specfic process only." ) do |val|
        options[:process_id] = val
      end
      opts.on('--event-id ID', String, "Display details about a specfic process event only." ) do |val|
        options[:event_id] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes for a specific instance.\n" + 
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)

    # shortcut to other actions
    if options[:process_id]
      return history_details(raw_args)
    elsif options[:event_id]
      return history_event_details(raw_args)
    end

    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      # container_ids = instance['containers']
      # if options[:node_id] && container_ids.include?(options[:node_id])
      #   container_ids = [options[:node_id]]
      # end
      params = {}
      params.merge!(parse_list_options(options))
      # params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history(instance['id'], params)
        return
      end
      json_response = @instances_interface.history(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options, "processes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processes'], options)
        return 0
      else

        title = "Instance History: #{instance['name']}"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if json_response['processes'].empty?
          print "#{cyan}No process history found.#{reset}\n\n"
        else
          history_records = []
          json_response["processes"].each do |process|
            row = {
              id: process['id'],
              eventId: nil,
              uniqueId: process['uniqueId'],
              name: process['displayName'],
              description: process['description'],
              processType: process['processType'] ? (process['processType']['name'] || process['processType']['code']) : process['processTypeName'],
              createdBy: process['createdBy'] ? (process['createdBy']['displayName'] || process['createdBy']['username']) : '',
              startDate: format_local_dt(process['startDate']),
              duration: format_process_duration(process),
              status: format_process_status(process),
              error: format_process_error(process, options[:details] ? nil : 20),
              output: format_process_output(process, options[:details] ? nil : 20)
            }
            history_records << row
            process_events = process['events'] || process['processEvents']
            if options[:show_events]
              if process_events
                process_events.each do |process_event|
                  event_row = {
                    id: process['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event, options[:details] ? nil : 20),
                    output: format_process_output(process_event, options[:details] ? nil : 20)
                  }
                  history_records << event_row
                end
              else
                
              end
            end
          end
          columns = [
            {:id => {:display_name => "PROCESS ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error
          ]
          if options[:show_events]
            columns.insert(1, {:eventId => {:display_name => "EVENT ID"} })
          end
          if options[:show_output]
            columns << :output
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(history_records, columns, options)
          #print_results_pagination(json_response)
          print_results_pagination(json_response, {:label => "process", :n_label => "processes"})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_details(args)
    options = {}
    process_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [process-id]")
      opts.on('--process-id ID', String, "Display details about a specfic event." ) do |val|
        options[:process_id] = val
      end
      opts.add_hidden_option('process-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[process-id] is required. This is the id of the process."
    end
    optparse.parse!(args)
    if args.count == 2
      process_id = args[1]
    elsif args.count == 1 && options[:process_id]
      process_id = options[:process_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_details(instance['id'], process_id, params)
        return
      end
      json_response = @instances_interface.history_details(instance['id'], process_id, params)
      if options[:json]
        puts as_json(json_response, options, "process")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "process")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['process'], options)
        return 0
      else
        process = json_response["process"]
        title = "Instance History Details"
        subtitles = []
        subtitles << " Process ID: #{process_id}"
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_details(process)
  
        print_h2 "Process Events", options
        process_events = process['events'] || process['processEvents'] || []
        history_records = []
        if process_events.empty?
          puts "#{cyan}No events found.#{reset}"
        else      
          process_events.each do |process_event|
            event_row = {
                    id: process_event['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event),
                    output: format_process_output(process_event)
                  }
            history_records << event_row
          end
          columns = [
            {:id => {:display_name => "EVENT ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error,
            :output
          ]
          print cyan
          print as_pretty_table(history_records, columns, options)
          print_results_pagination({size: process_events.size, total: process_events.size})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_event_details(args)
    options = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [event-id]")
      opts.on('--event-id ID', String, "Display details about a specfic event." ) do |val|
        options[:event_id] = val
      end
      opts.add_hidden_option('event-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process event.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[event-id] is required. This is the id of the process event."
    end
    optparse.parse!(args)
    if args.count == 2
      process_event_id = args[1]
    elsif args.count == 1 && options[:event_id]
      process_event_id = options[:event_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_event_details(instance['id'], process_event_id, params)
        return
      end
      json_response = @instances_interface.history_event_details(instance['id'], process_event_id, params)
      if options[:json]
        puts as_json(json_response, options, "processEvent")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processEvent")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processEvent'], options)
        return 0
      else
        process_event = json_response['processEvent'] || json_response['event']
        title = "Instance History Event"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_event_details(process_event)
        print reset, "\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execution_request(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on('--script SCRIPT', "Script to be executed" ) do |val|
        script_content = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          script_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an arbitrary script or command on an instance." + "\n" +
                    "[id] is required. This is the id or name of an instance." + "\n" +
                    "[script] is required. This is the script that is to be executed."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      params['instanceId'] = instance['id']
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # prompt for Script
        if script_content.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'script', 'type' => 'code-editor', 'fieldLabel' => 'Script', 'required' => true, 'description' => 'The script content'}], options[:options])
          script_content = v_prompt['script']
        end
        payload['script'] = script_content
      end
      @execution_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @execution_request_interface.dry.create(params, payload)
        return 0
      end
      # do it
      json_response = @execution_request_interface.create(params, payload)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      execution_request = json_response['executionRequest']
      print_green_success "Executing request #{execution_request['uniqueId']}"
      if do_refresh
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId'], "--refresh"])
      else
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

private

  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      json_results = @clouds_interface.get(val.to_i)
      zone = json_results['zone']
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      json_results = @clouds_interface.get({groupId: group_id, name: val})
      zone = json_results['zones'] ? json_results['zones'][0] : nil
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end
  def find_host_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
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
    results = @servers_interface.list({name: name})
    if results['servers'].empty?
      print_red_alert "Host not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple hosts exist with the name #{name}. Try using id instead"
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

  def find_workflow_by_name(name)
    task_set_results = @task_sets_interface.get(name)
    if !task_set_results['taskSets'].nil? && !task_set_results['taskSets'].empty?
      return task_set_results['taskSets'][0]
    else
      print_red_alert "Workflow not found by name #{name}"
      exit 1
    end
  end

  # def print_instances_table(instances, opts={})
  #   table_color = opts[:color] || cyan
  #   rows = instances.collect {|instance| 
  #     {
  #       id: instance['id'],
  #       name: instance['name'],
  #       connection: format_instance_connection_string(instance),
  #       environment: instance['instanceContext'],
  #       nodes: instance['containers'].count,
  #       status: format_instance_status(instance, table_color),
  #       type: instance['instanceType']['name'],
  #       group: !instance['group'].nil? ? instance['group']['name'] : nil,
  #       cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil
  #     }
  #   }
  #   print table_color
  #   tp rows, :id, :name, :group, :cloud, :type, :environment, :nodes, :connection, :status
  #   print reset
  # end

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

  def clone_instance_option_types(connected=true)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for the new instance'},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true},
    ]
  end

  def instance_scaling_option_types(instance=nil)
    
    # Group
    group_id = nil
    if instance && instance['group']
      group_id = instance['group']['id']
    end

    available_clouds = group_id ? get_available_clouds(group_id) : []
    zone_dropdown = [{'name' => 'Use Scale Priority', 'value' => 0}] 
    zone_dropdown += available_clouds.collect {|cloud| {'name' => cloud['name'], 'value' => cloud['id']} }

    list = []
    list << {'fieldName' => 'autoUp', 'fieldLabel' => 'Auto Upscale', 'type' => 'checkbox', 'description' => 'Enable auto upscaling', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'autoDown', 'fieldLabel' => 'Auto Downscale', 'type' => 'checkbox', 'description' => 'Enable auto downscaling', 'required' => true, 'defaultValue' => false}
    
    list << {'fieldName' => 'zoneId', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => zone_dropdown, 'description' => "Choose a cloud to scale into.", 'placeHolder' => 'ID'}

    list << {'fieldName' => 'minCount', 'fieldLabel' => 'Min Count', 'type' => 'number', 'description' => 'Minimum number of nodes', 'placeHolder' => 'NUMBER'}
    list << {'fieldName' => 'maxCount', 'fieldLabel' => 'Max Count', 'type' => 'number', 'description' => 'Maximum number of nodes', 'placeHolder' => 'NUMBER'}
    

    list << {'fieldName' => 'memoryEnabled', 'fieldLabel' => 'Enable Memory Threshold', 'type' => 'checkbox', 'description' => 'Scale when memory thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory', 'type' => 'number', 'description' => 'Minimum memory percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory', 'type' => 'number', 'description' => 'Maximum memory percent (0-100)', 'placeHolder' => 'PERCENT'}

    list << {'fieldName' => 'diskEnabled', 'fieldLabel' => 'Enable Disk Threshold', 'type' => 'checkbox', 'description' => 'Scale when disk thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minDisk', 'fieldLabel' => 'Min Disk', 'type' => 'number', 'description' => 'Minimum storage percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxDisk', 'fieldLabel' => 'Max Disk', 'type' => 'number', 'description' => 'Maximum storage percent (0-100)', 'placeHolder' => 'PERCENT'}

    list << {'fieldName' => 'cpuEnabled', 'fieldLabel' => 'Enable CPU Threshold', 'type' => 'checkbox', 'description' => 'Scale when cpu thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minCpu', 'fieldLabel' => 'Min CPU', 'type' => 'number', 'description' => 'Minimum CPU percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxCpu', 'fieldLabel' => 'Max CPU', 'type' => 'number', 'description' => 'Maximum CPU percent (0-100)', 'placeHolder' => 'PERCENT'}

    # list << {'fieldName' => 'iopsEnabled', 'fieldLabel' => 'Enable Iops Threshold', 'type' => 'checkbox', 'description' => 'Scale when iops thresholds are met.'}
    # list << {'fieldName' => 'minIops', 'fieldLabel' => 'Min Iops', 'type' => 'number', 'description' => 'Minimum iops'}
    # list << {'fieldName' => 'maxIops', 'fieldLabel' => 'Max Iops', 'type' => 'number', 'description' => 'Maximum iops'}

    # list << {'fieldName' => 'networkEnabled', 'fieldLabel' => 'Enable Iops Threshold', 'type' => 'checkbox', 'description' => 'Scale when network thresholds are met.'}
    # list << {'fieldName' => 'minNetwork', 'fieldLabel' => 'Min Network', 'type' => 'number', 'description' => 'Minimum networking'}

    # list << {'fieldName' => 'comment', 'fieldLabel' => 'Comment', 'type' => 'text', 'description' => 'Comment on these scaling settings.'}

    list
  end

  def instance_load_balancer_option_types(instance=nil)
    list = []
    list << {'fieldContext' => 'instance', 'fieldName' => 'hostName', 'fieldLabel' => 'Host Name', 'type' => 'checkbox', 'description' => 'Enable auto upscaling', 'required' => true, 'defaultValue' => instance ? instance['hostName'] : nil}
    list << {'fieldName' => 'proxyProtocol', 'fieldLabel' => 'Protocol', 'type' => 'checkbox', 'description' => 'Enable auto downscaling', 'required' => true, 'defaultValue' => false}
    list
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

  def print_instance_threshold_description_list(instance_threshold)
    description_cols = {
      # "Instance" => lambda {|it| "#{instance['id']} - #{instance['name']}" },
      "Auto Upscale" => lambda {|it| format_boolean(it['autoUp']) },
      "Auto Downscale" => lambda {|it| format_boolean(it['autoDown']) },
      "Cloud" => lambda {|it| it['zoneId'] ? "#{it['zoneId']}" : 'Use Scale Priority' },
      "Min Count" => lambda {|it| it['minCount'] },
      "Max Count" => lambda {|it| it['maxCount'] },
      "Memory Enabled" => lambda {|it| format_boolean(it['memoryEnabled']) },
      "Min Memory" => lambda {|it| it['memoryEnabled'] ? (it['minMemory'] ? "#{it['minMemory']}%" : '') : '' },
      "Max Memory" => lambda {|it| it['memoryEnabled'] ? (it['maxMemory'] ? "#{it['maxMemory']}%" : '') : '' },
      "Disk Enabled" => lambda {|it| format_boolean(it['diskEnabled']) },
      "Min Disk" => lambda {|it| it['diskEnabled'] ? (it['minDisk'] ? "#{it['minDisk']}%" : '') : '' },
      "Max Disk" => lambda {|it| it['diskEnabled'] ? (it['maxDisk'] ? "#{it['maxDisk']}%" : '') : '' },
      "CPU Enabled" => lambda {|it| format_boolean(it['cpuEnabled']) },
      "Min CPU" => lambda {|it| it['cpuEnabled'] ? (it['minCpu'] ? "#{it['minCpu']}%" : '') : '' },
      "Max CPU" => lambda {|it| it['cpuEnabled'] ? (it['maxCpu'] ? "#{it['maxCpu']}%" : '') : '' },
      # "Iops Enabled" => lambda {|it| format_boolean(it['iopsEnabled']) },
      # "Min Iops" => lambda {|it| it['minIops'] },
      # "Max Iops" => lambda {|it| it['maxDisk'] },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
    print_description_list(description_cols, instance_threshold)
  end

  def print_process_details(process)
    description_cols = {
      "Process ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['displayName'] },
      "Description" => lambda {|it| it['description'] },
      "Process Type" => lambda {|it| it['processType'] ? (it['processType']['name'] || it['processType']['code']) : it['processTypeName'] },
      "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['displayName'] || it['createdBy']['username']) : '' },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Duration" => lambda {|it| format_process_duration(it) },
      "Status" => lambda {|it| format_process_status(it) },
      # "# Events" => lambda {|it| (it['events'] || []).size() },
    }
    print_description_list(description_cols, process)

    if process['error']
      print_h2 "Error", options
      print reset
      #puts format_process_error(process_event)
      puts process['error'].to_s.strip
    end

    if process['output']
      print_h2 "Output", options
      print reset
      #puts format_process_error(process_event)
      puts process['output'].to_s.strip
    end
  end

  def print_process_event_details(process_event)
    # process_event =~ process
    description_cols = {
      "Process ID" => lambda {|it| it['processId'] },
      "Event ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['displayName'] },
      "Description" => lambda {|it| it['description'] },
      "Process Type" => lambda {|it| it['processType'] ? (it['processType']['name'] || it['processType']['code']) : it['processTypeName'] },
      "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['displayName'] || it['createdBy']['username']) : '' },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Duration" => lambda {|it| format_process_duration(it) },
      "Status" => lambda {|it| format_process_status(it) },
    }
    print_description_list(description_cols, process_event)

    if process_event['error']
      print_h2 "Error", options
      print reset
      #puts format_process_error(process_event)
      puts process_event['error'].to_s.strip
    end

    if process_event['output']
      print_h2 "Output", options
      print reset
      #puts format_process_error(process_event)
      puts process_event['output'].to_s.strip
    end
  end
  

end
