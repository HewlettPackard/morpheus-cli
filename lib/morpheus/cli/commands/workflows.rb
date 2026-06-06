require 'morpheus/cli/cli_command'

class Morpheus::Cli::Workflows
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::JobsHelper

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
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on("-t", "--type TYPE", "Type of workflow. i.e. provision or operation. Default is provision.") do |val|
        workflow_type = val.to_s.downcase
        if workflow_type.include?('provision')
          workflow_type = 'provision'
        elsif workflow_type.include?('operation')
          workflow_type = 'operation'
        end
        params['type'] = workflow_type
      end
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_standard_list_options(opts, options)
      opts.footer = "List workflows."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @task_sets_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @task_sets_interface.dry.get(params)
      return
    end
    json_response = @task_sets_interface.get(params)
    task_sets = json_response['taskSets']
    render_response(json_response, options, 'taskSets') do
      title = "Morpheus Workflows"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if params['type']
        subtitles << "Type: #{params['type']}"
      end
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
    if task_sets.empty?
      return 1, "no workflows found"
    else
      return 0, nil
    end
  end

  def add(args)
    options = {}
    params = {}
    tasks = nil
    task_arg_list = nil
    option_types = nil
    option_type_arg_list = nil
    workflow_type = nil # 'provision'
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --tasks taskId:phase,taskId2:phase,taskId3:phase")
      opts.on("--name NAME", String, "Name for workflow") do |val|
        params['name'] = val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on("--description DESCRIPTION", String, "Description of workflow") do |val|
        params['description'] = val
      end
      opts.on("-t", "--type TYPE", "Type of workflow. i.e. provision or operation. Default is provision.") do |val|
        workflow_type = val.to_s.downcase
        if workflow_type.include?('provision')
          workflow_type = 'provision'
        elsif workflow_type.include?('operation')
          workflow_type = 'operation'
        end
        params['type'] = workflow_type
      end
      opts.on("--operational", "--operational", "Create an operational workflow, alias for --type operational.") do |val|
        workflow_type = 'operation'
        params['type'] = workflow_type
      end
      opts.on("--tasks [x,y,z]", Array, "List of tasks to run in order, in the format <Task ID>:<Task Phase> Task Phase is optional. Default is the same workflow type: 'provision' or 'operation'.") do |list|
        task_arg_list = []
        list.each do |it|
          task_id, task_phase = it.split(":")
          task_arg_list << {task_id: task_id.to_s.strip, task_phase: task_phase.to_s.strip}
        end if list
      end
      opts.on("--option-types x,y,z", Array, "List of option type name or IDs. For use with operational workflows to add configuration during execution.") do |list|
        option_type_arg_list = []
        list.each do |it|
          option_type_arg_list << {option_type_id: it.to_s.strip}
        end
      end
      opts.on('--platform [PLATFORM]', String, "Platform, eg. linux, windows or osx") do |val|
        params['platform'] = val.to_s.empty? ? nil : val.to_s.downcase
      end
      opts.on('--allow-custom-config [on|off]', String, "Allow Custom Config") do |val|
        params['allowCustomConfig'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--visibility VISIBILITY', String, "Visibility, eg. private or public") do |val|
        params['visibility'] = val.to_s.downcase
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'taskSet' => passed_options})  unless passed_options.empty?
      else
        params.deep_merge!(passed_options)  unless passed_options.empty?
        if args[0]
          params['name'] = args[0]
        end
        # if params['name'].to_s.empty?
        #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [name]\n#{optparse}"
        #   return 1
        # end
        # if task_arg_list.nil?
        #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --tasks\n#{optparse}"
        #   return 1
        # end
        
        # Name
        if params['name'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name'}], options[:options], @api_client)
          params['name'] = v_prompt['name'] unless v_prompt['name'].to_s.empty?
        end

        # Description
        if params['description'].nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description'}], options[:options], @api_client)
          params['description'] = v_prompt['description'] unless v_prompt['description'].to_s.empty?
        end
        
        # Type
        if workflow_type.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_workflow_types(), 'required' => true, 'description' => 'Workflow Type', 'defaultValue' => workflow_type || 'provision'}], options[:options], @api_client)
          workflow_type = v_prompt['type'] unless v_prompt['type'].to_s.empty?
          params['type'] = workflow_type
        end

        # Tasks
        while tasks.nil? do
          if task_arg_list.nil?
            tasks_val = nil
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tasks', 'fieldLabel' => 'Tasks', 'type' => 'text', 'required' => false, 'description' => "List of tasks to run in order, in the format <Task ID>:<Task Phase> Task Phase is optional. Default is the same workflow type: 'provision' or 'operation'."}], options[:options], @api_client)
            tasks_val = v_prompt['tasks'] unless v_prompt['tasks'].to_s.empty?
            if tasks_val
              task_arg_list = []
              tasks_val.split(",").each do |it|
                task_id, task_phase = it.split(":")
                task_arg_list << {task_id: task_id.to_s.strip, task_phase: task_phase.to_s.strip}
              end
            else
              # empty array is allowed
              tasks = []
            end
          end
          if task_arg_list
            tasks = []
            task_arg_list.each do |task_arg|
              found_task = find_task_by_name_or_id(task_arg[:task_id])
              #return 1 if found_task.nil?
              if found_task.nil?
                task_arg_list = nil
                tasks = nil
                break
              end
              row = {'taskId' => found_task['id']}
              if !task_arg[:task_phase].to_s.strip.empty?
                row['taskPhase'] = task_arg[:task_phase]
              elsif workflow_type == 'operation'
                row['taskPhase'] = 'operation'
              end
              tasks << row
            end
          else
            if options[:no_prompt]
              # empty array is allowed
              tasks = []
            end
          end
        end

        # Option Types
        if workflow_type == 'operation'
          while option_types.nil? do
            if option_type_arg_list.nil?
              option_types_val = nil
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'optionTypes', 'fieldLabel' => 'Option Types', 'type' => 'text', 'description' => "List of option type name or IDs. For use with operational workflows to add configuration during execution."}], options[:options], @api_client)
              option_types_val = v_prompt['optionTypes'] unless v_prompt['optionTypes'].to_s.empty?
              if option_types_val
                option_type_arg_list = []
                option_types_val.split(",").each do |it|
                  option_type_arg_list << {option_type_id: it.to_s.strip}
                end
              else
                option_types = [] # not required, break out
              end
            end
            if option_type_arg_list
              option_types = []
              option_type_arg_list.each do |option_type_arg|
                found_option_type = find_option_type_by_name_or_id(option_type_arg[:option_type_id])
                #return 1 if found_option_type.nil?
                if found_option_type.nil?
                  option_type_arg_list = nil
                  option_types = nil
                  break
                end
                option_types << found_option_type['id']
              end
            end
          end
        end

        payload = {'taskSet' => {}}
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # params['type'] = workflow_type
        payload['taskSet'].deep_merge!(params)
        if tasks
          payload['taskSet']['tasks'] = tasks
        end
        if option_types && option_types.size > 0
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
        print_green_success "Workflow #{workflow['name']} created"
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
          "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
          "Description" => 'description',
          "Type" => lambda {|workflow| format_workflow_type(workflow) },
          "Platform" => lambda {|it| format_platform(it['platform']) },
          "Allow Custom Config" => lambda {|it| format_boolean(it['allowCustomConfig']) },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        print_description_list(description_cols, workflow)

        #task_names = tasks.collect {|it| it['name'] }
        print_h2 "Workflow Tasks"
        if tasks.empty?
          print cyan,"No tasks in this workflow.",reset,"\n"
        else
          print cyan
          # tasks.each_with_index do |taskSetTask, index|
          #   puts "#{(index+1).to_s.rjust(3, ' ')}. #{taskSetTask['task']['name']}"
          # end
          task_set_task_columns = [
            #{"ID" => lambda {|it| it['id'] } }, 
            {"TASK ID" => lambda {|it| it['task']['id'] } },
            {"NAME" => lambda {|it| it['task']['name'] } },
            {"TYPE" => lambda {|it| it['task']['taskType'] ? it['task']['taskType']['name'] : '' } },
            {"PHASE" => lambda {|it| it['taskPhase'] } }, # not returned yet?
          ]
          print cyan
          print as_pretty_table(tasks, task_set_task_columns)
        end

        workflow_option_types = workflow['optionTypes']

        if workflow_option_types && workflow_option_types.size() > 0
          print_h2 "Workflow Option Types"
          columns = [
            {"ID" => lambda {|it| it['id'] } },
            {"NAME" => lambda {|it| it['name'] } },
            {"TYPE" => lambda {|it| it['type'] } },
            {"FIELD NAME" => lambda {|it| it['fieldName'] } },
            {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
            {"DEFAULT" => lambda {|it| it['defaultValue'] } },
            {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
          ]
          print as_pretty_table(workflow_option_types, columns)
        end
        print reset
        print "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    tasks = nil
    task_arg_list = nil
    option_types = nil
    option_type_arg_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --tasks taskId:phase,taskId2:phase,taskId3:phase")
      opts.on("--name NAME", String, "New name for workflow") do |val|
        params['name'] = val
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on("--description DESCRIPTION", String, "Description of workflow") do |val|
        params['description'] = val
      end
      opts.on("--tasks [x,y,z]", Array, "List of tasks to run in order, in the format <Task ID>:<Task Phase> Task Phase is optional. Default is the same workflow type: 'provision' or 'operation'.") do |list|
        task_arg_list = []
        list.each do |it|
          task_id, task_phase = it.split(":")
          task_arg_list << {task_id: task_id.to_s.strip, task_phase: task_phase.to_s.strip}
        end if list
      end
      opts.on("--option-types [x,y,z]", Array, "List of option type name or IDs. For use with operational workflows to add configuration during execution.") do |list|
        option_type_arg_list = []
        list.each do |it|
          option_type_arg_list << {option_type_id: it.to_s.strip}
        end if list
      end
      opts.on('--platform [PLATFORM]', String, "Platform, eg. linux, windows or osx") do |val|
        params['platform'] = val.to_s.empty? ? nil : val.to_s.downcase
      end
      opts.on('--allow-custom-config [on|off]', String, "Allow Custom Config") do |val|
        params['allowCustomConfig'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--visibility VISIBILITY', String, "Visibility, eg. private or public") do |val|
        params['visibility'] = val.to_s.downcase
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
        if task_arg_list
          tasks = []
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
        if option_type_arg_list
          option_types = []
          option_type_arg_list.each do |option_type_arg|
            found_option_type = find_option_type_by_name_or_id(option_type_arg[:option_type_id])
            return 1 if found_option_type.nil?
            option_types << found_option_type['id']
          end
        end
        payload = {'taskSet' => {}}
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        payload['taskSet'].deep_merge!(params)
        if tasks
          payload['taskSet']['tasks'] = tasks
        end
        if option_types
          payload['taskSet']['optionTypes'] = option_types
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
        print_green_success "Workflow #{json_response['taskSet']['name']} updated"
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
        print_green_success "Workflow #{workflow['name']} removed"
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
    instance_label = nil
    server_ids = []
    servers = []
    server_label = nil
    default_refresh_interval = 5
    all_target_types = ['appliance', 'instance', 'instance-label', 'server', 'server-label']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[workflow] [options]")
      opts.on('--context-type VALUE', String, "Context Type, #{ored_list(all_target_types)}") do |val|
        val = val.downcase
        val = 'appliance' if val == 'none'
        if target_type && target_type != val
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        if !all_target_types.include?(val)
          raise ::OptionParser::InvalidOption.new("'#{val}' is invalid. It must be one of the following: instance, instance-label, server, server-label or appliance")
        end
        target_type = val
      end
      opts.on('--target-type VALUE', String, "alias for context-type") do |val|
        val = val.downcase
        val = 'appliance' if val == 'none'
        if target_type && target_type != val
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        if !all_target_types.include?(val)
          raise ::OptionParser::InvalidOption.new("'#{val}' is invalid. It must be one of the following: instance, instance-label, server, server-label or appliance")
        end
        target_type = val
      end
      opts.add_hidden_option('--target-type')
      opts.on('--instance INSTANCE', String, "Instance name or id to target for execution. This option can be passed more than once.") do |val|
        if target_type && target_type != 'instance'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'instance'
        instance_ids << val
      end
      opts.on('--instances LIST', Array, "Instances, comma separated list of instance names or IDs.") do |list|
        if target_type && target_type != 'instance'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'instance'
        instance_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--instance-label LABEL', String, "Instance Label") do |val|
        if target_type && target_type != 'instance-label'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'instance-label'
        instance_label = val
      end
      opts.on('--server SERVER', String, "Server name or id to target for execution. This option can be passed more than once.") do |val|
        if target_type && target_type != 'server'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'server'
        server_ids << val
      end
      opts.on('--servers LIST', Array, "Servers, comma separated list of host names or IDs.") do |list|
        if target_type && target_type != 'server'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.on('--server-label LABEL', String, "Server Label") do |val|
        if target_type && target_type != 'server-label'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'server-label'
        server_label = val
      end
      opts.on('--host HOST', String, "alias for --server") do |val|
        if target_type && target_type != 'server'
          raise ::OptionParser::InvalidOption.new("cannot be combined with another context (#{target_type})")
        end
        target_type = 'server'
        server_ids << val
      end
      opts.add_hidden_option('--host')
      opts.on('--hosts HOSTS', Array, "alias for --servers") do |list|
        if target_type && target_type != 'server'
          raise ::OptionParser::InvalidOption.new("The --hosts option cannot be combined with another context (#{target_type})")
        end
        target_type = 'server'
        server_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      end
      opts.add_hidden_option('--hosts')
      opts.on('-a', '--appliance', "Execute on the appliance, the target is the appliance itself.") do
        if target_type && target_type != 'appliance'
          raise ::OptionParser::InvalidOption.new("The --appliance option cannot be combined with another context (#{target_type})")
        end
        target_type = 'appliance'
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      opts.on(nil, '--no-refresh', "Do not refresh" ) do
        options[:no_refresh] = true
      end
      build_standard_post_options(opts, options)
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    workflow_name = args[0]
    connect(options)
    
      workflow = find_workflow_by_name_or_id(workflow_name)
      return 1 if workflow.nil?

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'job' => passed_options})  unless passed_options.empty?
      else
        # prompt for target type and target
        if target_type.nil?
          # todo: Need api to fetch available Context Types for taskId/workflowId
          available_target_types = get_available_contexts_for_workflow(workflow)
          default_target_type = available_target_types.first ? available_target_types.first['name'] : nil
          if !available_target_types.empty?
            default_target_type = available_target_types.first ? available_target_types.first['name'] : nil
            target_type = Morpheus::Cli::OptionTypes.prompt([{'switch' => 'context-type', 'fieldName' => 'targetType', 'fieldLabel' => 'Context Type', 'type' => 'select', 'selectOptions' => available_target_types, 'defaultValue' => default_target_type, 'required' => true, 'description' => 'Context Type determines the type of target(s) for the execution'}], options[:options], @api_client)['targetType']
          end
        end
        if target_type
          params['targetType'] = target_type
        end
        if target_type == 'instance'
          if instance_ids.empty?
            instance_ids_value = Morpheus::Cli::OptionTypes.prompt([{'switch' => 'instances', 'fieldName' => 'instances', 'fieldLabel' => 'Instance(s)', 'type' => 'text', 'required' => true, 'description' => 'Instances, comma separated list of instance names or IDs.'}], options[:options], @api_client)['instances']
            instance_ids = parse_array(instance_ids_value)
          end
          instance_ids.each do |instance_id|
            instance = find_instance_by_name_or_id(instance_id)
            return 1 if instance.nil?
            instances << instance
          end
          params['instances'] = instances.collect {|it| it['id'] }
        elsif target_type == 'instance-label'
          if instance_label.nil?
            instance_label = Morpheus::Cli::OptionTypes.prompt([{'switch' => 'instance-label', 'fieldName' => 'instanceLabel', 'fieldLabel' => 'Instance Label', 'type' => 'text', 'required' => true, 'description' => 'Instance Label'}], options[:options], @api_client)['instanceLabel']
          end
          # params['config'] ||= {}
          # params['config']['instanceLabel'] = instance_label
          params['instanceLabel'] = instance_label
        elsif target_type == 'server'
          if server_ids.empty?
            server_ids_value = Morpheus::Cli::OptionTypes.prompt([{'switch' => 'servers', 'fieldName' => 'servers', 'fieldLabel' => 'Server(s)', 'type' => 'text', 'required' => true, 'description' => 'Servers, comma separated list of server names or IDs.'}], options[:options], @api_client)['servers']
            server_ids = parse_array(server_ids_value)
          end
          server_ids.each do |server_id|
            server = find_server_by_name_or_id(server_id)
            return 1 if server.nil?
            servers << server
          end
          params['servers'] = servers.collect {|it| it['id'] }
        elsif target_type == 'server-label'
          if server_label.nil?
            server_label = Morpheus::Cli::OptionTypes.prompt([{'switch' => 'server-label', 'fieldName' => 'serverLabel', 'fieldLabel' => 'Server Label', 'type' => 'text', 'required' => true, 'description' => 'Server Label'}], options[:options], @api_client)['serverLabel']
          end
          # params['config'] ||= {}
          # params['config']['serverLabel'] = server_label
          params['serverLabel'] = server_label
        end

        # prompt to workflow optionTypes for customOptions
        custom_options = nil
        if workflow['optionTypes'] && workflow['optionTypes'].size() > 0
          # Clone to avoid mutating workflow data, and clear fieldContext so that
          # accumulated results remain flat (not nested under 'customOptions') when
          # passed as params to dependent option source API calls. If fieldContext
          # were left as 'customOptions', option_params would be sent to the options
          # API as customOptions[zoneId]=2 instead of the expected flat zoneId=2,
          # causing dependent option lists (e.g. Resource Pools) to return empty.
          custom_option_types = workflow['optionTypes'].collect {|it|
            ot = it.clone
            ot.delete('fieldContext')
            ot
          }
          # Support both -O fieldName=value AND the legacy -O customOptions.fieldName=value syntax.
          prompt_options = (options[:options] || {}).dup
          if prompt_options['customOptions'].is_a?(Hash)
            prompt_options.merge!(prompt_options.delete('customOptions'))
          end
          prompt_results = Morpheus::Cli::OptionTypes.prompt(custom_option_types, prompt_options, @api_client, {})
          custom_options = {'customOptions' => prompt_results} unless prompt_results.empty?
        end
        job_payload = {}
        job_payload.deep_merge!(params)
        passed_options.delete('customOptions')
        job_payload.deep_merge!(passed_options) unless passed_options.empty?
        if custom_options
          # job_payload.deep_merge!('config' => custom_options)
          job_payload.deep_merge!(custom_options)
        end
        payload = {'job' => job_payload}
      end

      @task_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @task_sets_interface.dry.run(workflow['id'], payload)
        return 0
      end
      json_response = @task_sets_interface.run(workflow['id'], payload)

      render_response(json_response, options) do
        target_desc = nil
        if instances.size() > 0
          target_desc = (instances.size() == 1) ? "instance #{instances[0]['name']}" : "#{instances.size()} instances"
        elsif servers.size() > 0
          target_desc = (servers.size() == 1) ? "host #{servers[0]['name']}" : "#{servers.size()} hosts"
        end
        if target_desc
          print_green_success "Executing workflow #{workflow['name']} on #{target_desc}"
        else
          print_green_success "Executing workflow #{workflow['name']}"
        end
        if json_response["jobExecution"] && json_response["jobExecution"]["id"]
          job_execution_id = json_response["jobExecution"]["id"]
          if options[:no_refresh]
            get_args = [json_response["jobExecution"]["id"], "--details"] + (options[:remote] ? ["-r",options[:remote]] : [])
            Morpheus::Logging::DarkPrinter.puts((['jobs', 'get-execution'] + get_args).join(' ')) if Morpheus::Logging.debug?
            ::Morpheus::Cli::JobsCommand.new.handle(['get-execution'] + get_args)
          else
            #Morpheus::Cli::JobsCommand.new.handle(["get-execution", job_execution_id, "--refresh", options[:refresh_interval].to_s]+ (options[:remote] ? ["-r",options[:remote]] : []))
            job_execution_results = wait_for_job_execution(job_execution_id, options.merge({:details => true}))
          end
        end
      end
      return 0, nil
  end

  private

  def get_available_workflow_types
    [{"name" => "Provisioning", "value" => "provision", "isDefault" => true}, {"name" => "Operational", "value" => "operation"}]
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
        return nil
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
        return nil
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
      {"LABELS" => lambda {|it| format_list(it['labels'], '', 3) rescue '' }},
      {"DESCRIPTION" => lambda {|workflow| workflow['description'] } },
      {"TYPE" => lambda {|workflow| format_workflow_type(workflow) } },
      {"TASKS" => lambda {|workflow| 
        # (workflow['taskSetTasks'] || []).sort { |x,y| x['taskOrder'].to_i <=> y['taskOrder'].to_i }.collect { |taskSetTask|
        #   taskSetTask['task']['name']
        # }.join(', ')
        (workflow['taskSetTasks'] || []).size.to_s
       } },
      {"CREATED" => lambda {|workflow| format_local_dt(workflow['dateCreated']) } },
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

  def format_platform(platform)
    if platform.nil?
      "All"
    elsif platform == 'osx'
      "OSX"
    else
      platform.to_s.capitalize
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
        return nil
      else
        raise e
      end
    end
  end

  def find_option_type_by_name(name)
    json_results = @option_types_interface.list({name: name.to_s})
    if json_results['optionTypes'].empty?
      print_red_alert "Option Type not found by name #{name}"
      return nil
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
        return nil
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
        return nil
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
