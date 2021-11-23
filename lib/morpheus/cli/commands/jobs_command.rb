require 'morpheus/cli/cli_command'

class Morpheus::Cli::JobsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'jobs'

  register_subcommands :list, :get, :add, :update, :execute, :remove
  register_subcommands :list_executions, :get_execution, :get_execution_event
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @jobs_interface = @api_client.jobs
    @options_interface = @api_client.options
    @tasks_interface = @api_client.tasks
    @task_sets_interface = @api_client.task_sets
    @instances_interface = @api_client.instances
    @servers_interface = @api_client.servers
    @containers_interface = @api_client.containers
    @execute_schedules_interface = @api_client.execute_schedules
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    options[:show_stats] = true
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("--source [all|user|discovered]", String, "Filters job based upon specified source. Default is all") do |val|
        options[:source] = val.to_s
      end
      opts.on("--internal [true|false]", String, "Filters job based on internal flag. Internal jobs are excluded by default.") do |val|
        params["internalOnly"] = (val.to_s != "false")
      end
      opts.on("--stats [true|false]", String, "Hide Execution Stats. Job statistics are displayed by default.") do |val|
        options[:show_stats] = (val.to_s != "false")
      end
      build_standard_list_options(opts, options)
      opts.footer = "List jobs."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end


    params.merge!(parse_list_options(options))

    if !options[:source].nil?
      if !['all', 'user', 'discovered', 'sync'].include?(options[:source])
        print_red_alert "Invalid source filter #{options[:source]}"
        exit 1
      end
      params['itemSource'] = options[:source] == 'discovered' ? 'sync' : options[:source]
    end

    @jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @jobs_interface.dry.list(params)
      return
    end
    json_response = @jobs_interface.list(params)
    jobs = json_response['jobs']
    render_response(json_response, options, 'jobs') do
      title = "Morpheus Jobs"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if params["internalOnly"]
        subtitles << "internalOnly: #{params['internalOnly']}"
      end
      print_h1 title, subtitles, options
      if jobs.empty?
        print cyan,"No jobs found.",reset,"\n"
      else
        columns = {
          "ID" => 'id',
          "Type" => lambda {|job| job['type'] ? job['type']['name'] : '' },
          "Name" => 'name',
          "Details" => lambda {|job| job['jobSummary'] },
          "Enabled" => lambda {|job| "#{job['enabled'] ? '' : yellow}#{format_boolean(job['enabled'])}#{cyan}" },
          # "Date Created" => lambda {|job| format_local_dt(job['dateCreated']) },
          # "Last Updated" => lambda {|job| format_local_dt(job['lastUpdated']) },
          "Last Run" => lambda {|job| format_local_dt(job['lastRun']) },
          "Next Run" =>  lambda {|job| job['enabled'] && job['scheduleMode'] && job['scheduleMode'] != 'manual' ? format_local_dt(job['nextFire']) : '' },
          "Last Result" =>  lambda {|job| format_status(job['lastResult']) },
        }
        print as_pretty_table(jobs, columns.upcase_keys!, options)
        print_results_pagination(json_response)
        if options[:show_stats]
          if stats = json_response['stats']
            label_width = 17

            print_h2 "Execution Stats - Last 7 Days"
            print cyan

            print "Jobs".rjust(label_width, ' ') + ": #{stats['jobCount']}\n"
            print "Executions Today".rjust(label_width, ' ') + ": #{stats['todayCount']}\n"
            print "Daily Executions".rjust(label_width, ' ') + ": " + stats['executionsPerDay'].join(' | ') + "\n"
            print "Total Executions".rjust(label_width, ' ') + ": #{stats['execCount']}\n"
            print "Completed".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['execSuccessRate'].to_f, 100, {bar_color:green}) + "#{stats['execSuccess']}".rjust(15, ' ') + " of " + "#{stats['execCount']}".ljust(15, ' ') + "\n#{cyan}"
            print "Failed".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['execFailedRate'].to_f, 100, {bar_color:red}) + "#{stats['execFailed']}".rjust(15, ' ') + " of " + "#{stats['execCount']}".ljust(15, ' ') + "\n#{cyan}"
          end
          print reset,"\n"
        end
      end
      print reset,"\n"
    end
    if jobs.empty?
      return 1, "no jobs found"
    else
      return 0, nil
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[job] [max-exec-count]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[job] is required. Job ID or name.\n" +
          "[max-exec-count] is optional. Specified max # of most recent executions. Defaults is 3"
    end
    optparse.parse!(args)
    if args.count < 1
      raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], args.count > 1 ? args[1].to_i : nil, options)
  end

  def _get(job_id, max_execs = 3, options = {})
    begin
      @jobs_interface.setopts(options)

      if !(job_id.to_s =~ /\A\d{1,}\Z/)
        job = find_by_name_or_id('job', job_id)

        if !job
          print_red_alert "Job #{job_id} not found"
          exit 1
        end
        job_id = job['id']
      end

      max_execs = 3 if max_execs.nil?

      params = {'includeExecCount' => max_execs}

      if options[:dry_run]
        print_dry_run @jobs_interface.dry.get(job_id, params)
        return
      end
      json_response = @jobs_interface.get(job_id, params)

      render_result = render_with_format(json_response, options, 'job')
      return 0 if render_result

      title = "Morpheus Job"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      job = json_response['job']
      schedule_name = ''
      if !job['scheduleMode'].nil?
        if job['scheduleMode'] == 'manual'
          schedule_name = 'Manual'
        elsif job['scheduleMode'].to_s.downcase == 'datetime'
          schedule_name = ("Date and Time - " + (format_local_dt(job['dateTime']).to_s rescue 'n/a'))
        elsif job['scheduleMode'].to_s == ''
          schedule_name = 'n/a' # should not happen
        else
          begin
            schedule = @execute_schedules_interface.get(job['scheduleMode'])['schedule']
            schedule_name = schedule ? schedule['name'] : ''
          rescue => ex
            Morpheus::Logging::DarkPrinter.puts "Failed to load schedule name" if Morpheus::Logging.debug?
            schedule_name = 'n/a'
          end
        end
      end

      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name']},
          "Job Type" => lambda {|it| it['type']['name']},
          "Enabled" => lambda {|it| format_boolean(it['enabled'])},
          (job['workflow'] ? 'Workflow' : 'Task') => lambda {|it| it['jobSummary']},
          "Schedule" => lambda {|it| schedule_name}
      }

      if job['targetType']
        description_cols["Context Type"] = lambda {|it| it['targetType'] == 'appliance' ? 'None' : it['targetType'] }

        if job['targetType'] != 'appliance'
          description_cols["Context #{job['targetType'].capitalize}#{job['targets'].count > 1 ? 's' : ''}"] = lambda {|it| it['targets'].collect {|it| it['name']}.join(', ')}
        end
      end

      print_description_list(description_cols, job)

      if max_execs != 0
        print_h2 "Recent Executions"
        print_job_executions(json_response['executions']['jobExecutions'], options)

        if json_response['executions']['meta'] && json_response['executions']['meta']['total'] > max_execs
          print_results_pagination(json_response['executions'])
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name]")
      opts.on("--name NAME", String, "Updates job name") do |val|
        params['name'] = val.to_s
      end
      opts.on('-a', '--active [on|off]', String, "Can be used to enable / disable the job. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--task [TASK]', String, "Task ID or code, assigns task to job. Incompatible with --workflow option.") do |val|
        if options[:workflow].nil?
          options[:task] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('-w', '--workflow [WORKFLOW]', String, "Workflow ID or code, assigns workflow to job. Incompatible with --task option.") do |val|
        if options[:task].nil?
          options[:workflow] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('--context-type [TYPE]', String, "Context type (instance|server|none). Default is none") do |val|
        params['targetType'] = (val == 'none' ? 'appliance' : val)
      end
      opts.on('--instances [LIST]', Array, "Context instances(s), comma separated list of instance IDs. Incompatible with --servers") do |list|
        params['targetType'] = 'instance'
        params['targets'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--servers [LIST]', Array, "Context server(s), comma separated list of server IDs. Incompatible with --instances") do |list|
        params['targetType'] = 'server'
        params['targets'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('-S', '--schedule [SCHEDULE]', String, "Job execution schedule type name or ID") do |val|
        options[:schedule] = val
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      opts.on('-R', '--run [on|off]', String, "Can be used to run the job now.") do |val|
        params['run'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--date-time DATETIME', String, "Can be used to run schedule at a specific date and time. Use UTC time in the format 2020-02-15T05:00:00Z. This sets scheduleMode to 'dateTime'.") do |val|
        options[:schedule] = 'dateTime'
        params['dateTime'] = val.to_s
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create job."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0 or 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      if options[:payload]
        payload = parse_payload(options, 'job')
      else
        apply_options(params, options)

        # name
        params['name'] = params['name'] || args[0] || name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Job Name', 'required' => true, 'description' => 'Job Name.'}],options[:options],@api_client,{})['name']

        if options[:task].nil? && options[:workflow].nil?
          # prompt job type
          job_types = @options_interface.options_for_source('jobTypes', {})['data']
          job_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'jobType', 'type' => 'select', 'fieldLabel' => 'Job Type', 'selectOptions' => job_types, 'required' => true, 'description' => 'Select Job Type.'}],options[:options],@api_client,{})['jobType']
          job_type = job_types.find {|it| it['value'] == job_type_id}

          job_options = @jobs_interface.options(job_type_id)

          # prompt task / workflow
          if ['morpheus.task.jobType', 'morpheus.task'].include?(job_type['code'])
            params['task'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'task.id', 'fieldLabel' => 'Task', 'type' => 'select', 'required' => true, 'optionSource' => 'tasks'}], options[:options], @api_client, {})['task']
          else
            params['workflow'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'workflow.id', 'fieldLabel' => 'Workflow', 'type' => 'select', 'required' => true, 'optionSource' => 'operationTaskSets'}], options[:options], @api_client, {})['workflow']
          end
        end

        # task
        if !options[:task].nil?
          task = find_by_name_or_id('task', options[:task])

          if task.nil?
            print_red_alert "Task #{options[:task]} not found"
            exit 1
          end
          params['task'] = {'id' => task['id']}
          job_type_id = load_job_type_id_by_code('morpheus.task.jobType') || load_job_type_id_by_code('morpheus.task')
        end

        # workflow
        task_set = nil
        if !options[:workflow].nil?
          task_set = find_by_name_or_id('task_set', options[:workflow])

          if task_set.nil?
            print_red_alert "Workflow #{options[:workflow]} not found"
            exit 1
          end
          params['workflow'] = {'id' => task_set['id']}
          job_type_id = load_job_type_id_by_code('morpheus.workflow.jobType') || load_job_type_id_by_code('morpheus.workflow')
        end
        # load workflow if we havent yet
        if (params['workflow'] && params['workflow']['id']) && task_set.nil?
          task_set = find_by_name_or_id('task_set', params['workflow']['id'])
          if task_set.nil?
            print_red_alert "Workflow #{params['workflow']['id']} not found"
            exit 1
          end
        end
        # prompt for custom options for workflow
        custom_option_types = task_set ? task_set['optionTypes'] : nil
        if custom_option_types && custom_option_types.size() > 0
          # they are all returned in a single array right now, so skip prompting for the jobType optionTypes
          custom_option_types.reject! { |it| it['code'] && it['code'].include?('job.type') }
          custom_option_types = custom_option_types.collect {|it|
            it['fieldContext'] = 'customOptions'
            it
          }
          custom_options = Morpheus::Cli::OptionTypes.prompt(custom_option_types, options[:options], @api_client, {})
          params['customOptions'] = custom_options['customOptions']
        end


        # load options based upon job type + task / taskset
        job_options = @jobs_interface.options(job_type_id, {'taskId' => params['task'] ? params['task']['id'] : nil, 'workflowId' => params['workflow'] ? params['workflow']['id'] : nil})
        option_type_id = job_options['optionTypes'][0]['id']

        # context type
        if params['targetType'].nil?
          params['targetType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetType', 'fieldLabel' => 'Context Type', 'type' => 'select', 'required' => true, 'selectOptions' => job_options['targetTypes'], 'defaultValue' => job_options['targetTypes'].first['name']}], options[:options], @api_client, {})['targetType']
        end

        # contexts
        if ['instance', 'server'].include?(params['targetType']) && (params['targets'].nil? || params['targets'].empty?)
          targets = []
          if params['targetType'] == 'instance'
            avail_targets = @instances_interface.list({max:10000})['instances'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          else
            avail_targets = @servers_interface.list({max:10000, 'vmHypervisor' => nil, 'containerHypervisor' => nil})['servers'].collect {|it| {'name' => it['name'], 'value' => it['id']}}
          end
          target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'target', 'fieldLabel' => "Context #{params['targetType'].capitalize}", 'type' => 'select', 'required' => true, 'selectOptions' => avail_targets}], options[:options], @api_client, {}, options[:no_prompt], true)['target']
          targets << target_id
          avail_targets.reject! {|it| it['value'] == target_id}

          while !target_id.nil? && !avail_targets.empty? && Morpheus::Cli::OptionTypes.confirm("Add another context #{params['targetType']}?", {:default => false})
            target_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'target', 'fieldLabel' => "Context #{params['targetType'].capitalize}", 'type' => 'select', 'required' => false, 'selectOptions' => avail_targets}], options[:options], @api_client, {}, options[:no_prompt], true)['target']

            if !target_id.nil?
              targets << target_id
              avail_targets.reject! {|it| it['value'] == target_id}
            end
          end
          params['targets'] = targets.collect {|it| {'refId' => it}}
        end

        # schedule
        if options[:schedule].nil?
          options[:schedule] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scheduleMode', 'fieldLabel' => "Schedule", 'type' => 'select', 'required' => true, 'selectOptions' => job_options['schedules'], 'defaultValue' => job_options['schedules'].first['name']}], options[:options], @api_client, {})['scheduleMode']
          params['scheduleMode'] = options[:schedule]
        end

        if options[:schedule] == 'manual'
          # cool
        elsif options[:schedule].to_s.downcase == 'datetime'
          # prompt for dateTime
          if params['dateTime'].nil?
            params['dateTime'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dateTime', 'fieldLabel' => "Date and Time", 'type' => 'text', 'required' => true}], options[:options], @api_client, {}, options[:no_prompt], true)['dateTime']
          end
        elsif options[:schedule].to_s != ''
           # ok they passed a schedule name or id
          schedule = job_options['schedules'].find {|it| it['name'] == options[:schedule] || it['value'] == options[:schedule].to_i}

          if schedule.nil?
            print_red_alert "Schedule #{options[:schedule]} not found"
            exit 1
          end
          options[:schedule] = schedule['value']
        end
        params['scheduleMode'] = options[:schedule]

        # custom config
        if params['customConfig'].nil? && job_options['allowCustomConfig']
          params['customConfig'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'config', 'fieldLabel' => "Custom Config", 'type' => 'text', 'required' => false}], options[:options], @api_client, {})['config']
        end
        payload = {'job' => params}
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.create(payload)
        return
      end
      json_response = @jobs_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job created"
          _get(json_response['id'], 0, options)
        else
          print_red_alert "Error creating job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      opts.on("--name NAME", String, "Updates job name") do |val|
        params['name'] = val.to_s
      end
      opts.on('-a', '--active [on|off]', String, "Can be used to enable / disable the job. Default is on") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('-t', '--task [TASK]', String, "Task ID or code, assigns task to job. Incompatible with --workflow option.") do |val|
        if options[:workflow].nil?
          options[:task] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('-w', '--workflow [WORKFLOW]', String, "Workflow ID or code, assigns workflow to job. Incompatible with --task option.") do |val|
        if options[:task].nil?
          options[:workflow] = val
        else
          raise_command_error "Options --task and --workflow are incompatible"
        end
      end
      opts.on('--context-type [TYPE]', String, "Context type (instance|server|none). Default is none") do |val|
        params['targetType'] = (val == 'none' ? 'appliance' : val)
      end
      opts.on('--instances [LIST]', Array, "Context instances(s), comma separated list of instance IDs. Incompatible with --servers") do |list|
        params['targetType'] = 'instance'
        options[:targets] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip.to_i }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--servers [LIST]', Array, "Context server(s), comma separated list of server IDs. Incompatible with --instances") do |list|
        params['targetType'] = 'server'
        options[:targets] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip.to_i }.compact.uniq.collect {|it| {'refId' => it.to_i}}
      end
      opts.on('--schedule [SCHEDULE]', String, "Job execution schedule type name or ID") do |val|
        options[:schedule] = val
      end
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      opts.on('-R', '--run [on|off]', String, "Can be used to run the job now.") do |val|
        params['run'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--date-time DATETIME', String, "Can be used to run schedule at a specific date and time. Use UTC time in the format 2020-02-15T05:00:00Z. This sets scheduleMode to 'dateTime'.") do |val|
        options[:schedule] = 'dateTime'
        params['dateTime'] = val.to_s
      end
      build_common_options(opts, options, [:options, :payload, :list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Update job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      if options[:payload]
        payload = parse_payload(options, 'job')
      else
        apply_options(params, options)

        job_type_id = job['type']['id']

        if !options[:task].nil?
          task = find_by_name_or_id('task', options[:task])

          if task.nil?
            print_red_alert "Task #{options[:task]} not found"
            exit 1
          end
          params['task'] = {'id': task['id']}
          job_type_id = load_job_type_id_by_code('morpheus.task')
        end

        if !options[:workflow].nil?
          task_set = find_by_name_or_id('task_set', options[:workflow])

          if task_set.nil?
            print_red_alert "Workflow #{options[:workflow]} not found"
            exit 1
          end
          params['workflow'] = {'id': task_set['id']}
          job_type_id = load_job_type_id_by_code('morpheus.workflow')
        end

        if !options[:targets].nil? && ['instance', 'server'].include?(params['targetType'])
          params['targets'] = []
          target_type = params['targetType'] || job['targetType']
          options[:targets].collect do |it|
            target = find_by_name_or_id(target_type, it['refId'])

            if target.nil?
              print_red_alert "Context #{target_type} #{it['refId']} not found"
              exit 1
            end
            params['targets'] << it
          end
        end

        if !options[:schedule].nil?
          if options[:schedule] != 'manual' && options[:schedule].to_s.downcase != 'datetime'
            job_options = @jobs_interface.options(job_type_id)
            schedule = job_options['schedules'].find {|it| it['name'] == options[:schedule] || it['value'] == options[:schedule].to_i}

            if schedule.nil?
              print_red_alert "Schedule #{options[:schedule]} not found"
              exit 1
            end
            options[:schedule] = schedule['value']
          end
          params['scheduleMode'] = options[:schedule]
        end


        # schedule
        if !options[:schedule].nil?
          

          if options[:schedule] == 'manual'
            # cool
          elsif options[:schedule].to_s.downcase == 'datetime'
            # prompt for dateTime
            if params['dateTime'].nil?
              raise_command_error "--date-time is required for schedule '#{options[:schedule]}'\n#{optparse}"
            end
          elsif options[:schedule].to_s != ''
            job_options = @jobs_interface.options(job_type_id)
            options[:schedule] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'schedule', 'fieldLabel' => "Schedule", 'type' => 'select', 'required' => true, 'selectOptions' => job_options['schedules'], 'defaultValue' => job_options['schedules'].first['name']}], options[:options], @api_client, {})['schedule']
            params['scheduleMode'] = options[:schedule]
             # ok they passed a schedule name or id
            schedule = job_options['schedules'].find {|it| it['name'] == options[:schedule] || it['value'] == options[:schedule].to_i}

            if schedule.nil?
              print_red_alert "Schedule #{options[:schedule]} not found"
              exit 1
            end
            options[:schedule] = schedule['value']
          end
        end

        payload = {'job' => params}
      end

      if payload['job'].nil? || payload['job'].empty?
        print_green_success "Nothing to update"
        exit 1
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.update(job['id'], payload)
        return
      end
      json_response = @jobs_interface.update(job['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job updated"
          _get(job['id'], nil, options)
        else
          print_red_alert "Error updating job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execute(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      opts.on('--config [TEXT]', String, "Custom config") do |val|
        params['customConfig'] = val.to_s
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Run job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.execute_job(job['id'], params)
        return
      end

      json_response = @jobs_interface.execute_job(job['id'], params)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Job queued for execution"
          _get(job['id'], nil, options)
        else
          print_red_alert "Error executing job: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[job]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Remove job.\n" +
          "[job] is required. Job ID or name"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      job = find_by_name_or_id('job', args[0])

      if job.nil?
        print_red_alert "Job #{args[0]} not found"
        exit 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the job '#{job['name']}'?", options)
        return 9, "aborted command"
      end

      @jobs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @jobs_interface.dry.destroy(job['id'], params)
        return
      end

      json_response = @jobs_interface.destroy(job['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Job #{job['name']} removed"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_executions(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[job]")
      opts.on('--job JOB', String, "Filter by Job ID or name.") do |val|
        options[:job] = val
      end
      opts.on("--internal [true|false]", String, "Filters executions based on internal flag. Internal executions are excluded by default.") do |val|
        params["internalOnly"] = (val.to_s != "false")
      end
      build_standard_list_options(opts, options)
      opts.footer = "List job executions.\n" +
          "[job] is optional. Job ID or name to filter executions."

    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, max:1)
    if args.count > 0
      options[:job] = args.join(" ")
    end

    params.merge!(parse_list_options(options))

    if options[:job]
      job = find_by_name_or_id('job', options[:job])
      if job.nil?
        raise_command_error "Job #{options[:job]} not found"
      end
      params['jobId'] = job['id']
    end

    @jobs_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @jobs_interface.dry.list_executions(params)
      return
    end
    json_response = @jobs_interface.list_executions(params)
    job_executions = json_response['jobExecutions']
    render_response(json_response, options, 'jobExecutions') do
      title = "Morpheus Job Executions"
      subtitles = job ? ["Job: #{job['name']}"] : []
      subtitles += parse_list_subtitles(options)
      if params["internalOnly"]
        subtitles << "internalOnly: #{params['internalOnly']}"
      end
      print_h1 title, subtitles, options
      print_job_executions(job_executions, options)
      print_results_pagination(json_response)
      print reset,"\n"
    end
    if job_executions.empty?
      return 3, "no executions found"
    else
      return 0, nil
    end
  end

  def get_execution(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('-D', '--details [on|off]', String, "Can be used to enable / disable execution details. Default is on") do |val|
        options[:details] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[id] is required. Job execution ID."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      @jobs_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @jobs_interface.dry.get_execution(args[0], params)
        return
      end
      json_response = @jobs_interface.get_execution(args[0], params)

      render_result = render_with_format(json_response, options, 'jobExecution')
      return 0 if render_result

      title = "Morpheus Job Execution"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      exec = json_response['jobExecution']
      process = exec['process']
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id'] },
          "Job" => lambda {|it| it['job'] ? it['job']['name'] : ''},
          "Job Type" => lambda {|it| it['job'] && it['job']['type'] ? (it['job']['type']['code'] == 'morpheus.workflow' ? 'Workflow' : 'Task') : ''},
          # "Description" => lambda {|it| it['description'] || (it['job'] ? it['job']['description'] : '') },
          "Start Date" => lambda {|it| format_local_dt(it['startDate'])},
          "ETA/Time" => lambda {|it| it['duration'] ? format_human_duration(it['duration'] / 1000.0) : ''},
          "Status" => lambda {|it| format_status(it['status'])},
          "Error" => lambda {|it| it['process'] && (it['process']['message'] || it['process']['error']) ? red + (it['process']['message'] || it['process']['error']) + cyan : ''},
          "Created By" => lambda {|it| it['createdBy'].nil? ? '' : it['createdBy']['displayName'] || it['createdBy']['username']}
      }
      description_cols["Process ID"] = lambda {|it| process['id']} if !process.nil?

      print_description_list(description_cols, exec)

      if !process.nil?
        if options[:details]
        process_data = get_process_event_data(process)
          print_h2 "Execution Details"
          description_cols = {
              "Process ID" => lambda {|it| it[:id]},
              "Description" => lambda {|it| it[:description]},
              "Start Date" => lambda {|it| it[:start_date]},
              "Created By" => lambda {|it| it[:created_by]},
              "Duration" => lambda {|it| it[:duration]},
              "Status" => lambda {|it| it[:status]}
          }
          if !options[:details]
            description_cols["Output"] = lambda {|it| it[:output]} if process_data[:output] && process_data[:output].strip.length > 0
            description_cols["Error"] = lambda {|it| it[:error]} if process_data[:error] && process_data[:error].strip.length > 0
          end

          print_description_list(description_cols, process_data)

          if process_data[:output] && process_data[:output].strip.length > 0
            print_h2 "Output"
            print process['output']
          end
          if process_data[:error] && process_data[:error].strip.length > 0
            print_h2 "Error"
            print process['message'] || process['error']
            print reset,"\n"
          end
        end

        if process['events'] && !process['events'].empty?
          print_h2 "Execution Events"
          print_process_events(process['events'])
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_execution_event(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [event]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a job.\n" +
          "[id] is required. Job execution ID.\n" +
          "[event] is required. Process event ID."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      @jobs_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @jobs_interface.dry.get_execution_event(args[0].to_i, args[1].to_i, params)
        return
      end
      json_response = @jobs_interface.get_execution_event(args[0].to_i, args[1].to_i, params)

      render_result = render_with_format(json_response, options, 'processEvent')
      return 0 if render_result

      title = "Morpheus Job Execution Event"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      event = json_response['processEvent']
      event_data = get_process_event_data(event)
      description_cols = {
          "ID" => lambda {|it| it[:id]},
          "Description" => lambda {|it| it[:description]},
          "Start Date" => lambda {|it| it[:start_date]},
          "Created By" => lambda {|it| it[:created_by]},
          "Duration" => lambda {|it| it[:duration]},
          "Status" => lambda {|it| it[:status]}
      }

      print_description_list(description_cols, event_data)

      if event_data[:output] && event_data[:output].strip.length > 0
        print_h2 "Output"
        print event['output']
      end
      if event_data[:error] && event_data[:error].strip.length > 0
        print_h2 "Error"
        print event['message'] || event['error']
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def get_process_event_data(process_or_event)
    {
        id: process_or_event['id'],
        description: process_or_event['description'] || (process_or_event['refType'] == 'instance' ? process_or_event['displayName'] : (process_or_event['processTypeName'] || '').capitalize),
        start_date: format_local_dt(process_or_event['startDate']),
        created_by: process_or_event['createdBy'] ? process_or_event['createdBy']['displayName'] : '',
        duration: format_human_duration((process_or_event['duration'] || process_or_event['statusEta'] || 0) / 1000.0),
        status: format_status(process_or_event['status']),
        error: truncate_string(process_or_event['message'] || process_or_event['error'], 32),
        output: truncate_string(process_or_event['output'], 32)
    }
  end

  # both process and process events
  def print_process_events(events, options={})
    print as_pretty_table(events.collect {|it| get_process_event_data(it)}, [:id, :description, :start_date, :created_by, :duration, :status, :error], options)
    print reset,"\n"
  end

  def print_job_executions(execs, options={})
    if execs.empty?
      print cyan,"No job executions found.",reset,"\n"
    else
      rows = execs.collect do |ex|
        {
            id: ex['id'],
            job: ex['job'] ? ex['job']['name'] : '',
            description: ex['description'] || ex['job'] ? ex['job']['description'] : '',
            type: ex['job'] && ex['job']['type'] ? (ex['job']['type']['code'] == 'morpheus.workflow' ? 'Workflow' : 'Task') : '',
            start: format_local_dt(ex['startDate']),
            duration: ex['duration'] ? format_human_duration(ex['duration'] / 1000.0) : '',
            status: format_status(ex['status']),
            error: truncate_string(ex['process'] && (ex['process']['message'] || ex['process']['error']) ? ex['process']['message'] || ex['process']['error'] : '', 32)
        }
      end

      columns = [
          :id, :job, :type, {'START DATE' => :start}, {'ETA/TIME' => :duration}, :status, :error
      ]
      print as_pretty_table(rows, columns, options)
      print reset,"\n"
    end
  end

  def format_status(status_string, return_color=cyan)
    out = ""
    if status_string
      if ['complete','success', 'successful', 'ok'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['error', 'offline', 'failed', 'failure'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{yellow}#{status_string.upcase}"
      end
    end
    out + return_color
  end

  def find_by_name_or_id(type, val)
    interface = instance_variable_get "@#{type}s_interface"
    typeCamelCase = type.gsub(/(?:^|_)([a-z])/) do $1.upcase end
    typeCamelCase = typeCamelCase[0, 1].downcase + typeCamelCase[1..-1]
    (val.to_s =~ /\A\d{1,}\Z/) ? interface.get(val.to_i)[typeCamelCase] : interface.list({'name' => val})["#{typeCamelCase}s"].first
  end

  def load_job_type_id_by_code(code)
    @options_interface.options_for_source('jobTypes', {})['data'].find {|it| it['code'] == code}['value'] rescue nil
  end
end
