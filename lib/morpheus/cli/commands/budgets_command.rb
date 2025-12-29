require 'morpheus/cli/cli_command'
require 'time'

class Morpheus::Cli::BudgetsCommand
  include Morpheus::Cli::CliCommand
  set_command_name :budgets
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @budgets_interface = @api_client.budgets
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
      build_standard_list_options(opts, options)
      opts.footer = "List budgets."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    connect(options)
    
    params.merge!(parse_list_options(options))
    @budgets_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @budgets_interface.dry.list(params)
      return 0
    end
    json_response = @budgets_interface.list(params)
    budgets = json_response['budgets']
    render_response(json_response, options, 'budgets') do
      title = "Morpheus Budgets"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if budgets.empty?
        print cyan,"No budgets found.",reset,"\n"
      else
        columns = [
          {"ID" => lambda {|budget| budget['id'] } },
          {"NAME" => lambda {|budget| budget['name'] } },
          {"DESCRIPTION" => lambda {|budget| truncate_string(budget['description'], 30) } },
          # {"ENABLED" => lambda {|budget| format_boolean(budget['enabled']) } },
          # {"SCOPE" => lambda {|it| format_budget_scope(it) } },
          {"SCOPE" => lambda {|it| it['refName'] } },
          {"PERIOD" => lambda {|it| it['year'] } },
          {"INTERVAL" => lambda {|it| it['interval'].to_s.capitalize } },
          # the UI doesn't consider timezone, so uhh do it this hacky way for now.
          {"START DATE" => lambda {|it| 
            if it['timezone'] == 'UTC'
              ((parse_time(it['startDate'], "%Y-%m-%d").strftime("%x")) rescue it['startDate']) # + ' UTC'
            else
              format_local_date(it['startDate']) 
            end
          } },
          {"END DATE" => lambda {|it| 
            if it['timezone'] == 'UTC'
              ((parse_time(it['endDate'], "%Y-%m-%d").strftime("%x")) rescue it['endDate']) # + ' UTC'
            else
              format_local_date(it['endDate']) 
            end
          } },
          {"TOTAL" => lambda {|it| format_money(it['totalCost'], it['currency']) } },
          {"AVERAGE" => lambda {|it| format_money(it['averageCost'], it['currency']) } },
          # {"CREATED BY" => lambda {|budget| budget['createdByName'] ? budget['createdByName'] : budget['createdById'] } },
          # {"CREATED" => lambda {|budget| format_local_dt(budget['dateCreated']) } },
          # {"UPDATED" => lambda {|budget| format_local_dt(budget['lastUpdated']) } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(budgets, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return budgets.empty? ? [3, "no budgets found"] : [0, nil]
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[budget]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    params.merge!(parse_query_options(options))
    @budgets_interface.setopts(options)
    if options[:dry_run]
      if args[0].to_s =~ /\A\d{1,}\Z/
        print_dry_run @budgets_interface.dry.get(args[0], params)
      else
        print_dry_run @budgets_interface.dry.list({name: args[0].to_s})
      end
      return 0
    end
    budget = find_budget_by_name_or_id(args[0])
    return 1 if budget.nil?
    # skip reload if already fetched via get(id)
    json_response = {'budget' => budget}
    if args[0].to_s != budget['id'].to_s
      json_response = @budgets_interface.get(budget['id'], params)
      budget = json_response['budget']
    end
    
    render_response(json_response, options, 'budget') do
      
      print_h1 "Budget Details"
      print cyan
      budget_columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Enabled" => lambda {|budget| format_boolean(budget['enabled']) },
        "Scope" => lambda {|it| format_budget_scope(it) },
        "Period" => lambda {|it| it['year'] },
        "Interval" => lambda {|it| it['interval'].to_s.capitalize },
        "Forecast Model" => lambda {|it| it['forecastType'] ? it['forecastType']['name'] : '' },
        # the UI doesn't consider timezone, so uhh do it this hacky way for now.
        "Start Date" => lambda {|it| 
          if it['timezone'] == 'UTC'
            ((parse_time(it['startDate'], "%Y-%m-%d").strftime("%x")) rescue it['startDate']) # + ' UTC'
          else
            format_local_date(it['startDate']) 
          end
        },
        "End Date" => lambda {|it| 
          if it['timezone'] == 'UTC'
            ((parse_time(it['endDate'], "%Y-%m-%d").strftime("%x")) rescue it['endDate']) # + ' UTC'
          else
            format_local_date(it['endDate']) 
          end
        },
        # "Costs" => lambda {|it| 
        #   if it['costs'].is_a?(Array)
        #     it['costs'] ? it['costs'].join(', ') : '' 
        #   elsif it['costs'].is_a?(Hash)
        #     it['costs'].to_s
        #   else
        #     it['costs'].to_s
        #   end
        # },
        "Created By" => lambda {|it| it['createdByName'] ? it['createdByName'] : it['createdById'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      print_description_list(budget_columns, budget, options)
      # print reset,"\n"

      # a chart of Budget cost vs Actual cost for each interval in the period.
      print_h2 "Budget Summary", options
      if budget['stats'] && budget['stats']['intervals']
        begin
          budget_summary_columns = {
            # "Cost" => lambda {|it| it[:label] },
            " " => lambda {|it| it[:label] },
          }
          budget_row = {label:"Budget"}
          actual_row = {label:"Actual"}
          forecast_row = {label:"Forecast"}
          multi_year = false
          if budget['startDate'] && budget['endDate'] && parse_time(budget['startDate']).year != parse_time(budget['endDate']).year
            multi_year = true
          end
          budget['stats']['intervals'].each do |it|
            currency = budget['currency'] || budget['stats']['currency']
            interval_key = format_budget_interval_label(budget, it).to_s.upcase
            # interval_date = parse_time(it["startDate"]) rescue nil
            budget_summary_columns[interval_key] = interval_key
            budget_cost = it["budget"].to_f
            actual_cost = it["cost"].to_f
            over_budget = actual_cost > 0 && actual_cost > budget_cost
            if over_budget
              budget_row[interval_key] = "#{cyan}#{format_money(budget_cost, currency)}#{cyan}"
              actual_row[interval_key] = "#{red}#{format_money(actual_cost, currency)}#{cyan}"
            else
              budget_row[interval_key] = "#{cyan}#{format_money(budget_cost, currency)}#{cyan}"
              actual_row[interval_key] = "#{cyan}#{format_money(actual_cost, currency)}#{cyan}"
            end
            forecast_cost = it["forecast"] ? it["forecast"].to_f : 0
            forecast_over_budget = forecast_cost > 0 && forecast_cost > budget_cost
            if forecast_over_budget
              forecast_row[interval_key] = "#{red}#{format_money(forecast_cost, currency)}#{cyan}"
            else
              forecast_row[interval_key] = "#{cyan}#{format_money(forecast_cost, currency)}#{cyan}"
            end
          end
          chart_data = [budget_row, actual_row]
          if budget['stats']['intervals'].find { |it| it['forecast'] && it['forecast'] != 0 }
            chart_data << forecast_row
          end
          print as_pretty_table(chart_data, budget_summary_columns, options)
          print reset,"\n"
        rescue => ex
          print red,"Failed to render budget summary.",reset,"\n"
          raise ex
        end
      else
        print cyan,"No budget stat data found.",reset,"\n"
      end
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    costs = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_budget_option_types)
      # opts.on('--cost [amount]', String, "Budget cost amount, for use with default year interval.") do |val|
      #   costs['year'] = (val.nil? || val.empty?) ? 0 : val.to_f
      # end
      opts.on('--costs LIST', String, "Budget cost amounts, one for each interval in the budget. eg \"350\" for one year, \"25,25,25,100\" for quarters, and \"10,10,10,10,10,10,10,10,10,10,10,50\" for each month") do |val|
        val = val.to_s.gsub('[', '').gsub(']', '')
        costs = val.to_s.split(',').collect {|it| parse_cost_amount(it) }
      end
      (1..12).each.with_index do |cost_index, i|
        opts.on("--cost#{cost_index} VALUE", String, "Cost #{cost_index.to_s.capitalize} amount") do |val|
          #params["cost#{cost_index.to_s}"] = parse_cost_amount(val)
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--cost#{cost_index}")
      end
      [:q1,:q2,:q3,:q4,].each.with_index do |quarter, i|
        opts.on("--#{quarter.to_s} VALUE", String, "#{quarter.to_s.capitalize} cost amount, use with quarter interval.") do |val|
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--#{quarter.to_s}")
      end
      [:january,:february,:march,:april,:may,:june,:july,:august,:september,:october,:november,:december].each_with_index do |month, i|
        opts.on("--#{month.to_s} VALUE", String, "#{month.to_s.capitalize} cost amount, use with month interval.") do |val|
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--#{month.to_s}")
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a budget.
The default period is the current year, eg. "#{Time.now.year}"
and the default interval is "year".
Costs can be passed as an array of values, one for each interval. eg. --costs "[999]"

Examples:
budgets add example-budget --interval "year" --costs "[2500]"
budgets add example-qtr-budget --interval "quarter" --costs "[500,500,500,1000]"
budgets add example-monthly-budget --interval "month" --costs "[400,100,100,100,100,100,100,100,100,100,400,800]"
budgets add example-future-budget --year "2022" --interval "year" --costs "[5000]"
budgets add example-custom-budget --year "custom" --interval "year" --start "2021-01-01" --end "2023-12-31" --costs "[2500,5000,10000]"
EOT
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'budget' => {
          }
        }
        # allow arbitrary -O options
        #passed_options.delete('costs')
        passed_options.delete('tenant')
        passed_options.delete('group')
        passed_options.delete('cloud')
        passed_options.delete('user')
        payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
        # prompt for options
        v_prompt = Morpheus::Cli::OptionTypes.prompt(add_budget_option_types, options[:options], @api_client)
        params.deep_merge!(v_prompt)
        # downcase year 'custom' always
        if params['year']
          params['interval'] = params['interval'].to_s.downcase
        end
        # downcase interval always
        if params['interval']
          params['interval'] = params['interval'].to_s.downcase
        end
        # parse MM/DD/YY but need to convert to to ISO format YYYY-MM-DD for api
        standard_start_date = (params['startDate'] ? Time.strptime(params['startDate'], "%x") : nil) rescue nil
        if standard_start_date
          params['startDate'] = format_date(standard_start_date, {format:"%Y-%m-%d"})
        end
        standard_end_date = (params['endDate'] ? Time.strptime(params['endDate'], "%x") : nil) rescue nil
        if standard_end_date
          params['endDate'] = format_date(standard_end_date, {format:"%Y-%m-%d"})
        end
        if !costs.empty?
          params['costs'] = costs
        else
          params['costs'] = prompt_costs(params, options)
        end
        # budgets api expects scope prefixed parameters like this
        if params['tenant'].is_a?(String) || params['tenant'].is_a?(Numeric)
          params['scopeTenantId'] = params.delete('tenant')
        end
        if params['group'].is_a?(String) || params['group'].is_a?(Numeric)
          params['scopeGroupId'] = params.delete('group')
        end
        if params['cloud'].is_a?(String) || params['cloud'].is_a?(Numeric)
          params['scopeCloudId'] = params.delete('cloud')
        end
        if params['user'].is_a?(String) || params['user'].is_a?(Numeric)
          params['scopeUserId'] = params.delete('user')
        end
        payload.deep_merge!({'budget' => params}) unless params.empty?
      end

      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.create(payload)
        return
      end
      json_response = @budgets_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['budget']  ? json_response['budget']['name'] : ''
        print_green_success "Budget #{display_name} added"
        get([json_response['budget']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
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
    costs = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[budget] [options]")
      build_option_type_options(opts, options, update_budget_option_types)
      # opts.on('--cost [amount]', String, "Budget cost amount, for use with default year interval.") do |val|
      #   costs['year'] = (val.nil? || val.empty?) ? 0 : val.to_f
      # end
      opts.on('--costs COSTS', String, "Budget cost amounts, one for each interval in the budget. eg. [999]") do |val|
        val = val.to_s.gsub('[', '').gsub(']', '')
        costs = val.to_s.split(',').collect {|it| parse_cost_amount(it) }
      end
      (1..12).each.with_index do |cost_index, i|
        opts.on("--cost#{cost_index} VALUE", String, "Cost #{cost_index.to_s.capitalize} amount") do |val|
          #params["cost#{cost_index.to_s}"] = parse_cost_amount(val)
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--cost#{cost_index}")
      end
      [:q1,:q2,:q3,:q4,].each.with_index do |quarter, i|
        opts.on("--#{quarter.to_s} VALUE", String, "#{quarter.to_s.capitalize} cost amount, use with quarter interval.") do |val|
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--#{quarter.to_s}")
      end
      [:january,:february,:march,:april,:may,:june,:july,:august,:september,:october,:november,:december].each_with_index do |month, i|
        opts.on("--#{month.to_s} VALUE", String, "#{month.to_s.capitalize} cost amount, use with month interval.") do |val|
          costs[i] = parse_cost_amount(val)
        end
        opts.add_hidden_option("--#{month.to_s}")
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a budget.
[budget] is required. Budget ID or name
EOT
      opts.footer = "Update a budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    
    budget = find_budget_by_name_or_id(args[0])
    return 1 if budget.nil?

    original_year = budget['year']
    original_interval = budget['interval']
    original_costs = budget['costs'].is_a?(Array) ? budget['costs'] : nil

    # construct payload
    passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
    else
      payload = {
        'budget' => {
        }
      }
      # allow arbitrary -O options
      #passed_options.delete('costs')
      passed_options.delete('tenant')
      passed_options.delete('group')
      passed_options.delete('cloud')
      passed_options.delete('user')
      payload.deep_merge!({'budget' => passed_options}) unless passed_options.empty?
      # prompt for options
      #params = Morpheus::Cli::OptionTypes.prompt(update_budget_option_types, options[:options], @api_client, options[:params])
      v_prompt = Morpheus::Cli::OptionTypes.prompt(update_budget_option_types, options[:options].merge(:no_prompt => true), @api_client)
      params.deep_merge!(v_prompt)
      # downcase year 'custom' always
      if params['year']
        params['interval'] = params['interval'].to_s.downcase
      end
      # downcase interval always
      if params['interval']
        params['interval'] = params['interval'].to_s.downcase
      end
      # parse MM/DD/YY but need to convert to to ISO format YYYY-MM-DD for api
      if params['startDate']
        params['startDate'] = format_date(parse_time(params['startDate']), {format:"%Y-%m-%d"})
      end
      if params['endDate']
        params['endDate'] = format_date(parse_time(params['endDate']), {format:"%Y-%m-%d"})
      end
      if !costs.empty?
        params['costs'] = costs
        # merge original costs in on update unless interval is changing too, should check original_year too probably if going to custom...
        if params['interval'] && params['interval'] != original_interval
          original_costs = nil
        end
        if original_costs
          original_costs.each_with_index do |original_cost, i|
            if params['costs'][i].nil?
              params['costs'][i] = original_cost
            end
          end
        end
      else
        if params['interval'] && params['interval'] != original_interval
          raise_command_error "Changing interval requires setting the costs as well.\n#{optparse}"
        end
      end
      # budgets api expects scope prefixed parameters like this
      if params['tenant'].is_a?(String) || params['tenant'].is_a?(Numeric)
        params['scopeTenantId'] = params.delete('tenant')
      end
      if params['group'].is_a?(String) || params['group'].is_a?(Numeric)
        params['scopeGroupId'] = params.delete('group')
      end
      if params['cloud'].is_a?(String) || params['cloud'].is_a?(Numeric)
        params['scopeCloudId'] = params.delete('cloud')
      end
      if params['user'].is_a?(String) || params['user'].is_a?(Numeric)
        params['scopeUserId'] = params.delete('user')
      end
      payload.deep_merge!({'budget' => params}) unless params.empty?
      if payload.empty? || payload['budget'].empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @budgets_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @budgets_interface.dry.update(budget['id'], payload)
      return
    end
    json_response = @budgets_interface.update(budget['id'], payload)
    render_response(json_response, options, 'budget') do
      display_name = json_response['budget'] ? json_response['budget']['name'] : ''
      print_green_success "Budget #{display_name} updated"
      get([json_response['budget']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete budget.\n[budget] is required. Budget ID or name"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      budget = find_budget_by_name_or_id(args[0])
      return 1 if budget.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the budget #{budget['name']}?")
        return 9, "aborted command"
      end
      @budgets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @budgets_interface.dry.destroy(budget['id'])
        return
      end
      json_response = @budgets_interface.destroy(budget['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Budget #{budget['name']} removed"
        # list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_budget_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_budget_by_id(val)
    else
      return find_budget_by_name(val)
    end
  end

  def find_budget_by_id(id)
    raise "#{self.class} has not defined @budgets_interface" if @budgets_interface.nil?
    begin
      json_response = @budgets_interface.get(id)
      return json_response['budget']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Budget not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_budget_by_name(name)
    raise "#{self.class} has not defined @budgets_interface" if @budgets_interface.nil?
    budgets = @budgets_interface.list({name: name.to_s})['budgets']
    if budgets.empty?
      print_red_alert "Budget not found by name #{name}"
      return nil
    elsif budgets.size > 1
      print_red_alert "#{budgets.size} Budgets found by name #{name}"
      print as_pretty_table(budgets, [:id,:name], {color:red})
      print reset,"\n"
      return nil
    else
      return budgets[0]
    end
  end

  def add_budget_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      # {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true},
      {'fieldName' => 'scope', 'fieldLabel' => 'Scope', 'code' => 'budget.scope', 'type' => 'select', 'selectOptions' => [{'name'=>'Account','value'=>'account'},{'name'=>'Tenant','value'=>'tenant'},{'name'=>'Cloud','value'=>'cloud'},{'name'=>'Group','value'=>'group'},{'name'=>'User','value'=>'user'}], 'defaultValue' => 'account', 'required' => true},
      {'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        @options_interface.options_for_source("tenants", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:tenant'},
      {'fieldName' => 'user', 'fieldLabel' => 'User', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params|
        @options_interface.options_for_source("users", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:user'},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        @options_interface.options_for_source("groups", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:group'},
      {'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        @options_interface.options_for_source("clouds", {})['data']
      }, 'required' => true, 'dependsOnCode' => 'budget.scope:cloud'},
      {'fieldName' => 'year', 'fieldLabel' => 'Period', 'code' => 'budget.year', 'type' => 'text', 'required' => true, 'defaultValue' => Time.now.year, 'description' => "The period (year) the budget applies, YYYY or 'custom' to enter Start Date and End Date manually"},
      {'fieldName' => 'startDate', 'fieldLabel' => 'Start Date', 'type' => 'text', 'required' => true, 'description' => 'The Start Date for custom period budget eg. 2021-01-01', 'dependsOnCode' => 'budget.year:custom'},
      {'fieldName' => 'endDate', 'fieldLabel' => 'End Date', 'type' => 'text', 'required' => true, 'description' => 'The End Date for custom period budget eg. 2023-12-31 (must be 1, 2 or 3 years from Start Date)', 'dependsOnCode' => 'budget.year:custom'},
      {'fieldName' => 'interval', 'fieldLabel' => 'Interval', 'type' => 'select', 'selectOptions' => [{'name'=>'Year','value'=>'year'},{'name'=>'Quarter','value'=>'quarter'},{'name'=>'Month','value'=>'month'}], 'defaultValue' => 'year', 'required' => true, 'description' => 'The budget interval, determines cost amounts: "year", "quarter" or "month"'},
      {'fieldName' => 'forecastType.id', 'fieldLabel' => 'Forecast Model', 'type' => 'select', 'optionSource' => 'forecastTypes', 'description' => 'The budget forcecast model type, determines projected cost calculations.'},
    ]
  end

  def update_budget_option_types
    list = add_budget_option_types()
    # list = list.reject {|it| ["interval"].include? it['fieldName'] }
    list.each {|it| 
      it.delete('required') 
      it.delete('defaultValue')
      it.delete('dependsOnCode')
    }
    list
  end

  def prompt_costs(params={}, options={})
    # user did -O costs="[3.50,3.50,3.50,5.00]" so just pass through
    default_costs = []
    if options[:options]['costs'] && options[:options]['costs'].is_a?(Array)
      default_costs = options[:options]['costs']
      default_costs.each_with_index do |default_cost, i|
        interval_index =  i + 1
        if !default_cost.nil?
          options[:options]["cost#{interval_index}"] = default_cost
        end
      end
    end
    # prompt for each Period Cost based on interval [year|quarter|month]
    budget_period_year = (params['year'] || params['periodValue'])
    is_custom = budget_period_year == 'custom'
    interval = params['interval'] #.to_s.downcase
    total_years = 1
    total_months = 12
    costs = []
    # custom timeframe so prompt from start to end by interval
    start_date = nil
    end_date = nil

    if is_custom
      start_date = parse_time(params['startDate'])
      if start_date.nil?
        raise_command_error "startDate is required for custom period budgets"
      end
      end_date = parse_time(params['endDate'])
      if end_date.nil?
        raise_command_error "endDate is required for custom period budgets"
      end
    else
      budget_year = budget_period_year ? budget_period_year.to_i : Time.now.year.to_i
      start_date = Time.new(budget_year, 1, 1)
      end_date = Time.new(budget_year, 12, 31)
    end
    epoch_start_month = (start_date.year * 12) + start_date.month
    epoch_end_month = (end_date.year * 12) + end_date.month
    # total_months gets + 1 because endDate is same year, on last day of the month, Dec 31 by default
    total_months = (epoch_end_month - epoch_start_month) + 1
    total_years = (total_months / 12)
    cost_option_types = []
    interval_count = total_months
    if interval == 'year'
      interval_count = total_months / 12
    elsif interval == 'quarter'
      interval_count = total_months / 3
    end
    
    is_fiscal = start_date.month != 1 || start_date.day != 1

    # debug budget shenanigans
    # puts "START: #{start_date}"
    # puts "END: #{end_date}"
    # puts "EPOCH MONTHS: #{epoch_start_month} - #{epoch_end_month}"
    # puts "TOTAL MONTHS: #{total_months}"
    # puts "INTERVAL COUNT IS: #{interval_count}"

    if total_months < 0
      raise_command_error "budget cannot end (#{end_date}) before it starts (#{start_date})"
    end
    if (total_months % 12) != 0 || (total_months > 36)
      raise_command_error "budget custom period must be 12, 24, or 36 months."
    end
    if interval == 'year'
      (1..interval_count).each_with_index do |interval_index, i|
        interval_start_month = epoch_start_month + (i * 12)
        interval_date = Time.new((interval_start_month / 12), (interval_start_month % 12) == 0 ? 12 : (interval_start_month % 12), 1)
        display_year = is_fiscal ? "FY #{interval_date.year + 1}" : interval_date.year.to_s
        field_name = "cost#{interval_index}"
        field_label = "#{display_year} Cost"
        cost_option_types << {'fieldName' => field_name, 'fieldLabel' => field_label, 'type' => 'text', 'required' => true, 'defaultValue' => (default_costs[i] || 0).to_s}
      end
    elsif interval == 'quarter'
      (1..interval_count).each_with_index do |interval_index, i|
        interval_start_month = epoch_start_month + (i * 3)
        interval_date = Time.new((interval_start_month / 12), (interval_start_month % 12) == 0 ? 12 : (interval_start_month % 12), 1)
        interval_end_date = Time.new((interval_start_month / 12), (interval_start_month % 12) == 0 ? 12 : (interval_start_month % 12), 1)
        display_year = is_fiscal ? "FY #{interval_date.year + 1}" : interval_date.year.to_s
        field_name = "cost#{interval_index}"
        # field_label = "Q#{interval_index} Cost"
        field_label = "Q#{(i % 4) + 1} #{display_year} Cost"
        cost_option_types << {'fieldName' => field_name, 'fieldLabel' => field_label, 'type' => 'text', 'required' => true, 'defaultValue' => (default_costs[i] || 0).to_s}
      end
    elsif interval == 'month'
      (1..interval_count).each_with_index do |interval_index, i|
        interval_start_month = epoch_start_month + i
        interval_date = Time.new((interval_start_month / 12), (interval_start_month % 12) == 0 ? 12 : (interval_start_month % 12), 1)
        display_year = is_fiscal ? "FY #{interval_date.year + 1}" : interval_date.year.to_s
        field_name = "cost#{interval_index}"
        # field_label = "#{interval_date.strftime('%B %Y')} Cost"
        field_label = "#{interval_date.strftime('%B')} #{display_year} Cost"
        cost_option_types << {'fieldName' => field_name, 'fieldLabel' => field_label, 'type' => 'text', 'required' => true, 'defaultValue' => (default_costs[i] || 0).to_s}
      end
    end
    # values is a Hash like {"cost1": 99.0, "cost2": 55.0}
    values = Morpheus::Cli::OptionTypes.prompt(cost_option_types, options[:options], @api_client)
    values.each do |k,v|
      interval_index = k[4..-1].to_i
      costs[interval_index-1] = parse_cost_amount(v).to_f
    end
    return costs
  end

  def format_budget_scope(budget)
    if budget['refScope'] && budget['refName']
      "(#{budget['refScope']}) #{budget['refName']}"
    elsif budget['refType']
      budget['refType'] ? "#{budget['refType']} (#{budget['refId']}) #{budget['refName']}".strip : budget['refName'].to_s
    else
      ""
    end
  end

  # convert String like "$5,499.99" to Float 5499.99
  def parse_cost_amount(val)
    val.to_s.gsub(",","").gsub('$','').strip.to_f
  end

  def format_budget_interval_label(budget, budget_interval)
    label = ""
    if budget_interval['chartName']
      label = budget_interval['chartName']
    else
      label = (budget_interval['shortName'] || budget_interval['shortYear']).to_s
    end
    return label
  end

end
