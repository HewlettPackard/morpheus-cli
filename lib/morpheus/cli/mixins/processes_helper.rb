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

end
