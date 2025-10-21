require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageProvidersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'storage-buckets'

  register_subcommands :list, :get, :add, :update, :remove
  # file commands
  register_subcommands :'list-files' => :list_files
  register_subcommands :'ls' => :ls
  #register_subcommands :'file' => :get_file
  # register_subcommands :'history' => :file_history
  register_subcommands :'upload' => :upload_file
  register_subcommands :'download' => :download_file
  register_subcommands :'read' => :read_file
  register_subcommands :'remove-file' => :remove_file
  register_subcommands :'rm' => :remove_file

  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @storage_providers_interface = @api_client.storage_providers
    @storage_servers_interface = @api_client.storage_servers
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = "List storage buckets."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @storage_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @storage_providers_interface.dry.list(params)
      return
    end
    json_response = @storage_providers_interface.list(params)
    storage_buckets = json_response['storageBuckets']
    render_response(json_response, options, 'storageBuckets') do
      print_h1 "Morpheus Storage Buckets", parse_list_subtitles(options), options
      if storage_buckets.empty?
        print cyan,"No storage buckets found.",reset,"\n"
      else
        print as_pretty_table(storage_buckets, storage_bucket_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if storage_buckets.empty?
      return 1, "no storage buckets found"
    else
      return 0, nil
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-bucket]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a storage bucket." + "\n" +
                    "[storage-bucket] is required. This is the name or id of a storage bucket."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [storage-bucket]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @storage_providers_interface.dry.get(args[0].to_i)
        else
          print_dry_run @storage_providers_interface.dry.list({name:args[0]})
        end
        return
      end
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?
      json_response = {'storageBucket' => storage_provider}  # skip redundant request
      # json_response = @storage_providers_interface.get(storage_provider['id'])
      storage_provider = json_response['storageBucket']
      if options[:json]
        puts as_json(json_response, options, "storageBucket")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "storageBucket")
        return 0
      elsif options[:csv]
        puts records_as_csv([storage_provider], options)
        return 0
      end
      print_h1 "Storage Bucket Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "Provider Type" => lambda {|it| format_storage_provider_type(it) },
        "Bucket Name" => lambda {|it| format_bucket_name(it) },
        "Default Backup Target" => lambda {|it| it['defaultBackupTarget'] ? 'Yes' : 'No' },
        "Default Deployment Target" => lambda {|it| it['defaultDeploymentTarget'] ? 'Yes' : 'No' },
        "Default Virtual Image Store" => lambda {|it| it['defaultVirtualImageTarget'] ? 'Yes' : 'No' },
        "Archive Snapshots" => lambda {|it| it['copyToStore'] ? 'Yes' : 'No' }
      }
      print_description_list(description_cols, storage_provider)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    ip_range_list = nil
    create_bucket = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--name VALUE', String, "Name for this storage bucket") do |val|
        options['name'] = val
      end
      opts.on('--type code', String, "Storage Bucket Type Code") do |val|
        options['providerType'] = val
      end
      opts.on('--bucket-name VALUE', String, "Bucket Name") do |val|
        options['bucketName'] = val
      end
      opts.on('--default-backup-target [on|off]', String, "Default Backup Target") do |val|
        options['defaultBackupTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-deployment-target [on|off]', String, "Default Deployment Target") do |val|
        options['defaultDeploymentTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-virtual-image-target [on|off]', String, "Default Virtual Image Store") do |val|
        options['defaultVirtualImageTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--copy-to-store [on|off]', String, "Archive Snapshots") do |val|
        options['copyToStore'] = val.to_s == 'on' || val.to_s == 'true'
      end
      #opts.on('--create-bucket [on|off]', String, "Create Bucket") do |val|
      #  create_bucket = val.to_s == 'on' || val.to_s == 'true' || val.nil?
      #end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new storage bucket." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # support [name] as first argument
      if args[0]
        options['name'] = args[0]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for storage bucket options
        payload = {
          'storageBucket' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['storageBucket'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['storageBucket']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this storage bucket.'}], options)
          payload['storageBucket']['name'] = v_prompt['name']
        end

        # Storage Bucket Type
        storage_provider_type_code = nil
        if options['type']
          storage_provider_type_code = options['type'].to_s
        elsif options['providerType']
          storage_provider_type_code = options['providerType'].to_s
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'providerType',
                                                         'fieldLabel' => 'Provider Type',
                                                         'type' => 'select',
                                                         'selectOptions' => get_storage_provider_types(),
                                                         'required' => true,
                                                         'description' => 'Choose a storage bucket type.'}],
                                                       options, @api_client, {})
          storage_provider_type_code = v_prompt['providerType'] unless v_prompt['providerType'].nil?
        end
        if storage_provider_type_code == 'amazonS3'
          payload['storageBucket']['providerType'] = 's3'  # cloud provided amazonS3
        else
          payload['storageBucket']['providerType'] = storage_provider_type_code
        end

        # Storage Service (only for amazonS3)
        storage_server_type_id = nil
        storage_server_id = nil
        if storage_provider_type_code == 'amazonS3'
          storage_server_type = @api_client.storage_server_types.list({max:1000})['storageServerTypes'].find {|it| it['code'].downcase == storage_provider_type_code.downcase }
          if options['storageServer']
            storage_server_id = options['storageServer']
          else
            if storage_server_type.nil?
              raise_command_error "error: no storage server type found for amazonS3"
            end
            Morpheus::Logging::DarkPrinter.puts "Finding storage services..." if Morpheus::Logging.debug?
            storage_server_options = @storage_servers_interface.list({max:1000, 'typeId': storage_server_type['id']})['storageServers'].collect {|it| {'name' => it['name'], 'value' => it['id'] } }
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageServer',
                                                           'fieldLabel' => 'Storage Server',
                                                           'type' => 'select',
                                                           'selectOptions' => storage_server_options,
                                                           'required' => true,
                                                           'description' => 'Choose a connected storage service.'}], options, @api_client, {})
            storage_server_id = v_prompt['storageServer'] unless v_prompt['storageServer'].nil?
          end
          payload['storageBucket']['storageServer'] = storage_server_id.to_s # api before 8.0.11 expects a string instead of a number, oooof
        end

        # Provider Type Specific Options
        provider_type_option_types = nil
        if storage_provider_type_code == 's3'
          # print_h2 "Amazon S3 Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'accessKey', 'fieldLabel' => 'Access Key', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'secretKey', 'fieldLabel' => 'Secret Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => false, 'description' => 'Optional Amazon region if creating a new bucket.'},
            {'fieldContext' => 'config', 'fieldName' => 'endpoint', 'fieldLabel' => 'Endpoint URL', 'type' => 'text', 'required' => false, 'description' => 'Optional endpoint URL if pointing to an object store other than amazon that mimics the Amazon S3 APIs.'}
          ]
        elsif storage_provider_type_code == 'amazonS3'
          # print_h2 "Amazon S3 Provided by Cloud Options"
          provider_type_option_types = [
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => false, 'description' => 'Optional Amazon region if creating a new bucket.'},
            {'fieldContext' => 'config', 'fieldName' => 'endpoint', 'fieldLabel' => 'Endpoint URL', 'type' => 'text', 'required' => false, 'description' => 'Optional endpoint URL if pointing to an object store other than amazon that mimics the Amazon S3 APIs.'}
          ]

        elsif storage_provider_type_code == 'azure'
          # print_h2 "Azure Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'storageAccount', 'fieldLabel' => 'Storage Account', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'storageKey', 'fieldLabel' => 'Storage Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'},
          ]
        elsif storage_provider_type_code == 'alibaba'
          # print_h2 "Alibaba Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'accessKey', 'fieldLabel' => 'Access Key', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'secretKey', 'fieldLabel' => 'Secret Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => false, 'description' => 'Optional Alibaba region if creating a new bucket.'}
          ]
        elsif storage_provider_type_code == 'cifs'
          # print_h2 "CIFS Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'host', 'fieldLabel' => 'Host', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''}
          ]
        elsif storage_provider_type_code == 'local'
          # print_h2 "Local Storage Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'basePath', 'fieldLabel' => 'Storage Path', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'hidden', 'required' => true, 'description' => '', 'defaultValue' => '.'}
          ]
        elsif storage_provider_type_code == 'nfs'
          # print_h2 "NFSv3 Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'host', 'fieldLabel' => 'Host', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'exportFolder', 'fieldLabel' => 'Export Folder', 'type' => 'text', 'required' => false, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'hidden', 'required' => true, 'description' => '', 'defaultValue' => '/'}
          ]
        elsif storage_provider_type_code == 'openstack'
          # print_h2 "Openstack Swift Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'apiKey', 'fieldLabel' => 'API Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'},
            {'fieldContext' => 'config', 'fieldName' => 'identityUrl', 'fieldLabel' => 'Identity URL', 'type' => 'text', 'required' => true, 'description' => ''},
          ]
        elsif storage_provider_type_code == 'rackspace'
          # print_h2 "Rackspace CDN Options"
          provider_type_option_types = [
            {'fieldContext' => 'config', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'apiKey', 'fieldLabel' => 'API Key', 'type' => 'password', 'required' => true, 'description' => ''},
            {'fieldContext' => 'config', 'fieldName' => 'region', 'fieldLabel' => 'Region', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'bucketName', 'fieldLabel' => 'Bucket Name', 'type' => 'text', 'required' => true, 'description' => ''},
            {'fieldName' => 'createBucket', 'fieldLabel' => 'Create Bucket', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Create the bucket if it does not exist.'}
          ]
        else
          puts "warning: unrecognized storage bucket type: '#{storage_provider_type_code}'"
        end
        if provider_type_option_types
          v_prompt = Morpheus::Cli::OptionTypes.prompt(provider_type_option_types, options, @api_client, {})
          payload['storageBucket'].deep_merge!(v_prompt)
        end

        # Default Backup Target
        if options['defaultBackupTarget'] != nil
          payload['storageBucket']['defaultBackupTarget'] = options['defaultBackupTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultBackupTarget', 'fieldLabel' => 'Default Backup Target', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageBucket']['defaultBackupTarget'] = (v_prompt['defaultBackupTarget'].to_s == 'on') unless v_prompt['defaultBackupTarget'].nil?
        end

        # Archive Snapshots
        if options['copyToStore'] != nil
          payload['storageBucket']['copyToStore'] = options['copyToStore']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'copyToStore', 'fieldLabel' => 'Archive Snapshots', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'on'}], options)
          payload['storageBucket']['copyToStore'] = (v_prompt['copyToStore'].to_s == 'on') unless v_prompt['copyToStore'].nil?
        end

        # Default Deployment Target
        if options['defaultDeploymentTarget'] != nil
          payload['storageBucket']['defaultDeploymentTarget'] = options['defaultDeploymentTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultDeploymentTarget', 'fieldLabel' => 'Default Deployment Target', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageBucket']['defaultDeploymentTarget'] = (v_prompt['defaultDeploymentTarget'].to_s == 'on') unless v_prompt['defaultDeploymentTarget'].nil?
        end

        # Default Virtual Image Store
        if options['defaultVirtualImageTarget'] != nil
          payload['storageBucket']['defaultVirtualImageTarget'] = options['defaultVirtualImageTarget']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultVirtualImageTarget', 'fieldLabel' => 'Default Virtual Image Store', 'type' => 'checkbox', 'required' => false, 'description' => '', 'defaultValue' => 'off'}], options)
          payload['storageBucket']['defaultVirtualImageTarget'] = (v_prompt['defaultVirtualImageTarget'].to_s == 'on') unless v_prompt['defaultVirtualImageTarget'].nil?
        end
        #if create_bucket
        #  payload['createBucket'] = true
        #end
        if payload['storageBucket']['createBucket'] == 'on'
          payload['storageBucket']['createBucket'] = true
        end
      end

      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.create(payload)
        return
      end
      json_response = @storage_providers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        storage_provider = json_response['storageBucket']
        print_green_success "Added storage bucket #{storage_provider['name']}"
        get([storage_provider['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-bucket] [options]")
      opts.on('--name VALUE', String, "Name for this storage bucket") do |val|
        options['name'] = val
      end
      opts.on('--type code', String, "Storage Bucket Type Code") do |val|
        options['providerType'] = val
      end
      opts.on('--bucket-name VALUE', String, "Bucket Name") do |val|
        options['bucketName'] = val
      end
      opts.on('--default-backup-target [on|off]', String, "Default Backup Target") do |val|
        options['defaultBackupTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-deployment-target [on|off]', String, "Default Deployment Target") do |val|
        options['defaultDeploymentTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--default-virtual-image-target [on|off]', String, "Default Virtual Image Store") do |val|
        options['defaultVirtualImageTarget'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--copy-to-store [on|off]', String, "Archive Snapshots") do |val|
        options['copyToStore'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a storage bucket." + "\n" +
                    "[storage-bucket] is required. This is the id of a storage bucket."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for storage bucket options
        # preserve previous config settings
        payload = {
          'storageBucket' => {
            'config' => storage_provider['config']
          }
        }
        
        # allow arbitrary -O options
        payload['storageBucket'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['storageBucket']['name'] = options['name']
        end

        # Default Backup Target
        if options['defaultBackupTarget'] != nil
          payload['storageBucket']['defaultBackupTarget'] = options['defaultBackupTarget']
        end

        # Archive Snapshots
        if options['copyToStore'] != nil
          payload['storageBucket']['copyToStore'] = options['copyToStore']
        end

        # Default Deployment Target
        if options['defaultDeploymentTarget'] != nil
          payload['storageBucket']['defaultDeploymentTarget'] = options['defaultDeploymentTarget']
        end

        # Default Virtual Image Store
        if options['defaultVirtualImageTarget'] != nil
          payload['storageBucket']['defaultVirtualImageTarget'] = options['defaultVirtualImageTarget']
        end

        if payload['storageBucket']['createBucket'] == 'on'
          payload['storageBucket']['createBucket'] = true
        end
      end
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.update(storage_provider["id"], payload)
        return
      end
      json_response = @storage_providers_interface.update(storage_provider["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        storage_provider = json_response['storageBucket']
        print_green_success "Updated storage bucket #{storage_provider['name']}"
        get([storage_provider['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[storage-bucket]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a storage bucket." + "\n" +
                    "[storage-bucket] is required. This is the name or id of a storage bucket."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [storage-bucket]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(args[0])
      return 1 if storage_provider.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the storage bucket: #{storage_provider['name']}?")
        return 9, "aborted command"
      end
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.destroy(storage_provider['id'])
        return 0
      end
      json_response = @storage_providers_interface.destroy(storage_provider['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed storage bucket #{storage_provider['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_files(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[provider:/path]")
      opts.on('-a', '--all', "Show all files, including subdirectories under the /path.") do
        params[:fullTree] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run])
      opts.footer = "List files in a storage bucket. \nInclude [/path] to show files under a directory."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} list-files expects 1-2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    storage_provider_id, search_file_path  = parse_storage_provider_id_and_file_path(args[0], args[1])
    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(storage_provider_id)
      return 1 if storage_provider.nil?
      params.merge!(parse_list_options(options))
      [:fullTree].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.list_files(storage_provider['id'], search_file_path, params)
        return
      end
      json_response = @storage_providers_interface.list_files(storage_provider['id'], search_file_path, params)
      storage_files = json_response['storageFiles']
      # storage_provider = json_response['storageBucket']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      if options[:json]
        puts as_json(json_response, options, "storageFiles")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "storageFiles")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['storageFiles'], options)
        return 0
      end
      print_h1 "Storage Files", ["#{storage_provider['name']}:#{search_file_path}"]
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        # "Bucket Name" => 'bucketName',
        #"Path" => lambda {|it| search_file_path }
      }
      #print_description_list(description_cols, storage_provider)
      #print "\n"
      #print_h2 "Path: #{search_file_path}"
      # print "Directory: #{search_file_path}"
      if storage_files && storage_files.size > 0
        print_storage_files_table(storage_files, {fullTree: params[:fullTree]})
        #print_results_pagination(json_response, {:label => "file", :n_label => "files"})
        print reset, "\n"
        return 0
      else
        # puts "No files found for path #{search_file_path}"
        if search_file_path.empty? || search_file_path == "/"
          puts "This storage bucket has no files."
          print reset,"\n"
          return 0
        else
          puts "No files found for path #{search_file_path}"
          print reset,"\n"
          return 1
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def ls(args)
    options = {}
    params = {}
    do_one_file_per_line = false
    do_long_format = false
    do_human_bytes = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket/path]")
      opts.on('-a', '--all', "Show all files, including subdirectories under the /path.") do
        params[:fullTree] = true
        do_one_file_per_line = true
      end
      opts.on('-l', '--long', "Lists files in the long format, which contains lots of useful information, e.g. the exact size of the file, the file type, and when it was last modified.") do
        do_long_format = true
        do_one_file_per_line
      end
      opts.on('-H', '--human', "Humanized file sizes. The default is just the number of bytes.") do
        do_human_bytes = true
      end
      opts.on('-1', '--oneline', "One file per line. The default delimiter is a single space.") do
        do_one_file_per_line = true
      end
      build_common_options(opts, options, [:list, :json, :fields, :dry_run])
      opts.footer = "Print filenames for a given location.\nPass storage location in the format bucket/path."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} ls expects 1-2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    storage_provider_id, search_file_path  = parse_storage_provider_id_and_file_path(args[0], args[1])
    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(storage_provider_id)
      return 1 if storage_provider.nil?
      params.merge!(parse_list_options(options))
      [:fullTree].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.list_files(storage_provider['id'], search_file_path, params)
        return 0
      end
      json_response = @storage_providers_interface.list_files(storage_provider['id'], search_file_path, params)
      if options[:json]
        puts as_json(json_response, options, "storageFiles")
        # no files is an error condition for this command
        if !json_response['storageFiles'] || json_response['storageFiles'].size == 0
          return 1
        end
        return 0
      end
      #storage_provider = json_response['storageBucket'] # yep, this is returned too
      storage_files = json_response['storageFiles']
      # print_h2 "Directory: #{search_file_path}"
      # print "Directory: #{search_file_path}"
      if storage_files && storage_files.size > 0
        if do_long_format
          # ls long format
          # owner groups filesize type filename
          now = Time.now
          storage_files.each do |storage_file|
            # -rw-r--r--    1 jdickson  staff   1361 Oct 23 08:00 voltron_2.10.log
            file_color = cyan # reset
            if storage_file['isDirectory']
              file_color = blue
            end
            file_info = []
            # Number of links
            # file_info << file["linkCount"].to_i + 1
            # Owner
            owner_str = ""
            if storage_file['owner']
              owner_str = storage_file['owner']['name']
            elsif storage_provider['owner']
              owner_str = storage_provider['owner']['name']
            else
              owner_str = "noone"
            end
            #file_info << truncate_string(owner_str, 15).ljust(15, " ")
            # Group (Tenants)
            groups_str = ""
            if storage_file['visibility'] == 'public'
              # this is confusing because of Public URL (isPublic) setting
              groups_str = "public"
            else
              if storage_file['accounts'].instance_of?(Array) && storage_file['accounts'].size > 0
                # groups_str = storage_file['accounts'].collect {|it| it['name'] }.join(',')
                groups_str = (storage_file['accounts'].size == 1) ? "#{storage_file['accounts'][0]['name']}" : "#{storage_file['accounts'].size} tenants"
              elsif storage_provider['accounts'].instance_of?(Array) && storage_provider['accounts'].size > 0
                # groups_str = storage_provider['accounts'].collect {|it| it['name'] }.join(',')
                groups_str = (storage_provider['accounts'].size == 1) ? "#{storage_provider['accounts'][0]['name']}" : "#{storage_provider['accounts'].size} tenants"
              else
                groups_str = owner_str
              end
            end
            #file_info << truncate_string(groups_str, 15).ljust(15, " ")
            # File Type
            content_type = storage_file['contentType'].to_s
            if storage_file['isDirectory']
              content_type = "directory"
            else
              content_type = storage_file['contentType'].to_s
            end
            file_info << content_type.ljust(25, " ")
            filesize_str = ""
            if do_human_bytes
              # filesize_str = format_bytes(storage_file['contentLength'])
              filesize_str = format_bytes_short(storage_file['contentLength'])
            else
              filesize_str = storage_file['contentLength'].to_i.to_s
            end
            # file_info << filesize_str.ljust(12, " ")
            file_info << filesize_str.ljust(7, " ")
            mtime = ""
            last_updated = parse_time(storage_file['dateModified'])
            if last_updated
              if last_updated.year == now.year
                mtime = format_local_dt(last_updated, {format: "%b %e %H:%M"})
              else
                mtime = format_local_dt(last_updated, {format: "%b %e %Y"})
              end
            end
            file_info << mtime.ljust(12, " ")
            fn = format_filename(storage_file['name'], {fullTree: params[:fullTree]})
            file_info << file_color + fn.to_s + cyan
            print cyan, file_info.join("  "), reset, "\n"
          end
        else
          file_names = storage_files.collect do |storage_file|
            file_color = cyan # reset
            if storage_file['isDirectory']
              file_color = blue
            end
            fn = format_filename(storage_file['name'], {fullTree: params[:fullTree]})
            file_color + fn.to_s + reset
          end
          if do_one_file_per_line
            print file_names.join("\n")
          else
            print file_names.join("\t")
          end
          print "\n"
        end
      else
        print_error yellow, "No files found for path: #{search_file_path}", reset, "\n"
        return 1
      end
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  # def get_file(args)
  #   todo...
  # end

  def upload_file(args)
    options = {}
    query_params = {}
    do_recursive = false
    ignore_regexp = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[local-file] [provider:/path]")
      # opts.on('--filename FILEPATH', String, "Remote file path for the file or folder being uploaded, this is an alternative to [remote-file-path]." ) do |val|
      #   options['type'] = val
      # end
      opts.on( '-R', '--recursive', "Upload a directory and all of its files. This must be passed if [local-file] is a directory." ) do
        do_recursive = true
      end
      opts.on('--ignore-files PATTERN', String, "Pattern of files to be ignored when uploading a directory." ) do |val|
        ignore_regexp = /#{Regexp.escape(val)}/
      end
      opts.footer = "Upload a local file or folder to a storage bucket. " +
                    "\nThe first argument [local-file] should be the path of a local file or directory." +
                    "\nThe second argument [provider:/path] should contain the name or id of the provider." +
                    "\nThe [:/path] component is optional and can be used to specify the destination of the uploaded file or folder." +
                    "\nThe default destination is the same name as the [local-file], under the root directory '/'. " +
                    "\nThis will overwrite any existing remote files that match the destination /path."
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)
    
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} upload expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    # validate local file path
    local_file_path = File.expand_path(args[0].squeeze('/'))
    if local_file_path == "" || local_file_path == "/" || local_file_path == "."
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [local-file]\n#{optparse}"
      return 1
    end
    if !File.exist?(local_file_path)
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} bad argument: [local-file]\nFile '#{local_file_path}' was not found.\n#{optparse}"
      return 1
    end

    # validate provider:/path
    storage_provider_id, remote_file_path  = parse_storage_provider_id_and_file_path(args[1], args[2])

    # if local_file_path.include?('../') # || options[:yes]
    #   raise_command_error "Sorry, you may not use relative paths in your local filepath."
    # end
    
    # validate provider name (or id)
    if !storage_provider_id
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [provider]\n#{optparse}"
      return 1
    end
    
    # strip leading slash of remote name
    # if remote_file_path[0].chr == "/"
    #   remote_file_path = remote_file_path[1..-1]
    # end

    if remote_file_path.include?('./') # || options[:yes]
      raise_command_error "Sorry, you may not use relative paths in your remote filepath."
    end

    # if !options[:yes]
    scary_local_paths = ["/", "/root", "C:\\"]
    if scary_local_paths.include?(local_file_path)
      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload all the files in local directory '#{local_file_path}' !?")
        return 9, "aborted command"
      end
    end
    # end

    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(storage_provider_id)
      return 1 if storage_provider.nil?

      # how many files we dealing with?
      files_to_upload = []
      if File.directory?(local_file_path)
        # upload directory
        if !do_recursive
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: '#{local_file_path}' is a directory.  Use -R or --recursive to upload a directory.\n#{optparse}"
          return 1
        end
        found_files = Dir.glob("#{local_file_path}/**/*")
        # note:  api call for directories is not needed
        found_files = found_files.select {|file| File.file?(file) }
        if ignore_regexp
          found_files = found_files.reject {|it| it =~ ignore_regexp} 
        end
        files_to_upload = found_files

        if files_to_upload.size == 0
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: Local directory '#{local_file_path}' contains 0 files."
          return 1
        end

        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload directory #{local_file_path} (#{files_to_upload.size} files) to #{storage_provider['name']}:#{remote_file_path}?")
          return 9, "aborted command"
        end

        if !options[:yes]
          if files_to_upload.size > 100
            unless Morpheus::Cli::OptionTypes.confirm("Are you REALLY sure you want to upload #{files_to_upload.size} files ?")
              return 9, "aborted command"
            end
          end
        end

        # local_dirname = File.dirname(local_file_path)
        # local_basename = File.basename(local_file_path)
        upload_file_list = []
        files_to_upload.each do |file|
          destination = file.sub(local_file_path, (remote_file_path || "")).squeeze('/')
          upload_file_list << {file: file, destination: destination}
        end
        @storage_providers_interface.setopts(options)
        if options[:dry_run]
          # print_h1 "DRY RUN"
          print "\n",cyan, bold, "Uploading #{upload_file_list.size} Files...", reset, "\n"
          upload_file_list.each do |obj|
            file, destination = obj[:file], obj[:destination]
            #print cyan,bold, "  - Uploading #{file} to #{storage_provider_id}:#{destination} DRY RUN", reset, "\n"
            print_dry_run @storage_providers_interface.dry.upload_file(storage_provider['id'], file, destination)
            print "\n"
          end
          return 0
        end

        print "\n",cyan, bold, "Uploading #{upload_file_list.size} Files...", reset, "\n"
        bad_upload_responses = []
        upload_file_list.each do |obj|
          file, destination = obj[:file], obj[:destination]
          print cyan,bold, "  - Uploading #{file} to #{storage_provider_id}:#{destination}", reset
          upload_response = @storage_providers_interface.upload_file(storage_provider['id'], file, destination)
          if upload_response['success']
            print bold," #{green}SUCCESS#{reset}"
          else
            print bold," #{red}ERROR#{reset}"
            if upload_response['msg']
              bad_upload_responses << upload_response
              print " #{upload_response['msg']}#{reset}"
            end
          end
          print "\n"
        end
        if bad_upload_responses.size > 0
          print cyan, bold, "Completed Upload of #{upload_file_list.size} Files. #{red}#{bad_upload_responses.size} Errors!", reset, "\n"
        else
          print cyan, bold, "Completed Upload of #{upload_file_list.size} Files!", reset, "\n"
        end

      else

        # upload file
        if !File.exist?(local_file_path) && !File.file?(local_file_path)
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "#{command_name} bad argument: [local-file]\nFile '#{local_file_path}' was not found.\n#{optparse}"
          return 1
        end

        # local_dirname = File.dirname(local_file_path)
        # local_basename = File.basename(local_file_path)
        
        file = local_file_path
        destination = File.basename(file)
        if remote_file_path[-1].chr == "/"
          # work like `cp`, and place into the directory
          destination = remote_file_path + File.basename(file)
        elsif remote_file_path
          # renaming file
          destination = remote_file_path
        end
        destination = destination.squeeze('/')

        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload #{local_file_path} to #{storage_provider['name']}:#{destination}?")
          return 9, "aborted command"
        end
        @storage_providers_interface.setopts(options)
        if options[:dry_run]
          #print cyan,bold, "  - Uploading #{file} to #{storage_provider_id}:#{destination} DRY RUN", reset, "\n"
          # print_h1 "DRY RUN"
          print_dry_run @storage_providers_interface.dry.upload_file(storage_provider['id'], file, destination)
          print "\n"
          return 0
        end
      
        print cyan,bold, "  - Uploading #{file} to #{storage_provider_id}:#{destination}", reset
        upload_response = @storage_providers_interface.upload_file(storage_provider['id'], file, destination)
        if upload_response['success']
          print bold," #{green}Success#{reset}"
        else
          print bold," #{red}Error#{reset}"
          if upload_response['msg']
            print " #{upload_response['msg']}#{reset}"
          end
        end
        print "\n"

      end
      #print cyan, bold, "Upload Complete!", reset, "\n"

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def download_file(args)
    full_command_string = "#{command_name} download #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[provider:/path] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download a file or directory.\n" + 
                    "[provider:/path] is required. This is the name or id of the provider and /path the file or folder to be downloaded.\n" +
                    "[local-file] is required. This is the full local filepath for the downloaded file.\n" +
                    "Directories will be downloaded as a .zip file, so you'll want to specify a [local-file] with a .zip extension."
    end
    optparse.parse!(args)
    if args.count < 2 || args.count > 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} download expects 2-3 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    storage_provider_id = nil
    local = nil
    outfile = nil
    if args.count == 3
      storage_provider_id, file_path = parse_storage_provider_id_and_file_path(args[0], args[1])
      outfile = args[2]
    else
      storage_provider_id, file_path = parse_storage_provider_id_and_file_path(args[0])
      outfile = args[1]
    end
    connect(options)
    begin
      storage_provider = find_storage_provider_by_name_or_id(storage_provider_id)
      return 1 if storage_provider.nil?

      file_path = file_path.squeeze('/')
      outfile = File.expand_path(outfile)
      if Dir.exist?(outfile)
        outfile = File.join(outfile, File.basename(file_path))
      end
      if Dir.exist?(outfile)
        print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exist?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          print_red_alert "[local-file] is invalid. Directory not found: #{destination_dir}"
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
          puts_error "[local-file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end
      begin
        @storage_providers_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @storage_providers_interface.dry.download_file_chunked(storage_provider['id'], file_path, outfile), full_command_string
          return 0
        end
        if !options[:quiet]
          print cyan + "Downloading archive file #{storage_provider['name']}:#{file_path} to #{outfile} ... "
        end

        http_response = @storage_providers_interface.download_file_chunked(storage_provider['id'], file_path, outfile)

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
        # this is not reached
        if e.response && e.response.code == 404
          print_red_alert "Storage file not found by path #{file_path}"
          return nil
        else
          raise e
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    
  end

  def read_file(args)
    full_command_string = "#{command_name} read #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[provider:/path]")
      build_common_options(opts, options, [:dry_run])
      opts.footer = "Print the contents of a storage file.\n" + 
                    "[provider:/path] is required. This is the name or id of the provider and /path the file or folder to be downloaded.\n" +
                    "This confirmation can be skipped with the -y option."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} read expects 1-2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      storage_provider_id, file_path = parse_storage_provider_id_and_file_path(args[0], args[1])
      storage_provider = find_storage_provider_by_name_or_id(storage_provider_id)
      return 1 if storage_provider.nil?

      file_path = file_path.squeeze('/')
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_providers_interface.dry.download_file(storage_provider['id'], file_path), full_command_string
        return 1
      end
      file_response = @storage_providers_interface.download_file(storage_provider['id'], file_path)
      puts file_response.body.to_s
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    
  end

  def remove_file(args)
    options = {}
    query_params = {}
    do_recursive = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[provider:/path]")
      opts.on( '-R', '--recursive', "Delete a directory and all of its files. This must be passed if specifying a directory." ) do
        do_recursive = true
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
      opts.footer = "Delete a storage file or directory."
    end
    optparse.parse!(args)
    # consider only allowing args.count == 1 here in the format [provider:/path]
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-file expects 1-2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    storage_provider_id, file_path  = parse_storage_provider_id_and_file_path(args[0], args[1])
    connect(options)
    begin
      
      storage_file = find_storage_file_by_bucket_and_path(storage_provider_id, file_path)
      return 1 if storage_file.nil?
      if storage_file['isDirectory']
        if !do_recursive
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: '#{file_path}' is a directory.  Use -R or --recursive to delete a directory.\n#{optparse}"
          return 1
        end
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the directory: #{args[0]}?")
          return 9, "aborted command"
        end
      else
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the file: #{args[0]}?")
          return 9, "aborted command"
        end
      end
      @storage_providers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_files_interface.dry.destroy(storage_file['id'], query_params)
        return 0
      end
      json_response = @storage_files_interface.destroy(storage_file['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed file #{args[0]}"
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end

  private

  def storage_bucket_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      # "Description" => 'description',
      "Provider Type" => lambda {|it| format_storage_provider_type(it) },
      "Bucket Name" => lambda {|it| format_bucket_name(it) },
      # "Source" => lambda {|it| it['source'] },
      "Backups" => lambda {|it| format_boolean(it['defaultBackupTarget']) },
      "Deployments" => lambda {|it| format_boolean(it['defaultDeploymentTarget']) },
      "Virtual Images" => lambda {|it| format_boolean(it['defaultVirtualImageTarget']) },
      # "Archive Snapshots" => lambda {|it| format_boolean(it['copyToStore']) },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def get_storage_provider_types()
    [
      {'name' => 'Amazon S3', 'value' => 'amazonS3'},
      {'name' => 'Alibaba', 'value' => 'alibaba'},
      {'name' => 'Azure', 'value' => 'azure'},
      {'name' => 'CIFS', 'value' => 'cifs'},
      {'name' => 'Local Storage', 'value' => 'local'},
      {'name' => 'NFSv3', 'value' => 'nfs'},
      {'name' => 'Openstack Swift', 'value' => 'openstack'},
      {'name' => 'Rackspace CDN', 'value' => 'rackspace'},
      {'name' => 'S3', 'value' => 's3'},
    ]
  end

  def find_storage_provider_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_storage_provider_by_id(val)
    else
      return find_storage_provider_by_name(val)
    end
  end

  def find_storage_provider_by_id(id)
    begin
      json_response = @storage_providers_interface.get(id.to_i)
      return json_response['storageBucket']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Storage Bucket not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_storage_provider_by_name(name)
    json_response = @storage_providers_interface.list({name: name.to_s})
    storage_providers = json_response['storageBuckets']
    if storage_providers.empty?
      print_red_alert "Storage Bucket not found by name #{name}"
      return nil
    elsif storage_providers.size > 1
      print_red_alert "#{storage_providers.size} storage buckets found by name #{name}"
      rows = storage_providers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return storage_providers[0]
    end
  end

  def format_bucket_name(storage_provider)
    if storage_provider['providerType'] == 'local'
      storage_provider['config'] ? storage_provider['config']['basePath'] : ''
    else
      storage_provider['bucketName']
    end      
  end

  def format_storage_provider_type(storage_provider)
    storage_provider['providerType'].to_s.capitalize
  end

  # parse_storage_provider_id_and_file_path() provides flexible argument formats for provider and path
  # it looks for [provider:/path] or [provider] [path]
  # @param delim [String] Default is a comma and any surrounding white space.
  # @return [Array] 2 elements, provider name (or id) and the file path.
  #         The default file path is "/".
  # Examples:
  #   parse_storage_provider_id_and_file_path("test") == ["test", "/"]
  #   parse_storage_provider_id_and_file_path("test:/global.cfg") == ["test", "/global.cfg"]
  #   parse_storage_provider_id_and_file_path("test:/node1/node.cfg") == ["test", "/node1/node.cfg"]
  #   parse_storage_provider_id_and_file_path("test/node1/node.cfg") == ["test", "/node1/node.cfg"]
  #   parse_storage_provider_id_and_file_path("test", "node1/node.cfg") == ["test", "/node1/node.cfg"]
  #
  def parse_storage_provider_id_and_file_path(*args)
    if args.size < 1 || args.size > 2
      return nil, nil
    end
    if !args[0]
      return nil, nil
    end
    full_path = args[0].to_s
    if args[1]
      if full_path.include?(":")
        full_path = "#{full_path}/#{args[1]}"
      else
        full_path = "#{full_path}:#{args[1]}"
      end
    end
    # ok fine, allow just id/filePath, without a colon.
    if !full_path.include?(":") && full_path.include?("/")
      path_elements = full_path.split("/")
      full_path = path_elements[0] + ":" + path_elements[1..-1].join("/")
    end
    uri_elements = full_path.split(":")
    storage_provider_id = uri_elements[0]
    file_path = uri_elements[1..-1].join("/") # [1]
    file_path = "/#{file_path}".squeeze("/")
    return storage_provider_id, file_path
  end

  def format_filename(filename, options={})
    if options[:fullTree]
      filename.to_s
    else
      filename.to_s.split('/').last()
    end
  end

  def print_storage_files_table(storage_files, options={})
    table_color = options[:color] || cyan
    rows = storage_files.collect do |storage_file|
      {
        id: storage_file['id'],
        name: format_filename(storage_file['name'], options),
        type: storage_file['isDirectory'] ? 'directory' : (storage_file['contentType']),
        size: storage_file['isDirectory'] ? '' : format_bytes(storage_file['contentLength']),
        lastUpdated: format_local_dt(storage_file['dateModified'])
      }
    end
    columns = [
      # :id,
      {:name => {:display_name => "File".upcase} },
      :type,
      :size,
      # {:dateCreated => {:display_name => "Date Created"} },
      {:lastUpdated => {:display_name => "Last Modified".upcase} }
    ]
    print table_color
    print as_pretty_table(rows, columns, options)
    print reset
  end

end
