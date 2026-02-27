require 'morpheus/cli/cli_command'

class Morpheus::Cli::TenantsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::WhoamiHelper
  set_command_name :tenants
  set_command_description "View and manage tenants (accounts)."
  register_subcommands :list, :count, :get, :add, :update, :remove
  alias_subcommand :details, :get
  set_default_subcommand :list

  # account-groups is under this namespace for now
  register_subcommands :'groups' => :account_groups

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_users_interface = @api_client.account_users
    @accounts_interface = @api_client.accounts
    @roles_interface = @api_client.roles
    @whoami_interface = @api_client.whoami
  end

  def handle(args)
    handle_subcommand(args)
  end

  def account_groups(args)
    Morpheus::Cli::AccountGroupsCommand.new.handle(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search phrase]")
      build_standard_list_options(opts, options)
      opts.footer = "List tenants."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    options[:phrase] = args.join(" ") if args.count > 0
    connect(options)

    params = {}
    params.merge!(parse_list_options(options))
    @accounts_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @accounts_interface.dry.list(params)
      return 0, nil
    end
    json_response = @accounts_interface.list(params)
    render_response(json_response, options, "accounts") do
      accounts = json_response['accounts']
      title = "Morpheus Tenants"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if accounts.empty?
        print cyan,"No tenants found.",reset,"\n"
      else
        print cyan
        print as_pretty_table(accounts, list_account_column_definitions, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of tenants."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @accounts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @accounts_interface.dry.list(params)
        return
      end
      json_response = @accounts_interface.list(params)
      # print number only
      if json_response['meta'] && json_response['meta']['total']
        print cyan, json_response['meta']['total'], reset, "\n"
      else
        print yellow, "unknown", reset, "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[tenant]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a tenant (account).
[tenant] is required. This is the name or id of a tenant. Supports 1-N arguments.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options={})
    args = [id] # heh
    @accounts_interface.setopts(options)
    if options[:dry_run]
      if args[0].to_s =~ /\A\d{1,}\Z/
        print_dry_run @accounts_interface.dry.get(args[0].to_i)
      else
        print_dry_run @accounts_interface.dry.list({name:args[0]})
      end
      return
    end
    account = find_account_by_name_or_id(args[0])
    exit 1 if account.nil?

    json_response = {'account' => account}
    render_result = render_with_format(json_response, options, 'account')
    return 0 if render_result

    print_h1 "Tenant Details", [], options
    
    print_description_list(account_column_definitions, account, options)

    print reset,"\n"
    return 0
    
  end


  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, add_account_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new tenant.
[name] is required. Name
[role] is required. Base Role name or ID
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:2)
    options[:options]['name'] = args[0] if args[0]
    #options[:options]['role'] = {'id' => args[1]} if args[1]
    connect(options)
    
    object_key = 'account' # 'tenant' someday
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_account_option_types, options[:options], @api_client, options[:params])
      payload.deep_merge!({object_key => v_prompt})
    end
    @accounts_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @accounts_interface.dry.create(payload)
      return
    end
    json_response = @accounts_interface.create(payload)
    render_response(json_response, options, object_key) do
      account = json_response[object_key]
      print_green_success "Tenant #{account['name']} added"
      return _get(account["id"], options)
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[tenant]")
      build_option_type_options(opts, options, update_account_option_types)
      opts.on('--active [on|off]', String, "Can be used to disable a tenant") do |val|
        options[:options]['active'] = val.to_s.empty? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an existing tenant.
[tenant] is required. Tenant name or ID
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    account = find_account_by_name_or_id(args[0])
    return [1, "account not found"] if account.nil?
    object_key = 'account' # 'tenant' someday
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(update_account_option_types, options[:options].merge(:no_prompt => true), @api_client, options[:params])
      payload.deep_merge!({object_key => v_prompt})
      # remove empty role object.. todo: prompt() or deep_compact! needs to  handle this! 
      if payload[object_key]['role'] && payload[object_key]['role'].empty?
        payload[object_key].delete('role')
      end
      if payload[object_key].empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @accounts_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @accounts_interface.dry.update(account['id'], payload)
      return
    end
    json_response = @accounts_interface.update(account['id'], payload)
    render_response(json_response, options, object_key) do
      account = json_response[object_key]
      print_green_success "Tenant #{account['name']} updated"
      return _get(account["id"], options)
    end
  end


  def remove(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[tenant]")
      opts.on('--remove-resources [on|off]', ['on','off'], "Remove Associated Instances. Default is off.") do |val|
        params[:removeResources] = val.nil? ? 'on' : val
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a tenant.
[tenant] is required. This is the name or id of a tenant.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    optparse.parse!(args)
    connect(options)
    begin
      # allow finding by ID since name is not unique!
      account = find_account_by_name_or_id(args[0])
      return 1, "tenant not found" if account.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the tenant #{account['name']}?")
        return 9, "aborted command"
      end
      @accounts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @accounts_interface.dry.destroy(account['id'], params)
        return
      end
      json_response = @accounts_interface.destroy(account['id'], params)
      render_response(json_response, options) do
        print_green_success "Tenant #{account['name']} removed"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def add_account_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
      {'fieldContext' => 'parentAccount', 'fieldName' => 'id', 'fieldLabel' => 'Parent Tenant', 'type' => 'select', 'optionSource' => lambda {  |api_client, api_params|
        @accounts_interface.list({max:10000})['accounts'].collect {|it|
          {"name" => (it["authority"] || it["name"]), "value" => it["id"]}
        }
      }, 'displayOrder' => 3},
      {'fieldContext' => 'role', 'fieldName' => 'id', 'fieldLabel' => 'Base Role', 'type' => 'select', 'optionSource' => lambda {  |api_client, api_params|
        tenant_id = (api_params['parentAccount']['id'] rescue nil)
        params = {max: 10000, roleType:'account', tenantId: tenant_id}
        @roles_interface.list(nil, params)['roles'].collect {|it|
          {"name" => (it["authority"] || it["name"]), "value" => it["id"]}
        }
      }, 'displayOrder' => 4},
      {'fieldName' => 'currency', 'fieldLabel' => 'Currency', 'type' => 'text', 'defaultValue' => 'USD', 'displayOrder' => 4}
    ]
  end

  def update_account_option_types
    list = add_account_option_types()
    list = list.reject {|it| it['fieldContext'] == 'parentAccount' }
    list.each {|it| it.delete('required') }
    list.each {|it| it.delete('defaultValue') }
    list
  end

end
