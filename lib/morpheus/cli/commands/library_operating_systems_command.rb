require 'morpheus/cli/cli_command'

class Morpheus::Cli::LibraryOperatingSystemsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-operating-systems'

  register_subcommands :list, :get, :add_image, :remove_image

  def initialize()
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_operating_systems_interface = @api_client.library_operating_systems
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List os types."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.list_os_types(params)
        return
      end
      # do it
      json_response = @library_operating_systems_interface.list_os_types(params)
      # print and/or return result
      # return 0 if options[:quiet]
      if options[:json]
        puts as_json(json_response, options, "osTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['osTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "osTypes")
        return 0
      end
      os_types = json_response['osTypes']
      title = "Morpheus Library - OS Types"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles
      if os_types.empty?
        print cyan,"No os types found.",reset,"\n"
      else
        rows = os_types.collect do |os_type|
          {
              id: os_type['id'],
              name: os_type['name'],
              code: os_type['code'],
              platform: os_type['platform'],
              vendor: os_type['vendor'],
              category: os_type['category'],
              family: os_type['osFamily']
          }
        end
        print as_pretty_table(rows, [:id, :name, :code, :platform, :vendor, :category, :family], options)
        print_results_pagination(json_response, {})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[osType]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display osType details." + "\n" +
                    "[osType] is required. This is the id of an osType."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    id_list.each do |id|

    end
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    begin
      @library_operating_systems_interface.setopts(options)

      if options[:dry_run]
          print_dry_run @library_operating_systems_interface.dry.get(id)
        return
      end
      os_type = find_os_type_by_id(id)
      if os_type.nil?
        return 1
      end

      json_response = {'osType' => os_type}

      if options[:json]
        puts as_json(json_response, options, "osType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "osType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['osType']], options)
        return 0
      end

      print_h1 "OsType Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Code" => lambda {|it| it['code']},
        "Platform" => lambda {|it| it['platform']},
        "Category" => lambda {|it|it['category']},
        "Vendor" => lambda {|it| it['vendor']},
        "Family" => lambda {|it| it['osFamily']},
        "Os Name" => lambda {|it| it['osName'] },
        "Install Agent" => lambda {|it| format_boolean(it['installAgent'])},
        "Bit Count" => lambda {|it| it['bitCount'] }
      }

      print_description_list(description_cols, os_type)
      title = "OsType - Images"
      print_h2 title
        if os_type['images'].empty?
          print cyan,"No images found.",reset,"\n"
        else
          rows = os_type['images'].collect do |image|
            {
                id: image['id'],
                virtual_image_id: image['virtualImageId'],
                virtual_image_name: image['virtualImageName'],
                account: image['account'],
                cloud: image['zone']
            }
          end
          print as_pretty_table(rows, [:id, :virtual_image_id, :virtual_image_name, :account, :cloud], options)
        end

      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[osTypeImage]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display osTypeImage details." + "\n" +
                    "[osTypeImage] is required. This is the id of an osTypeImage."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    id_list.each do |id|

    end
    return run_command_for_each_arg(id_list) do |arg|
      _get_image(arg, options)
    end
  end

  def _get_image(id)
    begin
      image = find_os_type_image_by_id(id)

      if image.nil?
        return 1
      end

      json_response = {'osTypeImage' => image}
    
      
      print_h1 "OsTypeImage Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "VirtualImage ID" => lambda {|it| it['virtualImageId'] },
        "VirtualImage Name" => lambda {|it| it['virtualImageName'] },
        "Account" => lambda {|it| it['account']},
        "Provision Type" => lambda {|it| it['provisionType']},
        "Cloud" => lambda {|it|it['zone']}
      }

      print_description_list(description_cols, image)

      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end
           


  def add_image(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('-o', '--osType VALUE', String, "Id of OsType") do |val|
        params['osType'] = val
      end
      opts.on('-v', '--virtualImage VALUE', String, "Id of Virtual Image") do |val|
        params['virtualImage'] = val
      end
      opts.on('-p', '--provisionType VALUE', String, "Provision Type") do |val|
        params['provisionType'] = val
      end
      opts.on('-z', '--zone VALUE', String, "Zone") do |val|
        params['zone'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create an OsType Image."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      params['osType'] = args[0]
    end
    begin
      if options[:payload]
        payload = options[:payload]
      else
        # support the old -O OPTION switch
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        
        # prompt for options
        if params['osType'].nil?
            params['osType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'osType', 'type' => 'select', 'fieldLabel' => 'Os Type', 'required' => true, 'optionSource' => 'osTypes'}], options[:options], @api_client,{})['osType']
        end

        if params['provisionType'].nil?
            params['provisionType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionType', 'type' => 'select', 'fieldLabel' => 'Provision Type', 'required' => false, 'optionSource' => 'provisionTypes'}], options[:options], @api_client,{'cli' => true})['provisionType']
        end

        if params['zone'].nil?
            params['zone'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zone', 'type' => 'select', 'fieldLabel' => 'Cloud', 'required' => false, 'optionSource' => 'clouds'}], options[:options], @api_client,{'provisionTypeIds' => params['provisionType']})['zone']
        end

        if params['virtualImage'].nil?
            virtual_image = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'virtualImage', 'fieldLabel' => 'Virtual Image', 'type' => 'select', 'required' => true, 'optionSource' => 'osTypeVirtualImage'}], options[:options], @api_client, {'osTypeImage' => params})['virtualImage']
  
            params['virtualImage'] = virtual_image
        end

        payload = {'osTypeImage' => params}
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.create_image(payload)
        return
      end

      json_response = @library_operating_systems_interface.create_image(payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Os Type Image"
      _get_image(json_response['id'])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def remove_image(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[osTypeImage]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete an Os Type Image." + "\n" +
                    "[osTypeImage] is required. This is the id of an osTypeImage."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      os_type_image = find_os_type_image_by_id(args[0])
      puts os_type_image
      if os_type_image.nil?
        return 1
      end

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the OsTypeImage?", options)
        exit
      end

      @library_operating_systems_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @library_operating_systems_interface.dry.destroy_image(os_type_image['id'])
        return
      end
      json_response = @library_operating_systems_interface.destroy_image(os_type_image['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        if json_response['success']
          print_green_success "Removed the OsTypeImage"
        else
          print_red_alert "Error removing osTypeImage: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private

  def find_os_type_by_id(id)
    begin
      json_response = @library_operating_systems_interface.get(id.to_i)
      return json_response['osType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "OsType not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_os_type_image_by_id(id)
    begin
      json_response = @library_operating_systems_interface.get_image(id.to_i)
      return json_response['osTypeImage']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "OsTypeImage not found by id #{id}"
      else
        raise e
      end
    end
  end
end