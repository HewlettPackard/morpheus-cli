require 'morpheus/cli/cli_command'

class Morpheus::Cli::PricesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'prices'

  register_subcommands :list, :get, :add, :update, :deactivate
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @prices_interface = @api_client.prices
    @accounts_interface = @api_client.accounts
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-i', '--include-inactive [on|off]', String, "Can be used to enable / disable inactive filter. Default is on") do |val|
        params['includeInactive'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--platform PLATFORM', Array, "Filter by platform eg. linux, windows") do |val|
        params['platform'] = val.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact
      end
      opts.on('--price-unit UNIT', Array, "Filter by priceUnit eg. hour, month") do |val|
        params['priceUnit'] = val.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact
      end
      opts.on('--currency CURRENCY', Array, "Filter by currency eg. usd") do |val|
        params['currency'] = val.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact
      end
      opts.on('--price-type TYPE', String, "Filter by priceType eg. fixed,platform,software,compute,storage,datastore,memory,cores,cpu") do |val|
        add_query_parameter(params, 'priceType', parse_array(val).collect {|it| get_price_type_code(it) })
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List prices."
    end
    optparse.parse!(args)
    #verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    
    params.merge!(parse_list_options(options))
    params['phrase'] = args.join(' ') if args.count > 0 && params['phrase'].nil? # pass args as phrase, every list command should do this
    load_whoami()
    @prices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @prices_interface.dry.list(params)
      return
    end
    json_response = @prices_interface.list(params)
    prices = json_response['prices']
    render_response(json_response, options, 'prices') do
      title = "Morpheus Prices"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if prices.empty?
        print cyan,"No prices found.",reset,"\n"
      else
        rows = prices.collect do |it|
          {
              id: (it['active'] ? cyan : yellow) + it['id'].to_s,
              name: it['name'],
              active: format_boolean(it['active']),
              priceType: price_type_label(it['priceType']),
              tenant: it['account'].nil? ? (is_master_account ? 'All Tenants' : nil) : it['account']['name'],
              priceUnit: it['priceUnit'].nil? ? nil : it['priceUnit'].capitalize,
              priceAdjustment: it['markupType'].nil? ? 'None' : it['markupType'].capitalize,
              cost: price_prefix(it) + format_amount(it['cost'] || 0),
              markup: price_markup(it),
              price: price_prefix(it) + format_amount(it['markupType'] == 'custom' ? it['customPrice'] || 0 : it['price'] || 0) + cyan
          }
        end
        columns = [
            :id, :name, :active, {'PRICE TYPE' => :priceType}, :tenant, {'PRICE UNIT' => :priceUnit}, {'PRICE ADJUSTMENT' => :priceAdjustment}, :cost, :markup, :price
        ]
        columns.delete(:active) if !params['includeInactive']

        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[price]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a price.\n" +
          "[price] is required. Price ID, name or code"
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    return _get(args[0], options)
  end

  def _get(price_id, options = {})
    params = {}
    begin
      @prices_interface.setopts(options)

      if !(price_id.to_s =~ /\A\d{1,}\Z/)
        price = find_price(price_id)

        if !price
          print_red_alert "Price #{price_id} not found"
          exit 1
        end
        price_id = price['id']
      end

      if options[:dry_run]
        print_dry_run @prices_interface.dry.get(price_id)
        return
      end
      json_response = @prices_interface.get(price_id)

      render_result = render_with_format(json_response, options, 'price')
      return 0 if render_result

      title = "Morpheus Price"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      price = json_response['price']
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']},
          "Code" => lambda {|it| it['code']},
          "Tenant" => lambda {|it| it['account'].nil? ? (is_master_account ? 'All Tenants' : nil) : it['account']['name']},
          "Price Type" => lambda {|it| price_type_label(it['priceType'])}
      }

      if price['priceType'] == 'platform'
        description_cols['Platform'] = lambda {|it| it['platform'].nil? ? nil : it['platform'].capitalize}
      elsif price['priceType'] == 'software'
        description_cols['Software'] = lambda {|it| it['software'].nil? ? nil : it['software']}
      elsif price['priceType'] == 'storage'
        description_cols['Volume Type'] = lambda {|it| it['volumeType'].nil? ? nil : it['volumeType']['name']}
      elsif price['priceType'] == 'datastore'
        description_cols['Data Store'] = lambda {|it| it['datastore'].nil? ? nil : it['datastore']['name']}
        description_cols['Apply Across Clouds'] = lambda {|it| it['crossCloudApply'] == true ? 'On' : 'Off'}
      end

      description_cols['Price Unit'] = lambda {|it| it['priceUnit'].nil? ? nil : it['priceUnit'].capitalize}
      description_cols['Incur Charges'] = lambda {|it| it['incurCharges'].nil? ? nil : (it['incurCharges'] != 'always' ? 'While ' : '') + it['incurCharges'].capitalize}
      description_cols['Currency'] = lambda {|it| (it['currency'] || '').upcase}
      description_cols['Cost'] = lambda {|it| price_prefix(it) + format_amount(it['cost'] || 0)}
      description_cols['Price Adjustment'] = lambda {|it| it['markupType'].nil? ? 'None' : it['markupType'].capitalize}

      if ['fixed', 'percent'].include?(price['markupType'])
        description_cols['Markup'] = lambda {|it| price_markup(it)}
      end

      description_cols['Custom Price'] = lambda {|it| price_prefix(it) + format_amount(it['customPrice'] || 0)}

      print_description_list(description_cols, price)
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
      opts.banner = subcommand_usage("[name] [code]")
      opts.on("--name NAME", String, "Price name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--code CODE", String, "Price code, unique identifier") do |val|
        params['code'] = val.to_s
      end
      opts.on("--tenant [ACCOUNT|all]", String, "Tenant account or all. Apply price to all tenants when not set.") do |val|
        options[:tenant] = val
      end
      opts.on("--type [TYPE]", String, "Price type") do |val|
        if price_types[val]
          params['priceType'] = val
        else
          raise_command_error "Invalid price type '#{val}'. Available price types: #{price_types.keys.join(', ')}"
        end
      end
      opts.on("--unit [UNIT]", String, "Price unit") do |val|
        if price_units.include?(val)
          params['priceUnit'] = val
        else
          raise_command_error "Invalid price unit '#{val}'. Available price units: #{price_units.join(', ')}"
        end
      end
      opts.on("--platform [PLATFORM]", String, "Price platform [centos|debian|fedora|canonical|opensuse|redhat|suse|xen|linux|windows]. Required for platform price type") do |val|
        if ['centos','debian','fedora','canonical','opensuse','redhat','suse','xen','linux', 'windows'].include?(val)
          params['platform'] = val
        else
          raise_command_error "Invalid platform '#{val}'. Available platforms/vendors: centos, debian, fedora, canonical, opensuse, redhat, suse, xen, linux, windows"
        end
      end
      opts.on("--software [TEXT]", String, "Price software. Required for software price type") do |val|
        params['software'] = val
      end
      opts.on("--volume [TYPE]", String, "Volume type ID or name. Required for storage price type") do |val|
        options[:volumeType] = val
      end
      opts.on("--datastore [DATASTORE]", String, "Datastore ID or name. Required for datastore price type") do |val|
        options[:datastore] = val
      end
      opts.on("--cross-apply [on|off]", String, "Apply price across clouds. Applicable for datastore price type only") do |val|
        options[:crossCloudApply] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--incur [WHEN]", String, "Incur charges [running|stopped|always]") do |val|
        if ['running', 'stopped', 'always'].include?(val)
          params['incurCharges'] = val
        else
          raise_command_error "Invalid incur charges '#{val}'. Available options: running, stopped, always"
        end
      end
      opts.on("--currency [CURRENCY]", String, "Price currency") do |val|
        options[:currency] = val
      end
      opts.on("--cost [AMOUNT]", Float, "Price cost") do |val|
        params['cost'] = val
      end
      opts.on("--fixed-markup [AMOUNT]", Float, "Add fixed price adjustment") do |val|
        params['markupType'] = 'fixed'
        params['markup'] = val
      end
      opts.on("--percent-markup [PERCENT]", Float, "Add percent price adjustment") do |val|
        params['markupType'] = 'percent'
        params['markupPercent'] = val
      end
      opts.on("--custom-price [AMOUNT]", Float, "Set customer price directly. Can be used to override price calculation based on cost and markup") do |val|
        params['markupType'] = 'custom'
        params['customPrice'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create price"
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    if options[:currency]
      if avail_currencies.include?(options[:currency].upcase)
        params['currency'] = options[:currency].upcase
      else
        raise_command_error "Unsupported currency '#{options[:currency]}'. Available currencies: #{avail_currencies.join(', ')}"
        return 1
      end
    end

    begin
      payload = parse_payload(options)

      if !payload
        # name
        params['name'] ||= args[0] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Price Name', 'required' => true, 'description' => 'Price Set Name.'}],options[:options],@api_client,{}, options[:no_prompt])['name']

        # code
        params['code'] ||= args[1] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'text', 'fieldLabel' => 'Price Code', 'required' => true, 'defaultValue' => params['name'].gsub(/[^0-9a-z ]/i, '').gsub(' ', '.').downcase, 'description' => 'Price Set Code.'}],options[:options],@api_client,{}, options[:no_prompt])['code']

        # tenant
        if options[:tenant].nil?
          account_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'account', 'type' => 'select', 'fieldLabel' => 'Tenant', 'required' => false, 'description' => 'Assign price to tenant', 'selectOptions' => accounts_interface.list()['accounts'].collect {|it| {'name' => it['name'], 'value' => it['id']}}}], options[:options], @api_client, {}, options[:no_prompt])['account']
          if account_id
            params['account'] = {'id' => account_id}
          end
        elsif options[:tenant] != 'all'
          if account = find_account_by_name_or_id(options[:tenant])
            params['account'] = {'id' => account['id']}
          else
            print_red_alert "Tenant #{options[:tenant]} not found"
            exit 1
          end
        end

        # type (platform, software, datastore, storage)
        params['priceType'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'priceType', 'type' => 'select', 'fieldLabel' => 'Price Type', 'required' => true, 'description' => 'Select price type', 'selectOptions' => price_types.collect {|k,v| {'name' => v, 'value' => k}}}], options[:options], @api_client, {}, options[:no_prompt])['priceType']

        # price type
        prompt_for_price_type(params, options)

        # unit
        params['priceUnit'] ||= Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'priceUnit', 'type' => 'select', 'fieldLabel' => 'Price Unit', 'required' => true, 'description' => 'Select price unit', 'defaultValue' => 'month', 'selectOptions' => price_units.collect {|it| {'name' => it.split(' ').collect {|it| it.capitalize}.join(' '), 'value' => it}}], options[:options], @api_client, {}, options[:no_prompt])['priceUnit']

        # incur
        params['incurCharges'] ||= Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'incurCharges', 'type' => 'select', 'fieldLabel' => 'Incur Charges', 'required' => true, 'description' => 'Select when to incur charges', 'defaultValue' => 'running', 'selectOptions' => [{'name' => 'When Running', 'value' => 'running'}, {'name' => 'When Stopped', 'value' => 'stopped'}, {'name' => 'Always', 'value' => 'always'}]], options[:options], @api_client, {}, options[:no_prompt])['incurCharges']

        # currency
        params['currency'] ||= Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'currency', 'type' => 'select', 'fieldLabel' => 'Currency', 'required' => true, 'description' => 'Select when to incur charges', 'defaultValue' => 'USD', 'selectOptions' => avail_currencies.collect {|it| {'value' => it}}], options[:options], @api_client, {}, options[:no_prompt])['currency']

        # cost
        if params['cost'].nil?
          params['cost'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cost', 'type' => 'number', 'fieldLabel' => 'Cost', 'required' => true, 'description' => 'Price cost', 'defaultValue' => 0.0}],options[:options],@api_client,{}, options[:no_prompt])['cost']
        end

        # adjustment / markup type
        if params['markupType'].nil?
          markup_type = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'markupType', 'type' => 'select', 'fieldLabel' => 'Price Adjustment', 'required' => false, 'description' => 'Price Adjustment', 'selectOptions' => [{'name' => 'None', 'value' => 'none'}, {'name' => 'Fixed Markup', 'value' => 'fixed'}, {'name' => 'Percent Markup', 'value' => 'percent'}, {'name' => 'Custom Price', 'value' => 'custom'}], 'defaultValue' => 'none'}],options[:options],@api_client,{}, options[:no_prompt])['markupType']

          if markup_type && markup_type != 'none'
            params['markupType'] = markup_type
          end
        end

        prompt_for_markup_type(params, options)

        payload = {'price' => params}
      end

      @prices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @prices_interface.dry.create(payload)
        return
      end
      json_response = @prices_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Price created"
          _get(json_response['id'], options)
        else
          print_red_alert "Error creating price: #{json_response['msg'] || json_response['errors']}"
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
      opts.banner = subcommand_usage("[price]")
      opts.on("--name NAME", String, "Price name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--type [TYPE]", String, "Price type") do |val|
        if price_types[val]
          params['priceType'] = val
        else
          raise_command_error "Invalid price type '#{val}'. Available price types: #{price_types.keys.join(', ')}"
        end
      end
      opts.on("--unit [UNIT]", String, "Price unit") do |val|
        if price_units.include?(val)
          params['priceUnit'] = val
        else
          raise_command_error "Invalid price unit '#{val}'. Available price units: #{price_units.join(', ')}"
        end
      end
      opts.on("--platform [PLATFORM]", String, "Price platform [centos|debian|fedora|canonical|opensuse|redhat|suse|xen|linux|windows]. Required for platform price type") do |val|
        if ['centos','debian','fedora','canonical','opensuse','redhat','suse','xen','linux', 'windows'].include?(val)
          params['platform'] = val
        else
          raise_command_error "Invalid platform '#{val}'. Available platforms: centos, debian, fedora, canonical, opensuse, redhat, suse, xen, linux, windows"
        end
      end
      opts.on("--software [TEXT]", String, "Price software. Required for software price type") do |val|
        params['software'] = val
      end
      opts.on("--volume [TYPE]", String, "Volume type ID or name. Required for storage price type") do |val|
        options[:volumeType] = val
      end
      opts.on("--datastore [DATASTORE]", String, "Datastore ID or name. Required for datastore price type") do |val|
        options[:datastore] = val
      end
      opts.on("--cross-apply [on|off]", String, "Apply price across clouds. Applicable for datastore price type only") do |val|
        options[:crossCloudApply] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--incur [WHEN]", String, "Incur charges [running|stopped|always]") do |val|
        if ['running', 'stopped', 'always'].include?(val)
          params['incurCharges'] = val
        else
          raise_command_error "Invalid incur charges '#{val}'. Available options: running, stopped, always"
        end
      end
      opts.on("--currency [CURRENCY]", String, "Price currency") do |val|
        options[:currency] = val
      end
      opts.on("--cost [AMOUNT]", Float, "Price cost") do |val|
        params['cost'] = val
      end
      opts.on("--fixed-markup [AMOUNT]", Float, "Add fixed price adjustment") do |val|
        params['markupType'] = 'fixed'
        params['markup'] = val
      end
      opts.on("--percent-markup [PERCENT]", Float, "Add percent price adjustment") do |val|
        params['markupType'] = 'percent'
        params['markupPercent'] = val
      end
      opts.on("--custom-price [AMOUNT]", Float, "Set customer price directly. Can be used to override price calculation based on cost and markup") do |val|
        params['markupType'] = 'custom'
        params['customPrice'] = val
      end
      opts.on("--restart-usage [on|off]", String, "Apply price changes to usage. Default is on") do |val|
        params['restartUsage'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update price\n[price] is required. Price ID, name or code"
    end
    optparse.parse!(args)
    connect(options)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    if options[:currency]
      if avail_currencies.include?(options[:currency].upcase)
        params['currency'] = options[:currency].upcase
      else
        raise_command_error "Unsupported currency '#{options[:currency]}'. Available currencies: #{avail_currencies.join(', ')}"
        return 1
      end
    end

    begin
      price = find_price(args[0])

      if price.nil?
        print_red_alert "Price #{args[0]} not found"
        exit 1
      end

      payload = parse_payload(options)

      if payload.nil?
        # price type
        prompt_for_price_type(params, options, price)

        # adjustment / markup type
        prompt_for_markup_type(params, options)

        payload = {'price' => params}
      end

      if payload['price'].empty?
        print_green_success "Nothing to update"
        return
      end

      @prices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @prices_interface.dry.update(price['id'], payload)
        return
      end
      json_response = @prices_interface.update(price['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Price updated"
          _get(price['id'], options)
        else
          print_red_alert "Error updating price: #{json_response['msg'] || json_response['errors']}"
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
      opts.banner = subcommand_usage( "[price]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Deactivate price.\n" +
          "[price] is required. Price ID, name or code"
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      price = find_price(args[0])

      if !price
        print_red_alert "Price #{args[0]} not found"
        exit 1
      end

      if price['active'] == false
        print_green_success "Price #{price_set['name']} already deactived."
        return 0
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to deactivate the price '#{price['name']}'?", options)
        return 9, "aborted command"
      end

      @prices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @prices_interface.dry.deactivate(price['id'], params)
        return
      end

      json_response = @prices_interface.deactivate(price['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Price #{price['name']} deactivate"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_price(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @prices_interface.get(val.to_i)['price'] : @prices_interface.list({'code' => val, 'name' => val})['prices'].first
  end

  def find_datastore(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @prices_interface.get_datastore(val.to_i)['datastore'] : @prices_interface.list_datastores({'name' => val})['datastores'].first
  end

  def find_volume_type(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? @prices_interface.get_volume_type(val.to_i)['volumeType'] : @prices_interface.list_volume_types({'name' => val})['volumeTypes'].first
  end

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

  def price_type_label(type)
    price_types[type] || type.to_s.capitalize
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

  def get_price_type_code(value)
    rtn = value
    price_types.each do |k,v|
      if value.to_s.downcase == v.downcase
        rtn = k
      end
    end
    return rtn
  end

  def price_units
    ['minute', 'hour', 'day', 'month', 'year', 'two year', 'three year', 'four year', 'five year']
  end

  def format_amount(amount)
    rtn = amount.to_s
    if rtn.index('.').nil?
      rtn += '.00'
    elsif rtn.split('.')[1].length < 2
      rtn = rtn + (['0'] * (2 - rtn.split('.')[1].length) * '')
    end
    rtn
  end

  def avail_currencies
    if @avail_currencies.nil?
      @avail_currencies = @prices_interface.list_currencies()['currencies'].collect {|it| it['value']}
    end
    @avail_currencies
  end

  def prompt_for_price_type(params, options, price={})
    case params['priceType']
    when 'platform'
      params['platform'] ||= price['platform'] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'platform', 'type' => 'select', 'fieldLabel' => 'Platform', 'required' => true, 'description' => 'Select platform for platform price type', 'selectOptions' => [ {'name' => 'CentOS', 'value' => 'centos'}, {'name' => 'Debian', 'value' => 'debian'}, {'name' => 'Fedora', 'value' => 'fedora'}, {'name' => 'Canonical', 'value' => 'canonical'}, {'name' => 'openSUSE', 'value' => 'opensuse'}, {'name' => 'Red Hat', 'value' => 'redhat'}, {'name' => 'SUSE', 'value' => 'suse'}, {'name' => 'Xen', 'value' => 'xen'}, {'name' => 'Linux', 'value' => 'linux'}, {'name' => 'Windows', 'value' => 'windows'}]}], options[:options], @api_client, {}, options[:no_prompt])['platform']
    when 'software'
      params['software'] ||= price['software'] || Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'software', 'type' => 'text', 'fieldLabel' => 'Software', 'required' => true, 'description' => 'Set software for software price type'}], options[:options], @api_client,{}, options[:no_prompt])['software']
    when 'datastore'
      if options[:datastore]
        datastore = find_datastore(options[:datastore])
        if datastore
          params['datastore'] = {'id' => datastore['id']}
        else
          print_red_alert "Datastore #{options[:datastore]} not found"
          exit 1
        end
      else
        datastore_id = Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'datastore', 'type' => 'select', 'fieldLabel' => 'Datastore', 'required' => true, 'description' => 'Select datastore for datastore price type', 'selectOptions' => @prices_interface.list_datastores['datastores'].collect {|it| {'name' => it['name'], 'value' => it['id']}}], options[:options], @api_client, {}, options[:no_prompt])['datastore']
        params['datastore'] = {'id' => datastore_id}
      end

      if options[:crossCloudApply].nil?
        if !options[:no_prompt]
          params['crossCloudApply'] = price['crossCloudApply'] || Morpheus::Cli::OptionTypes.confirm("Apply price across clouds?", {:default => false})
        end
      else
        params['crossCloudApply'] = options[:crossCloudApply]
      end
    when 'storage'
      if options[:volumeType]
        volume_type = find_volume_type(options[:volumeType])
        if volume_type
          params['volumeType'] = {'id' => volume_type['id']}
        else
          print_red_alert "Volume type #{options[:volumeType]} not found"
          exit 1
        end
      else
        volume_type_id = (price['volumeType'] ? price['volumeType']['id'] : Morpheus::Cli::OptionTypes.prompt(['fieldName' => 'volumeType', 'type' => 'select', 'fieldLabel' => 'Volume Type', 'required' => true, 'description' => 'Select volume type for storage price type', 'selectOptions' => @prices_interface.list_volume_types['volumeTypes'].collect {|it| {'name' => it['name'], 'value' => it['id']}}], options[:options], @api_client, {}, options[:no_prompt], true)['volumeType'])
        params['volumeType'] = {'id' => volume_type_id}
      end
    end
  end

  def prompt_for_markup_type(params, options, price={})
    case params['markupType']
    when 'percent'
      params['markupPercent'] = price['markupPercent'] if params['markupPercent'].nil?
      if params['markupPercent'].nil?
        params['markupPercent'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'markupPercent', 'type' => 'number', 'fieldLabel' => 'Markup Percent', 'required' => true, 'description' => 'Markup Percent'}],options[:options],@api_client,{}, options[:no_prompt])['markupPercent']
      end
    when 'fixed'
      params['markup'] = price['markup'] if params['markup'].nil?
      if params['markup'].nil?
        params['markup'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'markup', 'type' => 'number', 'fieldLabel' => 'Markup Amount', 'required' => true, 'description' => 'Markup Amount'}],options[:options],@api_client,{}, options[:no_prompt])['markup']
      end
    when 'custom'
      params['customPrice'] = price['customPrice'] if params['customPrice'].nil?
      if params['customPrice'].nil?
        params['customPrice'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'customPrice', 'type' => 'number', 'fieldLabel' => 'Price', 'required' => true, 'description' => 'Price'}],options[:options],@api_client,{}, options[:no_prompt])['customPrice']
      end
    end
  end
end
