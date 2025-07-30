require 'morpheus/cli/cli_command'

# JD: I don't think a lot of this has ever worked, fix it up.

class Morpheus::Cli::VirtualImages
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  register_subcommands :list, :get, :add, :add_file, :remove_file, :update, :remove, 
                       :convert, {:types => :available_virtual_image_types}, :download
  register_subcommands :list_locations, :get_location, :remove_location

  # def initialize() 
  # 	# @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
  # end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @virtual_images_interface = @api_client.virtual_images
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-t', '--type IMAGE_TYPE', "Image Type" ) do |val|
        options[:imageType] = val.downcase
      end
      opts.on('--all', "All Images" ) do
        options[:filterType] = 'All'
      end
      opts.on('--user', "User Images" ) do
        options[:filterType] = 'User'
      end
      opts.on('--system', "System Images" ) do
        options[:filterType] = 'System'
      end
       opts.on('--synced', "Synced Images" ) do
        options[:filterType] = 'Synced'
      end
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      opts.on('--tags Name=Value',String, "Filter by tags (metadata name value pairs).") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('-a', '--details', "Show more details." ) do
        options[:details] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = "List virtual images. Default list applies User filter"
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    if options[:imageType]
      params[:imageType] = options[:imageType]
    end
    if options[:filterType]
      params[:filterType] = options[:filterType]
    end
    if options[:tags]
      options[:tags].each do |k,v|
        params['tags.' + k] = v
      end
    end
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.list(params)
      return
    end
    json_response = @virtual_images_interface.list(params)
    images = json_response['virtualImages']
    render_response(json_response, options, 'virtualImages') do
      get_available_virtual_image_types() # preload
      title = "Morpheus Virtual Images"
      subtitles = parse_list_subtitles(options)
      if options[:imageType]
        subtitles << "Image Type: #{options[:imageType]}".strip
      end
      if options[:filterType]
        subtitles << "Image Type: #{options[:filterType]}".strip
      end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if images.empty?
        print cyan,"No virtual images found.",reset,"\n"
      else
        virtual_image_column_definitions = {
          "ID" => 'id',
          "Name" => 'name',
          "Labels" => lambda {|it| format_list(it['labels'], '', 3) rescue '' },
          "Type" => lambda {|it| 
            # yick, api should return the type with every virtualImage
            image_type = virtual_image_type_for_name_or_code(it['imageType'])
            image_type ? "#{image_type['name']}" : it['imageType']
          },
          "Operating System" => lambda {|it| it['osType'] ? it['osType']['name'] : "" }, 
          "Storage" => lambda {|it| !it['storageProvider'].nil? ? it['storageProvider']['name'] : 'Default' }, 
          "Size" => lambda {|it| it['rawSize'].nil? ? 'Unknown' : "#{Filesize.from("#{it['rawSize']} B").pretty}" },
          "Visibility" => lambda {|it| it['visibility'] },
          # "Tenant" => lambda {|it| it['account'].instance_of?(Hash) ? it['account']['name'] : it['ownerId'] },
          "Tenants" => lambda {|it| format_list(it['accounts'].collect {|a| a['name'] }, '', 3) rescue '' },
          "Source" => lambda {|it| format_virtual_image_source(it) }, 
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
          "Tags" => lambda {|it| it['tags'] ? it['tags'].collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        }
        if json_response['multiTenant'] != true
          virtual_image_column_definitions.delete("Visibility")
          virtual_image_column_definitions.delete("Tenants")
        end
        if options[:details] != true
          virtual_image_column_definitions.delete("Tags")
          virtual_image_column_definitions.delete("Created")
          virtual_image_column_definitions.delete("Updated")
        end
        print as_pretty_table(images, virtual_image_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if images.empty?
      return -1, "no virtual images found"
    else
      return 0, nil
    end
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image]")
      opts.on('-a', '--details', "Show more details." ) do
        options[:details] = true
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'name:value, name:value'") do |val|
        options[:tags] = val
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a virtual image.
[image] is required. This is the name or id of a virtual image.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    # lookup IDs if names are given
    id_list = id_list.collect do |id|
      if id.to_s =~ /\A\d{1,}\Z/
        id
      else
        image = find_virtual_image_by_name_or_id(id)
        return 1, "virtual image not found for name '#{id}'" if image.nil?
        image['id']
      end
    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
      @virtual_images_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.get(id.to_i)
        return
      end
      json_response = @virtual_images_interface.get(id.to_i)
      image = json_response['virtualImage']
      image_config = image['config'] || {}
      image_volumes = image['volumes'] || []
      image_locations = image['locations'] || []
      image_files = json_response['cloudFiles'] || json_response['files']
      image_type = virtual_image_type_for_name_or_code(image['imageType'])
      image_type_display = image_type ? "#{image_type['name']}" : image['imageType']
      render_response(json_response, options, 'virtualImage') do
        get_available_virtual_image_types() # preload
        print_h1 "Virtual Image Details", [], options
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Labels" => lambda {|it| format_list(it['labels']) },
          "Type" => lambda {|it| image_type_display },
          "Operating System" => lambda {|it| it['osType'] ? it['osType']['name'] : "" }, 
          "Storage" => lambda {|it| !image['storageProvider'].nil? ? image['storageProvider']['name'] : 'Default' }, 
          "Size" => lambda {|it| image['rawSize'].nil? ? 'Unknown' : "#{Filesize.from("#{image['rawSize']} B").pretty}" },
          "Azure Publisher" => lambda {|it| image_config['publisher'] },
          "Azure Offer" => lambda {|it| image_config['offer'] },
          "Azure Sku" => lambda {|it| image_config['sku'] },
          "Azure Version" => lambda {|it| image_config['version'] },
          "Source" => lambda {|it| format_virtual_image_source(it) }, 
          "Tags" => lambda {|it| it['tags'] ? it['tags'].collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        description_cols.delete("Tags") if image['tags'].nil? || image['tags'].empty?
        if image['imageType'] == "azure-reference" || image['imageType'] == "azure"
          description_cols.delete("Size")
          description_cols.delete("Storage")
          description_cols["Source"] = lambda {|it| "#{bold}#{cyan}AZURE#{reset}#{cyan}" }
        else
          description_cols.delete("Azure Publisher")
          description_cols.delete("Azure Sku")
          description_cols.delete("Azure Offer")
          description_cols.delete("Azure Version")
        end
        advanced_description_cols = {
          #"OS Type" => lambda {|it| it['osType'] ? it['osType']['name'] : "" }, # displayed above as Operating System
          "Min Memory" => lambda {|it| it['minRam'].to_i != 0 ? Filesize.from("#{it['minRam']} B").pretty : "" },
          "Min Disk" => lambda {|it| it['minDisk'].to_i != 0 ? Filesize.from("#{it['minDisk']} B").pretty : "" },
          "Cloud Init?" => lambda {|it| format_boolean it['osType'] },
          "Install Agent?" => lambda {|it| format_boolean it['osType'] },
          "SSH Username" => lambda {|it| it['sshUsername'] },
          "SSH Password" => lambda {|it| it['sshPassword'] },
          "User Data" => lambda {|it| it['userData'] },
          "Owner" => lambda {|it| it['tenant'].instance_of?(Hash) ? it['tenant']['name'] : it['ownerId'] },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Tenants" => lambda {|it| format_tenants(it['accounts']) },
          "Auto Join Domain?" => lambda {|it| format_boolean it['isAutoJoinDomain'] },
          "VirtIO Drivers Loaded?" => lambda {|it| format_boolean it['virtioSupported'] },
          "VM Tools Installed?" => lambda {|it| format_boolean it['vmToolsInstalled'] },
          "Force Guest Customization?" => lambda {|it| format_boolean it['isForceCustomization'] },
          "Trial Version" => lambda {|it| format_boolean it['trialVersion'] },
          "Sysprep Enabled?" => lambda {|it| format_boolean it['isSysprep'] },
        }
        if options[:details]
          description_cols.merge!(advanced_description_cols)
        end
        print_description_list(description_cols, image)

        if image_volumes && !image_volumes.empty?
          print_h2 "Volumes", options
          image_volume_rows = image_volumes.collect do |image_volume|
            {name: image_volume['name'], size: Filesize.from("#{image_volume['rawSize']} B").pretty}
          end
          print cyan
          print as_pretty_table(image_volume_rows, [:name, :size])
          print cyan
          # print "\n", reset
        end

        if image_files && !image_files.empty?
          print_h2 "Files (#{image_files.size})"
          # image_files.each {|image_file|
          #   pretty_filesize = Filesize.from("#{image_file['size']} B").pretty
          #   print cyan,"  =  #{image_file['name']} [#{pretty_filesize}]", "\n"
          # }
          # size property changed to GB to match volumes
          # contentLength is bytes
          image_file_rows = image_files.collect do |image_file|
            {filename: image_file['name'], size: Filesize.from("#{image_file['contentLength'] || image_file['size']} B").pretty}
          end
          print cyan
          print as_pretty_table(image_file_rows, [:filename, :size])
          # print reset,"\n"
        end
        
        if image_locations && !image_locations.empty?
          print_h2 "Locations", options
          print as_pretty_table(image_locations, virtual_image_location_list_column_definitions.upcase_keys!, options)
        end

        if options[:details] && image_config && !image_config.empty?
          print_h2 "Config", options
          print cyan
          print as_description_list(image_config, image_config.keys, options)
          # print "\n", reset
        end

        print reset,"\n"
      end
      return 0, nil
  end

  def update(args)
    image_name = args[0]
    options = {}
    tenants_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [options]")
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          tenants_list = []
        else
          tenants_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--tags LIST', String, "Tags in the format 'name:value, name:value'. This will add and remove tags.") do |val|
        options[:tags] = val
      end
      opts.on('--add-tags TAGS', String, "Add Tags in the format 'name:value, name:value'. This will only add/update tags.") do |val|
        options[:add_tags] = val
      end
      opts.on('--remove-tags TAGS', String, "Remove Tags in the format 'name, name:value'. This removes tags, the :value component is optional and must match if passed.") do |val|
        options[:remove_tags] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a virtual image." + "\n" +
                    "[image] is required. This is the name or id of a virtual image."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)

    connect(options)
    
    virtual_image = find_virtual_image_by_name_or_id(image_name)
    return 1 if virtual_image.nil?

    passed_options = parse_passed_options(options)
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({virtual_image_object_key => passed_options}) unless passed_options.empty?
    else
      virtual_image_payload = passed_options
      if tenants_list
        virtual_image_payload['accounts'] = tenants_list
      end
      # metadata tags
      if options[:tags]
        virtual_image_payload['tags'] = parse_metadata(options[:tags])
      else
        # tags = prompt_metadata(options)
        # payload[virtual_image_object_key]['tags'] = tags of tags
      end
      # metadata tags
      if options[:add_tags]
        virtual_image_payload['addTags'] = parse_metadata(options[:add_tags])
      end
      if options[:remove_tags]
        virtual_image_payload['removeTags'] = parse_metadata(options[:remove_tags])
      end
      if virtual_image_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      payload = {'virtualImage' => virtual_image_payload}
    end
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.update(virtual_image['id'], payload)
      return
    end
    json_response = @virtual_images_interface.update(virtual_image['id'], payload)
    render_response(json_response, options, 'virtualImage') do
      print_green_success "Updated virtual image #{virtual_image['name']}"
      _get(virtual_image["id"], {}, options)
    end
    return 0, nil
    
  end

  def convert(args)
    image_name = args[0]
    options = {}
    # storageProviderId, format, name
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [options]")
      # opts.on('-n', '--name NAME', String, "Name (optional) of the new converted image. Default is name of the original image.") do |val|
      #   options[:options]['name'] = val
      # end
      # opts.on('-f', '--format FORMAT', String, "Format (optional). Default is 'qcow2'") do |val|
      #   options[:options]['format'] = val
      # end
      # opts.on('--storageProvider VALUE', String, "Storage Provider ID (optional). Default is storage provider of the original image.") do |val|
      #   options[:options]['storageProvider'] = val.to_s
      # end
      build_option_type_options(opts, options, convert_virtual_image_option_types)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Convert a virtual image to a new format." + "\n" +
        "[image] is required. This is the name or id of a virtual image."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:4)

    connect(options)

    virtual_image = find_virtual_image_by_name_or_id(image_name)
    return 1, "Virtual image not found for #{image_name}" if virtual_image.nil?

    passed_options = parse_passed_options(options)
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({virtual_image_object_key => passed_options}) unless passed_options.empty?
    else
      virtual_image_payload = passed_options
      source_format = virtual_image['imageType']
      v_prompt = Morpheus::Cli::OptionTypes.prompt(convert_virtual_image_option_types(source_format), options[:options], @api_client, {'virtualImageId': virtual_image['id']})
      v_prompt.deep_compact!
      virtual_image_payload.deep_merge!(v_prompt)
      # support "storageProviderId" too
      if virtual_image_payload['storageProviderId']
        virtual_image_payload['storageProvider'] = virtual_image_payload.delete('storageProviderId')
      end
      # convert "storageProvider":1 to "storageProvider": {"id":1}
      if virtual_image_payload['storageProvider'] && !virtual_image_payload['storageProvider'].is_a?(Hash)
        virtual_image_payload['storageProvider'] = {'id' => virtual_image_payload['storageProvider'].to_i }
      end
      payload = virtual_image_payload
    end
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.convert(virtual_image['id'], payload)
      return
    end
    json_response = @virtual_images_interface.convert(virtual_image['id'], payload)
    render_response(json_response, options, 'virtualImage') do
      print_green_success "Updated virtual image #{virtual_image['name']}"
      _get(virtual_image["id"], {}, options)
    end
    return 0, nil
  end

  def virtual_image_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      @virtual_images_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.virtual_image_types(params)
        return
      end
      json_response = @virtual_images_interface.virtual_image_types(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        image_types = json_response['virtualImageTypes']
        print_h1 "Morpheus Virtual Image Types"
        if image_types.nil? || image_types.empty?
          print cyan,"No image types found.",reset,"\n"
        else
          rows = image_types.collect do |lb_type|
            {name: lb_type['name'], code: lb_type['code']}
          end
          puts as_pretty_table(rows, [:name, :code], options)
        end
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    image_type_name = nil
    file_url = nil
    file_name = nil
    tenants_list = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t TYPE")
      opts.on( '-t', '--type TYPE', "Virtual Image Type" ) do |val|
        image_type_name = val
      end
      opts.on( '--filename NAME', "Image File Name. Specify a name for the uploaded file." ) do |val|
        file_name = val
      end
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of uploading local files." ) do |val|
        file_url = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud to scope image to, certain types require a cloud to be selected, eg. Azure Reference" ) do |val|
        # options[:cloud] = val
        options[:options]['cloud'] = val
      end
      opts.on( '--azure-offer OFFER', String, "Azure Reference offer value, only applies to Azure Reference" ) do |val|
        options[:options]['offer'] = val
      end
      opts.on( '--azure-sku SKU', String, "Azure SKU value, only applies to Azure Reference" ) do |val|
        options[:options]['sku'] = val
      end
      opts.on( '--azure-version VERSION', String, "Azure Version value, only applies to Azure Reference" ) do |val|
        options[:options]['version'] = val
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          tenants_list = []
        else
          tenants_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('-l', '--labels [LIST]', String, "Labels") do |val|
        options[:options]['labels'] = parse_labels(val)
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'name:value, name:value'") do |val|
        options[:tags] = val
      end
      # build_option_type_options(opts, options, add_virtual_image_option_types)
      # build_option_type_options(opts, options, add_virtual_image_advanced_option_types)
      build_standard_add_options(opts, options)

      opts.footer = "Create a virtual image."
    end
    optparse.parse!(args)
    # if args.count < 1
    # 	puts optparse
    # 	exit 1
    # end
    image_name = args[0]
    connect(options)

    # if image_type_name.nil?
    # 	puts "Virtual Image Type must be specified"
    # 	puts optparse
    # 	exit 1
    # end

    if image_name
      options[:options] ||= {}
      options[:options]['name'] ||= image_name
    end

     payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'virtualImage' => parse_passed_options(options)})
    else
      payload.deep_merge!({'virtualImage' => parse_passed_options(options)})
      virtual_image_payload = {}
      # v_prompt = Morpheus::Cli::OptionTypes.prompt(add_virtual_image_option_types, options[:options], @api_client, options[:params])
      if image_type_name
        image_type = virtual_image_type_for_name_or_code(image_type_name)
        # fix issue with api returning imageType vmware instead of vmdk
        if image_type.nil? && image_type_name == 'vmware'
          image_type = virtual_image_type_for_name_or_code('vmdk')
        elsif image_type.nil? && image_type_name == 'vmdk'
          image_type = virtual_image_type_for_name_or_code('vmware')
        end
        if image_type.nil?
          print_red_alert "Virtual Image Type not found by code '#{image_type_name}'"
          return 1
        end
        # options[:options] ||= {}
        # options[:options]['imageType'] ||= image_type['code']
      else
        image_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'imageType', 'fieldLabel' => 'Image Type', 'type' => 'select', 'optionSource' => 'virtualImageTypes', 'required' => true, 'description' => 'Select Virtual Image Type.', 'displayOrder' => 2}],options[:options],@api_client,{})
        image_type = virtual_image_type_for_name_or_code(image_type_prompt['imageType'])
      end

      # azure requires us to search the marketplace to select publisher, cloud, offerm sku
      if image_type['code'] == "azure-reference" || image_type['code'] == "azure"
        cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'optionSource' => 'clouds', 'required' => true, 'description' => 'Select Azure Cloud.', :fmt=>:natural}],options[:options],@api_client, {zoneTypeWhiteList: 'azure'})
        cloud_id = cloud_prompt['cloud'].to_i

        marketplace_config = prompt_azure_marketplace(cloud_id, options)
        virtual_image_payload['config'] ||= {}
        virtual_image_payload['config'].deep_merge!(marketplace_config)
      end

      my_option_types = add_virtual_image_option_types(image_type, !file_url)
      # if options[:no_prompt]
      #   my_option_types.each do |it| 
      #     if it['fieldContext'] == 'virtualImageFiles'
      #       opt['required'] = false
      #     end
      #   end
      # end
      v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      virtual_image_payload.deep_merge!(v_prompt)
      virtual_image_files = virtual_image_payload.delete('virtualImageFiles')
      upload_type = virtual_image_payload.delete('uploadType') # not used serverside
      virtual_image_payload['imageType'] = image_type['code']
      storage_provider_id = virtual_image_payload.delete('storageProviderId')
      if !storage_provider_id.to_s.empty?
        virtual_image_payload['storageProvider'] = {id: storage_provider_id}
      end
      if tenants_list
        virtual_image_payload['accounts'] = tenants_list
      end
      # metadata tags
        if options[:tags]
          tags = parse_metadata(options[:tags])
          virtual_image_payload['tags'] = tags if tags
        else
          # tags = prompt_metadata(options)
          # virtual_image_payload['tags'] = tags of tags
        end
      # fix issue with api returning imageType vmware instead of vmdk
      if virtual_image_payload && virtual_image_payload['imageType'] == 'vmware'
        virtual_image_payload['imageType'] == 'vmdk'
      end
      # no need to make second request anymore, just include virtualImage.url
      if file_url
        virtual_image_payload['url'] = file_url
        file_url = nil
      end
      #payload = {'virtualImage' => virtual_image_payload}
      payload.deep_merge!({'virtualImage' => virtual_image_payload})
    end

    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.create(payload)
      if file_url
        print_dry_run @virtual_images_interface.dry.upload_by_url(":id", file_url, file_name)
      elsif virtual_image_files && !virtual_image_files.empty?
        virtual_image_files.each do |key, filepath|
          print_dry_run @virtual_images_interface.dry.upload(":id", "(Contents of file #{filepath})")
        end
      end
      return
    end

    json_response = @virtual_images_interface.create(payload)
    virtual_image = json_response['virtualImage']

    # if options[:json]
    #   print JSON.pretty_generate(json_response)
    # elsif !options[:quiet]
    #   print "\n", cyan, "Virtual Image #{virtual_image['name']} created successfully", reset, "\n\n"
    # end

    # now upload the file, do this in the background maybe?
    if file_url
      unless options[:quiet]
        print cyan, "Uploading file by url #{file_url} ...", reset, "\n"
      end
      upload_json_response = @virtual_images_interface.upload_by_url(virtual_image['id'], file_url, file_name)
      # if options[:json]
      #   print JSON.pretty_generate(upload_json_response)
      # end
    elsif virtual_image_files && !virtual_image_files.empty?
      virtual_image_files.each do |key, filepath|
        unless options[:quiet]
          print cyan, "Uploading file (#{key}) #{filepath} ...", reset, "\n"
        end
        image_file = File.new(filepath, 'rb')
        upload_json_response = @virtual_images_interface.upload(virtual_image['id'], image_file, file_name)
        # if options[:json]
        #   print JSON.pretty_generate(upload_json_response)
        # end
      end
    else
      # puts cyan, "No files uploaded.", reset
    end

    render_response(json_response, options, 'virtualImage') do
      print_green_success "Added virtual image #{virtual_image['name']}"
      return _get(virtual_image["id"], {}, options)
    end
    return 0, nil
    
  end

  def add_file(args)
    file_url = nil
    file_name = nil
    do_gzip = false
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [filepath]")
      opts.on('--filename FILENAME', String, "Filename for uploaded file. Derived from [filepath] by default." ) do |val|
        file_name = val
      end
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of [filepath]" ) do |val|
        file_url = val
      end
      opts.on( nil, '--gzip', "Compress uploaded file" ) do
        do_gzip = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Upload a virtual image file." + "\n" +
                    "[image] is required. This is the name or id of a virtual image." + "\n" +
                    "[filepath] or --url is required. This is location of the virtual image file."
    end
    optparse.parse!(args)
    image_name = args[0]
    filepath = nil
    if file_url
      if args.count < 1
        puts optparse
        exit 1
      end
    else
      if args.count < 2
        puts optparse
        exit 1
      end
      filepath = args[1]
    end

    connect(options)

    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      @virtual_images_interface.setopts(options)
      if file_url
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload_by_url(image['id'], file_url, file_name)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file by url #{file_url} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload_by_url(image['id'], file_url, file_name)
        if options[:json]
          print JSON.pretty_generate(json_response)
        elsif !options[:quiet]
          print "\n", cyan, "Virtual Image #{image['name']} successfully updated.", reset, "\n\n"
          get([image['id']])
        end
      else
        image_file = File.new(filepath, 'rb')
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload(image['id'], image_file, file_name, do_gzip)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file #{filepath} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload(image['id'], image_file, file_name, do_gzip)
        if options[:json]
          print JSON.pretty_generate(json_response)
        elsif !options[:quiet]
          print "\n", cyan, "Virtual Image #{image['name']} successfully updated.", reset, "\n\n"
          get([image['id']])
        end
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_file(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [filename]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    image_name = args[0]
    filename = args[1]
    connect(options)
    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image filename #{filename}?")
        return 9, "aborted"
      end
      @virtual_images_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.destroy_file(image['id'], filename)
        return
      end
      json_response = @virtual_images_interface.destroy_file(image['id'], filename)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        print "\n", cyan, "Virtual Image #{image['name']} filename #{filename} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [location]")
      opts.on('--remove-from-cloud [true|false]', String, "Remove from all clouds. Default is true.") do |val|
        options[:options]['removeFromCloud'] = ['','true','on'].include?(val.to_s)
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a virtual image.
[image] is required. This is the name or id of a virtual image.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    image = find_virtual_image_by_name_or_id(args[0])
    return 1, "virtual image not found for '#{args[0]}'" if image.nil?
    params.merge!(parse_query_options(options))
    # Delete prompt
    # [ X ] Remove from all clouds
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'removeFromCloud', 'fieldLabel' => 'Remove from all clouds', 'type' => 'checkbox', 'defaultValue' => true, 'required' => true, 'description' => "Remove from all clouds"}], options[:options], @api_client)
    remove_from_cloud = v_prompt['removeFromCloud'].to_s == 'true' || v_prompt['removeFromCloud'].to_s == 'on'
    params['removeFromCloud'] = remove_from_cloud
    
    # Delete confirmation
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image #{image['name']}?")
      return 9, "aborted"
    end
    
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.destroy(image['id'], params)
      return
    end
    json_response = @virtual_images_interface.destroy(image['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed virtual image #{image['name']}"
    end
    return 0, nil
  end

  def list_locations(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List virtual image locations for a specific virtual image.
[image] is required. This is the name or id of a virtual image.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 1
      options[:phrase] = args[1..-1].join(" ")
    end
    connect(options)
    image = find_virtual_image_by_name_or_id(args[0])
    return 1, "virtual image not found for '#{args[0]}'" if image.nil?
    params.merge!(parse_list_options(options))
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.list_locations(image['id'], params)
      return
    end
    json_response = @virtual_images_interface.list_locations(image['id'], params)
    records = json_response['locations']
    render_response(json_response, options, 'virtualImages') do
      title = "Virtual Image Locations"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles
      if records.empty?
        print cyan,"No virtual image locations found.",reset,"\n"
      else
        print as_pretty_table(records, virtual_image_location_list_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_location(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [location]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Get details about a virtual image location.
[image] is required. This is the name or id of a virtual image.
[location] is required. This is the name or id of a virtual image location.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    image = find_virtual_image_by_name_or_id(args[0])
    return 1, "virtual image not found for '#{args[0]}'" if image.nil?
    location = find_virtual_image_location_by_name_or_id(image['id'], args[1])
    return 1, "location not found for '#{args[1]}'" if location.nil?
    params.merge!(parse_query_options(options))
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.get_location(image['id'], location['id'])
      return 0, nil
    end
    # json_response = @virtual_images_interface.get(image['id'], location['id'])
    json_response = {'location' => location} # skip redundant request
    render_response(json_response, options, 'location') do
      location = json_response['location']
      volumes = location['volumes'] || []
      print_h1 "Virtual Image Location Details", [], options
      print_description_list(virtual_image_location_column_definitions, location, options)
      if volumes && !volumes.empty?
        print_h2 "Volumes", options
        volume_rows = volumes.collect do |volume|
          {name: volume['name'], size: Filesize.from("#{volume['rawSize']} B").pretty}
        end
        print cyan
        print as_pretty_table(volume_rows, [:name, :size], options)
        print cyan
        # print "\n", reset
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def remove_location(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [location]")
      opts.on('--remove-from-cloud [true|false]', String, "Remove from cloud. Default is true.") do |val|
        options[:options]['removeFromCloud'] = ['','true','on'].include?(val.to_s)
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a virtual image location.
[image] is required. This is the name or id of a virtual image.
[location] is required. This is the name or id of a virtual image location.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    image = find_virtual_image_by_name_or_id(args[0])
    return 1, "virtual image not found for '#{args[0]}'" if image.nil?
    location = find_virtual_image_location_by_name_or_id(image['id'], args[1])
    return 1, "location not found for '#{args[1]}'" if location.nil?

    params.merge!(parse_query_options(options))
    
    # Delete prompt
    # [ X ] Remove from cloud
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'removeFromCloud', 'fieldLabel' => 'Remove from cloud', 'type' => 'checkbox', 'defaultValue' => true, 'required' => true, 'description' => "Remove from cloud"}], options[:options], @api_client)
    remove_from_cloud = v_prompt['removeFromCloud'].to_s == 'true' || v_prompt['removeFromCloud'].to_s == 'on'
    params['removeFromCloud'] = remove_from_cloud
    
    # Delete confirmation
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image location #{location['id']}?")
      return 9, "aborted"
    end
    
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.destroy_location(image['id'], location['id'], params)
      return
    end
    json_response = @virtual_images_interface.destroy_location(image['id'], location['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed virtual image location #{location['id']}"
    end
    return 0, nil
  end

  def download(args)
    full_command_string = "#{command_name} download #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download a virtual image as a .zip file.\n" + 
                    "[image] is required. This is the name or id of a virtual image.\n" +
                    "[local-file] is required. This is the full local filepath for the downloaded zip file."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    
    virtual_image = find_virtual_image_by_name_or_id(args[0])
    return 1 if virtual_image.nil?
    outfile = args[1]
    # if outfile.end_with?(".zip")
    #   print_red_alert "[local-file] is invalid. It must use extension .zip: #{outfile}"
    #   return 1
    # end
    outfile = File.expand_path(outfile)
    if Dir.exist?(outfile)
      raise_command_error "[local-file] is invalid. It is the name of an existing directory: #{outfile}", args, optparse
    end
    destination_dir = File.dirname(outfile)
    if !Dir.exist?(destination_dir)
      if do_mkdir
        print cyan,"Creating local directory #{destination_dir}",reset,"\n"
        FileUtils.mkdir_p(destination_dir)
      else
        raise_command_error "[local-file] is invalid. Directory not found: #{destination_dir}", args, optparse
      end
    end
    if File.exist?(outfile)
      if do_overwrite
        # uhh need to be careful wih the passed filepath here..
        # don't delete, just overwrite.
        # File.delete(outfile)
      else
        raise_command_error "[local-file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file.", args, optparse
      end
    end
    
    @virtual_images_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @virtual_images_interface.dry.download_chunked(virtual_image['id'], outfile), full_command_string
      return 0, nil
    end
    if !options[:quiet]
      print cyan + "Downloading archive file #{virtual_image['name']} to #{outfile} ... "
    end

    http_response = @virtual_images_interface.download_chunked(virtual_image['id'], outfile)

    # FileUtils.chmod(0600, outfile)
    success = http_response.code.to_i == 200
    if success
      if !options[:quiet]
        print green + "SUCCESS" + reset + "\n"
      end
      return 0, nil
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
      return 1, "Error downloading file"
    end
  end

  private
  
  def find_virtual_image_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_virtual_image_by_id(val)
    else
      return find_virtual_image_by_name(val)
    end
  end

  def find_virtual_image_by_id(id)
    begin
      json_response = @virtual_images_interface.get(id.to_i)
      return json_response['virtualImage']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Virtual Image not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_virtual_image_by_name(name)
    json_results = @virtual_images_interface.list({name: name.to_s})
    records = json_results['virtualImages']
    if records.empty?
      print_red_alert "Virtual Image not found by name #{name}"
      return nil
    elsif records.size > 1
      print_red_alert "More than one Virtual Image found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(records, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      virtual_image = records[0]
    end
    return virtual_image
  end


  def get_available_virtual_image_types(refresh=false)
    if !@available_virtual_image_types || refresh
      @available_virtual_image_types = @virtual_images_interface.virtual_image_types['virtualImageTypes'] #  || []
    end
    return @available_virtual_image_types
  end
  
  def virtual_image_type_for_name_or_code(name)
    return get_available_virtual_image_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  def add_virtual_image_option_types(image_type = nil, include_file_selection=true)
    
    # todo: make api provide virtualImageType and its optionTypes.
    tmp_option_types = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      #{'fieldName' => 'imageType', 'fieldLabel' => 'Image Type', 'type' => 'select', 'optionSource' => 'virtualImageTypes', 'required' => true, 'description' => 'Select Virtual Image Type.', 'displayOrder' => 2},
      {'fieldName' => 'osType', 'fieldLabel' => 'Operating System', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false, 'description' => 'Select Operating System.', 'displayOrder' => 3},
      {'fieldName' => 'minRamGB', 'fieldLabel' => 'Minimum Memory (GB)', 'type' => 'number', 'required' => false, 'description' => 'Minimum Memory (GB)', 'displayOrder' => 4},
      # {'fieldName' => 'minDiskGB', 'fieldLabel' => 'Minimum Disk (GB)', 'type' => 'number', 'required' => false, 'description' => 'Minimum Memory (GB)', 'displayOrder' => 4},
      {'fieldName' => 'isCloudInit', 'fieldLabel' => 'Cloud Init Enabled?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Cloud Init Enabled?', 'displayOrder' => 5},
      {'fieldName' => 'installAgent', 'fieldLabel' => 'Install Agent?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Install Agent?', 'displayOrder' => 6},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text', 'required' => false, 'description' => 'Enter an SSH Username', 'displayOrder' => 7},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false, 'description' => 'Enter an SSH Password', 'displayOrder' => 8},
      {'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Bucket', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.', 'displayOrder' => 9},
      {'fieldName' => 'userData', 'fieldLabel' => 'Cloud-Init User Data', 'type' => 'textarea', 'required' => false, 'displayOrder' => 10},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private', 'displayOrder' => 40},
      {'fieldName' => 'isAutoJoinDomain', 'fieldLabel' => 'Auto Join Domain?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Auto Join Domain?', 'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'virtioSupported', 'fieldLabel' => 'VirtIO Drivers Loaded?', 'type' => 'checkbox', 'defaultValue' => 'on', 'required' => false, 'description' => 'VirtIO Drivers Loaded?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'vmToolsInstalled', 'fieldLabel' => 'VM Tools Installed?', 'type' => 'checkbox', 'defaultValue' => 'on', 'required' => false, 'description' => 'VM Tools Installed?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'isForceCustomization', 'fieldLabel' => 'Force Guest Customization?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Force Guest Customization?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'trialVersion', 'fieldLabel' => 'Trial Version', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Trial Version',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'isSysprep', 'fieldLabel' => 'Sysprep Enabled?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Sysprep Enabled?',  'category' => 'advanced', 'displayOrder' => 40}      
    ]

    image_type_code = image_type ? image_type['code'] : nil
    if image_type_code
      if image_type_code == 'ami'
        tmp_option_types << {'fieldName' => 'externalId', 'fieldLabel' => 'AMI id', 'type' => 'text', 'required' => false, 'displayOrder' => 11}
        if include_file_selection
          tmp_option_types << {'fieldName' => 'imageFile', 'fieldLabel' => 'Image File', 'type' => 'file', 'required' => false, 'displayOrder' => 12}
        end
      elsif image_type_code == 'vmware' || image_type_code == 'vmdk'
        if include_file_selection
          tmp_option_types << {'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageFile', 'fieldLabel' => 'OVF File', 'type' => 'file', 'required' => false, 'displayOrder' => 11}
          tmp_option_types << {'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageDescriptorFile', 'fieldLabel' => 'VMDK File', 'type' => 'file', 'required' => false, 'displayOrder' => 12}
        end
      elsif image_type_code == 'pxe'
        tmp_option_types << {'fieldName' => 'config.menu', 'fieldLabel' => 'Menu', 'type' => 'text', 'required' => false, 'displayOrder' => 11}
        tmp_option_types << {'fieldName' => 'imagePath', 'fieldLabel' => 'Image Path', 'type' => 'text', 'required' => true, 'displayOrder' => 12}
        tmp_option_types.reject! {|opt| ['isCloudInit', 'installAgent', 'sshUsername', 'sshPassword'].include?(opt['fieldName'])}
      elsif image_type_code == 'azure' || image_type_code == 'azure-reference'
        # Azure Marketplace Prompt happens elsewhere
        tmp_option_types.reject! {|opt| ['storageProviderId', 'userData', 'sshUsername', 'sshPassword'].include?(opt['fieldName'])}
      else
        if include_file_selection
          tmp_option_types << {'code' => 'virtualImage.uploadType', 'fieldName' => 'uploadType', 'fieldLabel' => 'Create Image ID', 'type' => 'select', 'selectOptions' => [{'name' => 'File', 'value' => 'file'},{'name' => 'URL/Path', 'value' => 'url'},{'name' => 'None', 'value' => 'none'}], 'defaultValue' => 'file', 'required' => false, 'description' => 'Choose upload type: file, url or none', 'displayOrder' => 11}
          tmp_option_types << {'dependsOnCode' => 'virtualImage.uploadType:file', 'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageFile', 'fieldLabel' => 'Image File', 'type' => 'file', 'required' => false, 'description' => 'Choose an image file to upload', 'displayOrder' => 12}
          tmp_option_types << {'dependsOnCode' => 'virtualImage.uploadType:url', 'fieldName' => 'url', 'fieldLabel' => 'URL/Path', 'type' => 'text', 'required' => false, 'description' => 'Enter URL/Path to virtual image file(s)', 'displayOrder' => 13}
        end
      end
    end

    return tmp_option_types
  end

  def update_virtual_image_option_types(image_type = nil)
    list = add_virtual_image_option_types(image_type)
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
    }
    list
  end

  def convert_virtual_image_option_types(source_format=nil)
    [
      {'shorthand' => '-f', 'fieldName' => 'format', 'type' => 'select', 'fieldLabel' => 'Format', 'selectOptions' => get_convert_image_formats(source_format), 'required' => true, 'defaultValue' => (source_format == 'qcow2' ? nil : 'qcow2')},
      {'shorthand' => '-b', 'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Bucket', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider Bucket or File Share.'},
      {'shorthand' => '-n', 'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false}
    ]
  end

  def convert_source_types
    ["raw","qcow2","vmdk",'vmware', "vhd","ovf"]
  end

  def convert_destination_types
    #["raw", "qcow2", "vmdk",'vmware',"vhd","ovf"]
    convert_source_types
  end

  def get_convert_image_formats(source_format=nil)
    categories = [
      {'name' => 'QCOW2', 'value' => 'qcow2'},
      {'name' => 'VMDK', 'value' => 'ovf'},
      {'name' => 'VHD', 'value' => 'vhd'},
      {'name' => 'Raw', 'value' => 'raw'}
    ]
    # if source format (imageType) is not in the list, then no options
    # else reject the current value
    if source_format
      if !convert_source_types.include?(source_format.to_s.downcase)
        categories = []
      else
        categories = categories.select {|it| it['value'] != source_format.to_s.downcase }
      end
    end
    return categories
  end

  def format_tenants(accounts)
    if accounts && accounts.size > 0
      accounts = accounts.sort {|a,b| a['name'] <=> b['name'] }.uniq {|it| it['id'] }
      account_ids = accounts.collect {|it| it['id'] }
      account_names = accounts.collect {|it| it['name'] }
      "(#{account_ids.join(',')}) #{account_names.join(',')}"
    else
      ""
    end
  end
  
  def prompt_azure_marketplace(cloud_id, options)
    rtn = {}
    publisher_value, offer_value, sku_value, version_value = nil, nil, nil, nil

    # Marketplace Publisher & Offer
    marketplace_api_params = {'zoneId' => cloud_id}
    v_prompt = nil
    # API endpoints moved from /api/options to /api/options/azure...
    begin
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'offer', 'fieldLabel' => 'Azure Marketplace Offer', 'type' => 'typeahead', 'optionSourceType' => 'azure', 'optionSource' => 'searchAzureMarketplace', 'required' => true, 'description' => "Select Azure Marketplace Offer."}], options[:options],@api_client, marketplace_api_params)
    rescue => ex
      Morpheus::Logging::DarkPrinter.puts "Failed to load azure marketplace offers, trying older endpoint" if Morpheus::Logging.debug?
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'offer', 'fieldLabel' => 'Azure Marketplace Offer', 'type' => 'typeahead', 'optionSource' => 'searchAzureMarketplace', 'required' => true, 'description' => "Select Azure Marketplace Offer."}], options[:options],@api_client, marketplace_api_params)
    end
    # offer_value = v_prompt['marketplace']
    # actually need both offer and publisher of these to query correctly..sigh
    marketplace_option = Morpheus::Cli::OptionTypes.get_last_select()
    offer_value = marketplace_option['offer']
    publisher_value = marketplace_option['publisher']

    # SKU & VERSION
    if options[:options] && options[:options]['sku'] && options[:options]['version']
      # the value to match on is actually sku|version
      options[:options]['sku'] = options[:options]['sku'] + '|' + options[:options]['version']
    end
    sku_api_params = {'zoneId' => cloud_id, publisher: publisher_value, offer: offer_value}
    begin
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sku', 'fieldLabel' => 'Azure Marketplace SKU', 'type' => 'select', 'optionSourceType' => 'azure', 'optionSource' => 'searchAzureMarketplaceSkus', 'required' => true, 'description' => "Select Azure Marketplace SKU and Version, the format is SKU|Version"}], options[:options],@api_client, sku_api_params)
    rescue => ex
      Morpheus::Logging::DarkPrinter.puts "Failed to load azure marketplace offers, trying older endpoint" if Morpheus::Logging.debug?
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sku', 'fieldLabel' => 'Azure Marketplace SKU', 'type' => 'select', 'optionSource' => 'searchAzureMarketplaceSkus', 'required' => true, 'description' => "Select Azure Marketplace SKU and Version, the format is SKU|Version"}], options[:options],@api_client, sku_api_params)
    end
    # marketplace_option = Morpheus::Cli::OptionTypes.get_last_select()
    # sku_value = marketplace_option['sku']
    # version_value = marketplace_option['version']
    sku_value = v_prompt['sku']
    if sku_value && sku_value.include?("|")
      sku_value, version_value = sku_value.split("|")
    end

    rtn['publisher'] = publisher_value
    rtn['offer'] = offer_value
    rtn['sku'] = sku_value
    rtn['version'] = version_value
    return rtn
  end

  def format_virtual_image_source(virtual_image, return_color=cyan)
    out = ""
    if virtual_image['userUploaded']
      # out << "#{green}UPLOADED#{return_color}"
      out << "#{cyan}UPLOADED#{return_color}"
    elsif virtual_image['systemImage']
      out << "#{cyan}SYSTEM#{return_color}"
    else
      out << "#{cyan}SYNCED#{return_color}"
    end
    out
  end


  ## Virtual Image Locations

  def virtual_image_location_object_key
    "location"
  end

  def virtual_image_location_list_key
    "locations"
  end

  def find_virtual_image_location_by_name_or_id(virtual_image_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_virtual_image_location_by_id(virtual_image_id, val)
    else
      return find_virtual_image_location_by_name(virtual_image_id, val)
    end
  end

  def virtual_image_location_list_column_definitions
    virtual_image_location_column_definitions
  end

  def virtual_image_location_column_definitions
    {
      "ID" => 'id',
      "Name" => 'imageName',
      "Cloud" => lambda {|it| it['cloud']['name'] rescue '' }, 
      "Public" => lambda {|it| format_boolean(it['isPublic']) },
      "Region" => lambda {|it| it['imageRegion'] }, 
      "External ID" => lambda {|it| it['externalId'] }, 
      "Price Plan" => lambda {|it| it['pricePlan'] ? it['pricePlan']['name'] : nil }, 
      # "Virtual Image" => lambda {|it| it['virtualImage']['name'] rescue '' }, 
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end


  def find_virtual_image_location_by_id(virtual_image_id, id)
    begin
      json_response = @virtual_images_interface.get_location(virtual_image_id, id.to_i)
      return json_response[virtual_image_location_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Virtual Image Location not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_virtual_image_location_by_name(virtual_image_id, name)
    json_response = @virtual_images_interface.list_locations(virtual_image_id, {imageName: name.to_s})
    virtual_image_locations = json_response[virtual_image_location_list_key]
    if virtual_image_locations.empty?
      print_red_alert "Virtual Image Location not found by name '#{name}'"
      return nil
    elsif virtual_image_locations.size > 1
      print_red_alert "#{virtual_image_locations.size} Virtual Image Locations found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(virtual_image_locations, {"ID" => 'id', "NAME" => 'imageName'}, {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return virtual_image_locations[0]
    end
  end


end
