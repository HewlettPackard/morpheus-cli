# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::TenantsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
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
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @roles_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).roles
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_option_type_options(opts, options, add_account_option_types)
      build_common_options(opts, options, [:options, :json, :remote, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      if args.count > 1
        raise_command_error "wrong number of arguments. Expected 0-1 and received #{args.count} #{args.join(' ')}\n#{optparse}", args, 127
        #puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 0-1 and received #{args.count} #{args.join(' ')}\n#{optparse}"
        #return 127
      end
      if args[0]
        options[:options]['name'] = args[0]
      end
      params = Morpheus::Cli::OptionTypes.prompt(add_account_option_types, options[:options], @api_client, options[:params])
      #puts "parsed params is : #{params.inspect}"
      account_keys = ['name', 'description', 'currency']
      account_payload = params.select {|k,v| account_keys.include?(k) }
      account_payload['currency'] = account_payload['currency'].to_s.empty? ? "USD" : account_payload['currency'].upcase
      
      if params['role'].to_s != ''
        role = find_role_by_name(nil, params['role'])
        exit 1 if role.nil?
        account_payload['role'] = {id: role['id']}
      end
      payload = {account: account_payload}
      if options[:dry_run] && options[:json]
        puts as_json(payload, options)
        return 0
      end
      @accounts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @accounts_interface.dry.create(payload)
        return
      end
      json_response = @accounts_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Tenant #{account_payload['name']} added"
        get([account_payload["name"]])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--active [on|off]', String, "Can be used to disable a network") do |val|
        params['active'] = val.to_s.empty? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_option_type_options(opts, options, update_account_option_types)
      build_common_options(opts, options, [:options, :json, :remote, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      print_red_alert "Specify at least one option to update"
      puts optparse
      exit 1
    end
    connect(options)
    begin
      account = find_account_by_name_or_id(args[0])
      exit 1 if account.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(update_account_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      if params.empty?
        puts optparse
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      #account_keys = ['name', 'description', 'currency']
      account_payload = params
      account_payload['currency'] = account_payload['currency'].upcase unless account_payload['currency'].to_s.empty?
      
      if params['role'].to_s != ''
        role = find_role_by_name(nil, params['role'])
        exit 1 if role.nil?
        account_payload['role'] = {id: role['id']}
      end
      payload = {account: account_payload}
      if options[:dry_run] && options[:json]
        puts as_json(payload, options)
        return 0
      end
      @accounts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @accounts_interface.dry.update(account['id'], payload)
        return
      end
      json_response = @accounts_interface.update(account['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        account_name = account_payload['name'] || account['name']
        print_green_success "Tenant #{account_name} updated"
        get([account_name])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :remote, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      # allow finding by ID since name is not unique!
      account = find_account_by_name_or_id(args[0])
      exit 1 if account.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the account #{account['name']}?")
        exit
      end
      if options[:dry_run] && options[:json]
        puts as_json(payload, options)
        return 0
      end
      @accounts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @accounts_interface.dry.destroy(account['id'])
        return
      end
      json_response = @accounts_interface.destroy(account['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
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
      {'fieldName' => 'role', 'fieldLabel' => 'Base Role', 'type' => 'text', 'displayOrder' => 3},
      {'fieldName' => 'currency', 'fieldLabel' => 'Currency', 'type' => 'text', 'displayOrder' => 4}
    ]
  end

  def update_account_option_types
    add_account_option_types
  end

end
