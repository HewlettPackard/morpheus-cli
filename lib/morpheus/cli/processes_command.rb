require 'morpheus/cli/cli_command'

class Morpheus::Cli::Processes
  include Morpheus::Cli::CliCommand

  set_command_name :'process'

  register_subcommands :list, :get, {:'get-event' => :event_details}

  # alias_subcommand :details, :get
  # set_default_subcommand :list
  
  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @processes_interface = @api_client.processes
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on('--instance ID', String, "Limit results to specific instance(s).") do |val|
        params['instanceIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--container ID', String, "Limit results to specific container(s).") do |val|
        params['containerIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--host ID', String, "Limit results to specific host(s).") do |val|
        params['serverIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--cloud ID', String, "Limit results to specific cloud(s).") do |val|
        params['zoneIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes."
    end
    optparse.parse!(args)

    if args.count != 0
      puts optparse
      return 1
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      # params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      if options[:dry_run]
        print_dry_run @processes_interface.dry.list(params)
        return
      end
      json_response = @processes_interface.list(params)
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

        title = "Process List"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if json_response['processes'].empty?
          print "#{cyan}No processes found.#{reset}\n\n"
          return 0
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
              error: format_process_error(process),
              output: format_process_output(process)
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
                    error: format_process_error(process_event),
                    output: format_process_output(process_event)
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
          if options[:show_events]
            print_results_pagination({size: history_records.size, total: history_records.size}, {:label => "process", :n_label => "processes"})
          else
            print_results_pagination(json_response, {:label => "process", :n_label => "processes"})
          end
          print reset, "\n"
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
    params = {}
    process_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details for a specific process.\n"
                    "[id] is required. This is the id of the process."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      process_id = args[0]
      params.merge!(parse_list_options(options))
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      if options[:dry_run]
        print_dry_run @processes_interface.dry.get(process_id, params)
        return
      end
      json_response = @processes_interface.get(process_id, params)
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
        title = "Process Details"
        subtitles = []
        subtitles << " Process ID: #{process_id}"
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        print_process_details(process)
  
        print_h2 "Process Events"
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

  def event_details(args)
    options = {}
    params = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[event-id]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details for a specific process event.\n" +
                    "[event-id] is required. This is the id of the process event."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      process_event_id = args[0]
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @processes_interface.dry.get_event(process_event_id, params)
        return
      end
      json_response = @processes_interface.get_event(process_event_id, params)
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
        title = "Process Event Details"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        print_process_event_details(process_event)
        print reset, "\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
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
      print_h2 "Error"
      print reset
      #puts format_process_error(process_event)
      puts process['error'].to_s.strip
    end

    if process['output']
      print_h2 "Output"
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
      print_h2 "Error"
      print reset
      #puts format_process_error(process_event)
      puts process_event['error'].to_s.strip
    end

    if process_event['output']
      print_h2 "Output"
      print reset
      #puts format_process_error(process_event)
      puts process_event['output'].to_s.strip
    end
  end
  

  def format_process_status(process, return_color=cyan)
    out = ""
    status_string = process['status'].to_s
    if status_string == 'complete'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'expired'
      out << "#{red}#{status_string.upcase}#{return_color}"
    else
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    end
    out
  end

  # decolorize, remove newlines and truncate for table cell
  def format_process_error(process, max_length=50, return_color=cyan)
    out = ""
    if process['error']
      lines = process['error'].split("\n").collect {|line| reset + "#{line.to_s.strip}" }
      out = lines.join(" ")
      if max_length
        out = truncate_string(out, max_length)
      end
      out << return_color if return_color
    end
    out
  end

  # decolorize, remove newlines and truncate for table cell
  def format_process_output(process, max_length=50, return_color=cyan)
    out = ""
    if process['output']
      lines = process['output'].split("\n").collect {|line| reset + "#{line.to_s.strip}" }
      out = lines.join(" ")
      if max_length
        out = truncate_string(out, max_length)
      end
      out << return_color if return_color
    end
    out
  end

  # format for either ETA/Duration
  def format_process_duration(process, time_format="%H:%M:%S")
    out = ""
    if process['duration'] && process['duration'] > 0
      out = format_duration_milliseconds(process['duration'], time_format)
    elsif process['statusEta'] && process['statusEta'] > 0
      out = format_duration_milliseconds(process['statusEta'], time_format)
    elsif process['startDate'] && process['endDate']
      out = format_duration(process['startDate'], process['endDate'], time_format)
    else
      ""
    end
    out
  end
    

end
