require 'morpheus/cli/cli_command'

class Morpheus::Cli::PriceSetsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'price-sets'

  register_subcommands :list, :get, :add, :update, :deactivate
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @options_interface = @api_client.options
    @accounts_interface = @api_client.accounts
    @price_sets_interface = @api_client.price_sets
    @prices_interface = @api_client.prices
    @clouds_interface = @api_client.clouds
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {'includeZones': true}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-t', '--type TYPE', String, "Filter by type") do |val|
        add_query_parameter(params, 'type', parse_array(val).collect {|it| get_price_set_type_code(it) })
      end
      opts.on('-i', '--include-inactive [on|off]', String, "Can be used to enable / disable inactive filter. Default is on") do |val|
        params['includeInactive'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List price sets."
    end
    optparse.parse!(args)
    connect(options)
    params.merge!(parse_list_options(options))
    params['phrase'] = args.join(' ') if args.count > 0 && params['phrase'].nil? # pass args as phrase, every list command should do this
    @price_sets_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @price_sets_interface.dry.list(params)
      return
    end
    json_response = @price_sets_interface.list(params)
    price_sets = json_response['priceSets']
    render_response(json_response, options, 'priceSets') do
      title = "Morpheus Price Sets"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if price_sets.empty?
        print cyan,"No price sets found.",reset,"\n"
      else
        rows = price_sets.collect do |it|
          {
              id: (it['active'] ? cyan : yellow) + it['id'].to_s,
              name: it['name'],
              active: format_boolean(it['active']),
              priceUnit: it['priceUnit'],
              type: price_set_type_label(it['type']),
              price_count: it['prices'].count.to_s + cyan
          }
        end
        columns = [
            :id, :name, :active, :priceUnit, :type, '# OF PRICES' => :price_count
        ]
        columns.delete(:active) if !params['includeInactive']
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if price_sets.empty?
      return 1,  "0 price sets found"
    else
      return 0, nil
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[price-set]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a price set.\n" +
          "[price-set] is required. Price set ID, name or code"
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], options)
  end

  def _get(price_set_id, options = {})
    params = {}
    begin
      @price_sets_interface.setopts(options)

      if !(price_set_id.to_s =~ /\A\d{1,}\Z/)
        price_set = find_price_set(price_set_id)

        if !price_set
          print_red_alert "Price set #{price_set_id} not found"
          exit 1
        end
        price_set_id = price_set['id']
      end

      if options[:dry_run]
        print_dry_run @price_sets_interface.dry.get(price_set_id)
        return
      end
      json_response = @price_sets_interface.get(price_set_id)

      render_result = render_with_format(json_response, options, 'priceSet')
      return 0 if render_result

      title = "Morpheus Price Set"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      price_set = json_response['priceSet']
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']},
          "Code" => lambda {|it| it['code']},
          "Region Code" => lambda {|it| it['regionCode']},
          "Price Unit" => lambda {|it| (it['priceUnit'] || 'month').capitalize},
          "Type" => lambda {|it| price_set_type_label(it['type'])},
          "Cloud" => lambda {|it| it['zone'].nil? ? 'All' : it['zone']['name']},
          "Resource Pool" => lambda {|it| it['zonePool'].nil? ? nil : it['zonePool']['name']}
      }

      print_description_list(description_cols, price_set)

      print_h2 "Prices"
      prices = price_set['prices']

      if prices && !prices.empty?
        rows = prices.collect do |it|
          {
              id: it['id'],
              name: it['name'],
              pricing: (it['priceType'] == 'platform' ? '+' : '') + currency_symbol(it['currency']) + (it['price'] || 0.0).to_s + (it['additionalPriceUnit'].nil? ? '' : '/' + it['additionalPriceUnit']) + '/' + (it['priceUnit'] || 'month').capitalize
          }
        end
        print as_pretty_table(rows, [:id, :name, :pricing], options)
      else
        print cyan,"No prices.",reset,"\n"
      end
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
      opts.on("--name NAME", String, "Price set name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--code CODE", String, "Price set code, unique identifier") do |val|
        params['code'] = val.to_s
      end
      opts.on("--region-code CODE", String, "Price set region code") do |val|
        params['regionCode'] = val.to_s
      end
      opts.on("--cloud [CLOUD]", String, "Cloud ID or name") do |val|
        options[:cloud] = val
      end
      opts.on("--resource-pool [POOL]", String, "Resource pool ID or name") do |val|
        options[:resourcePool] = val
      end
      opts.on("--price-unit [UNIT]", String, "Price unit") do |val|
        if price_units.include?(val)
          params['priceUnit'] = val
        else
          raise_command_error "Unrecognized price unit '#{val}'\n- Available price units -\n#{price_units.join("\n")}"
        end
      end
      opts.on('-t', "--type [TYPE]", String, "Price set type") do |val|
        if ['fixed', 'compute_plus_storage', 'component','load_balancer','snapshot','virtual_image','software_or_service'].include?(val)
          params['type'] = val
        else
          raise_command_error "Unrecognized price set type #{val}"
        end
      end
      opts.on('--prices [LIST]', Array, 'Price(s), comma separated list of price IDs') do |list|
        params['prices'] = list.collect {|it| it.to_s.strip.empty? || !it.to_i ? nil : it.to_s.strip}.compact.uniq.collect {|it| {'id' => it.to_i}}
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create price set.\n" +
        "Name, code, type and price unit are required."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      payload = parse_payload(options)

      if !payload
        # name
        params['name'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Price Set Name', 'required' => true, 'description' => 'Price Set Name.'}],options[:options],@api_client,{}, options[:no_prompt])['name']

        # code
        params['code'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'text', 'fieldLabel' => 'Price Set Code', 'required' => true, 'defaultValue' => params['name'].gsub(/[^0-9a-z ]/i, '').gsub(' ', '.').downcase, 'description' => 'Price Set Code.'}],options[:options],@api_client,{}, options[:no_prompt])['code']

        # region code
        params['regionCode'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'regionCode', 'type' => 'text', 'fieldLabel' => 'Price Set Region Code', 'required' => false, 'description' => 'Price Set Region Code.'}],options[:options],@api_client,{}, options[:no_prompt])['regionCode']

        # cloud
        if options[:cloud]
          cloud = find_cloud(options[:cloud])

          if cloud.nil?
            print_red_alert "Cloud #{options[:cloud]} not found"
            exit 1
          end
          params['zone'] = {'id' => cloud['id']}
        else
          cloud_id = Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'zone', 'type' => 'select', 'fieldLabel' => 'Cloud', 'required' => false, 'description' => 'Select cloud for price set', 'selectOptions' => @clouds_interface.list['zones'].collect {|it| {'name' => it['name'], 'value' => it['id']}}], options[:options], @api_client, {}, options[:no_prompt], true)['zone']

          if cloud_id
            params['zone'] = {'id' => cloud_id}
          end
        end

        # resource pool
        if options[:resourcePool]
          resource_pool = find_resource_pool(params['zone'].nil? ? nil : params['zone']['id'], options[:resourcePool])

          if resource_pool.nil?
            print_red_alert "Resource pool #{options[:resourcePool]} not found"
            exit 1
          end
          params['zonePool'] = {'id' => resource_pool['id']}
        else
          resource_pool_id = Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'zonePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'required' => false, 'description' => 'Select resource pool for price set', 'selectOptions' => @cloud_resource_pools_interface.list(params['zone'] ? params['zone']['id'] : nil)['resourcePools'].collect {|it| {'name' => it['name'], 'value' => it['id']}}], options[:options], @api_client, {}, options[:no_prompt], true)['zonePool']

          if resource_pool_id
            params['zonePool'] = {'id' => resource_pool_id}
          end
        end

        # price unit
        params['priceUnit'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priceUnit', 'type' => 'select', 'fieldLabel' => 'Price Unit', 'selectOptions' => price_units.collect {|it| {'name' => it.split(' ').collect {|it| it.capitalize}.join(' '), 'value' => it}}, 'required' => true, 'description' => 'Price Unit.', 'defaultValue' => 'month'}],options[:options],@api_client,{}, options[:no_prompt])['priceUnit']
        if params['priceUnit'].nil?
          print_red_alert "Price unit is required"
          exit 1
        end

        # type
        price_set_type_options = price_set_types.collect {|k,v| {'name' => v[:label], 'value' => k} }
        params['type'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Price Set Type', 'selectOptions' => price_set_type_options, 'required' => true, 'description' => 'Price Set Type.'}],options[:options],@api_client,{}, options[:no_prompt])['type']
        
        if params['type'].nil?
          print_red_alert "Type is required"
          exit 1
        end

        # required prices
        price_set_type = price_set_types[params['type']]
        prices = params['prices'] ? @prices_interface.list({'ids' => params['prices'].collect {|it| it['id']}})['prices'] : []
        required = price_set_type[:requires].reject {|it| prices.find {|price| price['priceType'] == it}}

        if !options[:no_prompt]
          params['prices'] ||= []
          while required.count > 0 do
            price_type = required.pop
            avail_prices = @prices_interface.list({'priceType' => price_type, 'priceUnit' => params['priceUnit'], 'max' => 10000})['prices'].reject {|it| params['prices'].find {|price| price['id'] == it['id']}}.collect {|it| {'name' => it['name'], 'value' => it['id']}}

            if avail_prices.count > 0
              price_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'price', 'type' => 'select', 'fieldLabel' => "Add #{price_type_label(price_type)} Price", 'selectOptions' => avail_prices, 'required' => true, 'description' => "'#{price_set_type[:label]}' price sets require 1 or more '#{price_type_label(price_type)}' price types"}],options[:options],@api_client,{}, options[:no_prompt], true)['price']
              params['prices'] << {'id' => price_id}
            else
              print_red_alert "'#{price_set_type[:label]}' price sets require 1 or more '#{price_type_label(price_type)}' price types, however there are none available for the #{params['priceUnit']} price unit."
              exit 1
            end
          end

          # additional prices
          avail_price_types = (price_set_type[:requires] + price_set_type[:allows]).collect {|it| {'name' => price_type_label(it), 'value' => it}}
          price_type = nil
          while Morpheus::Cli::OptionTypes.confirm("Add additional prices?", {default:false}) do
            price_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priceType', 'type' => 'select', 'fieldLabel' => "Price Type", 'selectOptions' => avail_price_types, 'required' => true, 'defaultValue' => price_type, 'description' => "Select Price Type"}],options[:options],@api_client,{}, options[:no_prompt], true)['priceType']
            avail_prices = @prices_interface.list({'priceType' => price_type, 'priceUnit' => params['priceUnit'], 'max' => 10000})['prices'].reject {|it| params['prices'].find {|price| price['id'] == it['id']}}.collect {|it| {'name' => it['name'], 'value' => it['id']}}

            if avail_prices.count > 0
              price_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'price', 'type' => 'select', 'fieldLabel' => "Add #{price_type_label(price_type)} Price", 'selectOptions' => avail_prices, 'required' => true, 'description' => "Add #{price_type_label(price_type)} Price"}],options[:options],@api_client,{}, options[:no_prompt], true)['price']
              params['prices'] << {'id' => price_id}
            else
              print_red_alert "No available prices for '#{price_type}'"
            end
          end
        end
        payload = {'priceSet' => params}
      end

      @price_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @price_sets_interface.dry.create(payload)
        return
      end
      json_response = @price_sets_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Price set created"
          _get(json_response['id'], options)
        else
          print_red_alert "Error creating price set: #{json_response['msg'] || json_response['errors']}"
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
      opts.banner = subcommand_usage("[price-set]")
      opts.on("--name NAME", String, "Price set name") do |val|
        params['name'] = val.to_s
      end
      opts.on('--restart-usage [on|off]', String, "Apply price changes to usage. Default is on") do |val|
        params['restartUsage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--prices [LIST]', Array, 'Price(s), comma separated list of price IDs') do |list|
        params['prices'] = list.collect {|it| it.to_s.strip.empty? || !it.to_i ? nil : it.to_s.strip}.compact.uniq.collect {|it| {'id' => it.to_i}}
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update price set.\n" +
          "[price-set] is required. Price set ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      price_set = find_price_set(args[0])

      if price_set.nil?
        print_red_alert "Price set #{args[0]} not found"
        exit 1
      end

      payload = parse_payload(options)

      if payload.nil?
        payload = {'priceSet' => params}
      end

      if payload['priceSet'].empty?
        print_green_success "Nothing to update"
        return
      end

      @price_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @price_sets_interface.dry.update(price_set['id'], payload)
        return
      end
      json_response = @price_sets_interface.update(price_set['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Price set updated"
          _get(price_set['id'], options)
        else
          print_red_alert "Error updating price set: #{json_response['msg'] || json_response['errors']}"
        end
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
      opts.banner = subcommand_usage( "[price-set]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Deactivate price set.\n" +
          "[price-set] is required. Price set ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      price_set = find_price_set(args[0])

      if !price_set
        print_red_alert "Price set #{args[0]} not found"
        exit 1
      end

      if price_set['active'] == false
        print_green_success "Price set #{price_set['name']} already deactived."
        return 0
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to deactivate the price set '#{price_set['name']}'?", options)
        return 9, "aborted command"
      end

      @price_sets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @price_sets_interface.dry.deactivate(price_set['id'], params)
        return
      end

      json_response = @price_sets_interface.deactivate(price_set['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Price set #{price_set['name']} deactivate"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def price_prefix(price)
    (['platform', 'software'].include?(price['priceType']) ? '+' : '') + currency_symbol(price['currency'])
  end

  def price_markup(price)
    if price['markupType'] == 'fixed'
      currency_symbol(price['currency']) + format_amount(price['markup'] || 0)
    elsif price['markupType'] == 'percent'
      (price['markupPercent'] || 0).to_s + '%'
    else
      'N/A'
    end
  end

  def find_price_set(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @price_sets_interface.get(val.to_i)['priceSet'] : @price_sets_interface.list({'code' => val, 'name' => val})["priceSets"].first
  end

  def find_cloud(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @clouds_interface.get(val.to_i)['zone'] : @clouds_interface.list({'name' => val})["zones"].first
  end

  def find_resource_pool(cloud_id, val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @cloud_resource_pools_interface.get(cloud_id, val.to_i)['resourcePool'] : @cloud_resource_pools_interface.list(cloud_id, {'name' => val})["resourcePools"].first
  end

  def price_set_type_label(type)
    price_set_type = price_set_types[type]
    if price_set_type.nil?
      type.capitalize
    else
      price_set_type[:label]
    end
  end

  def price_types
    {
        'fixed' => 'Everything',
        'compute' => 'Memory + CPU',
        'memory' => 'Memory Only',
        'cores' => 'Cores Only',
        'storage' => 'Disk Only',
        'datastore' => 'Datastore',
        'platform' => 'Platform',
        'software' => 'Software',
        'load_balancer' => 'Load Balancer',
        'load_balancer_virtual_server' => 'Load Balancer Virtual Server',
    }
  end

  def price_type_label(type)
    price_types[type] || type.capitalize
  end

  def price_units
    ['minute', 'hour', 'day', 'month', 'year', 'two year', 'three year', 'four year', 'five year']
  end

  def price_set_types
    {
        'fixed' => {:label => 'Everything', :requires => ['fixed'], :allows => ['platform', 'software']},
        'compute_plus_storage' => {:label => 'Compute + Storage', :requires => ['compute', 'storage'], :allows => ['platform', 'software']},
        'component' => {:label => 'Component', :requires => ['memory', 'cores', 'storage'], :allows => ['platform', 'software']},
        'load_balancer' => {:label => 'Load Balancer', :requires => ['load_balancer'], :allows => ['load_balancer_virtual_server']},
        'snapshot' => {:label => 'Snapshot', :requires => ['storage'], :allows => ['storage', 'datastore']},
        'virtual_image' => {:label => 'Virtual Image', :requires => ['storage'], :allows => []},
        'software_or_service' => {:label => 'Software / Service', :requires => ['software'], :allows => []},
    }
  end

  def get_price_set_type_code(value)
    rtn = value
    price_set_types.each do |k,v|
      if value.to_s.downcase == v[:label].downcase
        rtn = k
      end
    end
    return rtn
  end

  def format_amount(amount)
    rtn = amount.to_s
    if rtn.index('.').nil?
      rtn += '.00'
    elsif rtn.split('.')[1].length < 2
      print rtn.split('.')[1].length
      rtn = rtn + (['0'] * (2 - rtn.split('.')[1].length) * '')
    end
    rtn
  end
end
