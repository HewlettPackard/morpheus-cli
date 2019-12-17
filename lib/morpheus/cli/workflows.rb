# require 'yaml'
require 'io/console'
require 'rest_client'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :execute
  set_default_subcommand :list
  
  # def initialize()
  #   @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  # end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @task_sets_interface = @api_client.task_sets
    @tasks_interface = @api_client.tasks
    @option_types_interface = @api_client.option_types
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
  end


  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.get(params)
        return
      end
      json_response = @task_sets_interface.get(params)
      task_sets = json_response['taskSets']
      # print result and return output
      if options[:json]
        puts as_json(json_response, options, "taskSets")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['taskSets'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "taskSets")
        return 0
      else
        task_sets = json_response['taskSets']
        title = "Morpheus Workflows"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if task_sets.empty?
          print cyan,"No workflows found.",reset,"\n"
        else
          print cyan
          print_workflows_table(task_sets)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    task_arg_list = nil
    option_type_arg_list = nil
    workflow_type = 'provision'
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --tasks taskId:phase,taskId2:phase,taskId3:phase")
      opts.on("--name NAME", String, "Name for workflow") do |val|
        params['name'] = val
      end
      opts.on("--type TYPE", String, "Type of workflow. i.e. provision or operation. Default is provision.") do |val|
        workflow_type = val.to_s.downcase
        if workflow_type == 'provisional'
          workflow_type = 'provision'
        elsif workflow_type == 'operational'
          workflow_type = 'operation'
        end
        params['type'] = workflow_type
      end
      opts.on("--tasks x,y,z", Array, "List of tasks to run in order, in the format <Task ID>:<Task Phase> Task Phase is optional, the default is 'provision'.") do |list|
        task_arg_list = []
        list.each do |it|
          task_id, task_phase = it.split(":")
          task_arg_list << {task_id: task_id.to_s.strip, task_phase: task_phase.to_s.strip}
        end
      end
      opts.on("--option-types x,y,z", Array, "List of option type name or IDs. For use with operational workflows to add configuration during execution.") do |list|
        option_type_arg_list = []
        list.each do |it|
          option_type_arg_list << {option_type_id: it.to_s.strip}
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        if args[0]
          params['name'] = args[0]
        end
        if params['name'].to_s.empty?
          puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [name]\n#{optparse}"
          return 1
        end
        if task_arg_list.nil?
          puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --tasks\n#{optparse}"
          return 1
        end
        tasks = []
        if task_arg_list
          task_arg_list.each do |task_arg|
            found_task = find_task_by_name_or_id(task_arg[:task_id])
            return 1 if found_task.nil?
            row = {'taskId' => found_task['id']}
            if !task_arg[:task_phase].to_s.strip.empty?
              row['taskPhase'] = task_arg[:task_phase]
            elsif workflow_type == 'operation'
              row['taskPhase'] = 'operation'
            end
            tasks << row
          end
        end
        option_types = []
        if option_type_arg_list
          # if workflow_type == 'operation'
          # end
          option_type_arg_list.each do |option_type_arg|
            found_option_type = find_option_type_by_name_or_id(option_type_arg[:option_type_id])
            return 1 if found_option_type.nil?
            option_types << found_option_type['id']
          end
        end
        payload = {'taskSet' => {}}
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        params['type'] = workflow_type
        payload['taskSet'].deep_merge!(params)
        if !tasks.empty?
          payload['taskSet']['tasks'] = tasks
        end
        if !option_types.empty?
          payload['taskSet']['optionTypes'] = option_types
        end
      end
      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.create(payload)
        return
      end
      json_response = @task_sets_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        workflow = json_response['taskSet']
        print "\n", cyan, "Workflow #{workflow['name']} created successfully", reset, "\n\n"
        get([workflow['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[workflow]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end
  
  def _get(id, options)
    workflow_name = id
    begin
      @task_sets_interface.setopts(options)
      if options[:dry_run]
        if workflow_name.to_s =~ /\A\d{1,}\Z/
          print_dry_run @task_sets_interface.dry.get(workflow_name.to_i)
        else
          print_dry_run @task_sets_interface.dry.get({name: workflow_name})
        end
        return
      end
      workflow = find_workflow_by_name_or_id(workflow_name)
      exit 1 if workflow.nil?
      # refetch it..
      json_response = {'taskSet' => workflow}
      unless workflow_name.to_s =~ /\A\d{1,}\Z/
        json_response = @task_sets_interface.get(workflow['id'])
      end
      workflow = json_response['taskSet']
      if options[:json]
        puts as_json(json_response, options, "taskSet")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "taskSet")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['taskSet']], options)
        return 0
      else
        # tasks = []
        # (workflow['tasks'] || []).each do |task_name|
        #   tasks << find_task_by_name_or_id(task_name)['id']
        # end
        tasks = workflow['taskSetTasks'].sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }
        print_h1 "Workflow Details"

        print cyan
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Description" => 'description',
          "Type" => lambda {|workflow| format_workflow_type(workflow) },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        print_description_list(description_cols, workflow)

        #task_names = tasks.collect {|it| it['name'] }
        print_h2 "Workflow Tasks"
        if tasks.empty?
          print yellow,"No tasks in this workflow.",reset,"\n"
        else
          print cyan
          # tasks.each_with_index do |taskSetTask, index|
          #   puts "#{(index+1).to_s.rjust(3, ' ')}. #{taskSetTask['task']['name']}"
          # end
          task_set_task_columns = [
            # this is the ID needed for the config options, by name would be nicer
            {"ID" => lambda {|it| it['id'] } }, 
            {"TASK ID" => lambda {|it| it['task']['id'] } },
            {"NAME" => lambda {|it| it['task']['name'] } },
            {"TYPE" => lambda {|it| it['task']['taskType'] ? it['task']['taskType']['name'] : '' } },
            {"PHASE" => lambda {|it| it['taskPhase'] } }, # not returned yet?
          ]
          print cyan
          puts as_pretty_table(tasks, task_set_task_columns)
        end
        print reset
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    task_arg_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --tasks taskId:phase,taskId2:phase,taskId3:phase")
      opts.on("--name NAME", String, "New name for workflow") do |val|
        params['name'] = val
      end
      opts.on("--tasks x,y,z", Array, "New list of tasks to run in the format <Task ID>:<Phase>. Phase is optional, the default is 'provision'.") do |list|
        task_arg_list = []
        list.each do |it|
          task_id, task_phase = it.split(":")
          task_arg_list << {task_id: task_id.to_s.strip, task_phase: task_phase.to_s.strip}
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    workflow_name = args[0]
    connect(options)
    begin
      workflow = find_workflow_by_name_or_id(workflow_name)
      return 1 if workflow.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        tasks = []
        if task_arg_list
          task_arg_list.each do |task_arg|
            found_task = find_task_by_name_or_id(task_arg[:task_id])
            return 1 if found_task.nil?
            row = {'taskId' => found_task['id']}
            if !task_arg[:task_phase].to_s.strip.empty?
              row['taskPhase'] = task_arg[:task_phase]
            end
            tasks << row
          end
        end
        payload = {'taskSet' => {}}
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload['taskSet'].deep_merge!(params)
        if !tasks.empty?
          payload['taskSet']['tasks'] = tasks
        end
      end
      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.update(workflow['id'], payload)
        return
      end
      json_response = @task_sets_interface.update(workflow['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Workflow #{json_response['taskSet']['name']} updated successfully", reset, "\n\n"
        get([workflow['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: morpheus workflows remove [name]"
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    workflow_name = args[0]
    connect(options)
    begin
      workflow = find_workflow_by_name_or_id(workflow_name)
      exit 1 if workflow.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the workflow #{workflow['name']}?")
        exit 1
      end
      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.destroy(workflow['id'])
        return
      end
      json_response = @task_sets_interface.destroy(workflow['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Workflow #{workflow['name']} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execute(args)
    params = {}
    options = {}
    target_type = nil
    instance_ids = []
    instances = []
    server_ids = []
    servers = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[workflow] --instance [instance] [options]")
      opts.on('--instance INSTANCE', String, "Instance name or id to execute the workflow on. This option can be passed more than once.") do |val|
        target_type = 'instance'
        instance_ids << val
      end
      opts.on('--instances [LIST]', Array, "Instances, comma separated list of instance names or IDs.") do |list|
        target_type = 'instance'
        instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--host HOST', String, "Host name or id to execute the workflow on. This option can be passed more than once.") do |val|
        target_type = 'server'
        server_ids << val
      end
      opts.on('--hosts [LIST]', Array, "Hosts, comma separated list of host names or IDs.") do |list|
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--server HOST', String, "alias for --host") do |val|
        target_type = 'server'
        server_ids << val
      end
      opts.on('--servers [LIST]', Array, "alias for --hosts") do |list|
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.add_hidden_option('--server')
      opts.add_hidden_option('--servers')
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    workflow_name = args[0]
    connect(options)
    begin
      workflow = find_workflow_by_name_or_id(workflow_name)
      return 1 if workflow.nil?

      if instance_ids.size > 0 && server_ids.size > 0
        raise_command_error "Pass --instance or --host, not both.\n#{optparse}"
      elsif instance_ids.size > 0
        instance_ids.each do |instance_id|
          instance = find_instance_by_name_or_id(instance_id)
          return 1 if instance.nil?
          instances << instance
        end
        params['instances'] = instances.collect {|it| it['id'] }
      elsif server_ids.size > 0
        server_ids.each do |server_id|
          server = find_server_by_name_or_id(server_id)
          return 1 if server.nil?
          servers << server
        end
        params['servers'] = instances.collect {|it| it['id'] }
      else
        raise_command_error "missing required option: --instance or --host\n#{optparse}"
      end

      # todo: prompt to workflow optionTypes for customOptions
      custom_options = nil
      if workflow['optionTypes'] && workflow['optionTypes'].size() > 0
        custom_option_types = workflow['optionTypes'].collect {|it|
          it['fieldContext'] = 'customOptions'
          it
        }
        custom_options = Morpheus::Cli::OptionTypes.prompt(custom_option_types, options[:options], @api_client, {})
      end

      params['targetType'] = target_type

      job_payload = {}
      job_payload.deep_merge!(params)
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      passed_options.delete('customOptions')
      job_payload.deep_merge!(passed_options) unless passed_options.empty?
      if custom_options
        # job_payload.deep_merge!('config' => custom_options)
        job_payload.deep_merge!(custom_options)
      end
      payload = {'job' => job_payload}

      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.run(workflow['id'], payload)
        return 0
      end
      response = @task_sets_interface.run(workflow['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        if !response['success']
          return 1
        end
      else
        target_desc = ""
        if instances.size() > 0
          target_desc = (instances.size() == 1) ? "instance #{instances[0]['name']}" : "#{instances.size()} instances"
        elsif servers.size() > 0
          target_desc = (servers.size() == 1) ? "host #{servers[0]['name']}" : "#{servers.size()} hosts"
        end
        print_green_success "Executing workflow #{workflow['name']} on #{target_desc}"
        # todo: load job/execution
        # get([workflow['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

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
    workflows = @task_sets_interface.list({name: name.to_s})['taskSets']
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

  def find_task_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_task_by_id(val)
    else
      return find_task_by_name(val)
    end
  end

  def find_task_by_id(id)
    begin
      json_response = @tasks_interface.get(id.to_i)
      return json_response['task']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Task not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_task_by_name(name)
    tasks = @tasks_interface.list({name: name.to_s})['tasks']
    if tasks.empty?
      print_red_alert "Task not found by name #{name}"
      return nil
    elsif tasks.size > 1
      print_red_alert "#{tasks.size} tasks by name #{name}"
      print_tasks_table(tasks, {color: red})
      print reset,"\n\n"
      return nil
    else
      return tasks[0]
    end
  end

  def print_workflows_table(workflows, opts={})
    columns = [
      {"ID" => lambda {|workflow| workflow['id'] } },
      {"NAME" => lambda {|workflow| workflow['name'] } },
      {"TYPE" => lambda {|workflow| format_workflow_type(workflow) } },
      {"TASKS" => lambda {|workflow| 
        (workflow['taskSetTasks'] || []).sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }.collect { |taskSetTask|
          taskSetTask['task']['name']
        }.join(', ')
       } },
      {"DATE CREATED" => lambda {|workflow| format_local_dt(workflow['dateCreated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(workflows, columns, opts)
  end

  def format_workflow_type(workflow)
    if workflow['type'] == 'provision'
      "Provisioning"
    elsif workflow['type'] == 'operation'
      "Operational"
    else
      workflow['type']
    end
  end

  def find_option_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_option_type_by_id(val)
    else
      return find_option_type_by_name(val)
    end
  end

  def find_option_type_by_id(id)
    begin
      json_response = @option_types_interface.get(id.to_i)
      return json_response['optionType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Option Type not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_option_type_by_name(name)
    json_results = @option_types_interface.list({name: name.to_s})
    if json_results['optionTypes'].empty?
      print_red_alert "Option Type not found by name #{name}"
      exit 1
    end
    option_type = json_results['optionTypes'][0]
    return option_type
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
      json_response = @instances_interface.get(id.to_i)
      return json_response['instance']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Instance not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_instance_by_name(name)
    instances = @instances_interface.list({name: name.to_s})['instances']
    if instances.empty?
      print_red_alert "Instance not found by name #{name}"
      return nil
    elsif instances.size > 1
      print_red_alert "#{instances.size} instances found by name #{name}"
      as_pretty_table(instances, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return instances[0]
    end
  end

  def find_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_server_by_id(val)
    else
      return find_server_by_name(val)
    end
  end

  def find_server_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Server not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_server_by_name(name)
    servers = @servers_interface.list({name: name.to_s})['servers']
    if servers.empty?
      print_red_alert "Host not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} hosts found by name #{name}"
      as_pretty_table(servers, [:id, :name], {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return servers[0]
    end
  end

end
