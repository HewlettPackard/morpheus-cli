# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/provisioning_helper'
require 'json'

class Morpheus::Cli::Roles
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  register_subcommands :list, :get, :add, :update, :remove, :'list-permissions', :'update-feature-access', :'update-global-group-access', :'update-group-access', :'update-global-cloud-access', :'update-cloud-access', :'update-global-instance-type-access', :'update-instance-type-access', :'update-global-blueprint-access', :'update-blueprint-access'
  alias_subcommand :details, :get
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @whoami_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).whoami
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @roles_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).roles
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @blueprints_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).blueprints
    @active_group_id = Morpheus::Cli::Groups.active_group
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List roles."
    end
    optparse.parse!(args)

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      
      params = {}
      params.merge!(parse_list_options(options))
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.list(account_id, params), options
        return
      end
      load_whoami()
      json_response = @roles_interface.list(account_id, params)
      if options[:json]
        puts as_json(json_response, options, "roles")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "roles")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['roles'], options)
        return 0
      end
      roles = json_response['roles']
      title = "Morpheus Roles"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if roles.empty?
        print cyan,"No roles found.",reset,"\n"
      else
        print_roles_table(roles, options.merge({is_master_account: @is_master_account}))
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('-p','--permissions', "Display Permissions") do |val|
        options[:include_feature_access] = true
      end
      opts.on('-f','--feature-access', "Display Feature Access [deprecated]") do |val|
        options[:include_feature_access] = true
      end
      opts.add_hidden_option('--feature-access')
      opts.on('-g','--group-access', "Display Group Access") do
        options[:include_group_access] = true
      end
      opts.on('-c','--cloud-access', "Display Cloud Access") do
        options[:include_cloud_access] = true
      end
      opts.on('-i','--instance-type-access', "Display Instance Type Access") do
        options[:include_instance_type_access] = true
      end
      opts.on('-b','--blueprint-access', "Display Blueprint Access") do
        options[:include_blueprint_access] = true
      end
      opts.on('-a','--all-access', "Display All Access Lists") do
        options[:include_feature_access] = true
        options[:include_group_access] = true
        options[:include_cloud_access] = true
        options[:include_instance_type_access] = true
        options[:include_blueprint_access] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a role.\n" +
                    "[name] is required. This is the name or id of a role."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      params.merge!(parse_query_options(options))

      @roles_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
        else
          print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
        end
        return
      end

      # role = find_role_by_name_or_id(account_id, args[0])
      # exit 1 if role.nil?
      # refetch from show action, argh
      # json_response = @roles_interface.get(account_id, role['id'])
      # role = json_response['role']

      json_response = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = @roles_interface.get(account_id, args[0].to_i)
        role = json_response['role']
      else
        role = find_role_by_name_or_id(account_id, args[0])
        exit 1 if role.nil?
        # refetch from show action, argh
        json_response = @roles_interface.get(account_id, role['id'])
        role = json_response['role']
      end

      render_result = render_with_format(json_response, options, 'role')
      return 0 if render_result

      print cyan
      print_h1 "Role Details", options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'authority',
        "Description" => 'description',
        "Scope" => lambda {|it| it['scope'] },
        "Type" => lambda {|it| format_role_type(it) },
        "Multitenant" => lambda {|it| 
          format_boolean(it['multitenant']).to_s + (it['multitenantLocked'] ? " (LOCKED)" : "")
        },
        "Owner" => lambda {|it| role['owner'] ? role['owner']['name'] : '' },
        #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, role)

      # print_h2 "Role Instance Limits", options
      # print cyan
      # print_description_list({
      #   "Max Storage"  => lambda {|it| (it && it['maxStorage'].to_i != 0) ? Filesize.from("#{it['maxStorage']} B").pretty : "no limit" },
      #   "Max Memory"  => lambda {|it| (it && it['maxMemory'].to_i != 0) ? Filesize.from("#{it['maxMemory']} B").pretty : "no limit" },
      #   "CPU Count"  => lambda {|it| (it && it['maxCpu'].to_i != 0) ? it['maxCpu'] : "no limit" }
      # }, role['instanceLimits'])

      print_h2 "Permissions", options
      print cyan
      if options[:include_feature_access]
        rows = json_response['featurePermissions'].collect do |it|
          {
            code: it['code'],
            name: it['name'],
            access: get_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:code, :name, :access], options)
      else
        print cyan,"Use --permissions to list permissions","\n"
      end

      print_h2 "Global Access", options
      # role_access_rows = [
      #   {name: "Groups", access: get_access_string(json_response['globalSiteAccess']) },
      #   {name: "Clouds", access: get_access_string(json_response['globalZoneAccess']) },
      #   {name: "Instance Types", access: get_access_string(json_response['globalInstanceTypeAccess']) },
      #   {name: "Blueprints", access: get_access_string(json_response['globalAppTemplateAccess'] || json_response['globalBlueprintAccess']) }
      # ]
      # puts as_pretty_table(role_access_rows, [:name, :access], options)
      puts as_pretty_table([json_response], [
        {"Groups" => lambda {|it| get_access_string(it['globalSiteAccess']) } },
        {"Clouds" => lambda {|it| get_access_string(it['globalZoneAccess']) } },
        {"Instance Types" => lambda {|it| get_access_string(it['globalInstanceTypeAccess']) } },
        {"Blueprints" => lambda {|it| get_access_string(it['globalAppTemplateAccess'] || it['globalBlueprintAccess']) } },
      ], options)

      #print_h2 "Group Access: #{get_access_string(json_response['globalSiteAccess'])}", options
      print cyan
      if json_response['globalSiteAccess'] == 'custom'
        print_h2 "Group Access", options
        if options[:include_group_access]
          rows = json_response['sites'].collect do |it|
            {
              name: it['name'],
              access: get_access_string(it['access']),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -g, --group-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Group Access: #{get_access_string(json_response['globalSiteAccess'])}",reset,"\n"
      end
      
      print cyan
      #puts "Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}"
      #print "\n"
      if json_response['globalZoneAccess'] == 'custom'
        print_h2 "Cloud Access", options
        if options[:include_cloud_access]
          rows = json_response['zones'].collect do |it|
            {
              name: it['name'],
              access: get_access_string(it['access']),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -c, --cloud-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}",reset,"\n"
      end

      print cyan
      # puts "Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}"
      # print "\n"
      if json_response['globalInstanceTypeAccess'] == 'custom'
        print_h2 "Instance Type Access", options
        if options[:include_instance_type_access]
          rows = json_response['instanceTypePermissions'].collect do |it|
            {
              name: it['name'],
              access: get_access_string(it['access']),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -i, --instance-type-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}",reset,"\n"
      end

      blueprint_global_access = json_response['globalAppTemplateAccess'] || json_response['globalBlueprintAccess']
      blueprint_permissions = json_response['appTemplatePermissions'] || json_response['blueprintPermissions'] || []
      print cyan
      # print_h2 "Blueprint Access: #{get_access_string(json_response['globalAppTemplateAccess'])}", options
      # print "\n"
      if blueprint_global_access == 'custom'
        print_h2 "Blueprint Access", options
        if options[:include_blueprint_access]
          rows = blueprint_permissions.collect do |it|
            {
              name: it['name'],
              access: get_access_string(it['access']),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -b, --blueprint-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Blueprint Access: #{get_access_string(json_response['globalAppTemplateAccess'])}",reset,"\n"
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List the permissions for a role.\n" +
                    "[role] is required. This is the name or id of a role."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      # role = find_role_by_name_or_id(account_id, args[0])
      # exit 1 if role.nil?

      @roles_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
        else
          print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
        end
        return
      end

      json_response = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = @roles_interface.get(account_id, args[0].to_i)
        role = json_response['role']
      else
        role = find_role_by_name_or_id(account_id, args[0])
        exit 1 if role.nil?
        # refetch from show action, argh
        json_response = @roles_interface.get(account_id, role['id'])
        role = json_response['role']
      end

      role_permissions = json_response['featurePermissions']

      if options[:json]
        puts as_json(role_permissions, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(role_permissions, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(role_permissions)
        return 0
      end

      print cyan
      print_h1 "Role Permissions: [#{role['id']}] #{role['authority']}", options

      print cyan
      if role_permissions && role_permissions.size > 0
        rows = role_permissions.collect do |it|
          {
            code: it['code'],
            name: it['name'],
            access: get_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:code, :name, :access], options)
      else
        puts "No permissions found"
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    usage = "Usage: morpheus roles add [options]"
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_role_option_types)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options]['authority'] = args[0]
    end
    connect(options)
    begin

      load_whoami()
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'role' => passed_options}) unless passed_options.empty?
      else
        # merge -O options into normally parsed options
        params.deep_merge!(passed_options)

        # argh, some options depend on others here...eg. multitenant is only available when roleType == 'user'
        #prompt_option_types = update_role_option_types()

        role_payload = params
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1}], options[:options])
        role_payload['authority'] = v_prompt['authority']
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2}], options[:options])
        role_payload['description'] = v_prompt['description']

        if @is_master_account
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => role_type_options, 'defaultValue' => 'user', 'displayOrder' => 3}], options[:options])
          role_payload['roleType'] = v_prompt['roleType']
        else
          role_payload['roleType'] = 'user'
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text', 'displayOrder' => 4}], options[:options])
        if v_prompt['baseRole'].to_s != ''
          base_role = find_role_by_name_or_id(account_id, v_prompt['baseRole'])
          exit 1 if base_role.nil?
          role_payload['baseRoleId'] = base_role['id']
        end

        if @is_master_account
          if role_payload['roleType'] == 'user'
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5}], options[:options])
            role_payload['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
            if role_payload['multitenant']
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it. '}], options[:options])
              role_payload['multitenantLocked'] = ['on','true'].include?(v_prompt['multitenantLocked'].to_s)
            end
          end
        end

        payload = {"role" => role_payload}
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.create(account_id, payload)
        return
      end
      json_response = @roles_interface.create(account_id, payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end

      role = json_response['role']
      display_name = role['authority'] rescue ''
      if account
        print_green_success "Added role #{display_name} to account #{account['name']}"
      else
        print_green_success "Added role #{display_name}"
      end

      get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
      if account
        get_args.push "--account-id", account['id'].to_s
      end

      details_options = [role_payload["authority"]]
      if account
        details_options.push "--account-id", account['id'].to_s
      end
      get(details_options)

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    usage = "Usage: morpheus roles update [name] [options]"
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_role_option_types)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end
    name = args[0]
    connect(options)
    begin

      load_whoami()

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'role' => passed_options}) unless passed_options.empty?
      else
        # merge -O options into normally parsed options
        params.deep_merge!(passed_options)
        prompt_option_types = update_role_option_types()
        if !@is_master_account
          prompt_option_types = prompt_option_types.reject {|it| ['roleType', 'multitenant','multitenantLocked'].include?(it['fieldName']) }
        end
        if role['roleType'] != 'user'
          prompt_option_types = prompt_option_types.reject {|it| ['multitenant','multitenantLocked'].include?(it['fieldName']) }
        end
        #params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])

        if params.empty?
          puts optparse
          option_lines = prompt_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
          puts "\nAvailable Options:\n#{option_lines}\n\n"
          exit 1
        end

        payload = {"role" => params}
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update(account_id, role['id'], payload)
        return
      end
      json_response = @roles_interface.update(account_id, role['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      role = json_response['role']
      display_name = role['authority'] rescue ''
      print_green_success "Updated role #{display_name}"

      get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
      if account
        get_args.push "--account-id", account['id'].to_s
      end
      get(get_args)

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    usage = "Usage: morpheus roles remove [name]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    name = args[0]
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the role #{role['authority']}?")
        exit
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.destroy(account_id, role['id'])
        return
      end
      json_response = @roles_interface.destroy(account_id, role['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} removed"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_feature_access(args)
    usage = "Usage: morpheus roles update-feature-access [name] [code] [full|read|user|yes|no|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [code] [full|read|user|yes|no|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 3
      puts optparse
      exit 1
    end
    name = args[0]
    permission_code = args[1]
    access_value = args[2].to_s.downcase

    # if !['full_decrypted','full', 'read', 'custom', 'none'].include?(access_value)
    #   puts optparse
    #   exit 1
    # end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: permission_code, access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} permission #{permission_code} set to #{access_value}"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_group_access(args)
    usage = "Usage: morpheus roles update-global-group-access [name] [full|read|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|read|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'read', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'ComputeSite', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global group access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_group_access(args)
    options = {}
    name = nil
    group_name = nil
    access_value = nil
    do_all = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-g', '--group GROUP', "Group name or id" ) do |val|
        group_name = val
      end
      opts.on( nil, '--all', "Update all groups at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [full|read|none]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a group or all groups.\n" +
                    "[name] is required. This is the name or id of a role.\n" + 
                    "--group or --all is required. This is the name or id of a group.\n" + 
                    "--access is required. This is the new access value."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [name] [group] [access]
    group_name ||= args[1]
    access_value ||= args[2]

    if (!group_name && !do_all) || !access_value
      puts optparse
      return 1
    end
    
    access_value = access_value.to_s.downcase

    if !['full', 'read', 'none'].include?(access_value)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalSiteAccess'] != 'custom'
        print "\n", red, "Global Group Access is currently: #{role_json['globalSiteAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-group-access \"#{name}\" custom`"
        print "\n\n", reset
        exit 1
      end

      group = nil
      group_id = nil
      if !do_all
        group = find_group_by_name_or_id_for_provisioning(group_name)
        return 1 if group.nil?
        group_id = group['id']
      end

      params = {}
      if do_all
        params['allGroups'] = true
      else
        params['groupId'] = group_id
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_group(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_group(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all groups"
        else
          print_green_success "Role #{role['authority']} access updated for group #{group['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_cloud_access(args)
    usage = "Usage: morpheus roles update-global-cloud-access [name] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'ComputeZone', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global cloud access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_cloud_access(args)
    options = {}
    cloud_name = nil
    access_value = nil
    do_all = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-c', '--cloud CLOUD', "Cloud name or id" ) do |val|
        puts "val is : #{val}"
        cloud_name = val
      end
      opts.on( nil, '--all', "Update all clouds at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [full|read|none]" ) do |val|
        access_value = val
      end
      opts.on( '-g', '--group GROUP', "Group to find cloud in" ) do |val|
        options[:group] = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a cloud or all clouds.\n" +
                    "[name] is required. This is the name or id of a role.\n" + 
                    "--cloud or --all is required. This is the name or id of a cloud.\n" + 
                    "--access is required. This is the new access value."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [name] [cloud] [access]
    cloud_name ||= args[1]
    access_value ||= args[2]

    if (!cloud_name && !do_all) || !access_value
      puts optparse
      return 1
    end
    puts "cloud_name is : #{cloud_name}"
    puts "access_value is : #{access_value}"
    access_value = access_value.to_s.downcase

    if !['full', 'none'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalZoneAccess'] != 'custom'
        print "\n", red, "Global Cloud Access is currently: #{role_json['globalZoneAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-cloud-access \"#{name}\" custom`"
        print "\n\n", reset
        exit 1
      end

      # crap, group_id is needed for this api, maybe just use infrastructure or some other optionSource instead.
      group_id = nil
      cloud_id = nil
      if !do_all
        group_id = nil
        if !options[:group].nil?
          group = find_group_by_name_or_id_for_provisioning(options[:group])
          group_id = group['id']
        else
          group_id = @active_group_id
        end
        if group_id.nil?
          print_red_alert "Group not found or specified!"
          return 1
        end
        cloud_id = find_cloud_id_by_name(group_id, cloud_name)
        return 1 if cloud_id.nil?
      end
      params = {}
      if do_all
        params['allClouds'] = true
      else
        params['cloudId'] = cloud_id
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_cloud(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_cloud(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all clouds"
        else
          print_green_success "Role #{role['authority']} access updated for cloud id #{cloud_id}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_instance_type_access(args)
    usage = "Usage: morpheus roles update-global-instance-type-access [name] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'InstanceType', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global instance type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_instance_type_access(args)
    options = {}
    instance_type_name = nil
    access_value = nil
    do_all = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '--instance-type INSTANCE_TYPE', String, "Instance Type name" ) do |val|
        instance_type_name = val
      end
      opts.on( nil, '--all', "Update all instance types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [full|read|none]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for an instance type or all instance types.\n" +
                    "[name] is required. This is the name or id of a role.\n" + 
                    "--instance-type or --all is required. This is the name of an instance type.\n" + 
                    "--access is required. This is the new access value."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [name] [instance-type] [access]
    instance_type_name ||= args[1]
    access_value ||= args[2]

    if (!instance_type_name && !do_all) || !access_value
      puts optparse
      return 1
    end
    
    access_value = access_value.to_s.downcase

    if !['full', 'none'].include?(access_value)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalInstanceTypeAccess'] != 'custom'
        print "\n", red, "Global Instance Type Access is currently: #{role_json['globalInstanceTypeAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-instance-type-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      instance_type = nil
      if !do_all
        instance_type = find_instance_type_by_name(instance_type_name)
        return 1 if instance_type.nil?
      end

      params = {}
      if do_all
        params['allInstanceTypes'] = true
      else
        params['instanceTypeId'] = instance_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_instance_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_instance_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all instance types"
        else
          print_green_success "Role #{role['authority']} access updated for instance type #{instance_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_blueprint_access(args)
    usage = "Usage: morpheus roles update-global-blueprint-access [name] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'AppTemplate', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global blueprint access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_blueprint_access(args)
    options = {}
    blueprint_id = nil
    access_value = nil
    do_all = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '--blueprint ID', String, "Blueprint ID or Name" ) do |val|
        blueprint_id = val
      end
      opts.on( nil, '--all', "Update all blueprints at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [full|read|none]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for an blueprint or all blueprints.\n" +
                    "[name] is required. This is the name or id of a role.\n" + 
                    "--blueprint or --all is required. This is the name or id of a blueprint.\n" + 
                    "--access is required. This is the new access value."
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [name] [blueprint] [access]
    blueprint_id ||= args[1]
    access_value ||= args[2]

    if (!blueprint_id && !do_all) || !access_value
      puts_error optparse
      return 1
    end
    
    access_value = access_value.to_s.downcase

    if !['full', 'none'].include?(access_value)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      blueprint_global_access = role_json['globalAppTemplateAccess'] || role_json['globalBlueprintAccess']
      blueprint_permissions = role_json['appTemplatePermissions'] || role_json['blueprintPermissions'] || []
      if blueprint_global_access != 'custom'
        print "\n", red, "Global Blueprint Access is currently: #{blueprint_global_access.to_s.capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-blueprint-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      # hacky, but support name or code lookup via the list returned in the show payload
      blueprint = nil
      if !do_all
        if blueprint_id.to_s =~ /\A\d{1,}\Z/
          blueprint = blueprint_permissions.find {|b| b['id'] == blueprint_id.to_i }
        else
          blueprint = blueprint_permissions.find {|b| b['name'] == blueprint_id || b['code'] == blueprint_id }
        end
        if blueprint.nil?
          print_red_alert "Blueprint not found: '#{blueprint_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allAppTemplates'] = true
        #params['allBlueprints'] = true
      else
        params['appTemplateId'] = blueprint['id']
        # params['blueprintId'] = blueprint['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_blueprint(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_blueprint(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all blueprints"
        else
          print_green_success "Role #{role['authority']} access updated for blueprint #{blueprint['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  # def get_access_string(val)
  #   val ||= 'none'
  #   if val == 'none'
  #     "#{white}#{val.to_s.capitalize}#{cyan}"
  #   else
  #     "#{green}#{val.to_s.capitalize}#{cyan}"
  #   end
  # end

  def add_role_option_types
    [
      {'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
      {'fieldName' => 'roleType', 'fieldLabel' => 'Role Type', 'type' => 'select', 'selectOptions' => [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}], 'defaultValue' => 'user', 'displayOrder' => 3},
      {'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text', 'displayOrder' => 4},
      {'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5},
      {'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it. ', 'displayOrder' => 6}
    ]
  end

  "A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use"
  def update_role_option_types
    add_role_option_types.reject {|it| ['roleType', 'baseRole'].include?(it['fieldName']) }
  end


  def find_cloud_id_by_name(group_id, name)
    option_results = @options_interface.options_for_source('clouds', {groupId: group_id})
    match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
    if match.nil?
      print_red_alert "Cloud not found by name #{name}"
      return nil
    else
      return match['value']
    end
  end

  def find_instance_type_by_name(name)
    results = @instance_types_interface.list({name: name})
    if results['instanceTypes'].empty?
      print_red_alert "Instance Type not found by name #{name}"
      return nil
    end
    return results['instanceTypes'][0]
  end

  def load_whoami
    whoami_response = @whoami_interface.get()
    @current_user = whoami_response["user"]
    if @current_user.empty?
      print_red_alert "Unauthenticated. Please login."
      exit 1
    end
    @is_master_account = whoami_response["isMasterAccount"]
  end

  def role_type_options
    [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}]
  end

end
