require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for fetching log records.
# The including class must establish @logs_interface, @containers_interface, @servers_interface
module Morpheus::Cli::LogsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def logs_interface
    # @api_client.logs
    raise "#{self.class} has not defined @logs_interface" if @logs_interface.nil?
    @logs_interface
  end

  def instances_interface
    # @api_client.instances
    raise "#{self.class} has not defined @instances_interface" if @instances_interface.nil?
    @instances_interface
  end

  def containers_interface
    ## @api_client.containers
    raise "#{self.class} has not defined @logs_interface" if @containers_interface.nil?
    @containers_interface
  end

  def servers_interface
    # @api_client.servers
    raise "#{self.class} has not defined @servers_interface" if @servers_interface.nil?
    @servers_interface
  end

  def clusters_interface
    # @api_client.clusters
    raise "#{self.class} has not defined @clusters_interface" if @clusters_interface.nil?
    @clusters_interface
  end

  def format_log_records(log_records, options={}, show_object=true)
    if options[:table]
      return format_log_table(log_records, options, show_object)
    end
    out = ""
    table_color = options.key?(:color) ? options[:color] : cyan
    log_records.each do |log_entry|
      log_level = format_log_level(log_entry['level'], table_color)
      out << table_color if table_color
      # out << "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}"
      out << "#{log_level} "
      out << "[#{log_entry['ts']}] "
      if show_object
        out << "(#{log_entry['typeCode']} #{log_entry['objectId']}) "
      end
      log_msg = ""
      if options[:details] || options[:all]
          log_msg = log_entry['message'].to_s.strip
        else
          # truncate_string(log_entry['message'].to_s.split.select {|it| it.to_s.strip != "" }.first, 100) 
          log_msg = truncate_string(log_entry['message'].to_s.gsub("\r\n", " ").gsub("\n", " "), 100) 
        end
      out << "- #{log_msg}"
      out << table_color if table_color
      out << "\n"
    end
    return out
  end

  def format_log_table(logs, options={}, show_object=true)
    out = ""
    table_color = options.key?(:color) ? options[:color] : cyan
    log_columns = [
      {"LEVEL" => lambda {|log_entry| format_log_level(log_entry['level'], table_color) } },
      {"DATE" => lambda {|log_entry| log_entry['ts'] } },
      {"SOURCE" => lambda {|log_entry| "#{log_entry['typeCode']} #{log_entry['objectId']}" } },
      {"MESSAGE" => lambda {|log_entry| 
        if options[:details] || options[:all]
          log_entry['message'].to_s
        else
          truncate_string(log_entry['message'].to_s.split.first, 100) 
        end
      } }
    ]
    if show_object != true
      log_columns = log_columns.reject {|it| it.key?("SOURCE") }
    end
    # if options[:include_fields]
    #   columns = options[:include_fields]
    # end
    out << as_pretty_table(logs, log_columns, options.merge(responsive_table:false))
    # out << "\n"
    return out
  end

  def format_log_level(val, return_color=cyan)
    log_level = ''
    case val
    when 'INFO'
      log_level = "#{blue}#{bold}INFO#{reset}#{return_color}"
    when 'DEBUG'
      log_level = "#{white}#{bold}DEBUG#{reset}#{return_color}"
    when 'WARN'
      log_level = "#{yellow}#{bold}WARN#{reset}#{return_color}"
    when 'ERROR'
      log_level = "#{red}#{bold}ERROR#{reset}#{return_color}"
    when 'FATAL'
      log_level = "#{red}#{bold}FATAL#{reset}#{return_color}"
    else
      log_level = val
    end
    return log_level
  end
end
