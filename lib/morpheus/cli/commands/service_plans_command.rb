require 'morpheus/cli/cli_command'

class Morpheus::Cli::ServicePlanCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper

  set_command_name :'service-plans'

  register_subcommands :list, :get, :add, :update, :activate, :deactivate, :remove
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @service_plans_interface = @api_client.service_plans
    @provision_types_interface = @api_client.provision_types
    @options_interface = @api_client.options
    @accounts_interface = @api_client.accounts
    @price_sets_interface = @api_client.price_sets
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {'includeZones': true}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-t', '--provision-type VALUE', String, "Filter by provision type ID or code") do |val|
        options[:provisionType] = val
      end
      opts.on('-i', '--include-inactive [on|off]', String, "Can be used to enable / disable inactive filter. Default is on") do |val|
        params['includeInactive'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_standard_list_options(opts, options)
      opts.footer = "List service plans."
    end
    optparse.parse!(args)
    #verify_args!(args:args, optparse:optparse, count:0)
    connect(options)

    
    params.merge!(parse_list_options(options))

    if !options[:provisionType].nil?
      type = find_provision_type(options[:provisionType])

      if type.nil?
        print_red_alert "Provision type #{options[:provisionType]} not found"
        exit 1
      end
      params['provisionTypeId'] = type['id']
    end

    @service_plans_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @service_plans_interface.dry.list(params)
      return
    end
    json_response = @service_plans_interface.list(params)
    plans = json_response['servicePlans']
    render_response(json_response, options, 'servicePlans') do
      title = "Morpheus Service Plans"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      if plans.empty?
        print cyan,"No service plans found.",reset,"\n"
      else
        rows = plans.collect do |it|
          {
              id: (it['active'] ? cyan : yellow) + it['id'].to_s,
              name: it['name'],
              type: it['provisionType'] ? it['provisionType']['name'] : '',
              active: format_boolean(it['active']),
              cores: it['maxCores'],
              memory: format_bytes(it['maxMemory']),
              clouds: it['zones'] ? truncate_string(it['zones'].collect {|it| it['name']}.join(', '), 30) : '',
              visibility: (it['visibility'] || '').capitalize,
              tenants: it['tenants'] || 'Global',
              price_sets: (it['priceSets'] ? it['priceSets'].count : 0).to_s + cyan
          }
        end
        columns = [
            :id, :name, :type, :active, :cores, :memory, :clouds, :visibility, :tenants, {"PRICE SETS" => :price_sets}
        ]
        columns.delete(:active) if !params['includeInactive']
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if plans.empty?
      return 1,  "0 plans found"
    else
      return 0, nil
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[plan]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a service plan.\n" +
          "[plan] is required. Service plan ID, name or code"
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], options)
  end

  def _get(plan_id, options = {})
    params = {}
    begin
      if !(plan_id.to_s =~ /\A\d{1,}\Z/)
        plan = find_service_plan(plan_id)

        if !plan
          print_red_alert "Service plan #{plan_id} not found"
          exit 1
        end
        plan_id = plan['id']
      end
      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.get(plan_id)
        return
      end
      json_response = @service_plans_interface.get(plan_id)

      render_result = render_with_format(json_response, options, 'servicePlan')
      return 0 if render_result

      title = "Morpheus Service Plan"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      service_plan = json_response['servicePlan']
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name'] || (it['accountIntegration'] ? 'Pending' : 'Not Set')},
          "Active" => lambda {|it| format_boolean(it['active'])},
          "Visibility" => lambda {|it| (it['visibility'] || '').capitalize},
          "Code" => lambda {|it| it['code']},
          "Display Order" => lambda {|it| it['sortOrder']},
          "Provision Type" => lambda {|it| it['provisionType'] ? it['provisionType']['name'] : ''},
          "Server Type" => lambda {|it| it['serverType']},
          "Storage" => lambda {|it| printable_byte_size(it, it['maxStorage'], 'storageSizeType', 'GB')}
      }

      provision_type = service_plan['provisionType'] || {}

      description_cols['Customize Root Volume'] = lambda {|it| format_boolean(it['customMaxStorage'])} if provision_type['rootDiskCustomizable']
      description_cols['Customize Extra Volumes'] = lambda {|it| format_boolean(it['customMaxDataStorage'])} if provision_type['customizeVolume']
      description_cols['Add Volumes'] = lambda {|it| format_boolean(it['addVolumes'])} if provision_type['addVolumes']
      description_cols['Max Disks Allowed'] = lambda {|it| it['maxDisks'] || 0} if provision_type['addVolumes']
      description_cols['Memory'] = lambda {|it| printable_byte_size(it, it['maxMemory'], 'memorySizeType')}
      description_cols['Custom Max Memory'] = lambda {|it| format_boolean(it['customMaxMemory'])}
      description_cols['Core Count'] = lambda {|it| it['maxCores']}
      description_cols['Custom Cores'] = lambda {|it| format_boolean(it['customCores'])}
      description_cols['Cores Per Socket'] = lambda {|it| it['coresPerSocket']} if provision_type['hasConfigurableCpuSockets'] && service_plan['customCores']
      description_cols['Custom CPU'] = lambda {|it| format_boolean(it['customCpu'])}

      ranges = (service_plan['config'] ? service_plan['config']['ranges'] : nil) || {}

      if (ranges['minStorage'] && ranges['minStorage'] != '') || (ranges['maxStorage'] && ranges['maxStorage'] != '')
        description_cols['Custom Total Storage Range'] = lambda {|it|
          get_range(
              ranges['minStorage'] && ranges['minStorage'] != '' ? "#{ranges['minStorage']} #{(it['config'] && it['config']['storageSizeType'] ? it['config']['storageSizeType'] : 'GB').upcase}" : nil,
              ranges['maxStorage'] && ranges['maxStorage'] != '' ? "#{ranges['maxStorage']} #{(it['config'] && it['config']['storageSizeType'] ? it['config']['storageSizeType'] : 'GB').upcase}" : nil,
          )
        }
      end
      if (ranges['minPerDiskSize'] && ranges['minPerDiskSize'] != '') || (ranges['maxPerDiskSize'] && ranges['maxPerDiskSize'] != '')
        description_cols['Custom Per Disk Range'] = lambda {|it|
          get_range(
            ranges['minPerDiskSize'] && ranges['minPerDiskSize'] != '' ? "#{ranges['minPerDiskSize']} GB" : nil,
            ranges['maxPerDiskSize'] && ranges['maxPerDiskSize'] != '' ? "#{ranges['maxPerDiskSize']} GB" : nil
          )
        }
      end
      if (ranges['minMemory'] && ranges['minMemory'] != '') || (ranges['maxMemory'] && ranges['maxMemory'] != '')
        description_cols['Custom Memory Range'] = lambda {|it|
          get_range(
              ranges['minMemory'] && ranges['minMemory'] != '' ? printable_byte_size(it, ranges['minMemory'], 'memorySizeType') : nil,
              ranges['maxMemory'] && ranges['maxMemory'] != '' ? printable_byte_size(it, ranges['maxMemory'], 'memorySizeType') : nil
          )
        }
      end
      if (ranges['minCores'] && ranges['minCores'] != '') || (ranges['maxCores'] && ranges['maxCores'] != '')
        description_cols['Custom Cores Range'] = lambda {|it|
          get_range(
              ranges['minCores'] && ranges['minCores'] != '' ? ranges['minCores'] : nil,
              ranges['maxCores'] && ranges['maxCores'] != '' ? ranges['maxCores'] : nil
          )
        }
      end

      print_description_list(description_cols, service_plan)

      print_h2 "Price Sets"
      price_sets = service_plan['priceSets']

      if price_sets && !price_sets.empty?
        rows = price_sets.collect do |it|
          {
              id: it['id'],
              unit: (it['priceUnit'] || '').capitalize,
              name: it['name']
          }
        end
        columns = [
            :id, :unit, :name
        ]
        print as_pretty_table(rows, columns, options)
      else
        print cyan,"No price sets.",reset,"\n"
      end

      print_permissions(service_plan['permissions'], ['plans', 'groupDefaults'])
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("--name NAME", String, "Service plan name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--code CODE", String, "Service plan code, unique identifier") do |val|
        params['code'] = val.to_s
      end
      opts.on('-t', '--provision-type [TYPE]', String, "Provision type ID or code") do |val|
        options[:provisionType] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        params['description'] = val.to_s
      end
      opts.on('--active [on|off]', String, "Can be used to enable / disable the plan. Default is on") do |val|
        params['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--editable [on|off]', String, "Can be used to enable / disable the editability of the service plan. Default is on") do |val|
        params['editable'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--storage [AMOUNT]', String, "Storage size is required. Assumes GB unless optional modifier specified, ex: 512MB" ) do |val|
        bytes = parse_bytes_param(val, '--storage', 'GB', true)
        params['maxStorage'] = bytes[:bytes]
        (params['config'] ||= {})['storageSizeType'] = bytes[:unit].downcase
      end
      opts.on('--memory [AMOUNT]', String, "Memory size is required. Assumes MB unless optional modifier specified, ex: 1GB" ) do |val|
        bytes = parse_bytes_param(val, '--memory', 'MB', true)
        params['maxMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--cores [NUMBER]', Integer, "Core count. Default is 1" ) do |val|
        params['maxCores'] = val.to_i || 1
      end
      opts.on('--disks [NUMBER]', Integer, "Max disks allowed" ) do |val|
        params['maxDisks'] = val.to_i || 1
      end
      opts.on('--cores-per-socket [NUMBER]', Integer, "Cores Per Socket") do |val|
        params['coresPerSocket'] = val.to_i || 1
      end
      opts.on('--custom-cores [on|off]', String, "Can be used to enable / disable customizable cores. Default is on") do |val|
        params['customCores'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-cpu [on|off]', String, "Can be used to enable / disable customizable CPUs. Default is on") do |val|
        params['customCpu'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-storage [on|off]', String, "Can be used to enable / disable customizable storage. Default is on") do |val|
        params['customMaxStorage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-volumes [on|off]', String, "Can be used to enable / disable customizable extra volumes. Default is on") do |val|
        params['customMaxDataStorage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-memory [on|off]', String, "Can be used to enable / disable customizable memory. Default is on") do |val|
        params['customMaxMemory'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--add-volumes [on|off]', String, "Can be used to enable / disable ability to add volumes. Default is on") do |val|
        params['addVolumes'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--sort-order NUMBER', Integer, "Sort order") do |val|
        params['sortOrder'] = val.to_i
      end
      opts.on('--price-sets [LIST]', Array, 'Price set(s), comma separated list of price set IDs') do |list|
        params['priceSets'] = list.collect {|it| it.to_s.strip.empty? || !it.to_i ? nil : it.to_s.strip}.compact.uniq.collect {|it| {'id' => it.to_i}}
      end
      opts.on('--min-storage NUMBER', String, "Min total storage in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minStorage'] = val.to_i
      end
      opts.on('--max-storage NUMBER', String, "Max total storage in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxStorage'] = val.to_i
      end
      opts.on('--min-per-disk-size NUMBER', String, "Min per disk size in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minPerDiskSize'] = val.to_i
      end
      opts.on('--max-per-disk-size NUMBER', String, "Max per disk size in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxPerDiskSize'] = val.to_i
      end
      opts.on('--min-memory NUMBER', String, "Min memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        # Memory does get converted to bytes
        bytes = parse_bytes_param(val, '--min-memory', 'MB', true)
        ((params['config'] ||= {})['ranges'] ||= {})['minMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--max-memory NUMBER', String, "Max memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        # Memory does get converted to bytes
        bytes = parse_bytes_param(val, '--max-memory', 'MB', true)
        ((params['config'] ||= {})['ranges'] ||= {})['maxMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--min-cores NUMBER', String, "Min cores") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minCores'] = val.to_i
      end
      opts.on('--max-cores NUMBER', String, "Max cores") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxCores'] = val.to_i
      end
      opts.on('--min-sockets NUMBER', String, "Min sockets") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minSockets'] = val.to_i
      end
      opts.on('--max-sockets NUMBER', String, "Max sockets") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxSockets'] = val.to_i
      end
      opts.on('--min-cores-per-socket NUMBER', String, "Min cores per socket") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minCoresPerSocket'] = val.to_i
      end
      opts.on('--max-cores-per-socket NUMBER', String, "Max cores per socket") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxCoresPerSocket'] = val.to_i
      end
      add_perms_options(opts, options, ['plans', 'groupDefaults'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create service plan"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      if options[:payload]
        payload = parse_payload(options, 'servicePlan')
      else
        apply_options(params, options)

        # name
        params['name'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Service Plan Name', 'required' => true, 'description' => 'Service Plan Name.'}],options[:options],@api_client,{}, options[:no_prompt])['name']

        # code
        params['code'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'text', 'fieldLabel' => 'Service Plan Code', 'required' => true, 'defaultValue' => params['name'].gsub(/[^0-9a-z ]/i, '').gsub(' ', '.').downcase, 'description' => 'Service Plan Code.'}],options[:options],@api_client,{}, options[:no_prompt])['code']

        # provision type
        options[:provisionType] = options[:provisionType] || (args.count > 1 ? args[1] : nil)
        provision_types = @service_plans_interface.provision_types()['provisionTypes']

        if options[:provisionType].nil? && !options[:no_prompt]
          provision_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'provisionType', 'type' => 'select', 'fieldLabel' => 'Provision Type', 'selectOptions' => provision_types.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Provision Type.'}],options[:options],@api_client,{}, options[:no_prompt], true)['provisionType']

          if !provision_type_id.nil?
            provision_type = provision_types.find {|it| it['id'] == provision_type_id}
          end
        else
          provision_type = provision_types.find {|it| it['name'] == options[:provisionType] || it['code'] == options[:provisionType] || it['id'] == options[:provisionType].to_i}

          if provision_type.nil?
            print_red_alert "Provision type #{options[:provisionType]} not found"
            exit 1
          end
        end

        params['provisionType'] = {'id' => provision_type['id']} if !provision_type.nil?

        # storage is required
        if params['maxStorage'].nil?
          if options[:no_prompt]
            print_red_alert "Storage size is required"
            exit 1
          end
          while params['maxStorage'].nil? do
            begin
              bytes = parse_bytes_param(
                  Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storage', 'type' => 'text', 'fieldLabel' => 'Storage (GB) [can use MB modifier]', 'required' => true, 'description' => 'Storage (GB)', 'defaultValue' => '0'}],options[:options],@api_client,{}, options[:no_prompt])['storage'],
                  'storage',
                  'GB',
                  true
              )
              params['maxStorage'] = bytes[:bytes]
              # (params['config'] ||= {})['storageSizeType'] = bytes[:unit].downcase
            rescue
              print "Invalid Value... Please try again.\n"
            end
          end
        end

        # memory is required
        if params['maxMemory'].nil?
          if options[:no_prompt]
            print_red_alert "Memory size is required"
            exit 1
          end
          while params['maxMemory'].nil? do
            begin
              bytes = parse_bytes_param(
                  Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'memory', 'type' => 'text', 'fieldLabel' => 'Memory (MB) [can use GB modifier]', 'required' => true, 'description' => 'Memory (MB)', 'defaultValue' => '0'}],options[:options],@api_client,{}, options[:no_prompt])['memory'],
                  'memory',
                  'MB',
                  true
              )
              params['maxMemory'] = bytes[:bytes]
            rescue
              print "Invalid Value... Please try again.\n"
            end
            params['customMaxMemory'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'customMaxMemory', 'type' => 'checkbox', 'fieldLabel' => 'Custom Max Memory', 'required' => false, 'description' => 'Custom Max Memory', 'defaultValue' => false}],options[:options],@api_client,{}, options[:no_prompt])['customMaxMemory']
          end
        end

        # add'n options
        addn_options = [
          {'fieldName' => 'maxCores', 'fieldLabel' => 'Core Count', 'type' => 'number', 'required' => true, 'defaultValue' => 1, 'displayOrder' => 1},
          {'fieldName' => 'customCores', 'fieldLabel' => 'Custom Cores', 'type' => 'checkbox', 'defaultValue' => false, 'displayOrder' => 2},
          {'fieldName' => 'coresPerSocket', 'fieldLabel' => 'Cores Per Socket', 'type' => 'number', 'required' => true, 'defaultValue' => 1, 'displayOrder' => 3},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minStorage', 'fieldLabel' => 'Min Total Storage (GB)', 'type' => 'number', 'displayOrder' => 1},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxStorage', 'fieldLabel' => 'Max Total Storage (GB)', 'type' => 'number', 'displayOrder' => 2},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minPerDiskSize', 'fieldLabel' => 'Min Per Disk Size (GB)', 'type' => 'number', 'displayOrder' => 3},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxPerDiskSize', 'fieldLabel' => 'Max Per Disk Size (GB)', 'type' => 'number', 'displayOrder' => 4},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory (GB)', 'type' => 'number', 'displayOrder' => 5},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory (GB)', 'type' => 'number', 'displayOrder' => 6},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minCores', 'fieldLabel' => 'Min Cores', 'type' => 'number', 'displayOrder' => 7},
          {'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxCores', 'fieldLabel' => 'Max Cores', 'type' => 'number', 'displayOrder' => 8}
        ]

        if provision_type['hasSocketRange']
          addn_options.push({'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minSockets', 'fieldLabel' => 'Min Sockets', 'type' => 'number', 'displayOrder' => 9})
          addn_options.push({'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxSockets', 'fieldLabel' => 'Max Sockets', 'type' => 'number', 'displayOrder' => 10})
        end

        if provision_type['hasCoresPerSocketRange']
          addn_options.push({'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'minCoresPerSocket', 'fieldLabel' => 'Min Cores Per Socket', 'type' => 'number', 'displayOrder' => 11})
          addn_options.push({'fieldContext' => 'config.ranges', 'fieldGroup' => 'Custom Ranges', 'fieldName' => 'maxCoresPerSocket', 'fieldLabel' => 'Max Cores Per Socket', 'type' => 'number', 'displayOrder' => 12})
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt(addn_options, options[:options], @api_client, params)
        params.deep_merge!(v_prompt)

        # price sets
        if params['priceSets'].nil? && !options[:no_prompt]
          price_sets = []
          while Morpheus::Cli::OptionTypes.confirm("Add #{price_sets.empty? ? '' : 'another '}price set?", {:default => false}) do
            price_unit = prompt_price_unit(options)

            avail_price_sets ||= @price_sets_interface.list({'priceUnit' => price_unit, 'max' => 10000})['priceSets'].collect {|it| {'name' => it['name'], 'value' => it['id'], 'priceUnit' => it['priceUnit']}}

            if price_set_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priceSet', 'type' => 'select', 'fieldLabel' => 'Price Set', 'selectOptions' => avail_price_sets, 'required' => false, 'description' => 'Select Price.'}],options[:options],@api_client,{}, options[:no_prompt], true)['priceSet']
              price_set = avail_price_sets.find {|it| it['value'] == price_set_id}
              price_sets << {'id' => price_set['value'], 'priceUnit' => price_set['priceUnit']}
              avail_price_sets.reject! {|it| it['value'] == price_set_id}
            end

            if avail_price_sets.empty?
              break
            end
          end
          params['priceSets'] = price_sets if !price_sets.empty?
        end

        # permissions
        if !options[:no_prompt]
          perms = prompt_permissions(options, ['plans', 'groupDefaults'])
          if perms['resourcePool'] && !perms['resourcePool']['visibility'].nil?
            params['visibility'] = perms['resourcePool']['visibility']
          end
          perms.delete('resourcePool')
          params['permissions'] = perms
        end
        payload = {'servicePlan' => params}
      end

      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.create(payload)
        return
      end
      json_response = @service_plans_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Service plan created"
          _get(json_response['id'], options)
        else
          print_red_alert "Error creating service plan: #{json_response['msg'] || json_response['errors']}"
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[plan]")
      opts.on("--name NAME", String, "Service plan name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--code CODE", String, "Service plan code, unique identifier") do |val|
        params['code'] = val.to_s
      end
      opts.on('-t', "--provision-type [TYPE]", String, "Provision type ID or code") do |val|
        options[:provisionType] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        params['description'] = val.to_s
      end
      opts.on('--active [on|off]', String, "Can be used to enable / disable the plan. Default is on") do |val|
        params['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--storage [AMOUNT]', String, "Storage size is required. Assumes GB unless optional modifier specified, ex: 512MB" ) do |val|
        bytes = parse_bytes_param(val, '--storage', 'GB', true)
        params['maxStorage'] = bytes[:bytes]
        (params['config'] ||= {})['storageSizeType'] = bytes[:unit].downcase
      end
      opts.on('--memory [AMOUNT]', String, "Memory size is required. Assumes MB unless optional modifier specified, ex: 1GB" ) do |val|
        bytes = parse_bytes_param(val, '--memory', 'MB', true)
        params['maxMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--cores [NUMBER]', Integer, "Core count. Default is 1" ) do |val|
        params['maxCores'] = val.to_i || 1
      end
      opts.on('--disks [NUMBER]', Integer, "Max disks allowed" ) do |val|
        params['maxDisks'] = val.to_i || 1
      end
      opts.on('--custom-cores [on|off]', String, "Can be used to enable / disable customizable cores. Default is on") do |val|
        params['customCores'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-cpu [on|off]', String, "Can be used to enable / disable customizable CPUs. Default is on") do |val|
        params['customCpu'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-storage [on|off]', String, "Can be used to enable / disable customizable storage. Default is on") do |val|
        params['customMaxStorage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-volumes [on|off]', String, "Can be used to enable / disable customizable extra volumes. Default is on") do |val|
        params['customMaxDataStorage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--custom-memory [on|off]', String, "Can be used to enable / disable customizable memory. Default is on") do |val|
        params['customMaxMemory'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--add-volumes [on|off]', String, "Can be used to enable / disable ability to add volumes. Default is on") do |val|
        params['addVolumes'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--sort-order NUMBER', Integer, "Sort order") do |val|
        params['sortOrder'] = val.to_i
      end
      opts.on('--price-sets [LIST]', Array, 'Price set(s), comma separated list of price set IDs') do |list|
        params['priceSets'] = list.collect {|it| it.to_s.strip.empty? || !it.to_i ? nil : it.to_s.strip}.compact.uniq.collect {|it| {'id' => it.to_i}}
      end
      opts.on('--min-storage NUMBER', String, "Min total storage in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minStorage'] = val.to_i
      end
      opts.on('--max-storage NUMBER', String, "Max total storage in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxStorage'] = val.to_i
      end
      opts.on('--min-per-disk-size NUMBER', String, "Min per disk size in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minPerDiskSize'] = val.to_i
      end
      opts.on('--max-per-disk-size NUMBER', String, "Max per disk size in GB.") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxPerDiskSize'] = val.to_i
      end
      opts.on('--min-memory NUMBER', String, "Min memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        # Memory does get converted to bytes
        bytes = parse_bytes_param(val, '--min-memory', 'MB')
        ((params['config'] ||= {})['ranges'] ||= {})['minMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--max-memory NUMBER', String, "Max memory. Assumes MB unless optional modifier specified, ex: 1GB") do |val|
        # Memory does get converted to bytes
        bytes = parse_bytes_param(val, '--max-memory', 'MB', true)
        ((params['config'] ||= {})['ranges'] ||= {})['maxMemory'] = bytes[:bytes]
        (params['config'] ||= {})['memorySizeType'] = bytes[:unit].downcase
      end
      opts.on('--min-cores NUMBER', String, "Min cores") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minCores'] = val.to_i
      end
      opts.on('--max-cores NUMBER', String, "Max cores") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxCores'] = val.to_i
      end
       opts.on('--min-sockets NUMBER', String, "Min sockets") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minSockets'] = val.to_i
      end
      opts.on('--max-sockets NUMBER', String, "Max sockets") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxSockets'] = val.to_i
      end
      opts.on('--min-cores-per-socket NUMBER', String, "Min cores per socket") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['minCoresPerSocket'] = val.to_i
      end
      opts.on('--max-cores-per-socket NUMBER', String, "Max cores per socket") do |val|
        ((params['config'] ||= {})['ranges'] ||= {})['maxCoresPerSocket'] = val.to_i
      end
      add_perms_options(opts, options, ['plans', 'groupDefaults'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update service plan.\n[plan] is required. Service plan ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      plan = find_service_plan(args[0])

      if plan.nil?
        print_red_alert "Service plan #{args[0]} not found"
        exit 1
      end

      if options[:payload]
        payload = parse_payload(options, 'servicePlan')
      else
        apply_options(params, options)

        # provision type
        options[:provisionType] = options[:provisionType] || (args.count > 1 ? args[1] : nil)

        if !options[:provisionType].nil?
          provision_types = @service_plans_interface.provision_types({max: 10000})['provisionTypes']
          provision_type = provision_types.find {|it| it['name'] == options[:provisionType] || it['code'] == options[:provisionType] || it['id'] == options[:provisionType].to_i}

          if provision_type.nil?
            print_red_alert "Provision type #{options[:provisionType]} not found"
            exit 1
          end
          params['provisionType'] = {'id' => provision_type['id']} if !provision_type.nil?
        end

        # perms
        resource_perms = {}
        resource_perms['all'] = true if options[:groupAccessAll]
        resource_perms['sites'] = options[:groupAccessList].collect {|site_id| {'id' => site_id.to_i}} if !options[:groupAccessList].nil?

        if !resource_perms.empty? || !options[:tenants].nil?
          params['permissions'] = {}
          params['permissions']['resourcePermissions'] = resource_perms if !resource_perms.empty?
          params['permissions']['tenantPermissions'] = {'accounts' => options[:tenants]} if !options[:tenants].nil?
        end

        # visibility
        params['visibility'] = options[:visibility] if !options[:visibility].nil?

        payload = {'servicePlan' => params}
      end

      if payload.empty? || !payload['servicePlan'] || payload['servicePlan'].empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
        # print_green_success "Nothing to update"
        # return 0
      end

      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.update(plan['id'], payload)
        return
      end
      json_response = @service_plans_interface.update(plan['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Service plan updated"
          _get(plan['id'], options)
        else
          print_red_alert "Error updating service plan: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  
  def activate(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[plan]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :auto_confirm])
      opts.footer = "Activate service plan.\n" +
          "[plan] is required. Service plan ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      plan = find_service_plan(args[0])

      if !plan
        print_red_alert "Service plan #{args[0]} not found"
        return 1
      end

      # if plan['active'] == true
      #   print_green_success "Service plan #{plan['name']} already actived."
      #   return 0
      # end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to activate the service plan '#{plan['name']}'?", options)
        return 9, "aborted command"
      end

      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.activate(plan['id'], params)
        return
      end

      json_response = @service_plans_interface.activate(plan['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Service plan #{plan['name']} activated"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def deactivate(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[plan]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :auto_confirm])
      opts.footer = "Deactivate service plan.\n" +
          "[plan] is required. Service plan ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      plan = find_service_plan(args[0])

      if !plan
        print_red_alert "Service plan #{args[0]} not found"
        return 1
      end

      # if plan['active'] == false
      #   print_green_success "Service plan #{plan['name']} already deactivated."
      #   return 0
      # end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to deactivate the service plan '#{plan['name']}'?", options)
        return 9, "aborted command"
      end

      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.deactivate(plan['id'], params)
        return
      end

      json_response = @service_plans_interface.deactivate(plan['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Service plan #{plan['name']} deactivated"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[plan]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :auto_confirm])
      opts.footer = "Delete a service plan.\n" +
        "[plan] is required. Service plan ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      plan = find_service_plan(args[0])

      if !plan
        print_red_alert "Service plan #{args[0]} not found"
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete the service plan '#{plan['name']}'?", options)
        return 9, "aborted command"
      end

      @service_plans_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @service_plans_interface.dry.destroy(plan['id'], params)
        return
      end

      json_response = @service_plans_interface.destroy(plan['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Service plan #{plan['name']} deleted"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_service_plan(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @service_plans_interface.get(val.to_i)['servicePlan'] : @service_plans_interface.list({'code' => val, 'name' => val})["servicePlans"].first
  end

  def find_provision_type(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @provision_types_interface.get(val.to_i)['provisionType'] : @provision_types_interface.list({'name' => val})["provisionTypes"].first
  end

  def printable_byte_size(plan, val, config_field, default_unit = 'MB')
    label = (((plan['config'] && plan['config'][config_field]) || default_unit) == 'MB' || val.to_i < 1024 * 1024 * 1024) ? 'MB' : 'GB'
    val = (val.to_i || 0) / (label == 'MB' ? 1024 * 1024 : 1024 * 1024 * 1024)
    "#{val} #{label}"
  end

  def get_range(min_val, max_val)
    if min_val && max_val
      "#{min_val} - #{max_val}"
    elsif min_val
      "> #{min_val}"
    elsif max_val
      "< #{max_val}"
    else
      ""
    end
  end

  def prompt_price_unit(options)
    price_units = ['Minute', 'Hour', 'Day', 'Month', 'Year', '2 Year', '3 Year', '4 Year', '5 Year'].collect {|it| {'name' => it, 'value' => it.downcase.delete(' ')}}
    Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priceUnit', 'type' => 'select', 'fieldLabel' => 'Price Unit', 'selectOptions' => price_units, 'required' => true, 'defaultValue' => 'hour', 'description' => 'Select Price Unit.'}],options[:options],@api_client,{})['priceUnit']
  end
end
