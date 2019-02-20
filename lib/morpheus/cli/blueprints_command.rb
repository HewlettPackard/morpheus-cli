require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::BlueprintsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  set_command_name :'blueprints'
  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'types' => :list_types
  register_subcommands :duplicate
  register_subcommands :'upload-image' => :upload_image
  register_subcommands :'update-permissions' => :update_permissions
  register_subcommands :'available-tiers'
  register_subcommands :'add-tier', :'update-tier', :'remove-tier', :'connect-tiers', :'disconnect-tiers'
  register_subcommands :'add-instance'
  #register_subcommands :'update-instance'
  register_subcommands :'remove-instance'
  register_subcommands :'add-instance-config'
  #register_subcommands :'update-instance-config'
  register_subcommands :'remove-instance-config'
  # alias_subcommand :details, :get
  # set_default_subcommand :list
  
  def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @blueprints_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).blueprints
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List blueprints."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.list(params)
        return
      end

      json_response = @blueprints_interface.list(params)
      blueprints = json_response['blueprints']

      if options[:json]
        puts as_json(json_response, options, "blueprints")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['blueprints'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "blueprints")
        return 0
      end

      
      title = "Morpheus Blueprints"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      if blueprints.empty?
        print cyan,"No blueprints found.",reset,"\n"
      else
        print_blueprints_table(blueprints, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
        options[:show_config] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :outfile, :dry_run, :remote])
      opts.footer = "Get details about a blueprint.\n" +
                    "[id] is required. This is the name or id of a blueprint."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      if options[:dry_run]
        @blueprints_interface.setopts(options)
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @blueprints_interface.dry.get(args[0].to_i)
        else
          print_dry_run @blueprints_interface.dry.list({name:args[0]})
        end
        return
      end
      @blueprints_interface.setopts(options)
      blueprint = find_blueprint_by_name_or_id(args[0])
      exit 1 if blueprint.nil?

      json_response = {'blueprint' => blueprint}  # skip redundant request
      #json_response = @blueprints_interface.get(blueprint['id'])
      blueprint = json_response['blueprint']

      # export just the config as json or yaml (default)
      if options[:show_config]
        unless options[:json] || options[:yaml] || options[:csv]
          options[:yaml] = true
        end
        blueprint_config = blueprint['config']
        render_result = render_with_format(blueprint_config, options)
        return 0 if render_result
      end

      render_result = render_with_format(json_response, options, 'blueprint')
      return 0 if render_result

      print_h1 "Blueprint Details"
      
      print_blueprint_details(blueprint)

      if blueprint['resourcePermission'].nil?
        #print "\n", "No group access found", "\n"
      else
        # print_h2 "Group Access"
        # rows = []
        # if blueprint['resourcePermission']['allSites'] || blueprint['resourcePermission']['all']
        #   rows.push({"name" => 'All'})
        # end
        # if blueprint['resourcePermission']['sites']
        #   blueprint['resourcePermission']['sites'].each do |site|
        #     rows.push(site)
        #   end
        # end
        # rows = rows.collect do |site|
        #   {group: site['name'], default: site['default'] ? 'Yes' : ''}
        # end
        # # columns = [:group, :default]
        # columns = [:group]
        # print cyan
        # print as_pretty_table(rows, columns)
        # print reset,"\n"
      end

      #print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_blueprint_option_types(false))
      opts.on('-t', '--type TYPE', String, "Blueprint Type. Default is morpheus.") do |val|
        options[:blueprint_type] = val.to_s
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new blueprint.\n" + 
                    "[name] is required. This is the name of the new blueprint."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add expects 0-1 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    options[:options] ||= {}
    if args[0]
      options[:options]['name'] = args[0]
    end
    connect(options)
    begin
      payload = {}
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        # prompt for payload
        payload = {}
        payload.deep_merge!(passed_options) unless passed_options.empty?
        if options[:blueprint_type]
          options[:options]['type'] = options[:blueprint_type]
        else
          # options[:options]['type'] = 'morpheus'
        end
        params = Morpheus::Cli::OptionTypes.prompt(add_blueprint_option_types, options[:options], @api_client, options[:params])
        params.deep_compact!
        #blueprint_payload = params.select {|k,v| ['name', 'description', 'category'].include?(k) }
        # expects no namespace, just the config
        #payload = blueprint_payload
        payload.deep_merge!(params)
      end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.create(payload)
        return
      end

      json_response = @blueprints_interface.create(payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        blueprint = json_response["blueprint"]
        print_green_success "Added blueprint #{blueprint['name']}"
        if !options[:no_prompt]
          if options[:payload].nil? && ::Morpheus::Cli::OptionTypes::confirm("Would you like to add a tier now?", options.merge({default: false}))
            add_tier([blueprint['id']])
            while ::Morpheus::Cli::OptionTypes::confirm("Add another tier?", options.merge({default: false})) do
              add_tier([blueprint['id']])
            end
          else
            # print details
            get([blueprint['id']])
          end
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      build_option_type_options(opts, options, update_blueprint_option_types(false))
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a blueprint.\n" + 
                    "[id] is required. This is the name or id of a blueprint.\n" +
                    "[options] Available options include --name and --description. This will update only the specified values.\n" +
                    "[--config] or [--config-file] can be used to replace the entire blueprint."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)

    begin

      blueprint = find_blueprint_by_name_or_id(args[0])
      return 1 if blueprint.nil?

      payload = {}
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        # no prompting, just merge passed options
        payload = blueprint["config"]
        payload.deep_merge!(passed_options) unless passed_options.empty?

        if passed_options.empty?
          print_red_alert "Specify atleast one option to update"
          puts optparse
          return 1
        end
      end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end

      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        unless options[:quiet]
          blueprint = json_response['blueprint']
          print_green_success "Updated blueprint #{blueprint['name']}"
          details_options = [blueprint['id']]
          get(details_options)
        end
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_permissions(args)
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val == '' || val.nil?
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      build_option_type_options(opts, options, update_blueprint_option_types(false))
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a blueprint permissions.\n" + 
                    "[id] is required. This is the name or id of a blueprint."
    end
    optparse.parse!(args)

    if args.count != 1
      puts optparse
      return 1
    end

    connect(options)

    begin

      blueprint = find_blueprint_by_name_or_id(args[0])
      return 1 if blueprint.nil?

      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {
          'blueprint' => {
          }
        }
        
        # allow arbitrary -O options
        payload['blueprint'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        # if options['tenants']
        #   payload['tenantPermissions'] = {}
        #   payload['tenantPermissions']['accounts'] = options['tenants']
        # end
        
        # Visibility
        if options['visibility'] != nil
          payload['blueprint']['visibility'] = options['visibility']
        end
      end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update_permissions(blueprint['id'], payload)
        return
      end

      json_response = @blueprints_interface.update_permissions(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        unless options[:quiet]
          blueprint = json_response['blueprint']
          print_green_success "Updated permissions for blueprint #{blueprint['name']}"
          details_options = [blueprint['id']]
          get(details_options)
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def upload_image(args)
    image_type_name = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [file]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Upload an image file to be used as the icon for a blueprint.\n" + 
                    "[id] is required. This is the name or id of a blueprint.\n" +
                    "[file] is required. This is the local path of a file to upload [png|jpg|svg]."
    end
    optparse.parse!(args)
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} upload-image expects 2 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    blueprint_name = args[0]
    filename = File.expand_path(args[1].to_s)
    image_file = nil
    if filename && File.file?(filename)
      # maybe validate it's an image file? [.png|jpg|svg]
      image_file = File.new(filename, 'rb')
    else
      print_red_alert "File not found: #{filename}"
      # print_error Morpheus::Terminal.angry_prompt
      # puts_error  "bad argument [file] - File not found: #{filename}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      exit 1 if blueprint.nil?
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.save_image(blueprint['id'], image_file)
        return 0
      end
      unless options[:quiet] || options[:json]
        print cyan, "Uploading file #{filename} ...", reset, "\n"
      end
      json_response = @blueprints_interface.save_image(blueprint['id'], image_file)
      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        blueprint = json_response['blueprint']
        new_image_url = blueprint['image']
        print cyan, "Updated blueprint #{blueprint['name']} image.\nNew image url is: #{new_image_url}", reset, "\n\n"
        get([blueprint['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def duplicate(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [new name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Duplicate a blueprint." + "\n" +
                    "[id] is required. This is the name or id of a blueprint." + "\n" +
                    "[new name] is required. This is the name for the clone."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    payload = {"blueprint" => {}}
    if args[1]
      payload["blueprint"]["name"] = args[1]
    end

    connect(options)
    begin
      blueprint = find_blueprint_by_name_or_id(args[0])
      exit 1 if blueprint.nil?
      # unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to duplicate the blueprint #{blueprint['name']}?")
      #   exit
      # end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.duplicate(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.duplicate(blueprint['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        new_blueprint = json_response["blueprint"] || {}
        print_green_success "Created duplicate blueprint '#{new_blueprint['name']}'"
        #get([new_blueprint["id"]])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a blueprint." + "\n" +
                    "[id] is required. This is the name or id of a blueprint."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      blueprint = find_blueprint_by_name_or_id(args[0])
      exit 1 if blueprint.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the blueprint #{blueprint['name']}?")
        exit
      end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.destroy(blueprint['id'])
        return
      end
      json_response = @blueprints_interface.destroy(blueprint['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed blueprint #{blueprint['name']}"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_instance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier] [instance-type]")
      # opts.on( '-g', '--group GROUP', "Group" ) do |val|
      #   options[:group] = val
      # end
      # opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |val|
      #   options[:cloud] = val
      # end
      opts.on('--name VALUE', String, "Instance Name") do |val|
        options[:instance_name] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a blueprint, adding an instance." + "\n" +
                    "[id] is required. This is the name or id of a blueprint." + "\n" +
                    "[tier] is required and will be prompted for. This is the name of the tier." + "\n" +
                    "[instance-type] is required and will be prompted for. This is the type of instance."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add-instance expects 3 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      blueprint_name = args[0]
      tier_name = args[1]
      instance_type_code = args[2]
      # we also need consider when there is multiple instances of the same type in
      # a template/tier.. so maybe split instance_type_code as [type-code]:[index].. or...errr

      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      if !tier_name
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tierName', 'fieldLabel' => 'Tier Name', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
        tier_name = v_prompt['tierName']
      end

      if !instance_type_code
        instance_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Type', 'optionSource' => 'instanceTypes', 'required' => true, 'description' => 'Select Instance Type.'}],options[:options],api_client,{})
        instance_type_code = instance_type_prompt['type']
      end
      instance_type = find_instance_type_by_code(instance_type_code)
      return 1 if instance_type.nil?
      
      tier_config = nil
      instance_config = nil

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]
      tiers ||= {}
      # tier identified by name, case sensitive...
      if !tiers[tier_name]
        tiers[tier_name] = {}
      end
      tier_config = tiers[tier_name]
      
      tier_config['instances'] ||= []
      instance_config = tier_config['instances'].find {|it| it["instance"] && it["instance"]["type"] && it["instance"]["type"] == instance_type["code"] }
      if !instance_config
        instance_config = {'instance' => {'type' => instance_type['code']} }
        tier_config['instances'].push(instance_config)
      end
      instance_config['instance'] ||= {}

      # just prompts for Instance Name (optional)
      instance_name = nil
      if options[:instance_name]
        instance_name = options[:instance_name]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Instance Name', 'type' => 'text', 'defaultValue' => instance_config['instance']['name']}])
        instance_name = v_prompt['name'] || ''
      end
      
      if instance_name
        if instance_name.to_s == 'null'
          instance_config['instance'].delete('name')
          # instance_config['instance']['name'] = ''
        else
          instance_config['instance']['name'] = instance_name
        end
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return 0
      end

      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print_green_success "Instance added to blueprint #{blueprint['name']}"
        # prompt for new instance
        if !options[:no_prompt]
          if ::Morpheus::Cli::OptionTypes::confirm("Would you like to add a config now?", options.merge({default: true}))
            # todo: this needs to work by index, because you can have multiple instances of the same type
            add_instance_config([blueprint['id'], tier_name, instance_type['code']])
            while ::Morpheus::Cli::OptionTypes::confirm("Add another config?", options.merge({default: false})) do
              add_instance_config([blueprint['id'], tier_name, instance_type['code']])
            end
          else
            # print details
            get([blueprint['name']])
          end
        end
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end

  def add_instance_config(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier] [instance]")
      opts.on( '-g', '--group GROUP', "Group" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-e', '--env ENVIRONMENT', "Environment" ) do |val|
        options[:environment] = val
      end
      opts.on('--name VALUE', String, "Instance Name") do |val|
        options[:instance_name] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a blueprint, adding an instance config." + "\n" +
                    "[id] is required. This is the name or id of a blueprint." + "\n" +
                    "[tier] is required. This is the name of the tier." + "\n" +
                    "[instance] is required. This is the type of instance."
    end
    optparse.parse!(args)

    if args.count < 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "Wrong number of arguments"
      puts_error optparse
      return 1
    end

    connect(options)

    begin

      blueprint_name = args[0]
      tier_name = args[1]
      instance_type_code = args[2]
      # we also need consider when there is multiple instances of the same type in
      # a template/tier.. so maybe split instance_type_code as [type-code]:[index].. or...errr

      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      instance_type = find_instance_type_by_code(instance_type_code)
      return 1 if instance_type.nil?
      
      tier_config = nil
      instance_config = nil

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]
      tiers ||= {}
      # tier identified by name, case sensitive...
      if !tiers[tier_name]
        tiers[tier_name] = {}
      end
      tier_config = tiers[tier_name]
      
      tier_config['instances'] ||= []
      instance_config = tier_config['instances'].find {|it| it["instance"] && it["instance"]["type"] && it["instance"]["type"] == instance_type["code"] }
      if !instance_config
        instance_config = {'instance' => {'type' => instance_type['code']} }
        tier_config['instances'].push(instance_config)
      end
      instance_config['instance'] ||= {}

      # group prompt

      # use active group by default
      options[:group] ||= @active_group_id
      

      # available_groups = get_available_groups()
      # group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => get_available_groups(), 'required' => true, 'defaultValue' => @active_group_id}],options[:options],@api_client,{})
      
      # group_id = group_prompt['group']
      # the_group = find_group_by_name_or_id_for_provisioning(group_id)

      # # cloud prompt
      # cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'optionSource' => 'clouds', 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})
      # cloud_id = cloud_prompt['cloud']

      # look for existing config for group + cloud

      options[:name_required] = false
      options[:instance_type_code] = instance_type["code"]
      
      #options[:options].deep_merge!(specific_config)
      # this provisioning helper method handles all (most) of the parsing and prompting
      instance_config_payload = prompt_new_instance(options)

      # strip all empty string and nil, would be problematic for update()
      instance_config_payload.deep_compact!
      
      # puts "INSTANCE CONFIG YAML:"
      # puts as_yaml(instance_config_payload)
      
      selected_environment = instance_config_payload.delete('instanceContext') || instance_config_payload.delete('environment')
      # groom provision instance payload for template purposes
      selected_cloud_id = instance_config_payload.delete('zoneId')
      selected_site = instance_config_payload['instance'].delete('site')
      selected_site_id = selected_site['id']

      selected_group = find_group_by_name_or_id_for_provisioning(selected_site_id)
      selected_cloud = find_cloud_by_name_or_id_for_provisioning(selected_group['id'], selected_cloud_id)

      # store config in environments => env => groups => groupname => clouds => cloudname => 
      current_config = instance_config
      if selected_environment.to_s != ''
        instance_config['environments'] ||= {}
        instance_config['environments'][selected_environment] ||= {}
        current_config = instance_config['environments'][selected_environment]
      end

      current_config['groups'] ||= {}
      current_config['groups'][selected_group['name']] ||= {}
      current_config['groups'][selected_group['name']]['clouds'] ||= {}
      current_config['groups'][selected_group['name']]['clouds'][selected_cloud['name']] = instance_config_payload

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return 0
      end

      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        print_green_success "Instance added to blueprint #{blueprint['name']}"
        get([blueprint['name']])
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end

  def remove_instance_config(args)
    instance_index = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier] [instance] -g GROUP -c CLOUD")
      opts.on( '-g', '--group GROUP', "Group" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-e', '--env ENV', "Environment" ) do |val|
        options[:environment] = val
      end
      # opts.on( nil, '--index NUMBER', "The index of the instance to remove, starting with 0." ) do |val|
      #   instance_index = val.to_i
      # end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Update a blueprint, removing a specified instance config." + "\n" +
                    "[id] is required. This is the name or id of a blueprint." + "\n" +
                    "[tier] is required. This is the name of the tier." + "\n" +
                    "[instance] is required. This is the type of instance." + "\n" +
                    "The config scope is specified with the -g GROUP, -c CLOUD and -e ENV. The -g and -c options are required."
    end
    optparse.parse!(args)
    
    if args.count < 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "Wrong number of arguments"
      puts_error optparse
      return 1
    end
    if !options[:group]
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "Missing required argument -g GROUP"
      puts_error optparse
      return 1
    end
    if !options[:cloud]
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "Missing required argument -g CLOUD"
      puts_error optparse
      return 1
    end
    connect(options)

    begin

      blueprint_name = args[0]
      tier_name = args[1]
      instance_type_code = args[2]
      # we also need consider when there is multiple instances of the same type in
      # a template/tier.. so maybe split instance_type_code as [type-code]:[index].. or...errr

      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      instance_type = find_instance_type_by_code(instance_type_code)
      return 1 if instance_type.nil?
      
      tier_config = nil
      # instance_config = nil

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]
      tiers ||= {}
      # tier identified by name, case sensitive...
      if !tiers[tier_name]
        print_red_alert "Tier not found by name #{tier_name}"
        return 1
      end
      tier_config = tiers[tier_name]
      
      if !tier_config
        print_red_alert "Tier not found by name #{tier1_name}!"
        return 1
      elsif tier_config['instances'].nil? || tier_config['instances'].empty?
        print_red_alert "Tier #{tier_name} is empty!"
        return 1
      end

      matching_indices = []
      if tier_config['instances']
        if instance_index
          matching_indices = [instance_index].compact
        else
          tier_config['instances'].each_with_index do |instance_config, index|
            is_match = instance_config['instance'] && instance_config['instance']['type'] == instance_type['code']
            if is_match
              matching_indices << index
            end
          end
        end
      end

      if matching_indices.size == 0
        print_red_alert "Instance not found by tier: #{tier_name}, type: #{instance_type_code}"
        return 1
      elsif matching_indices.size > 1
        #print_error Morpheus::Terminal.angry_prompt
        print_red_alert  "More than one instance found by tier: #{tier_name}, type: #{instance_type_code}"
        puts_error "Try using the --index option to identify the instance you wish to remove."
        puts_error optparse
        return 1
      end

      # ok, find the specified config
      instance_config = tier_config['instances'][matching_indices[0]]
      parent_config = nil
      current_config = instance_config
      delete_key = nil

      config_description = "type: #{instance_type['code']}"
      config_description << " environment: #{options[:environment]}" if options[:environment]
      config_description << " group: #{options[:group]}" if options[:group]
      config_description << " cloud: #{options[:cloud]}" if options[:cloud]
      config_description = config_description.strip

      
      # find config in environments => env => groups => groupname => clouds => cloudname => 
      if options[:environment]
        if current_config && current_config['environments'] && current_config['environments'][options[:environment]]
          parent_config = current_config['environments']
          delete_key  = options[:environment]
          current_config = parent_config[delete_key]
        else
          print_red_alert "Instance config not found for scope #{config_description}"
          return 1
        end
      end
      if options[:group]
        if current_config && current_config['groups'] && current_config['groups'][options[:group]]
          parent_config = current_config['groups']
          delete_key  = options[:group]
          current_config = parent_config[delete_key]
        else
          print_red_alert "Instance config not found for scope #{config_description}"
          return 1
        end
      end
      if options[:cloud]
        if current_config && current_config['clouds'] && current_config['clouds'][options[:cloud]]
          parent_config = current_config['clouds']
          delete_key  = options[:cloud]
          current_config = parent_config[delete_key]
        else
          print_red_alert "Instance config not found for scope #{config_description}"
          return 1
        end
      end
      
      # remove it
      parent_config.delete(delete_key)
      
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete this instance config #{config_description} ?")
        return 9
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        print_green_success "Removed instance from blueprint."
        get([blueprint['id']])
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_instance(args)
    print_red_alert "NOT YET SUPPORTED"
    return 5
  end

  def update_instance_config(args)
    print_red_alert "NOT YET SUPPORTED"
    return 5
  end

  def remove_instance(args)
    instance_index = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier] [instance]")
      # opts.on('--index NUMBER', Number, "Identify Instance by index within tier, starting with 0." ) do |val|
      #   instance_index = val.to_i
      # end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    
    if args.count < 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "Wrong number of arguments"
      puts_error optparse
      return 1
    end

    connect(options)

    begin

      blueprint_name = args[0]
      tier_name = args[1]
      instance_identier = args[2]

      # instance_type_code = args[2]
      # we also need consider when there is multiple instances of the same type in
      # a template/tier.. so maybe split instance_type_code as [type-code]:[index].. or...errr

      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      # instance_type = find_instance_type_by_code(instance_type_code)
      # return 1 if instance_type.nil?
      
      tier_config = nil
      # instance_config = nil

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]
      tiers ||= {}
      # tier identified by name, case sensitive...
      if !tiers[tier_name]
        print_red_alert "Tier not found by name #{tier_name}"
        return 1
      end
      tier_config = tiers[tier_name]
      
      if tier_config['instances'].nil? || tier_config['instances'].empty?
        print_red_alert "Tier #{tier_name} is empty!"
        return 1
      end

      # find instance
      matching_indices = []
      if tier_config['instances']
        if instance_identier.to_s =~ /\A\d{1,}\Z/
          matching_indices = [instance_identier.to_i].compact
        else
          tier_config['instances'].each_with_index do |instance_config, index|
            if instance_config['instance'] && instance_config['instance']['type'] == instance_identier
              matching_indices << index
            elsif instance_config['instance'] && instance_config['instance']['name'] == instance_identier
              matching_indices << index
            end
          end
        end
      end
      if matching_indices.size == 0
        print_red_alert "Instance not found by tier: #{tier_name}, instance: #{instance_identier}"
        return 1
      elsif matching_indices.size > 1
        #print_error Morpheus::Terminal.angry_prompt
        print_red_alert "More than one instance matched tier: #{tier_name}, instance: #{instance_identier}"
        puts_error "Instance can be identified type, name or index within the tier."
        puts_error optparse
        return 1
      end

      # remove it
      tier_config['instances'].delete_at(matching_indices[0])

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete this instance #{instance_type_code} instance from tier: #{tier_name}?")
        return 9
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        print_green_success "Removed instance from blueprint."
        get([blueprint['id']])
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_tier(args)
    options = {}
    boot_order = nil
    linked_tiers = nil
    tier_index = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier]")
      opts.on('--name VALUE', String, "Tier Name") do |val|
        options[:name] = val
      end
      opts.on('--bootOrder NUMBER', String, "Boot Order" ) do |val|
        boot_order = val
      end
      opts.on('--linkedTiers x,y,z', Array, "Connected Tiers.") do |val|
        linked_tiers = val
      end
      opts.on('--tierIndex NUMBER', Array, "Tier Index. Used for Display Order") do |val|
        tier_index = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add-tier requires argument: [id]\n#{optparse}"
      # puts optparse
      return 1
    end
    blueprint_name = args[0]
    tier_name = args[1]

    connect(options)

    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?
      
      blueprint["config"] ||= {}
      blueprint["config"]["tiers"] ||= {}
      tiers = blueprint["config"]["tiers"]

      # prompt new tier
      # Name
      # {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1, 'description' => 'A unique name for the blueprint.'},
      #   {'fieldName' => 'bootOrder', 'fieldLabel' => 'Boot Order', 'type' => 'text', 'required' => false, 'displayOrder' => 2, 'description' => 'Boot Order'}
      if !tier_name
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Tier Name', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
        tier_name = v_prompt['name']
      end
      # case insensitive match
      existing_tier_names = tiers.keys
      matching_tier_name = existing_tier_names.find {|k| k.downcase == tier_name.downcase }
      if matching_tier_name
        # print_red_alert "Tier #{tier_name} already exists"
        # return 1
        print cyan,"Tier #{tier_name} already exists.",reset,"\n"
        return 0
      end
      # idempotent
      if !tiers[tier_name]
        tiers[tier_name] = {'instances' => []}
      end
      tier = tiers[tier_name]
      
      # Boot Order
      if !boot_order
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'bootOrder', 'fieldLabel' => 'Boot Order', 'type' => 'text', 'required' => false, 'description' => 'Sequence order for starting app instances by tier. 0-N', 'defaultValue' => tier['bootOrder']}], options[:options])
        boot_order = v_prompt['bootOrder']
      end
      if boot_order.to_s == 'null'
        tier.delete('bootOrder')
      elsif boot_order.to_s != ''
        tier['bootOrder'] = boot_order.to_i
      end

      # Connected Tiers
      if !linked_tiers
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'linkedTiers', 'fieldLabel' => 'Connected Tiers', 'type' => 'text', 'required' => false, 'description' => 'Names of connected tiers, comma separated', 'defaultValue' => (linked_tiers ? linked_tiers.join(',') : nil)}], options[:options])
        linked_tiers = v_prompt['linkedTiers'].to_s.split(',').collect {|it| it.strip }.select {|it| it != ''}
      end
      if linked_tiers && !linked_tiers.empty?
        linked_tiers.each do |other_tier_name|
          link_result = link_tiers(tiers, [tier_name, other_tier_name])
          # could just re-prompt unless options[:no_prompt]
          return 1 if !link_result
        end
      end

      # Tier Index
      if !tier_index
        #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tierIndex', 'fieldLabel' => 'Tier Index', 'type' => 'number', 'required' => false, 'description' => 'Sequence order for displaying app instances by tier. 0-N', 'defaultValue' => tier['tierIndex']}], options[:options])
        #tier_index = v_prompt['tierIndex']
        tier_index = (tiers.size - 1)
      end

      if tier_index.to_s == 'null'
        tier.delete('tierIndex')
      elsif tier_index
        tier['tierIndex'] = tier_index.to_i
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = blueprint["config"]
      # payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print_green_success "Added tier #{tier_name}"
        # prompt for new instance
        if !options[:no_prompt]
          if ::Morpheus::Cli::OptionTypes::confirm("Would you like to add an instance now?", options.merge({default: true}))
            add_instance([blueprint['id'], tier_name])
            while ::Morpheus::Cli::OptionTypes::confirm("Add another instance now?", options.merge({default: false})) do
              add_instance([blueprint['id'], tier_name])
            end
            # if !add_instance_result
            # end
          end
        end
        # print details
        get([blueprint['name']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_tier(args)
    options = {}
    new_tier_name = nil
    boot_order = nil
    linked_tiers = nil
    tier_index = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier]")
      opts.on('--name VALUE', String, "Tier Name") do |val|
        new_tier_name = val
      end
      opts.on('--bootOrder NUMBER', String, "Boot Order" ) do |val|
        boot_order = val
      end
      opts.on('--linkedTiers x,y,z', Array, "Connected Tiers") do |val|
        linked_tiers = val
      end
      opts.on('--tierIndex NUMBER', String, "Tier Index. Used for Display Order") do |val|
        tier_index = val.to_i
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} update-tier expects 2 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    blueprint_name = args[0]
    tier_name = args[1]

    connect(options)

    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?
      
      blueprint["config"] ||= {}
      blueprint["config"]["tiers"] ||= {}
      tiers = blueprint["config"]["tiers"]
      
      if !tiers[tier_name]
        print_red_alert "Tier not found by name #{tier_name}"
        return 1
      end
      tier = tiers[tier_name]

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      
      if options[:no_prompt]
        if !(new_tier_name || boot_order || linked_tiers || tier_index || !passed_options.empty?)
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "#{command_name} update-tier requires an option to update.\n#{optparse}"
          return 1
        end
      end

      tier.deep_merge!(passed_options) unless passed_options.empty?

      # prompt update tier
      # Name
      if !new_tier_name
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Tier Name', 'type' => 'text', 'required' => true, 'description' => 'Rename the tier', 'defaultValue' => tier_name}], options[:options])
        new_tier_name = v_prompt['name']
      end
      if new_tier_name && new_tier_name != tier_name
        old_tier_name = tier_name
        if tiers[new_tier_name]
          print_red_alert "A tier named #{tier_name} already exists."
          return 1
        end
        tier = tiers.delete(tier_name)
        tiers[new_tier_name] = tier
        # Need to fix all the linkedTiers
        tiers.each do |k, v|
          if v['linkedTiers'] && v['linkedTiers'].include?(tier_name)
            v['linkedTiers'] = v['linkedTiers'].map {|it| it == tier_name ? new_tier_name : it }
          end
        end
        # old_tier_name = tier_name
        tier_name = new_tier_name
      end

      # Boot Order
      if !boot_order
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'bootOrder', 'fieldLabel' => 'Boot Order', 'type' => 'text', 'required' => false, 'description' => 'Sequence order for starting app instances by tier. 0-N', 'defaultValue' => tier['bootOrder']}], options[:options])
        boot_order = v_prompt['bootOrder']
      end
      if boot_order.to_s == 'null'
        tier.delete('bootOrder')
      elsif boot_order.to_s != ''
        tier['bootOrder'] = boot_order.to_i
      end

      # Connected Tiers
      if !linked_tiers
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'linkedTiers', 'fieldLabel' => 'Connected Tiers', 'type' => 'text', 'required' => false, 'description' => 'Names of connected tiers, comma separated', 'defaultValue' => (tier['linkedTiers'] ? tier['linkedTiers'].join(',') : nil)}], options[:options])
        linked_tiers = v_prompt['linkedTiers'].to_s.split(',').collect {|it| it.strip }.select {|it| it != ''}
      end
      current_linked_tiers = tier['linkedTiers'] || []
      if linked_tiers && linked_tiers != current_linked_tiers
        remove_tiers = current_linked_tiers - linked_tiers
        remove_tiers.each do |other_tier_name|
          unlink_result = unlink_tiers(tiers, [tier_name, other_tier_name])
          # could just re-prompt unless options[:no_prompt]
          return 1 if !unlink_result
        end
        add_tiers = linked_tiers - current_linked_tiers
        add_tiers.each do |other_tier_name|
          link_result = link_tiers(tiers, [tier_name, other_tier_name])
          # could just re-prompt unless options[:no_prompt]
          return 1 if !link_result
        end
      end

      # Tier Index
      if tier_index.to_s == 'null'
        tier.delete('tierIndex')
      elsif tier_index
        tier['tierIndex'] = tier_index.to_i
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = blueprint["config"]
      # payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print_green_success "Updated tier #{tier_name}"
        get([blueprint['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_tier(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [tier]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-tier expects 2 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    blueprint_name = args[0]
    tier_name = args[1]

    connect(options)

    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      blueprint["config"] ||= {}
      blueprint["config"]["tiers"] ||= {}
      tiers = blueprint["config"]["tiers"]

      if !tiers[tier_name]
        # print_red_alert "Tier not found by name #{tier_name}"
        # return 1
        print cyan,"Tier #{tier_name} does not exist.",reset,"\n"
        return 0
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the tier #{tier_name}?")
        exit
      end

      # remove it
      tiers.delete(tier_name)
      
      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = blueprint["config"]
      # payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end

      json_response = @blueprints_interface.update(blueprint['id'], payload)


      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed tier #{tier_name}"
        get([blueprint['name']])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def connect_tiers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [Tier1] [Tier2]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} connect-tiers expects 3 arguments and received #{args.count}: #{args}\n#{optparse}"
      # puts optparse
      return 1
    end
    blueprint_name = args[0]
    tier1_name = args[1]
    tier2_name = args[2]

    connect(options)

    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]

      if !tiers || tiers.keys.size == 0
        error_msg = "Blueprint #{blueprint['name']} has no tiers."
        # print_red_alert "Blueprint #{blueprint['name']} has no tiers."
        # raise_command_error "Blueprint #{blueprint['name']} has no tiers."
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "Blueprint #{blueprint['name']} has no tiers."
        return 1
      end

      connect_tiers = []
      tier1 = tiers[tier1_name]
      tier2 = tiers[tier2_name]
      # uhh support N args

      if tier1.nil?
        print_red_alert "Tier not found by name #{tier1_name}!"
        return 1
      end

      if tier2.nil?
        print_red_alert "Tier not found by name #{tier2_name}!"
        return 1
      end

      tier1["linkedTiers"] = tier1["linkedTiers"] || []
      tier2["linkedTiers"] = tier2["linkedTiers"] || []

      found_edge = tier1["linkedTiers"].include?(tier2_name) || tier2["linkedTiers"].include?(tier1_name)

      if found_edge
        puts cyan,"Tiers #{tier1_name} and #{tier2_name} are already connected.",reset
        return 0
      end

      # ok to be connect the tiers
      # note: the ui doesn't hook up both sides eh?

      if !tier1["linkedTiers"].include?(tier2_name)
        tier1["linkedTiers"].push(tier2_name)
      end

      if !tier2["linkedTiers"].include?(tier1_name)
        tier2["linkedTiers"].push(tier1_name)
      end

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = blueprint["config"]
      # payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)


      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Connected 2 tiers for blueprint #{blueprint['name']}"
        get([blueprint['name']])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def disconnect_tiers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [Tier1] [Tier2]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} disconnect-tiers expects 3 arguments and received #{args.count}: #{args}\n#{optparse}"
      # puts optparse
      return 1
    end
    blueprint_name = args[0]
    tier1_name = args[1]
    tier2_name = args[2]

    connect(options)

    begin
      blueprint = find_blueprint_by_name_or_id(blueprint_name)
      return 1 if blueprint.nil?

      blueprint["config"] ||= {}
      tiers = blueprint["config"]["tiers"]

      if !tiers || tiers.keys.size == 0
        # print_red_alert "Blueprint #{blueprint['name']} has no tiers."
        # raise_command_error "Blueprint #{blueprint['name']} has no tiers."
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "Blueprint #{blueprint['name']} has no tiers."
        return 1
      end

      connect_tiers = []
      tier1 = tiers[tier1_name]
      tier2 = tiers[tier2_name]
      # uhh support N args

      if tier1.nil?
        print_red_alert "Tier not found by name #{tier1_name}!"
        return 1
      end

      if tier2.nil?
        print_red_alert "Tier not found by name #{tier2_name}!"
        return 1
      end

      tier1["linkedTiers"] = tier1["linkedTiers"] || []
      tier2["linkedTiers"] = tier2["linkedTiers"] || []

      found_edge = tier1["linkedTiers"].include?(tier2_name) || tier2["linkedTiers"].include?(tier1_name)

      if found_edge
        puts cyan,"Tiers #{tier1_name} and #{tier2_name} are not connected.",reset
        return 0
      end

      # remove links
      tier1["linkedTiers"] = tier1["linkedTiers"].reject {|it| it == tier2_name }
      tier2["linkedTiers"] = tier2["linkedTiers"].reject {|it| it == tier1_name }

      # ok, make api request
      blueprint["config"]["tiers"] = tiers
      payload = blueprint["config"]
      # payload = {blueprint: blueprint}
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.update(blueprint['id'], payload)
        return
      end
      json_response = @blueprints_interface.update(blueprint['id'], payload)


      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Connected 2 tiers for blueprint #{blueprint['name']}"
        get([blueprint['name']])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def available_tiers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    params = {}

    begin
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.list_tiers(params)
        return
      end
      json_response = @blueprints_interface.list_tiers(params)
      tiers = json_response["tiers"] # just a list of names
      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        print_h1 "Available Tiers"
        if tiers.empty?
          print yellow,"No tiers found.",reset,"\n"
        else
          # rows = tiers.collect do |tier|
          #   {
          #     id: tier['id'],
          #     name: tier['name'],
          #   }
          # end
          # print cyan
          # tp rows, [:name]
          print cyan
          tiers.each do |tier_name|
            puts tier_name
          end
        end
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end

  end

  def list_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List blueprint types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @blueprints_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @blueprints_interface.dry.list_types(params)
        return
      end

      json_response = @blueprints_interface.list_types(params)
      blueprint_types = json_response['types']

      if options[:json]
        puts as_json(json_response, options, "types")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['types'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "types")
        return 0
      end

      
      title = "Morpheus Blueprint Types"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if blueprint_types.empty?
        print cyan,"No blueprint types found.",reset,"\n"
      else
        rows = blueprint_types.collect do |blueprint_type|
          {
            code: blueprint_type['code'],
            name: blueprint_type['name']
          }
        end
        columns = [:code, :name]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        # print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private


  def add_blueprint_option_types(connected=true)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'},
      {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => (connected ? get_available_blueprint_types() : []), 'required' => true, 'defaultValue' => 'morpheus'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false},
      #{'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true}
    ]
  end

  def get_available_blueprint_types(refresh=false)
    if !@available_blueprint_types || refresh
      begin
        # results = @options_interface.options_for_source('blueprintTypes',{})
        results = @blueprints_interface.list_types({})
        @available_blueprint_types = results['types'].collect {|it|
          {"name" => (it["name"] || it["code"]), "value" => (it["code"] || it["value"])}
        }
      rescue RestClient::Exception => e
        # older version
        @available_blueprint_types = [{"name" => "Morpheus", "value" => "morpheus"}, {"name" => "Terraform", "value" => "terraform"}, {"name" => "CloudFormation", "value" => "cloudFormation"}, {"name" => "ARM template", "value" => "arm"}]
      end
    end
    #puts "get_available_blueprints() rtn: #{@available_blueprints.inspect}"
    return @available_blueprint_types
  end

  def update_blueprint_option_types(connected=true)
    list = add_blueprint_option_types(connected)
    list = list.select {|it| ["name","decription","category"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

  def find_blueprint_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_blueprint_by_id(val)
    else
      return find_blueprint_by_name(val)
    end
  end

  def find_blueprint_by_id(id)
    begin
      json_response = @blueprints_interface.get(id.to_i)
      return json_response['blueprint']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Blueprint not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_blueprint_by_name(name)
    blueprints = @blueprints_interface.list({name: name.to_s})['blueprints']
    if blueprints.empty?
      print_red_alert "Blueprint not found by name #{name}"
      return nil
    elsif blueprints.size > 1
      print_red_alert "#{blueprints.size} blueprints by name #{name}"
      print_blueprints_table(blueprints, {color: red})
      print reset,"\n"
      return nil
    else
      return blueprints[0]
    end
  end

  def find_group_by_name(name)
    group_results = @groups_interface.get(name)
    if group_results['groups'].empty?
      print_red_alert "Group not found by name #{name}"
      return nil
    end
    return group_results['groups'][0]
  end

  def find_cloud_by_name(group_id, name)
    option_results = @options_interface.options_for_source('clouds',{groupId: group_id})
    match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
    if match.nil?
      print_red_alert "Cloud not found by name #{name}"
      return nil
    else
      return match['value']
    end
  end

  def print_blueprints_table(blueprints, opts={})
    table_color = opts[:color] || cyan
    rows = blueprints.collect do |blueprint|
      #instance_type_names = (blueprint['instanceTypes'] || []).collect {|it| it['name'] }.join(', ')
      instance_type_names = []
      # if blueprint['config'] && blueprint['config']["tiers"]
      #   blueprint['config']["tiers"]
      # end
      {
        id: blueprint['id'],
        name: blueprint['name'],
        description: blueprint['description'],
        type: blueprint['type'].kind_of?(Hash) ? blueprint['type']['name'] : blueprint['type'],
        category: blueprint['category'],
        tiers_summary: format_blueprint_tiers_summary(blueprint)
      }
    end

    term_width = current_terminal_width()
    tiers_col_width = 60
    if term_width > 190
      tiers_col_width += 130
    end
    columns = [
      :id,
      :name,
      :description,
      :type,
      :category,
      {:tiers_summary => {:display_name => "TIERS", :max_width => tiers_col_width} }
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print table_color
    print as_pretty_table(rows, columns, opts)
    print reset
  end

  def generate_id(len=16)
    id = ""
    len.times { id << (1 + rand(9)).to_s }
    id
  end

  def format_blueprint_tiers_summary(blueprint)
    # don't use colors here, or cell truncation will not work
    str = ""
    if blueprint["config"] && blueprint["config"]["tiers"]
      tier_descriptions = blueprint["config"]["tiers"].collect do |tier_name, tier_config|
        # maybe do Tier Name (instance, instance2)
        instance_blurbs = []
        if tier_config["instances"]
          tier_config["instances"].each do |instance_config|
            if instance_config["instance"] && instance_config["instance"]["type"]
              # only have type: code in the config, rather not name fetch remotely right now..
              # instance_blurbs << instance_config["instance"]["type"]
              instance_name = instance_config["instance"]["name"] || ""
              instance_type_code = instance_config["instance"]["type"]
              instances_str = "#{instance_type_code}"
              if instance_name.to_s != ""
                instances_str << " - #{instance_name}"
              end
              begin
                config_list = parse_scoped_instance_configs(instance_config)
                if config_list.size == 0
                  instances_str << " (No configs)"
                elsif config_list.size == 1
                  # configs_str = config_list.collect {|it| 
                  #   str = ""
                  #     it[:scope].to_s.inspect
                  #   }.join(", ")
                  the_config = config_list[0]
                  scope_str = the_config[:scope].collect {|k,v| v.to_s }.join("/")
                  instances_str << " (#{scope_str})"
                else
                  instances_str << " (#{config_list.size} configs)"
                end
              rescue => err
                puts_error "Failed to parse instance scoped instance configs: #{err.class} #{err.message}"
                raise err
              end
              instance_blurbs << instances_str
            end
          end
        end
        if instance_blurbs.size > 0
          tier_name + ": #{instance_blurbs.join(', ')}"
        else
          tier_name + ": (empty)"
        end
      end
      str += tier_descriptions.compact.join(", ")
    end
    str
  end

  def print_blueprint_details(blueprint)
    print cyan
    description_cols = {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| it['type'].kind_of?(Hash) ? it['type']['name'] : it['type'] },
      "Category" => 'category',
      "Image" => lambda {|it| it['config'] ? (it['config']['image'] == '/assets/apps/template.png' ? '(default)' : it['config']['image']) : '' },
      "Visibility" => 'visibility',
      "Tiers" => lambda {|it| 
          tiers = []
          if blueprint["config"]["tiers"].is_a?(Hash)
            tiers = blueprint["config"]["tiers"].keys
          end
          "#{tiers.collect {|it| it.is_a?(Hash) ? it['name'] : it }.join(',')}"
        },
        "Instances" => lambda {|it| 
          instances = []
          tiers = {}
          if blueprint["config"]["tiers"].is_a?(Hash)
            tiers = blueprint["config"]["tiers"]
          end
          sorted_tiers = tiers.collect {|k,v| [k,v] }.sort {|a,b| a[1]['tierIndex'] <=> b[1]['tierIndex'] }
          sorted_tiers.each do |tier_obj|
            tier_name = tier_obj[0]
            tier_config = tier_obj[1]
            if tier_config && tier_config['instances']
              tier_config['instances'].each_with_index do |instance_config, instance_index|
                instances << instance_config
              end
            end
          end
          #"(#{instances.count})"
          "(#{instances.count}) #{instances.collect {|it| it['instance'] ? it['instance']['type'] : (it['type'] || it['name']) }.join(',')}"
        },
        # "Containers" => lambda {|it| 
        #     i wish
        # },
      "Group Access" => lambda {|it| 
        group_access_str = ""
        begin
          rows = []
          if blueprint['resourcePermission']
            if blueprint['resourcePermission']['allSites'] || blueprint['resourcePermission']['all']
              rows.push({"name" => 'All'})
            end
            if blueprint['resourcePermission']['sites']
              blueprint['resourcePermission']['sites'].each do |site|
                rows.push(site)
              end
            end
          else
            # rows.push({"name" => 'All'})
          end
          group_access_str = rows.collect {|it| it['default'] ? "#{it['name']} (default)" : "#{it['name']}"}.join(',')
        rescue => ex
          Morpheus::Logging::DarkPrinter.puts "Error parsing group access: #{ex}" if Morpheus::Logging.debug?
        end
        group_access_str
      }
    }

    print_description_list(description_cols, blueprint)
    # print_h2 "Tiers"
    if blueprint["config"] && blueprint["config"]["tiers"] && blueprint["config"]["tiers"].keys.size != 0
      print cyan
      #puts as_yaml(blueprint["config"]["tiers"])
      tiers = blueprint["config"]["tiers"]
      sorted_tiers = tiers.collect {|k,v| [k,v] }.sort {|a,b| a[1]['tierIndex'] <=> b[1]['tierIndex'] }
      sorted_tiers.each do |tier_obj|
        tier_name = tier_obj[0]
        tier_config = tier_obj[1]
        # print_h2 "Tier: #{tier_name}"
        print_h2 tier_name
        # puts "  Instances:"
        if tier_config['instances'] && tier_config['instances'].size != 0
          # puts as_yaml(tier)
          tier_config['instances'].each_with_index do |instance_config, instance_index|
            instance_name = instance_config["instance"]["name"] || ""
            instance_type_code = ""
            if instance_config["instance"]["type"]
              instance_type_code = instance_config["instance"]["type"]
            end
            instance_bullet = ""
            # instance_bullet += "#{green}     - #{bold}#{instance_type_code}#{reset}"
            instance_bullet += "#{green}#{bold}#{instance_type_code}#{reset}"
            if instance_name.to_s != ""
              instance_bullet += "#{green} - #{instance_name}#{reset}"
            end
            puts instance_bullet
            # print "\n"
            begin
              config_list = parse_scoped_instance_configs(instance_config)
              print cyan
              if config_list.size > 0
                print "\n"
                if config_list.size == 1
                  puts "  Config:"
                else
                  puts "  Configs (#{config_list.size}):"
                end
                config_list.each do |config_obj| 
                  # puts "     = #{config_obj[:scope].inspect}"
                  config_scope = config_obj[:scope]
                  scoped_instance_config = config_obj[:config]
                  config_description = ""
                  config_items = []
                  if config_scope[:environment]
                    config_items << {label: "Environment", value: config_scope[:environment]}
                  end
                  if config_scope[:group]
                    config_items << {label: "Group", value: config_scope[:group]}
                  end
                  if config_scope[:cloud]
                    config_items << {label: "Cloud", value: config_scope[:cloud]}
                  end
                  # if scoped_instance_config['plan'] && scoped_instance_config['plan']['code']
                  #   config_items << {label: "Plan", value: scoped_instance_config['plan']['code']}
                  # end
                  config_description = config_items.collect {|item| "#{item[:label]}: #{item[:value]}"}.join(", ")
                  puts "  * #{config_description}"
                end
              else
                print white,"  Instance has no configs, see `app-templates add-instance-config \"#{blueprint['name']}\" \"#{tier_name}\" \"#{instance_type_code}\"`",reset,"\n"
              end
            rescue => err
              #puts_error "Failed to parse instance scoped instance configs for blueprint #{blueprint['id']} #{blueprint['name']} Exception: #{err.class} #{err.message}"
            end
            print "\n"
            #puts as_yaml(instance_config)
            # todo: iterate over 
            #   instance_config["groups"][group_name]["clouds"][cloud_name]
          end
          
          print cyan
          if tier_config['bootOrder']
            puts "Boot Order: #{tier_config['bootOrder']}"
          end
          if tier_config['linkedTiers'] && !tier_config['linkedTiers'].empty?
            puts "Connected Tiers: #{tier_config['linkedTiers'].join(', ')}"
          end  
          
        else
          print white,"  Tier is empty, see `app-templates add-instance \"#{blueprint['name']}\" \"#{tier_name}\"`",reset,"\n"
        end
        # print "\n"

      end
      # print "\n"

    else
      print white,"\nTemplate is empty, see `app-templates add-tier \"#{blueprint['name']}\"`",reset,"\n"
    end
  end

  # this parses the environments => groups => clouds tree structure
  # and returns a list of objects like {scope: {group:'thegroup'}, config: Map}
  # this would be be better as a recursive function, brute forced for now.
  def parse_scoped_instance_configs(instance_config)
    config_list = []
    if instance_config['environments'] && instance_config['environments'].keys.size > 0
      instance_config['environments'].each do |env_name, env_config|
        if env_config['groups']
          env_config['groups'].each do |group_name, group_config|
            if group_config['clouds'] && !group_config['clouds'].empty?
              group_config['clouds'].each do |cloud_name, cloud_config|
                config_list << {config: cloud_config, scope: {environment: env_name, group: group_name, cloud: cloud_name}}
              end
            end
            if (!group_config['clouds'] || group_config['clouds'].empty?)
              config_list << {config: group_config, scope: {environment: env_name, group: group_name}}
            end
          end
        end
        if env_config['clouds'] && !env_config['clouds'].empty?
          env_config['clouds'].each do |cloud_name, cloud_config|
            config_list << {config: cloud_config, scope: {environment: env_name, cloud: cloud_name}}
          end
        end
        if (!env_config['groups'] || env_config['groups'].empty?) && (!env_config['clouds'] || env_config['clouds'].empty?)
          config_list << {config: env_config, scope: {environment: env_name}}
        end
      end
    end
    if instance_config['groups']
      instance_config['groups'].each do |group_name, group_config|
        if group_config['clouds'] && !group_config['clouds'].empty?
          group_config['clouds'].each do |cloud_name, cloud_config|
            config_list << {config: cloud_config, scope: {group: group_name, cloud: cloud_name}}
          end
        end
        if (!group_config['clouds'] || group_config['clouds'].empty?)
          config_list << {config: group_config, scope: {group: group_name}}
        end
      end
    end
    if instance_config['clouds']
      instance_config['clouds'].each do |cloud_name, cloud_config|
        config_list << {config: cloud_config, scope: {cloud: cloud_name}}
      end
    end
    return config_list
  end

  def link_tiers(tiers, tier_names)
    # tiers = blueprint["config"]["tiers"]
    tier_names = [tier_names].flatten.collect {|it| it }.compact.uniq
    if !tiers
      print_red_alert "No tiers found for template"
      return false
    end

    existing_tier_names = tiers.keys
    matching_tier_names = tier_names.map {|tier_name| 
      existing_tier_names.find {|k| k.downcase == tier_name.downcase }
    }.compact
    if matching_tier_names.size != tier_names.size
      print_red_alert "Template does not contain tiers: '#{tier_names}'"
      return false
    end
    matching_tier_names.each do |tier_name|
      tier = tiers[tier_name]
      tier['linkedTiers'] ||= []
      other_tier_names = matching_tier_names.select {|it| tier_name != it}
      other_tier_names.each do |other_tier_name|
        if !tier['linkedTiers'].include?(other_tier_name)
          tier['linkedTiers'].push(other_tier_name)
        end
      end
    end
    return true
  end

  def unlink_tiers(tiers, tier_names)
    # tiers = blueprint["config"]["tiers"]
    tier_names = [tier_names].flatten.collect {|it| it }.compact.uniq
    if !tiers
      print_red_alert "No tiers found for template"
      return false
    end

    existing_tier_names = tiers.keys
    matching_tier_names = tier_names.map {|tier_name| 
      existing_tier_names.find {|k| k.downcase == tier_name.downcase }
    }.compact
    if matching_tier_names.size != tier_names.size
      print_red_alert "Template does not contain tiers: '#{tier_names}'"
      return false
    end
    matching_tier_names.each do |tier_name|
      tier = tiers[tier_name]
      tier['linkedTiers'] ||= []
      other_tier_names = matching_tier_names.select {|it| tier_name != it}
      other_tier_names.each do |other_tier_name|
        if tier['linkedTiers'].include?(other_tier_name)
          tier['linkedTiers'] = tier['linkedTiers'].reject {|it| it == other_tier_name }
        end
      end
    end
    return true
  end

end
