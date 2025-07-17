require 'morpheus/cli/cli_command'

class Morpheus::Cli::FileCopyRequestCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'file-copy-request'

  register_subcommands :get, :execute, :download, :add
  #register_subcommands :'execute-against-lease' => :execute_against_lease
  
  # set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    # @instances_interface = @api_client.instances
    # @containers_interface = @api_client.containers
    # @servers_interface = @api_client.servers
    @file_copy_request_interface = @api_client.file_copy_request
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[uid]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.on('--refresh [SECONDS]', String, "Refresh until execution is finished. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_finished] = true
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.footer = "Get details about a file copy request." + "\n" +
                    "[uid] is required. This is the unique id of a file copy request."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    file_copy_request_id = args[0]
    begin
      params.merge!(parse_list_options(options))
      @file_copy_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @file_copy_request_interface.dry.get(file_copy_request_id, params)
        return
      end
      json_response = @file_copy_request_interface.get(file_copy_request_id, params)
      if options[:json]
        puts as_json(json_response, options, "fileCopyRequest")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "fileCopyRequest")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['fileCopyRequest']], options)
        return 0
      end

      file_copy_request = json_response['fileCopyRequest']

      # refresh until a status is reached
      if options[:refresh_until_finished]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        if ['complete', 'failed', 'expired', 'pending'].include?(file_copy_request['status'])
          # it is finished
        else
          print cyan
          refresh_display_seconds = options[:refresh_interval] % 1.0 == 0 ? options[:refresh_interval].to_i : options[:refresh_interval]
          print "File copy request has not yet finished. Refreshing every #{refresh_display_seconds} seconds"
          while !['complete', 'failed', 'expired', 'pending'].include?(file_copy_request['status']) do
            sleep(options[:refresh_interval])
            print cyan,".",reset
            json_response = @file_copy_request_interface.get(file_copy_request_id, params)
            file_copy_request = json_response['fileCopyRequest']
          end
          #sleep_with_dots(options[:refresh_interval])
          print "\n", reset
          # get(raw_args)
        end
      end

      print_h1 "File Copy Request Details"
      print cyan
      description_cols = {
        #"ID" => lambda {|it| it['id'] },
        "Unique ID" => lambda {|it| it['uniqueId'] },
        "Server ID" => lambda {|it| it['serverId'] },
        "Instance ID" => lambda {|it| it['instanceId'] },
        "Container ID" => lambda {|it| it['containerId'] },
        "Expires At" => lambda {|it| format_local_dt it['expiresAt'] },
        #"Exit Code" => lambda {|it| it['exitCode'] },
        "Status" => lambda {|it| format_file_copy_request_status(it) },
        #"Created By" => lambda {|it| it['createdById'] },
        #"Subdomain" => lambda {|it| it['subdomain'] },
      }
      print_description_list(description_cols, file_copy_request)      

      if file_copy_request['stdErr']
        print_h2 "Error"
        puts file_copy_request['stdErr'].to_s.strip
      end
      if file_copy_request['stdOut']
        print_h2 "Output"
        puts file_copy_request['stdOut'].to_s.strip
      end
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def execute(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--server ID', String, "Server ID") do |val|
        params['serverId'] = val
      end
      opts.on('--instance ID', String, "Instance ID") do |val|
        params['instanceId'] = val
      end
      opts.on('--container ID', String, "Container ID") do |val|
        params['containerId'] = val
      end
      opts.on('--request ID', String, "File Copy Request ID") do |val|
        params['requestId'] = val
      end
      opts.on('--file FILE', "Local file to be copied." ) do |val|
        filename = val
      end
      opts.on('--target-path PATH', "Target path for file on destination host." ) do |val|
        params['targetPath'] = val
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Copy a file to a remote host(s)." + "\n" +
                    "[server] or [instance] or [container] is required. This is the id of a server, instance or container." + "\n" +
                    "[file] is required. This is the local filename that is to be copied." + "\n" +
                    "[target-path] is required. This is the target path for the file on the destination host."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if params['serverId'].nil? && params['instanceId'].nil? && params['containerId'].nil? && params['requestId'].nil?
      puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --server or --instance or --container\n#{optparse}"
      return 1
    end
    # if filename.nil?
    #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --file\n#{optparse}"
    #   return 1
    # end
    # if params['targetPath'].nil?
    #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --target-path\n#{optparse}"
    #   return 1
    # end
    begin
      # construct payload
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      full_filename = nil
      if filename.nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'file', 'type' => 'file', 'fieldLabel' => 'File', 'required' => true, 'description' => 'The local file to be copied'}], options[:options])
        filename = v_prompt['file']
      end
      full_filename = File.expand_path(filename)        
      if !File.exist?(full_filename)
        print_red_alert "File not found: #{full_filename}"
        return 1
      end
      local_file = File.new(full_filename, 'rb')
      
      if params['targetPath'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetPath', 'type' => 'text', 'fieldLabel' => 'Target Path', 'required' => true, 'description' => 'The target path for the file on the destination host.'}], options[:options])
        params['targetPath'] = v_prompt['targetPath']
      end

      @file_copy_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @file_copy_request_interface.dry.create(local_file, params)
        return 0
      end
      # do it
      json_response = @file_copy_request_interface.create(local_file, params)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      file_copy_request = json_response['fileCopyRequest']
      print_green_success "Executing file copy request #{file_copy_request['uniqueId']}"
      if do_refresh
        get([file_copy_request['uniqueId'], "--refresh"])
      else
        get([file_copy_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def download(args)
    options = {}
    params = {}
    script_content = nil
    filename = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[uid] [file]")
      opts.on('--file FILE', "Local file destination for the downloaded file." ) do |val|
        filename = val
      end
      opts.on( '-f', '--force', "Overwrite existing [file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [file] if they do not exist." ) do
        do_mkdir = true
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Download a file associated with a file copy request." + "\n" +
                    "[uid] is required. This is the unique id of a file copy request." + "\n" +
                    "[file] is required. This is the full local filepath for the downloaded file."
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    file_copy_request_id = args[0]
    if args[1]
      filename = args[1]
    end
    outfile = File.expand_path(filename)
    if Dir.exist?(outfile)
      print_red_alert "[file] is invalid. It is the name of an existing directory: #{outfile}"
      return 1
    end
    destination_dir = File.dirname(outfile)
    if !Dir.exist?(destination_dir)
      if do_mkdir
        print cyan,"Creating local directory #{destination_dir}",reset,"\n"
        FileUtils.mkdir_p(destination_dir)
      else
        print_red_alert "[file] is invalid. Directory not found: #{destination_dir}"
        return 1
      end
    end
    if File.exist?(outfile)
      if do_overwrite
        # uhh need to be careful wih the passed filepath here..
        # don't delete, just overwrite.
        # File.delete(outfile)
      else
        print_error Morpheus::Terminal.angry_prompt
        puts_error "[file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
        # puts_error optparse
        return 1
      end
    end
    begin
      # construct payload
      
      @file_copy_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @file_copy_request_interface.dry.download_file_chunked(file_copy_request_id, outfile, params)
        return 0
      end
      # do it
      
      if !options[:quiet]
        print cyan + "Downloading file copy request #{file_copy_request_id} to #{outfile} ... "
      end

      http_response = @file_copy_request_interface.download_file_chunked(file_copy_request_id, outfile, params)

      # FileUtils.chmod(0600, outfile)
      success = http_response.code.to_i == 200
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
        end
        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
        end
        # F it, just remove a bad result
        if File.exist?(outfile) && File.file?(outfile)
          Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
          File.delete(outfile)
        end
        if options[:debug]
          puts_error http_response.inspect
        end
        return 1
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    filename = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--server ID', String, "Server ID") do |val|
        params['serverId'] = val
      end
      opts.on('--instance ID', String, "Instance ID") do |val|
        params['instanceId'] = val
      end
      opts.on('--container ID', String, "Container ID") do |val|
        params['containerId'] = val
      end
      opts.on('--file FILE', "Local file to be copied." ) do |val|
        filename = val
      end
      opts.on('--target-path PATH', "Target path for file on destination host." ) do |val|
        params['targetPath'] = val
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a file copy request to be later used." + "\n" +
                    "[server] or [instance] or [container] is required. This is the id of a server, instance or container." + "\n" +
                    "[file] is required. This is the local filename that is to be copied." + "\n" +
                    "[target-path] is required. This is the target path for the file on the destination host."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if params['serverId'].nil? && params['instanceId'].nil? && params['containerId'].nil?
      puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --server or --instance or --container\n#{optparse}"
      return 1
    end
    # if filename.nil?
    #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --file\n#{optparse}"
    #   return 1
    # end
    # if params['targetPath'].nil?
    #   puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: --target-path\n#{optparse}"
    #   return 1
    # end
    begin
      # construct payload
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      full_filename = nil
      if filename.nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'file', 'type' => 'file', 'fieldLabel' => 'File', 'required' => true, 'description' => 'The local file to be copied'}], options[:options])
        filename = v_prompt['file']
      end
      full_filename = File.expand_path(filename)
      if !File.exist?(full_filename)
        print_red_alert "File not found: #{full_filename}"
        return 1
      end
      local_file = File.new(full_filename, 'rb')

      if params['targetPath'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'targetPath', 'type' => 'text', 'fieldLabel' => 'Target Path', 'required' => true, 'description' => 'The target path for the file on the destination host.'}], options[:options])
        params['targetPath'] = v_prompt['targetPath']
      end

      @file_copy_request_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @file_copy_request_interface.dry.add(local_file, params)
        return 0
      end
      # do it
      json_response = @file_copy_request_interface.add(local_file, params)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      file_copy_request = json_response['fileCopyRequest']
      print_green_success "Adding file copy request #{file_copy_request['uniqueId']}"
      if do_refresh
        puts "THIS IS THE NEW REQUEST ID: #{file_copy_request['uniqueId']}"
        get([file_copy_request['uniqueId'], "--refresh"])
      else
        get([file_copy_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def format_file_copy_request_status(file_copy_request, return_color=cyan)
    out = ""
    status_str = file_copy_request['status']
    if status_str == 'complete'
      out << "#{green}#{status_str.upcase}#{return_color}"
    elsif status_str == 'failed' || status_str == 'expired'
      out << "#{red}#{status_str.upcase}#{return_color}"
    else
      out << "#{cyan}#{status_str.upcase}#{return_color}"
    end
    out
  end

end
