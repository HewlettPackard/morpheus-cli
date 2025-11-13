require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for viewing process history
module Morpheus::Cli::ProcessesHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def api_client
    raise "#{self.class} has not defined @api_client" if @api_client.nil?
    @api_client
  end

  def processes_interface
    # get_interface('processes')
    api_client.processes
  end

  def print_process_details(process, options={})
    description_cols = {
      "Process ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['displayName'] },
      "Description" => lambda {|it| it['description'] },
      "Process Type" => lambda {|it| it['processType'] ? (it['processType']['name'] || it['processType']['code']) : it['processTypeName'] },
      "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['displayName'] || it['createdBy']['username']) : '' },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Duration" => lambda {|it| format_process_duration(it) },
    }
    if process['message'].to_s.strip != ''
      description_cols.merge!({ "Message" => lambda {|it| it['message']}
      })
    end
    description_cols.merge!({
      "Status" => lambda {|it| format_process_status(it) },
      # "# Events" => lambda {|it| (it['events'] || []).size() },
    })
    print_description_list(description_cols, process, options)

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

  def print_process_event_details(process_event, options={})
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
    print_description_list(description_cols, process_event, options)

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
  def format_process_error(process, max_length=20, return_color=cyan)
    truncate_string(process['error'].to_s.strip.gsub("\n", " "), max_length)
  end

  # decolorize, remove newlines and truncate for table cell
  def format_process_output(process, max_length=20, return_color=cyan)
    truncate_string(process['output'].to_s.strip.gsub("\n", " "), max_length)
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

  def wait_for_process_execution(process_id, options={}, print_output = true)
    refresh_interval = 10
    if options[:refresh_interval].to_i > 0
      refresh_interval = options[:refresh_interval]
    end
    refresh_display_seconds = refresh_interval % 1.0 == 0 ? refresh_interval.to_i : refresh_interval
    unless options[:quiet]
      print cyan, "Refreshing every #{refresh_display_seconds} seconds until process is complete...", "\n", reset
    end
    process = processes_interface.get(process_id)['process']
    while ['new','queued','pending','running'].include?(process['status']) do
      sleep(refresh_interval)
      process = processes_interface.get(process_id)['process']
    end
    if print_output && options[:quiet] != true
      print_h1 "Process Details", [], options
      print_process_details(process, options)
    end
    return process
  end

  def handle_history_command(args, arg_name, label, ref_type, &block)
    raw_args = args.dup
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} #{command_name} history [#{arg_name}]"
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      # opts.on('--process-id ID', String, "Display details about a specfic process only." ) do |val|
      #   options[:process_id] = val
      # end
      # opts.on('--event-id ID', String, "Display details about a specfic process event only." ) do |val|
      #   options[:event_id] = val
      # end
      build_standard_list_options(opts, options)
      opts.footer = "List historical processes for a specific #{label}.\n" + 
                    "[#{arg_name}] is required. This is the name or id of an #{label}."
    end
    optparse.parse!(args)

    # shortcut to other actions
    # if options[:process_id]
    #   return history_details(raw_args)
    # elsif options[:event_id]
    #   return history_event_details(raw_args)
    # end

    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
    record = block.call(args[0])
    # block should raise_command_error if not found
    if record.nil?
      raise_command_error "#{label} not found for name or id '#{args[0]}'"
    end
    params = {}
    params.merge!(parse_list_options(options))
    # params['query'] = params.delete('phrase') if params['phrase']
    params['refType'] = ref_type
    params['refId'] = record['id']
    @processes_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @processes_interface.dry.list(params)
      return
    end
    json_response = @processes_interface.list(params)
    render_response(json_response, options, "processes") do
      title = "#{label} History: #{record['name'] || record['id']}"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles, options
      processes = json_response['processes']
      if processes.empty?
        print "#{cyan}No process history found.#{reset}\n\n"
      else
        history_records = []
        processes.each do |process|
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
      end
    end
    return 0, nil
  end

end
