require 'morpheus/cli/cli_command'
# require 'morpheus/cli/commands/boot_scripts_command'
# require 'morpheus/cli/commands/preseed_scripts_command'

class Morpheus::Cli::ImageBuilderCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  set_command_name :'image-builder' # :'image-builds'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :run
  register_subcommands :'list-runs' => :list_executions

  # err, these are kept under this namespace
  register_subcommands :'boot-scripts' => :boot_scripts
  register_subcommands :'preseed-scripts' => :preseed_scripts

  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @image_builder_interface = @api_client.image_builder
    @image_builds_interface = @image_builder_interface.image_builds
    @boot_scripts_interface = @image_builder_interface.boot_scripts
    @preseed_scripts_interface = @image_builder_interface.preseed_scripts
    @groups_interface = @api_client.groups
    @clouds_interface = @api_client.clouds
    @instances_interface = @api_client.instances
    @instance_types_interface = @api_client.instance_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def boot_scripts(args)
    Morpheus::Cli::BootScriptsCommand.new.handle(args)
  end

  def preseed_scripts(args)
    Morpheus::Cli::PreseedScriptsCommand.new.handle(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @image_builds_interface.dry.list(params)
        return
      end

      json_response = @image_builds_interface.list(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      image_builds = json_response['imageBuilds']
      title = "Morpheus Image Builds"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if image_builds.empty?
        print cyan,"No image builds found.",reset,"\n"
      else
        rows = image_builds.collect {|image_build| 
            last_result = image_build['lastResult']
            status_str = format_image_build_status(image_build, cyan)
            result_str = format_image_build_execution_result(last_result, cyan)
            row = {
              id: image_build['id'],
              name: image_build['name'],
              # description: image_build['description'],
              type: image_build['type'] ? image_build['type']['name'] : 'N/A',
              group: image_build['site'] ? image_build['site']['name'] : '',
              cloud: image_build['zone'] ? image_build['zone']['name'] : '',
              executionCount: image_build['executionCount'] ? image_build['executionCount'].to_i : '',
              lastRunDate: last_result ? format_local_dt(last_result['startDate']) : '',
              status: status_str,
              result: result_str
            }
            row
          }
          columns = [:id, :name, :type, {:lastRunDate => {label: 'Last Run Date'.upcase}}, 
                      :status, {:result => {max_width: 60}}]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image-build]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [image-build]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @image_builds_interface.dry.get(args[0].to_i)
        else
          print_dry_run @image_builds_interface.dry.list({name:args[0]})
        end
        return
      end
      image_build = find_image_build_by_name_or_id(args[0])
      return 1 if image_build.nil?
      # json_response = {'imageBuild' => image_build}  # skip redundant request
      json_response = @image_builds_interface.get(image_build['id'])
      image_build = json_response['imageBuild']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      print_h1 "Image Build Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        # "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Name" => 'name',
        "Description" => 'description',
        "Group" => lambda {|it| it['site'] ? it['site']['name'] : '' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Plan" => lambda {|it| 
          if it['config'] && it['config']['plan']
            it['config']['plan']['code'] # name needed!
          else
            ""
          end
        },
        "Image" => lambda {|it| 
          if it['config'] && it['config']['template']
            it['config']['template']
          elsif it['config'] && it['config']['image']
            it['config']['image']
          else
            ""
          end
        },
        "Boot Script" => lambda {|it| 
          if it['bootScript']
            if it['bootScript'].kind_of?(Hash)
               it['bootScript']['fileName'] || it['bootScript']['name']  || it['bootScript']['id']
            else
              it['bootScript']
            end
          else
            ""
          end
        },
        "Preseed Script" => lambda {|it| 
          if it['preseedScript']
            if it['preseedScript'].kind_of?(Hash)
              it['preseedScript']['fileName'] || it['preseedScript']['name'] || it['preseedScript']['id']
            else
              it['preseedScript']
            end
          else
            ""
          end
        },
        # Additional Scripts
        "Scripts" => lambda {|it|
          if it['scripts']
            script_names = it['scripts'].collect do |script|
              if script.kind_of?(Hash)
                script['name']
              else
                script
              end
            end
            script_names.join(", ")
          else
            ""
          end
        },
        "SSH Username" => lambda {|it| it['sshUsername'] },
        "SSH Password" => lambda {|it| it['sshPassword'].to_s.empty? ? '' : '(hidden)' }, # api returns masked
        "Storage Provider" => lambda {|it| 
          if it['storageProvider']
            if it['storageProvider'].kind_of?(Hash)
              it['storageProvider']['name'] || it['storageProvider']['id']
            else
              it['storageProvider']
            end
          else
            ""
          end
        },
        "Build Output Name" => lambda {|it| it['buildOutputName'] },
        "Conversion Formats" => lambda {|it| it['conversionFormats'] },
        "Cloud Init?" => lambda {|it| it['isCloudInit'] ? 'Yes' : 'No' },
        "Keep Results" => lambda {|it| it['keepResults'].to_i == 0 ? 'All' : it['keepResults'] },
        "Last Run Date" => lambda {|it| 
          last_result = it['lastResult']
          last_result ? format_local_dt(last_result['startDate']) : ''
        },
        "Status" => lambda {|it| format_image_build_status(it) },
      }
      print_description_list(description_cols, image_build)

      #json_response = @image_builds_interface.list_executions(image_build['id'], params)
      image_build_executions = json_response['imageBuildExecutions'] # yep, show() returns the last 100 run
      image_build_executions = image_build_executions.first(10) # limit to just 10
      if image_build_executions && image_build_executions.size > 0
        print_h2 "Recent Executions"
        print_image_build_executions_table(image_build_executions, opts={})
        print_results_pagination({size:image_build_executions.size,total:image_build['executionCount'].to_i}, {:label => "execution", :n_label => "executions"})
      else
        puts "\nNo executions found.\n"
      end

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      # build_option_type_options(opts, options, add_image_build_option_types(false))
      opts.on( '-t', '--type TYPE', "Image Build Type" ) do |val|
        options['type'] = val
      end
      opts.on('--name VALUE', String, "Name") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        options['description'] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options['group'] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options['cloud'] = val
      end
      # opts.on( '-e', '--env ENVIRONMENT', "Environment" ) do |val|
      #   options[:cloud] = val
      # end
      opts.on('--config JSON', String, "Instance Config JSON") do |val|
        options['config'] = JSON.parse(val.to_s)
      end
      opts.on('--config-yaml YAML', String, "Instance Config YAML") do |val|
        options['config'] = YAML.load(val.to_s)
      end
      opts.on('--config-file FILE', String, "Instance Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      # opts.on('--configFile FILE', String, "Instance Config from a local file") do |val|
      #   options['configFile'] = val.to_s
      # end
      opts.on('--bootScript VALUE', String, "Boot Script ID") do |val|
        options['bootScript'] = val.to_s
      end
      opts.on('--bootCommand VALUE', String, "Boot Command. This can be used in place of a bootScript") do |val|
        options['bootCommand'] = val.to_s
      end
      opts.on('--preseedScript VALUE', String, "Preseed Script ID") do |val|
        options['preseedScript'] = val.to_s
      end
      opts.on('--scripts LIST', String, "Additional Scripts (comma separated names or ids)") do |val|
        # uh don't put commas or leading/trailing spaces in script names pl
        options['scripts'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--sshUsername VALUE', String, "SSH Username") do |val|
        options['sshUsername'] = val.to_s
      end
      opts.on('--sshPassword VALUE', String, "SSH Password") do |val|
        options['sshPassword'] = val.to_s
      end
      opts.on('--storageProvider VALUE', String, "Storage Provider ID") do |val|
        options['storageProvider'] = val.to_s
      end
      opts.on('--isCloudInit [on|off]', String, "Cloud Init?") do |val|
        options['isCloudInit'] = (val.to_s == 'on' || val.to_s == 'true')
      end
      opts.on('--buildOutputName VALUE', String, "Build Output Name") do |val|
        options['buildOutputName'] = val.to_s
      end
      opts.on('--conversionFormats VALUE', String, "Conversion Formats ie. ovf, qcow2, vhd") do |val|
        options['conversionFormats'] = val.to_s
      end
      opts.on('--keepResults VALUE', String, "Keep only the most recent builds. Older executions will be deleted along with their associated Virtual Images. The value 0 disables this functionality.") do |val|
        options['keepResults'] = val.to_i
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count > 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 0-1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support options top of --payload
        options.merge!(options[:options]) if options[:options] # so -O var= works..
        option_params = options.reject {|k,v| k.is_a?(Symbol) }
        payload.deep_merge!({'imageBuild' => option_params}) unless option_params.empty?
      else
        options.merge!(options[:options]) if options[:options] # so -O var= works..

        # use the -g GROUP or active group by default
        # options['group'] ||=  @active_group_id
        
        # support first arg as name instead of --name
        if args[0] && !options['name']
          options['name'] = args[0]
        end

        image_build_payload = prompt_new_image_build(options)
        return 1 if !image_build_payload
        payload = {'imageBuild' => image_build_payload}
      end
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @image_builds_interface.dry.create(payload)
        return
      end
      json_response = @image_builds_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        new_image_build = json_response['imageBuild']
        print_green_success "Added image build #{new_image_build['name']}"
        get([new_image_build['id']])
        # list([])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image-build] [options]")
      # build_option_type_options(opts, options, update_image_build_option_types(false))
      # cannot update type
      opts.on( '-t', '--type TYPE', "Image Build Type" ) do |val|
        options['type'] = val
      end
      opts.on('--name VALUE', String, "New Name") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        options['description'] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options['group'] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options['cloud'] = val
      end
      # opts.on( '-e', '--env ENVIRONMENT', "Environment" ) do |val|
      #   options[:cloud] = val
      # end
      opts.on('--config JSON', String, "Instance Config JSON") do |val|
        options['config'] = JSON.parse(val.to_s)
      end
      opts.on('--config-yaml YAML', String, "Instance Config YAML") do |val|
        options['config'] = YAML.load(val.to_s)
      end
      opts.on('--config-file FILE', String, "Instance Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      # opts.on('--configFile FILE', String, "Instance Config from a local file") do |val|
      #   options['configFile'] = val.to_s
      # end
      opts.on('--bootScript VALUE', String, "Boot Script ID") do |val|
        options['bootScript'] = val.to_s
      end
      opts.on('--bootCommand VALUE', String, "Boot Command. This can be used in place of a bootScript") do |val|
        options['bootCommand'] = val.to_s
      end
      opts.on('--preseedScript VALUE', String, "Preseed Script ID") do |val|
        options['preseedScript'] = val.to_s
      end
      opts.on('--scripts LIST', String, "Additional Scripts (comma separated names or ids)") do |val|
        # uh don't put commas or leading/trailing spaces in script names pl
        options['scripts'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--sshUsername VALUE', String, "SSH Username") do |val|
        options['sshUsername'] = val.to_s
      end
      opts.on('--sshPassword VALUE', String, "SSH Password") do |val|
        options['sshPassword'] = val.to_s
      end
      opts.on('--storageProvider VALUE', String, "Storage Provider ID") do |val|
        options['storageProvider'] = val.to_s
      end
      opts.on('--isCloudInit [on|off]', String, "Cloud Init?") do |val|
        options['isCloudInit'] = (val.to_s == 'on' || val.to_s == 'true')
      end
      opts.on('--buildOutputName VALUE', String, "Build Output Name") do |val|
        options['buildOutputName'] = val.to_s
      end
      opts.on('--conversionFormats VALUE', String, "Conversion Formats ie. ovf, qcow2, vhd") do |val|
        options['conversionFormats'] = val.to_s
      end
      # opts.on('--keepResultsEnabled [on|off]', String, "Delete Old Results. Enables the Keep Results option") do |val|
      #   options['keepResultsEnabled'] = (val.to_s == 'on' || val.to_s == 'true')
      # end
      opts.on('--keepResults VALUE', String, "Keep only the most recent builds. Older executions will be deleted along with their associated Virtual Images. The value 0 disables this functionality.") do |val|
        options['keepResults'] = val.to_i
        # 0 disables it
        # options['deleteOldResults'] = (options['keepResults'] > 0)
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      image_build = find_image_build_by_name_or_id(args[0])
      return 1 if !image_build
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support options top of --payload
        options.merge!(options[:options]) if options[:options] # so -O var= works..
        option_params = options.reject {|k,v| k.is_a?(Symbol) }
        payload.deep_merge!({'imageBuild' => option_params}) unless option_params.empty?
      else
        options.merge!(options[:options]) if options[:options] # so -O var= works..
        image_build_payload = prompt_edit_image_build(image_build, options)
        return 1 if !image_build_payload
        payload = {'imageBuild' => image_build_payload}
      end
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @image_builds_interface.dry.update(image_build["id"], payload)
        return
      end
      json_response = @image_builds_interface.update(image_build["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated image build #{image_build['name']}"
        get([image_build['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image-build]")
      opts.on( '-K', '--keep-virtual-images', "Preserve associated virtual images" ) do
        query_params['keepVirtualImages'] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [image-build]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      image_build = find_image_build_by_name_or_id(args[0])
      return 1 if image_build.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the image build: #{image_build['name']}?")
        return 9, "aborted command"
      end
      if query_params['keepVirtualImages'].nil?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'keepVirtualImages', 'type' => 'checkbox', 'fieldLabel' => 'Keep Virtual Images?', 'required' => false, 'defaultValue' => false, 'description' => 'Preserve associated virtual images. By default, they are deleted as well.'}],options,@api_client,{})
        query_params['keepVirtualImages'] = v_prompt['keepVirtualImages']
      end
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @image_builds_interface.dry.destroy(image_build['id'], query_params)
        return 0
      end
      json_response = @image_builds_interface.destroy(image_build['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed image build #{image_build['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def run(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image-build]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [image-build]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      image_build = find_image_build_by_name_or_id(args[0])
      return 1 if image_build.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to run the image build: #{image_build['name']}?")
        return 9, "aborted command"
      end
      @image_builds_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @image_builds_interface.dry.run(image_build['id'], query_params)
        return 0
      end
      json_response = @image_builds_interface.run(image_build['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "New run started for image build #{image_build['name']}"
        get([image_build['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_executions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[image-build]")
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
      opts.footer = "List executions for an image build."
      opts.footer = "Display a list of executions for an image build.\n"
                    "[image-build] is the name or id of an image build."
    end
    optparse.parse!(args)
    if args.count > 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    image_build = find_image_build_by_name_or_id(args[0])
    return 1 if image_build.nil?
    

    params = {}
    [:phrase, :offset, :max, :sort, :direction].each do |k|
      params[k] = options[k] unless options[k].nil?
    end
    @image_builds_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @image_builds_interface.dry.list_executions(image_build['id'], params)
      return 0
    end
    json_response = @image_builds_interface.list_executions(image_build['id'], params)
    if options[:json]
      puts JSON.pretty_generate(json_response)
      return 0
    end
    image_build = json_response['imageBuild']
    image_build_executions = json_response['imageBuildExecutions']
    print_h1 "Image Build Executions: [#{image_build['id']}] #{image_build['name']}"
    print cyan
    if image_build_executions && image_build_executions.size > 0
      print_image_build_executions_table(image_build_executions, opts={})
      print_results_pagination(json_response, {:label => "execution", :n_label => "executions"})
    end

    return 0
  end

  def delete_execution(args)
    puts "todo: implement me"
    return 0
  end

  private

  def get_available_image_build_types()
    [
      {'name' => 'VMware', 'code' => 'vmware', 'instanceType' => {'code' => 'vmware'}},
      {'name' => 'KVM', 'code' => 'kvm', 'instanceType' => {'code' => 'kvm'}}
    ]
  end

  def get_available_image_build_types_dropdown(group=nil, cloud=nil)
    get_available_image_build_types().collect {|it| 
      {'name' => it['name'], 'value' => it['code']}
    }
  end

  def add_image_build_option_types(connected=true)
    [
      {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_image_build_types_dropdown(), 'required' => true, 'description' => 'Choose the type of image build.'},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this image build.'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true},
      #{'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => [], 'required' => true},
      # tons more, this isn't used anymore though..
    ]
  end

  def update_image_build_option_types(connected=true)
    list = add_image_build_option_types(connected)
    # list = list.reject {|it| ["group"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

 def find_image_build_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_image_build_by_id(val)
    else
      return find_image_build_by_name(val)
    end
  end

  def find_image_build_by_id(id)
    begin
      json_response = @image_builds_interface.get(id.to_i)
      return json_response['imageBuild']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Image Build not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_image_build_by_name(name)
    image_builds = @image_builds_interface.list({name: name.to_s})['imageBuilds']
    if image_builds.empty?
      print_red_alert "Image Build not found by name #{name}"
      return nil
    elsif image_builds.size > 1
      print_red_alert "#{image_builds.size} image builds found by name #{name}"
      # print_image_builds_table(image_builds, {color: red})
      rows = image_builds.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print as_pretty_table(rows, [:id, :name], {color:red})
      print reset,"\n"
      return nil
    else
      return image_builds[0]
    end
  end

  def format_image_build_status(image_build, return_color=cyan)
    out = ""
    return out if !image_build
    if image_build && image_build['lastResult']
      out << format_image_build_execution_status(image_build['lastResult'])
    else
      out << ""
    end
    out
  end

  def format_image_build_execution_status(image_build_execution, return_color=cyan)
    return "" if !image_build_execution
    out = ""
    status_string = image_build_execution['status']
    if status_string == 'running'
      out <<  "#{cyan}#{bold}#{status_string.upcase}#{reset}#{return_color}"
    elsif status_string == 'success'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'failed'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'pending'
      out <<  "#{cyan}#{status_string.upcase}#{return_color}"
    elsif !status_string.to_s.empty?
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    else
      #out <<  "#{cyan}No Executions#{return_color}"
    end
    out
  end

  def format_image_build_execution_result(image_build_execution, return_color=cyan)
    return "" if !image_build_execution
    out = ""
    status_string = image_build_execution['status']
    if status_string == 'running' # || status_string == 'pending'
      out << generate_usage_bar(image_build_execution['statusPercent'], 100, {max_bars: 10, bar_color: cyan})
      out << return_color if return_color
    end
    if image_build_execution['tempInstance'].to_s != ''
      out << " Instance:"
      out << " [#{image_build_execution['tempInstance']['id']}] #{image_build_execution['tempInstance']['name']}"
      out << " -"
    end
    if image_build_execution['statusMessage'].to_s != ''
      out << " #{image_build_execution['statusMessage']}"
    end
    if image_build_execution['errorMessage'].to_s != ''
      out << " #{red}#{image_build_execution['errorMessage']}#{return_color}"
    end
    if image_build_execution['virtualImages']
      img_count = image_build_execution['virtualImages'].size
      if img_count == 1
        out << " Virtual Image:"
      elsif img_count > 1
        out << "(#{img_count}) Virtual Images:"
      end
      image_build_execution['virtualImages'].each do |virtual_image|
        out << " [#{virtual_image['id']}] #{virtual_image['name']}#{return_color}"
      end
    end
    out.strip #.squeeze(' ')
  end

  def print_image_build_executions_table(executions, opts={})
    table_color = opts[:color] || cyan
    rows = executions.collect do |execution|
      {
        id: execution['id'],
        build: execution['buildNumber'],
        createdBy: execution['createdBy'] ? execution['createdBy']['username'] : nil,
        start: execution['startDate'] ? format_local_dt(execution['startDate']) : '',
        end: execution['endDate'] ? format_local_dt(execution['endDate']) : '',
        duration: format_duration(execution['startDate'], execution['endDate']),
        status: format_image_build_execution_status(execution, table_color),
        result: format_image_build_execution_result(execution, table_color)
      }
    end

    term_width = current_terminal_width()
    result_col_width = 60
    if term_width > 250
      result_col_width += 100
    end
    columns = [
      #:id,
      :build,
      {:createdBy => {:display_name => "CREATED BY"} },
      :start,
      :end,
      :duration,
      {:status => {:display_name => "STATUS"} },
      {:result => {:display_name => "RESULT", :max_width => result_col_width} }
    ]
    # # custom pretty table columns ...
    # if options[:include_fields]
    #   columns = options[:include_fields]
    # end
    print table_color
    print as_pretty_table(rows, columns, opts)
    print reset
  end

  # def get_available_boot_scripts()
  #   boot_scripts_dropdown = []
  #   scripts = @boot_scripts_interface.list({max:1000})['bootScripts']
  #   scripts.each do |it| 
  #     boot_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id']}
  #   end
  #   boot_scripts_dropdown << {'name'=>'Custom','value'=> 'custom'}
  #   return boot_scripts_dropdown
  # end

  def get_available_boot_scripts(refresh=false)
    if !@available_boot_scripts || refresh
      # option_results = options_interface.options_for_source('bootScripts',{})['data']
      boot_scripts_dropdown = []
      scripts = @boot_scripts_interface.list({max:1000})['bootScripts']
      scripts.each do |it| 
        boot_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id'],'id'=>it['id']}
      end
      boot_scripts_dropdown << {'name'=>'Custom','value'=> 'custom','id'=> 'custom'}
      @available_boot_scripts = boot_scripts_dropdown
    end
    #puts "available_boot_scripts() rtn: #{@available_boot_scripts.inspect}"
    return @available_boot_scripts
  end

  def find_boot_script(val)
    if val.nil? || val.to_s.empty?
      return nil
    else
      return get_available_boot_scripts().find { |it| 
        (it['id'].to_s.downcase == val.to_s.downcase) || 
        (it['name'].to_s.downcase == val.to_s.downcase)
      }
    end
  end

  def get_available_preseed_scripts(refresh=false)
    if !@available_preseed_scripts || refresh
      # option_results = options_interface.options_for_source('preseedScripts',{})['data']
      preseed_scripts_dropdown = []
      scripts = @preseed_scripts_interface.list({max:1000})['preseedScripts']
      scripts.each do |it| 
        preseed_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id'],'id'=>it['id']}
      end
      # preseed_scripts_dropdown << {'name'=>'Custom','value'=> 'custom','value'=> 'custom'}
      @available_preseed_scripts = preseed_scripts_dropdown
    end
    #puts "available_preseed_scripts() rtn: #{@available_preseed_scripts.inspect}"
    return @available_preseed_scripts
  end

  def find_preseed_script(val)
    if val.nil? || val.to_s.empty?
      return nil
    else
      return get_available_preseed_scripts().find { |it| 
        (it['id'].to_s.downcase == val.to_s.downcase) || 
        (it['name'].to_s.downcase == val.to_s.downcase)
      }
    end
  end

  def prompt_new_image_build(options={}, default_values={}, do_require=true)
    payload = {}

    # load to create-options data for help with prompting
    create_options = nil
    begin
      create_options = @image_builds_interface.create_options({})
    rescue => ex
      Morpheus::Logging::DarkPrinter.puts "Unable to load image build create options data" if Morpheus::Logging.debug?
    end
    # Summary / Settings Tab

    # Image Build Type
    image_build_types = nil
    if create_options && create_options['imageBuildTypes']
      image_build_types = create_options['imageBuildTypes'].collect {|it| it.merge({'value' => it['code']}) }
    else
      image_build_types = get_available_image_build_types_dropdown
    end
    image_build_type = nil
    if options['type']
      image_build_type = image_build_types.find { |it| (it['code'].to_s.downcase == options['type'].to_s.downcase) ||  (it['name'].to_s.downcase == options['type'].to_s.downcase) }
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => image_build_types, 'required' => do_require, 'description' => 'Choose the type of image build.', 'defaultValue' => default_values['type'], :fmt=>:natural}], options, @api_client)
      image_build_type = Morpheus::Cli::OptionTypes.get_last_select()
    end
    if !image_build_type
      print_red_alert "Image Build Type not found!"
      return false
    end
    payload['type'] = image_build_type['code'] # = {'id'=> image_build_type['id']}

    # Name
    if options['name']
      payload['name'] = options['name']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => do_require, 'description' => 'Enter a name for this image build.', 'defaultValue' => default_values['name'], :fmt=>:natural}], options, @api_client)
      payload['name'] = v_prompt['name']
    end

    # Description
    if options['description']
      payload['description'] = options['description']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'defaultValue' => default_values['description'], :fmt=>:natural}], options, @api_client)
      payload['description'] = v_prompt['description']
    end

    # Group
    group = nil
    if options['group']
      group = find_group_by_name_or_id_for_provisioning(options['group'])
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => do_require, 'description' => 'Select Group.', 'defaultValue' => default_values['group'], :fmt=>:natural}],options,@api_client,{})
      group = find_group_by_name_or_id_for_provisioning(v_prompt['group'])
    end
    if !group
      #print_red_alert "Group not found!"
      return false
    end
    # pick one
    #payload['group'] = {'id' => group['id']}
    payload['site'] = {'id' => group['id']}

    # Cloud
    cloud = nil
    if options['cloud']
      cloud = find_cloud_by_name_or_id_for_provisioning(group['id'], options['cloud'])
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => get_available_clouds(group['id']), 'required' => do_require, 'description' => 'Select Cloud.', 'defaultValue' => default_values['cloud'], :fmt=>:natural}],options,@api_client,{groupId: group['id']})
      cloud = find_cloud_by_name_or_id_for_provisioning(group['id'], v_prompt['cloud'])
    end
    if !cloud
      # print_red_alert "Cloud not found!"
      return false
    end
    # pick one
    #payload['cloud'] = {'id' => cloud['id']}
    payload['zone'] = {'id' => cloud['id']}


    # Configure Tab
    # either pass --config, --configFile or be prompted..
    if options['config']
      payload['config'] = options['config']
    elsif options['configFile']
      config_file = File.expand_path(options['configFile'])
      if !File.exist?(config_file) || !File.file?(config_file)
        print_red_alert "File not found: #{config_file}"
        return false
      end
      if config_file =~ /\.ya?ml\Z/
        payload['config'] = YAML.load_file(config_file)
      else
        payload['config'] = JSON.parse(File.read(config_file))
      end
    elsif default_values['config']
      # for now, skip this config prompting if updating existing record
      # this is problematic, if they are changing the group or cloud though...
      # payload['config'] = default_values['config']
    else
      # Instance Type is derived from the image build type
      instance_type_code = image_build_type['instanceType']['code']
      instance_type = find_instance_type_by_code(instance_type_code)
      return false if !instance_type
      
      instance_config_options = options.dup
      #instance_config_options[:no_prompt] = options[:no_prompt]
      # use active group by default
      instance_config_options[:group] = group['id']
      instance_config_options[:cloud] = cloud['id']
      instance_config_options[:instance_type_code] = instance_type["code"] # instance_type_code
      instance_config_options[:name_required] = false
      # this provisioning helper method handles all (most) of the parsing and prompting
      # puts "instance_config_options is: #{instance_config_options.inspect}"
      instance_config_payload = prompt_new_instance(instance_config_options)
      # strip all empty string and nil, would be problematic for update()
      instance_config_payload.deep_compact!

      payload['config'] = instance_config_payload
    end

    # merge group and cloud parameters into config..
    payload['config'] ||= {}
    payload['config']['zoneId'] = cloud['id']
    # payload['config']['siteId'] = group['id']
    payload['config']['instance'] ||= {}
    payload['config']['instance']['site'] = {'id' => group['id']}


    # Scripts tab
    boot_script = nil
    boot_script_id = nil
    boot_command = nil
    if options['bootScript']
      boot_script = find_boot_script(options['bootScript'])
      if !boot_script
        print_red_alert "Boot Script not found: #{options['bootScript']}"
        return false
      end
      boot_script_id = boot_script['id']
    else
      boot_script_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'bootScript', 'type' => 'select', 'fieldLabel' => 'Boot Script', 'selectOptions' => get_available_boot_scripts(), 'required' => do_require, 'description' => 'Select Boot Script.', 'defaultValue' => default_values['bootScript'], :fmt=>:natural}],options,api_client,{})
      # boot_script_id = boot_script_prompt['bootScript']
      boot_script = find_boot_script(boot_script_prompt['bootScript'])
      if !boot_script
        print_red_alert "Boot Script not found: '#{boot_script_prompt['bootScript']}'"
        return false
      end
      boot_script_id = boot_script['id']
    end

    if boot_script_id == "custom" || options['bootCommand']
      if options['bootCommand']
        boot_command = options['bootCommand']
      else
        boot_command_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'bootCommand', 'type' => 'code-editor', 'fieldLabel' => 'Boot Command', 'required' => do_require, 'description' => 'Enter a boot command.', :fmt=>:natural}],options,api_client,{})
        boot_command = boot_command_prompt['bootCommand']
      end
      boot_script_id = nil
    else
      # boot_command = nil
    end
    
    if boot_script_id
      # payload['bootScript'] = boot_script_id
      if boot_script_id == ""
        payload['bootScript'] = nil
      else
        payload['bootScript'] = {id: boot_script_id}
      end
    elsif boot_command
      payload['bootCommand'] = boot_command
    end

    # Preseed Script
    preseed_script = nil
    preseed_script_id = nil
    if options['preseedScript']
      preseed_script = find_preseed_script(options['preseedScript'])
      if preseed_script
        preseed_script_id = preseed_script['id']
      end
    else
      preseed_script_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'preseedScript', 'type' => 'select', 'fieldLabel' => 'Preseed Script', 'selectOptions' => get_available_preseed_scripts(), 'required' => false, 'description' => 'Select Preseed Script.', 'defaultValue' => default_values['preseedScript'], :fmt=>:natural}],options,api_client,{})
      # preseed_script_id = preseed_script_prompt['preseedScript']
      preseed_script = find_preseed_script(preseed_script_prompt['preseedScript'])
      if preseed_script
        preseed_script_id = preseed_script['id']
      end
    end
    if preseed_script_id
      # payload['preseedScript'] = preseed_script_id
      if preseed_script_id == ""
        payload['preseedScript'] = nil
      else
        payload['preseedScript'] = {id: preseed_script_id}
      end
    end

    # Additional Scripts
    if options['scripts']
      payload['scripts'] = options['scripts'] #.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
    else
      scripts_default_value = default_values['scripts']
      if scripts_default_value.kind_of?(Array)
        scripts_default_value = scripts_default_value.collect {|it| it["name"] }.join(", ")
      end
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scripts', 'fieldLabel' => 'Additional Scripts', 'type' => 'text', 'description' => 'Additional Scripts (comma separated names or ids)', 'defaultValue' => scripts_default_value, :fmt=>:natural}], options, @api_client)
      payload['scripts'] = v_prompt['scripts'].to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
    end

    # SSH Username
    if options['sshUsername']
      payload['sshUsername'] = options['sshUsername']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'required' => do_require, 'type' => 'text', 'description' => 'SSH Username', 'defaultValue' => default_values['sshUsername'], :fmt=>:natural}], options, @api_client)
      payload['sshUsername'] = v_prompt['sshUsername']
    end

    # SSH Password
    if options['sshPassword']
      payload['sshPassword'] = options['sshPassword']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'required' => do_require, 'type' => 'password', 'description' => 'SSH Password', 'defaultValue' => default_values['sshPassword'], :fmt=>:natural}], options, @api_client)
      payload['sshPassword'] = v_prompt['sshPassword']
    end

    # Storage Provider
    if options['storageProvider']
      payload['storageProvider'] = options['storageProvider']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProvider', 'fieldLabel' => 'Storage Provider', 'type' => 'select', 'optionSource' => 'storageProviders', 'description' => 'Storage Provider', 'defaultValue' => default_values['storageProvider'], :fmt=>:natural}], options, @api_client, {})
      payload['storageProvider'] = v_prompt['storageProvider']
    end

    # Cloud Init
    if options['isCloudInit']
      payload['isCloudInit'] = options['isCloudInit']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'isCloudInit', 'fieldLabel' => 'Cloud Init?', 'type' => 'checkbox', 'description' => 'Cloud Init', 'defaultValue' => (default_values['isCloudInit'].nil? ? false : default_values['isCloudInit']), :fmt=>:natural}], options, @api_client, {})
      payload['isCloudInit'] = v_prompt['isCloudInit']
    end

    # Build Output Name
    if options['buildOutputName']
      payload['buildOutputName'] = options['buildOutputName']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'buildOutputName', 'fieldLabel' => 'Build Output Name', 'type' => 'text', 'description' => 'Build Output Name', 'defaultValue' => default_values['buildOutputName'], :fmt=>:natural}], options, @api_client)
      payload['buildOutputName'] = v_prompt['buildOutputName']
    end

    # Conversion Formats
    if options['conversionFormats']
      payload['conversionFormats'] = options['conversionFormats']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'conversionFormats', 'fieldLabel' => 'Conversion Formats', 'type' => 'text', 'description' => 'Conversion Formats ie. ovf, qcow2, vhd', 'defaultValue' => default_values['conversionFormats'], :fmt=>:natural}], options, @api_client)
      payload['conversionFormats'] = v_prompt['conversionFormats']
    end

    ## Retention

    # Delete Old Builds?
    # Keep Results
    if options['keepResults']
      payload['keepResults'] = options['keepResults'].to_i
    else
      default_keep_results = default_values['keepResults'] ? default_values['keepResults'] : nil # 0
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'keepResults', 'fieldLabel' => 'Keep Results', 'type' => 'text', 'description' => 'Keep only the most recent builds. Older executions will be deleted along with their associated Virtual Images. The value 0 disables this functionality.', 'defaultValue' => default_keep_results, :fmt=>:natural}], options, @api_client)
      payload['keepResults'] = v_prompt['keepResults'].to_i
    end

    return payload
  end

  def prompt_edit_image_build(image_build, options={}, do_require=false)
    # populate default prompt values with the existing image build 
    default_values = image_build.dup # lazy, but works as long as GET matches POST api structure
    if image_build['type'].kind_of?(Hash)
      default_values['type'] = image_build['type']['code']
    end
    if image_build['group'].kind_of?(Hash)
      default_values['group'] = image_build['group']['name'] # ['id']
    elsif image_build['site'].kind_of?(Hash)
      default_values['group'] = image_build['site']['name'] # ['id']
    end
    if image_build['cloud'].kind_of?(Hash)
      default_values['cloud'] = image_build['cloud']['name']# ['id']
    elsif image_build['zone'].kind_of?(Hash)
      default_values['cloud'] = image_build['zone']['name'] # ['id']
    end
    if image_build['bootCommand'] && !image_build['bootScript']
      default_values['bootScript'] = 'custom'
    end
    if image_build['bootScript'].kind_of?(Hash)
      default_values['bootScript'] = image_build['bootScript']['fileName'] # ['id']
    end
    if image_build['preseedScript'].kind_of?(Hash)
      default_values['preseedScript'] = image_build['preseedScript']['fileName'] # ['id']
    end
    if image_build['storageProvider']
      default_values['storageProvider'] = image_build['storageProvider']['name'] # ['id']
    end
    # any other mismatches? preseedScript, bootScript?
    return prompt_new_image_build(options, default_values, do_require)
  end

end
