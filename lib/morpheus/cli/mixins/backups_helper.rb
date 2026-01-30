require 'morpheus/cli/mixins/print_helper'
# Mixin for Morpheus::Cli command classes
# Provides common methods for backups management
module Morpheus::Cli::BackupsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def backups_interface
    raise "#{self.class} has not defined @backups_interface" if @backups_interface.nil?
    @backups_interface
  end

  def backup_jobs_interface
    raise "#{self.class} has not defined @backup_jobs_interface" if @backup_jobs_interface.nil?
    @backup_jobs_interface
  end

  def backup_object_key
    'backup'
  end

  def backup_list_key
    'backups'
  end

  def find_backup_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_backup_by_id(val)
    else
      return find_backup_by_name(val)
    end
  end

  def find_backup_by_id(id)
    begin
      json_response = backups_interface.get(id.to_i)
      return json_response[backup_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Backup not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_backup_by_name(name)
    json_response = backups_interface.list({name: name.to_s})
    backups = json_response[backup_list_key]
    if backups.empty?
      print_red_alert "Backup not found by name '#{name}'"
      return nil
    elsif backups.size > 1
      print_red_alert "#{backups.size} backups found by name '#{name}'"
      puts_error as_pretty_table(backups, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return backups[0]
    end
  end

  def backup_job_object_key
    # 'backupJob'
    'job'
  end

  def backup_job_list_key
    # 'backupJobs'
    'jobs'
  end

  def find_backup_job_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_backup_job_by_id(val)
    else
      return find_backup_job_by_name(val)
    end
  end

  def find_backup_job_by_id(id)
    begin
      json_response = backup_jobs_interface.get(id.to_i)
      return json_response[backup_job_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Backup job not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_backup_job_by_name(name)
    json_response = backup_jobs_interface.list({name: name.to_s})
    backup_jobs = json_response[backup_job_list_key]
    if backup_jobs.empty?
      print_red_alert "Backup job not found by name '#{name}'"
      return nil
    elsif backup_jobs.size > 1
      print_red_alert "#{backup_jobs.size} backup jobs found by name '#{name}'"
      puts_error as_pretty_table(backup_jobs, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return backup_jobs[0]
    end
  end

  ## Backup Results

  def backup_result_list_column_definitions()
    {
      "ID" => 'id',
      "Backup" => lambda {|it| it['backup']['name'] rescue '' },
      "Type" => lambda {|it| format_backup_result_type_tag(it) },
      "Location" => lambda {|it| format_backup_result_location_tag(it) },
      "Status" => lambda {|it| format_backup_result_status(it) },
      #"Duration" => lambda {|it| format_duration(it['startDate'], it['endDate']) },
      "Duration" => lambda {|it| format_duration_milliseconds(it['durationMillis']) if it['durationMillis'].to_i > 0 },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Size" => lambda {|it| it['sizeInMb'].to_i != 0 ? format_bytes(it['sizeInMb'], 'MB') : '' },
    }
  end

  def backup_result_column_definitions()
    backup_result_list_column_definitions()
  end

  def format_backup_result_status(backup_result, return_color=cyan)
    out = ""
    status_string = backup_result['status'].to_s.upcase
    if status_string == 'SUCCEEDED' || status_string == 'SUCCESS'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'FAILED'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string
      out <<  "#{cyan}#{status_string.upcase}#{return_color}"
    else
      out <<  ""
    end
    out
  end

  ## Backup Restores

  def backup_restore_list_column_definitions()
    {
      "ID" => 'id',
      "Backup" => lambda {|it| it['backup']['name'] rescue '' },
      "Backup Result ID" => lambda {|it| it['backupResultId'] rescue '' },
      "Target" => lambda {|it| it['instance']['name'] rescue '' },
      "Status" => lambda {|it| format_backup_result_status(it) },
      #"Duration" => lambda {|it| format_duration(it['startDate'], it['endDate']) },
      "Duration" => lambda {|it| format_duration_milliseconds(it['durationMillis']) if it['durationMillis'].to_i > 0 },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
    }
  end

  def backup_restore_column_definitions()
    backup_restore_list_column_definitions()
  end

  def format_backup_restore_status(backup_restore, return_color=cyan)
    format_backup_result_status(backup_restore, return_color)
  end

  # format backup result type tag based on associated backup data
  def format_backup_result_type_tag(backup_result)
    backup = backup_result['backup'] || {}
    if backup['cronExpression'] || (backup['schedule'] && backup['schedule']['id']) || (backup['job'] && backup['job']['id'])
      "#{cyan}POLICY#{reset}"
    else
      "#{yellow}MANUAL#{reset}"
    end
  end

  # format backup result location tag based on storage provider
  def format_backup_result_location_tag(backup_result)
    backup = backup_result['backup'] || {}
    if backup_result['storageProvider'] && backup_result['storageProvider']['id']
      "#{green}REMOTE#{reset}"
    elsif backup['storageProvider'] && backup['storageProvider']['id']
      "#{green}REMOTE#{reset}"
    elsif backup_result['backupProvider'] && backup_result['backupProvider']['id']
      "#{green}REMOTE#{reset}"
    elsif backup['backupProvider'] && backup['backupProvider']['id']
      "#{green}REMOTE#{reset}"
    else
      "#{blue}LOCAL#{reset}"
    end
  end
  
end