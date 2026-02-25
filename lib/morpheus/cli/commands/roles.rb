require 'morpheus/cli/cli_command'

class Morpheus::Cli::Roles
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper
  register_subcommands :list, :get, :add, :update, :remove, :validate,
    :'list-permissions', :'update-feature-access',
    :'update-group-access', :'update-global-group-access', :'update-default-group-access',
    :'update-global-cloud-access', :'update-cloud-access', :'update-default-cloud-access',
    :'update-global-instance-type-access', :'update-instance-type-access', :'update-default-instance-type-access',
    :'update-global-blueprint-access', :'update-blueprint-access', :'update-default-blueprint-access',
    :'update-global-catalog-item-type-access', :'update-catalog-item-type-access', :'update-default-catalog-item-type-access',
    :'update-persona-access', :'update-default-persona-access',
    :'update-global-vdi-pool-access', :'update-vdi-pool-access', :'update-default-vdi-pool-access',
    :'update-global-report-type-access', :'update-report-type-access', :'update-default-report-type-access',
    :'update-global-task-access', :'update-task-access', :'update-default-task-access',
    :'update-global-workflow-access', :'update-workflow-access', :'update-default-workflow-access',
    :'update-cluster-type-access', :'update-default-cluster-type-access'
  set_subcommands_hidden(
    subcommands.keys.select{|c|
    c.include?('update-global')
  })
  alias_subcommand :details, :get
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @whoami_interface = @api_client.whoami
    @account_users_interface = @api_client.account_users
    @accounts_interface = @api_client.accounts
    @roles_interface = @api_client.roles
    @groups_interface = @api_client.groups
    @options_interface = @api_client.options
    @instances_interface = @api_client.instances
    @instance_types_interface = @api_client.instance_types
    @blueprints_interface = @api_client.blueprints
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search phrase]")
      opts.on( '--tenant TENANT', "Tenant Filter for list of Roles." ) do |val|
        options[:tenant] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List roles."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    options[:phrase] = args.join(" ") if args.count > 0
    connect(options)

    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params = {}
    params.merge!(parse_list_options(options))
    @roles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @roles_interface.dry.list(account_id, params), options
      return 0, nil
    end
    load_whoami()
    if options[:tenant]
      params[:tenant] = options[:tenant]
    end
    json_response = @roles_interface.list(account_id, params)

    render_response(json_response, options, "roles") do
      roles = json_response['roles']
      title = "Morpheus Roles"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if roles.empty?
        print cyan,"No roles found.",reset,"\n"
      else
        print cyan
        columns = @is_master_account ? role_column_definitions : subtenant_role_column_definitions
        print as_pretty_table(roles, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      opts.on('-p','--permissions', "Display Permissions [deprecated]") do |val|
        options[:include_feature_access] = true
      end
      opts.add_hidden_option('-p,')
      opts.on('-f','--feature-access', "Display Feature Access") do |val|
        options[:include_feature_access] = true
      end
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
      opts.on(nil,'--catalog-item-type-access', "Display Catalog Item Type Access") do
        options[:include_catalog_item_type_access] = true
      end
      opts.on(nil,'--personas', "Display Persona Access") do
        options[:include_persona_access] = true
      end
      opts.add_hidden_option('--personas')
      opts.on(nil,'--persona-access', "Display Persona Access") do
        options[:include_persona_access] = true
      end
      opts.on(nil,'--vdi-pool-access', "Display VDI Pool Access") do
        options[:include_vdi_pool_access] = true
      end
      opts.on(nil,'--report-type-access', "Display Report Type Access") do
        options[:include_report_type_access] = true
      end
      opts.on(nil,'--workflow-access', "Display Workflow Access") do
        options[:include_workflow_access] = true
      end
      opts.on(nil,'--task-access', "Display Task Access") do
        options[:include_task_access] = true
      end
      opts.on(nil,'--cluster-type-access', "Display Cluster Type Access") do
        options[:include_cluster_type_access] = true
      end
      opts.on('-a','--all', "Display All Access Lists") do
        options[:include_all_access] = true
      end
      opts.on(nil, '--include-default-access', "Include default access levels in the output (returns all available resources)") do
        options[:include_default_access] = true
      end
      opts.on('--account-id ID', String, "Clarify Owner of Role") do |val|
        options[:account_id] = val.to_s
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a role.
[role] is required. This is the name (authority) or id of a role.
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
    params = {}
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil

    params.merge!(parse_query_options(options))
    params['includeDefaultAccess'] = true if options[:include_default_access]
    @roles_interface.setopts(options)
    if options[:dry_run]
      if args[0].to_s =~ /\A\d{1,}\Z/
        print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
      else
        print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
      end
      return
    end

    load_whoami()
    json_response = nil
    role = nil
    if args[0].to_s =~ /\A\d{1,}\Z/
      json_response = @roles_interface.get(account_id, args[0].to_i, params)
      role = json_response['role']
    else
      role = find_role_by_name_or_id(account_id, args[0])
      exit 1 if role.nil?
      # refetch from show action, argh
      json_response = @roles_interface.get(account_id, role['id'], params)
      role = json_response['role']
    end

    render_response(json_response, options, 'role') do

      print cyan
      print_h1 "Role Details", options
      print cyan
      columns = @is_master_account ? role_column_definitions : subtenant_role_column_definitions
      print_description_list(columns, role, options)

      print_h2 "Permissions", options
      print cyan
      permissions = json_response['featurePermissions'] || role['permissions'] || []
      if options[:include_feature_access] || options[:include_all_access]
        rows = permissions.collect do |it|
          {
            code: it['code'],
            name: it['name'],
            category: it['subCategory'].to_s.titleize,
            access: format_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        else
          rows.sort! {|a,b| [a[:category],a[:name],a[:code]] <=> [b[:category],b[:name],b[:code]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:category, :name, :code, :access], options)
        # print reset,"\n"
      else
        print cyan,"Use --feature-access to list feature access","\n"
      end

      has_group_access = true
      has_cloud_access = true
      print_h2 "Default Access", options
      global_access_columns = {
        "Groups" => lambda {|it| get_access_string(it['globalSiteAccess']) },
        "Clouds" => lambda {|it| get_access_string(it['globalZoneAccess']) },
        "Instance Types" => lambda {|it| get_access_string(it['globalInstanceTypeAccess']) },
        "Blueprints" => lambda {|it| get_access_string(it['globalAppTemplateAccess'] || it['globalBlueprintAccess']) },
        "Personas" => lambda {|it| get_access_string(it['globalPersonaAccess']) },
        "Report Types" => lambda {|it| get_access_string(it['globalReportTypeAccess']) },
        "Catalog Item Types" => lambda {|it| get_access_string(it['globalCatalogItemTypeAccess']) },
        "VDI Pools" => lambda {|it| get_access_string(it['globalVdiPoolAccess']) },
        "Workflows" => lambda {|it| get_access_string(it['globalTaskSetAccess']) },
        "Tasks" => lambda {|it| get_access_string(it['globalTaskAccess']) },
        "Cluster Types" => lambda {|it| get_access_string(it['globalClusterTypeAccess']) },
      }

      if role['roleType'].to_s.downcase == 'account'
        global_access_columns.delete("Groups")
        has_group_access = false
      else
        global_access_columns.delete("Clouds")
        has_cloud_access = false
      end

      print as_pretty_table([json_response], global_access_columns, options)

      if has_group_access
        #print_h2 "Group Access: #{get_access_string(json_response['globalSiteAccess'])}", options
        print cyan
        print_h2 "Group Access", options
        if options[:include_group_access] || options[:include_all_access]
          rows = json_response['sites'].collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","read","full"]),
            }
          end
          if !options[:include_default_access]
            rows = rows.select {|row| row[:access] && row[:access] != 'default '}
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -g, --group-access to list custom access","\n"
        end
      end

      if has_cloud_access
        print cyan
        #puts "Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}"
        #print "\n"
        if json_response['sites'].find{|it| it['access'] && it['access'] != 'default'}
          print_h2 "Cloud Access", options
          if options[:include_cloud_access] || options[:include_all_access]
            rows = json_response['zones'].collect do |it|
              {
                name: it['name'],
                access: format_access_string(it['access'], ["none","read","full"]),
              }
            end
            if !options[:include_default_access]
              rows = rows.select {|row| row[:access] && row[:access] != 'default '}
            end
            print as_pretty_table(rows, [:name, :access], options)
          else
            print cyan,"Use -c, --cloud-access to list custom access","\n"
          end
          # print reset,"\n"
        else
          # print "\n"
          # print cyan,bold,"Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}",reset,"\n"
        end
      end

      print cyan
      # puts "Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}"
      # print "\n"
      instance_type_global_access = json_response['globalInstanceTypeAccess']
      instance_type_permissions = role['instanceTypes'] ? role['instanceTypes'] : (json_response['instanceTypePermissions'] || [])

      # if have any custom, then we want to show the flag indicator
      # if including, show

      if options[:include_instance_type_access] || options[:include_all_access]
        print_h2 "Instance Type Access", options
        rows = instance_type_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","read","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif instance_type_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Instance Type Access", options
        print cyan,"Use -i, --instance-type-access to list custom access","\n"
      end

      blueprint_global_access = json_response['globalAppTemplateAccess'] || json_response['globalBlueprintAccess']
      blueprint_permissions = (role['appTemplates'] || role['blueprints']) ? (role['appTemplates'] || role['blueprints']) : (json_response['appTemplatePermissions'] || json_response['blueprintPermissions'] || [])
      print cyan
      if options[:include_blueprint_access] || options[:include_all_access]
        print_h2 "Blueprint Access", options
        rows = blueprint_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","read","full"]),
          }
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif blueprint_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Blueprint Access", options
        print cyan,"Use -b, --blueprint-access to list custom access","\n"
      end

      catalog_item_type_global_access = json_response['globalCatalogItemTypeAccess']
      catalog_item_type_permissions = role['catalogItemTypes'] ? role['catalogItemTypes'] : (json_response['catalogItemTypePermissions'] || [])
      print cyan
      if options[:include_catalog_item_type_access] || options[:include_all_access]
        print_h2 "Catalog Item Type Access", options
        rows = catalog_item_type_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","read","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif catalog_item_type_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Catalog Item Type Access", options
        print cyan,"Use --catalog-item-type-access to list access","\n"
      end

      persona_global_access = json_response['globalPersonaAccess']
      persona_permissions = role['personas'] ? role['personas'] : (json_response['personaPermissions'] || [])
      print cyan
      if options[:include_persona_access] || options[:include_all_access]
        print_h2 "Persona Access", options
        rows = persona_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif persona_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Persona Access", options
        print cyan,"Use --persona-access to list access","\n"
      end

      vdi_pool_global_access = json_response['globalVdiPoolAccess']
      vdi_pool_permissions = role['vdiPools'] ? role['vdiPools'] : (json_response['vdiPoolPermissions'] || [])
      print cyan
      if options[:include_vdi_pool_access] || options[:include_all_access]
        print_h2 "VDI Pool Access", options
        rows = vdi_pool_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif vdi_pool_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "VDI Pool Access", options
        print cyan,"Use --vdi-pool-access to list custom access","\n"
      end

      report_type_global_access = json_response['globalReportTypeAccess']
      report_type_permissions = role['reportTypes'] ? role['reportTypes'] : (json_response['reportTypePermissions'] || [])
      print cyan
      if options[:include_report_type_access] || options[:include_all_access]
        print_h2 "Report Type Access", options
        rows = report_type_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif report_type_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Report Type Access", options
        print cyan,"Use --report-type-access to list custom access","\n"
      end

      task_global_access = json_response['globalTaskAccess']
      task_permissions = role['tasks'] ? role['tasks'] : (json_response['taskPermissions'] || [])
      print cyan
      if options[:include_task_access] || options[:include_all_access]
        print_h2 "Task Access", options
        rows = task_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif task_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Task Access", options
        print cyan,"Use --task-access to list custom access","\n"
      end

      workflow_global_access = json_response['globalTaskSetAccess']
      workflow_permissions = role['taskSets'] ? role['taskSets'] : (json_response['taskSetPermissions'] || [])
      print cyan
      if options[:include_workflow_access] || options[:include_all_access]
        print_h2 "Workflow Access", options
        rows = workflow_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif workflow_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Workflow Access", options
        print cyan,"Use --workflow-access to list custom access","\n"
      end

      cluster_type_global_access = json_response['globalClusterTypeAccess']
      cluster_type_permissions = role['clusterTypes'] ? role['clusterTypes'] : (json_response['clusterTypePermissions'] || [])
      print cyan
      if options[:include_cluster_type_access] || options[:include_all_access]
        print_h2 "Cluster Type Access", options
        rows = cluster_type_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","full"]),
          }
        end
        if !options[:include_default_access]
          rows = rows.select {|row| row[:access] && row[:access] != 'default '}
        end
        print as_pretty_table(rows, [:name, :access], options)
      elsif cluster_type_permissions.find {|it| it['access'] && it['access'] != 'default'}
        print_h2 "Cluster Type Access", options
        print cyan,"Use --cluster-type-access to list custom access","\n"
      end

      print reset,"\n"
      return 0, nil
    end
  end

  def list_permissions(args)
    options = {}
    available_categories = ['feature', 'group', 'cloud', 'instance-type', 'blueprint', 'report-type', 'persona', 'catalog-item-type', 'vdi-pool', 'workflow', 'task', 'cluster-type']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [category]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List the access for a role.\n" +
        "[role] is required. This is the name or id of a role.\n" +
        "[category] is optional. Available categories: #{ored_list(available_categories)}"
    end

    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min: 1, max:2)
    connect(options)

    category = args[1].to_s.downcase if args[1]

    if !category.nil? && !available_categories.include?(category)
      raise_command_error("invalid category: #{category}", args, optparse)
    end

    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil

    @roles_interface.setopts(options)
    if options[:dry_run]
      if args[0].to_s =~ /\A\d{1,}\Z/
        print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
      else
        print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
      end
      return
    end

    if args[0].to_s =~ /\A\d{1,}\Z/
      role = @roles_interface.get(account_id, args[0].to_i)
    else
      role = find_role_by_name_or_id(account_id, args[0])
      exit 1 if role.nil?
      role = @roles_interface.get(account_id, role['id'])
    end

    available_categories.reject! {|category| category == 'cloud'} if role['role']['roleType'] == 'user'
    available_categories.reject! {|category| category == 'group'} if role['role']['roleType'] == 'account'

    permission_name = -> (s) {
      return 'sites' if s == 'group'
      return 'zones' if s == 'cloud'
      s = 'task-set' if s == 'workflow'
      s = 'app-template' if s == 'blueprint'
      s.split('-').map.with_index{|s,i| i == 0 ? s : s.capitalize}.join + 'Permissions'
    }
    permission_label = -> (s) {s.split('-').collect{|s| s.capitalize}.join(' ') + ' Permissions'}

    if category.nil?
      permissions = available_categories.reject{|category| role[permission_name.call(category)].nil?}.collect{|category|
        role[permission_name.call(category)].map{|perm| perm.merge({'category' => permission_label.call(category)})}
      }.flatten
    else
      permissions = role[permission_name.call(category)]
    end

    if options[:json]
      puts as_json(permissions, options)
      return 0
    elsif options[:yaml]
      puts as_yaml(permissions, options)
      return 0
    elsif options[:csv]
      puts records_as_csv(permissions, :include_fields => ['category', 'id', 'code', 'name', 'access', 'sub category'])
      return 0
    end

    print cyan
    print_h1 "Role: [#{role['role']['id']}#{(role['role']['owner'].nil? ? ']' : ", #{role['role']['owner']['name']}]")} #{role['role']['authority']}", options

    (category.nil? ? available_categories : [category]).each do |category|
      permissions = role[permission_name.call(category)]
      next if permissions.nil?
      print_h2 "#{permission_label.call(category)}", options
      if permissions.size > 0
        rows = permissions.collect do |it|
          {
            code: it['code'],
            name: it['name'],
            category: it['subCategory'].to_s.titleize,
            access: format_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        else
          rows.sort! {|a,b| [a[:category],a[:name],a[:code]] <=> [b[:category],b[:name],b[:code]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:category, :name, :code, :access], options)
      else
        puts "No permissions found"
      end
    end
    print reset,"\n"
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_role_option_types)
      build_role_access_options(opts, options, params)
      opts.on('--owner ID', String, "Set the owner/tenant/account for the role by account id. This option requires the admin permission to manage tenants." ) do |val|
        params['owner'] = val
      end
      opts.on(nil, '--include-default-access', "Include default access levels in the response (returns all available resources)") do
        options[:include_default_access] = true
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new role.
[name] is required. This is a unique name (authority) for the new role.
All the role permissions and access values can be configured.
Use --feature-access "CODE=ACCESS,CODE=ACCESS" to update access levels for specific feature permissions identified by code. 
Use --default-instance-type-access custom --instance-types "CODE=ACCESS,CODE=ACCESS" to customize instance type access.
Only the specified permissions,instance types, etc. are updated.
Use --reset-feature-access to set access to "none" for all unspecified feature permissions.
Use --reset-all-access to set access to "none" for all unspecified feature permissions and default access values for groups, instance types, etc.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
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

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1}], options[:options])
        params['authority'] = v_prompt['authority']
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2}], options[:options])
        params['description'] = v_prompt['description']
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'landingUrl', 'fieldLabel' => 'Landing URL', 'type' => 'text', 'displayOrder' => 3, 'description' => 'An optional override for the default landing page after login for a user.'}], options[:options])
        params['landingUrl'] = v_prompt['landingUrl']

        can_manage_accounts = @user_permissions.find { |it| it['code'] == 'admin-accounts' && it['access'] == 'full'}

        if can_manage_accounts
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'owner', 'fieldLabel' => 'Owner', 'type' => 'select', 'selectOptions' => role_owner_options, 'defaultValue' => current_account['id'], 'displayOrder' => 3}], options[:options])
          params['owner'] = v_prompt['owner']
        else
          params['owner'] = current_account['id']
        end  

        if can_manage_accounts
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => role_type_options, 'defaultValue' => 'user', 'displayOrder' => 4}], options[:options])
          params['roleType'] = v_prompt['roleType']
        else
          params['roleType'] = 'user'
        end

        if options[:cloud_permissions] && params['roleType'] == 'user'
          raise_command_error "The --clouds option is only available for user roles, not account roles"
        end
        if options[:group_permissions] && params['roleType'] == 'account'
          raise_command_error "The --groups option is only available for account roles, not user roles"
        end
        if params['globalZoneAccess'] && params['roleType'] == 'user'
          raise_command_error "The --default-cloud-access option is only available for account roles, not user roles"
        end
        if params['globalSiteAccess'] && params['roleType'] == 'account'
          raise_command_error "The --default-group-access option is only available for user roles, not account roles"
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'select', 'selectOptions' => base_role_options(params), 'displayOrder' => 5}], options[:options])
        if v_prompt['baseRole'].to_s != ''
          base_role = find_role_by_name_or_id(account_id, v_prompt['baseRole'])
          exit 1 if base_role.nil?
          params['baseRoleId'] = base_role['id']
        end

        if @is_master_account && params['owner'] == current_account['id']
          if params['roleType'] == 'user'
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5}], options[:options])
            params['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
            if params['multitenant']
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it.'}], options[:options])
              params['multitenantLocked'] = ['on','true'].include?(v_prompt['multitenantLocked'].to_s)
            end
          end
        end

        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'optionSource' => 'personas', 'description' => 'Default Persona'}], options[:options], @api_client)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'selectOptions' => get_persona_select_options(), 'description' => 'Default Persona'}], options[:options], @api_client)
        params['defaultPersona'] = {'code' => v_prompt['defaultPersona']} unless v_prompt['defaultPersona'].to_s.strip.empty?

        # bulk role permissions
        parse_role_access_options(options, params)
        payload = {"role" => params}
      end
      query_params = parse_query_options(options)
      query_params['includeDefaultAccess'] = true if options[:include_default_access]
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.create(account_id, payload, query_params)
        return
      end
      json_response = @roles_interface.create(account_id, payload, query_params)

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

      details_options = [params["authority"]]
      if account
        details_options.push "--account-id", account['id'].to_s
      end

      if params['owner']
        details_options.push "--account-id", params['owner'].to_s
      end
      get(details_options)

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [options]")
      build_option_type_options(opts, options, update_role_option_types)
      build_role_access_options(opts, options, params)
      opts.on(nil, '--include-default-access', "Include default access levels in the output (returns all available resources)") do
        options[:include_default_access] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a role.
[role] is required. This is the name (authority) or id of a role.
All the role permissions and access values can be configured.
Use --feature-access "CODE=ACCESS,CODE=ACCESS" to update access levels for specific feature permissions identified by code. 
Use --default-instance-type-access custom --instance-types "CODE=ACCESS,CODE=ACCESS" to customize instance type access.
Only the specified permissions,instance types, etc. are updated.
Use --reset-feature-access to set access to "none" for all unspecified feature permissions.
Use --reset-all-access to set access to "none" for all unspecified feature permissions and global access values for groups, instance types, etc.
EOT
    end
    optparse.parse!(args)

    verify_args!(args:args, optparse:optparse, count:1)
    
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
        # if !has_complete_access
        #   prompt_option_types = prompt_option_types.reject {|it| ['roleType', 'multitenant','multitenantLocked'].include?(it['fieldName']) }
        # end
        if role['roleType'] != 'user'
          prompt_option_types = prompt_option_types.reject {|it| ['multitenant','multitenantLocked'].include?(it['fieldName']) }
        end
        #params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])
        if options[:cloud_permissions] && role['roleType'] == 'user'
          raise_command_error "The --clouds option is only available for user roles, not account roles"
        end
        if options[:group_permissions] && role['roleType'] == 'account'
          raise_command_error "The --groups option is only available for account roles, not user roles"
        end
        if params['globalZoneAccess'] && role['roleType'] == 'user'
          raise_command_error "The --default-cloud-access option is only available for account roles, not user roles"
        end
        if params['globalSiteAccess'] && role['roleType'] == 'account'
          raise_command_error "The --default-group-access option is only available for user roles, not account roles"
        end
        # bulk role permissions
        parse_role_access_options(options, params)

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        payload = {"role" => params}
      end
      query_params = parse_query_options(options)
      query_params['includeDefaultAccess'] = true if options[:include_default_access]
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update(account_id, role['id'], payload, query_params)
        return
      end
      json_response = @roles_interface.update(account_id, role['id'], payload, query_params)
      render_response(json_response, options, "role") do
        role = json_response['role']
        display_name = role['authority'] rescue ''
        print_green_success "Updated role #{display_name}"

        get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        if account
          get_args.push "--account-id", account['id'].to_s
        end
        get(get_args)
      end
      return 0, nil

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = <<-EOT
Delete a role.
[role] is required. This is the name (authority) or id of a role.
EOT
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

  def validate(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [options]")
      build_option_type_options(opts, options, add_role_option_types)
      build_role_access_options(opts, options, params)
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = <<-EOT
Validate role permissions without creating or updating a role.
[role] is optional. This is the name (authority) or id of a role.
This is useful for testing permission configurations before applying them.
All the role permissions and access values can be validated.
Use --feature-access "CODE=ACCESS,CODE=ACCESS" to validate access levels for specific feature permissions.
Example: morpheus roles validate --authority "Test Role" --feature-access "admin=full,activity=read"
Example: morpheus roles validate "Existing Role" --feature-access "activity=full"
EOT
    end
    optparse.parse!(args)
    
    # allow 0-1 arguments
    verify_args!(args:args, optparse:optparse, max:1)
    
    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      # load existing role if arg passed
      role = nil
      if args[0]
        role = find_role_by_name_or_id(account_id, args[0])
        exit 1 if role.nil?
      end

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'role' => passed_options}) unless passed_options.empty?
      else
        # merge -O options into normally parsed options
        params.deep_merge!(passed_options)
        
        # Parse role access options
        parse_role_access_options(options, params)

        # Validate role type constraints
        role_type = role ? role['roleType'] : params['roleType']
        if role_type
          if params['globalZoneAccess'] && role_type == 'user'
            raise_command_error "The --default-cloud-access option is only available for account roles, not user roles"
          end
          if params['globalSiteAccess'] && role_type == 'account'
            raise_command_error "The --default-group-access option is only available for user roles, not account roles"
          end
        end

        if params.empty? && passed_options.empty? && role.nil?
          raise_command_error "Specify at least one role configuration option to validate.\n#{optparse}"
        end
        
        payload = {"role" => params}
      end
      
      if role
        payload['role']['id'] = role['id']
      end
      
      query_params = parse_query_options(options)
      @roles_interface.setopts(options)
      
      if options[:dry_run]
        print_dry_run @roles_interface.dry.validate(account_id, payload, query_params)
        return 0, nil
      end
      
      json_response = @roles_interface.validate(account_id, payload, query_params)
      
      render_response(json_response, options) do
        if json_response['success'] && json_response['valid']
          print_green_success json_response['msg'] || "Role permissions are valid"
        else
          print_red_alert "Validation failed: #{json_response['msg'] || 'Invalid role permissions'}"
          if json_response['errors'] && !json_response['errors'].empty?
            print_h2 "Validation Errors", options
            json_response['errors'].each do |key, msg|
              print red, "  #{key}: #{msg}", reset, "\n"
            end
          end
        end
      end
      
      # Return exit code based on validation result
      return json_response['success'] && json_response['valid'] ? 0 : 1
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_feature_access(args)
    options = {}
    allowed_access_values = ["full", "full_decrypted", "group", "listfiles", "managerules", "no", "none", "provision", "read", "rolemappings", "user", "view", "yes"]
    permission_code = nil
    access_value = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [permission] [access]")
      opts.on( '-p', '--permission CODE', "Permission code or name" ) do |val|
        permission_code = val
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}] (varies per permission)" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a permission.
[role] is required. This is the name (authority) or id of a role.
[permission] is required. This is the code or name of a permission.
[access] is required. This is the new access value: #{ored_list(allowed_access_values)}
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:3)
    name = args[0]
    permission_code = args[1] if args[1]
    access_value = args[2].to_s.downcase if args[2]

    if !permission_code
      raise_command_error("missing required argument: [permission]", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    # access_value = access_value.to_s.downcase
    # if !allowed_access_values.include?(access_value)
    #   raise_command_error("invalid access value: #{access_value}", args, optparse)
    # end
    # need to load the permission and then split accessTypes, so just allows all for now, server validates...
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
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_group_access(args)
  end

  def update_default_group_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default group access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, read, or none.
Only applicable to User roles.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'read', 'none', 'custom'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      if role['roleType'] == 'account'
        raise_command_error "The default-group-access command is only available for user roles, not account roles"
      end

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
        print_green_success "Role #{role['authority']} default group access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_group_access(args)
    options = {}
    name = nil
    group_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'read', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [group] [access]")
      opts.on( '-g', '--group GROUP', "Group name or id" ) do |val|
        group_id = val
      end
      opts.on( nil, '--all', "Update all groups at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a group or all groups.
[role] is required. This is the name or id of a role.
--group or --all is required. This is the name or id of a group.
--access is required. This is the new access value: #{ored_list(allowed_access_values)}
EOT
      
    end
    optparse.parse!(args)

    # usage: update-group-access [role] [access] --all
    #        update-group-access [role] [group] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      group_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !group_id && !do_all
      raise_command_error("missing required argument: [group] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      group = nil
      if !do_all
        group = find_group_by_name_or_id_for_provisioning(group_id)
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
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_cloud_access(args)
  end

  def update_default_cloud_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default cloud access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, read or none.
Only applicable to Tenant roles.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'read', 'none', 'custom'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      if role['roleType'] == 'user'
        raise_command_error "The default-cloud-access command is only available for account roles, not user roles"
      end

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
        print_green_success "Role #{role['authority']} default cloud access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_cloud_access(args)
    options = {}
    cloud_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'read', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      opts.on( '-c', '--cloud CLOUD', "Cloud name or id" ) do |val|
        cloud_id = val
      end
      opts.on( nil, '--all', "Update all clouds at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a cloud or all clouds.
[role] is required. This is the name or id of a role.
--cloud or --all is required. This is the name or id of a cloud.
--access is required. This is the new access value: #{ored_list(allowed_access_values)}
EOT
    end
    optparse.parse!(args)

    # usage: update-cloud-access [role] [access] --all
    #        update-cloud-access [role] [cloud] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      cloud_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !cloud_id && !do_all
      raise_command_error("missing required argument: [cloud] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})

      cloud = nil
      if !do_all
        cloud = find_cloud_by_name_or_id_for_provisioning(nil, cloud_id)
        return 1 if cloud.nil?
        cloud_id = cloud['id']
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
          print_green_success "Role #{role['authority']} access updated for cloud #{cloud['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_instance_type_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_instance_type_access(args)
  end

  def update_default_instance_type_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update default instance type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
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
        print_green_success "Role #{role['authority']} default instance type access updated"
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
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [type] [access]")
      opts.on( '--instance-type INSTANCE_TYPE', String, "Instance Type name" ) do |val|
        instance_type_name = val
      end
      opts.on( nil, '--all', "Update all instance types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for an instance type or all instance types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--instance-type or --all is required. This is the name of an instance type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [role] [instance-type] [access]
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

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
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
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_blueprint_access(args)
  end

  def update_default_blueprint_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update default blueprint access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
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
        print_green_success "Role #{role['authority']} default blueprint access updated"
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
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [blueprint] [access]")
      opts.on( '--blueprint ID', String, "Blueprint ID or Name" ) do |val|
        blueprint_id = val
      end
      opts.on( nil, '--all', "Update all blueprints at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a blueprint or all blueprints.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--blueprint or --all is required. This is the name or id of a blueprint.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-blueprint-access [role] [access] --all
    #        update-blueprint-access [role] [blueprint] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      blueprint_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !blueprint_id && !do_all
      raise_command_error("missing required argument: [blueprint] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      blueprint_global_access = role_json['globalAppTemplateAccess'] || role_json['globalBlueprintAccess']
      blueprint_permissions = role_json['appTemplatePermissions'] || role_json['blueprintPermissions'] || []

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

  def update_global_catalog_item_type_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_catalog_item_type_access(args)
  end

  def update_default_catalog_item_type_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update default catalog item type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'CatalogItemType', access: access_value}
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
        print_green_success "Role #{role['authority']} default catalog item type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_catalog_item_type_access(args)
    options = {}
    catalog_item_type_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [catalog-item-type] [access]")
      opts.on( '--catalog-item-type ID', String, "Catalog Item Type ID or Name" ) do |val|
        catalog_item_type_id = val
      end
      opts.on( nil, '--all', "Update all catalog item types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a catalog item type or all types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--catalog-item-type or --all is required. This is the name or id of a catalog item type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-catalog_item_type-access [role] [access] --all
    #        update-catalog_item_type-access [role] [catalog-item-type] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      catalog_item_type_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !catalog_item_type_id && !do_all
      raise_command_error("missing required argument: [catalog-item-type] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      catalog_item_type_global_access = role_json['globalCatalogItemTypeAccess']
      catalog_item_type_permissions = role_json['catalogItemTypePermissions'] || role_json['catalogItemTypes'] []

      # hacky, but support name or code lookup via the list returned in the show payload
      catalog_item_type = nil
      if !do_all
        if catalog_item_type_id.to_s =~ /\A\d{1,}\Z/
          catalog_item_type = catalog_item_type_permissions.find {|b| b['id'] == catalog_item_type_id.to_i }
        else
          catalog_item_type = catalog_item_type_permissions.find {|b| b['name'] == catalog_item_type_id }
        end
        if catalog_item_type.nil?
          print_red_alert "Catalog Item Type not found: '#{catalog_item_type_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allCatalogItemTypes'] = true
      else
        params['catalogItemTypeId'] = catalog_item_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_catalog_item_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_catalog_item_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all catalog item types"
        else
          print_green_success "Role #{role['authority']} access updated for catalog item type #{catalog_item_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_default_persona_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default persona access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
      EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'Persona', access: access_value}
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
        print_green_success "Role #{role['authority']} default persona access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_persona_access(args)
    options = {}
    persona_id = nil
    name = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [persona] [access]")
      opts.on( '--persona CODE', String, "Persona Code" ) do |val|
        persona_id = val
      end
      opts.on( nil, '--all', "Update all personas at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a persona or all personas.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--persona or --all is required. This is the code of a persona. Service Catalog, Standard, or Virtual Desktop\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-persona-access [role] [access] --all
    #        update-persona-access [role] [persona] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      persona_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !persona_id && !do_all
      raise_command_error("missing required argument: [persona] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      
      # no lookup right now, pass the code serviceCatalog|standard
      persona_code = persona_id

      params = {}
      if do_all
        params['allPersonas'] = true
      else
        params['personaCode'] = persona_code
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_persona(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_persona(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all personas"
        else
          print_green_success "Role #{role['authority']} access updated for persona #{persona_code}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_vdi_pool_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_vdi_pool_access(args)
  end

  def update_default_vdi_pool_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update default VDI pool access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      # note: VdiPools being plural is odd, the others are singular
      params = {permissionCode: 'VdiPools', access: access_value}
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
        print_green_success "Role #{role['authority']} default vdi pool access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_vdi_pool_access(args)
    options = {}
    vdi_pool_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [vdi-pool] [access]")
      opts.on( '--vdi-pool ID', String, "VDI Pool ID or Name" ) do |val|
        vdi_pool_id = val
      end
      opts.on( nil, '--all', "Update all VDI pools at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a VDI pool or all VDI pools.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--vdi-pool or --all is required. This is the name or id of a VDI pool.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      vdi_pool_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !vdi_pool_id && !do_all
      raise_command_error("missing required argument: [vdi-pool] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      vdi_pool_global_access = role_json['globalVdiPoolAccess']
      vdi_pool_permissions = role_json['vdiPoolPermissions'] || role_json['vdiPools'] || []

      # hacky, but support name or code lookup via the list returned in the show payload
      vdi_pool = nil
      if !do_all
        if vdi_pool_id.to_s =~ /\A\d{1,}\Z/
          vdi_pool = vdi_pool_permissions.find {|b| b['id'] == vdi_pool_id.to_i }
        else
          vdi_pool = vdi_pool_permissions.find {|b| b['name'] == vdi_pool_id }
        end
        if vdi_pool.nil?
          print_red_alert "VDI Pool not found: '#{vdi_pool_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allVdiPools'] = true
      else
        params['vdiPoolId'] = vdi_pool['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_vdi_pool(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_vdi_pool(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all VDI pools"
        else
          print_green_success "Role #{role['authority']} access updated for VDI pool #{vdi_pool['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_report_type_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_report_type_access(args)
  end

  def update_default_report_type_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default report type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full or none.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      # note: ReportTypes being plural is odd, the others are singular
      params = {permissionCode: 'ReportTypes', access: access_value}
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
        print_green_success "Role #{role['authority']} default report type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_report_type_access(args)
    options = {}
    report_type_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [report-type] [access]")
      opts.on( '--report-type ID', String, "Report Type ID or Name" ) do |val|
        report_type_id = val
      end
      opts.on( nil, '--all', "Update all report types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a report type or all report types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--report-type or --all is required. This is the name or id of a report type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-report-type-access [role] [access] --all
    #        update-report-type-access [role] [report-type] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      report_type_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !report_type_id && !do_all
      raise_command_error("missing required argument: [report-type] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      report_type_global_access = role_json['globalReportTypeAccess']
      report_type_permissions = role_json['reportTypePermissions'] || role_json['reportTypes'] || []

      # hacky, but support name or code lookup via the list returned in the show payload
      report_type = nil
      if !do_all
        if report_type_id.to_s =~ /\A\d{1,}\Z/
          report_type = report_type_permissions.find {|b| b['id'] == report_type_id.to_i }
        else
          report_type = report_type_permissions.find {|b| b['name'] == report_type_id }
        end
        if report_type.nil?
          print_red_alert "Report Type not found: '#{report_type_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allReportTypes'] = true
      else
        params['reportTypeId'] = report_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_report_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_report_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all report types"
        else
          print_green_success "Role #{role['authority']} access updated for report type #{report_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_task_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_task_access(args)
  end

  def update_default_task_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default task access for a role.
[role] is required. This is the id of a role.
[access] is required. This is the access level to assign: full or none.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      # note: ReportTypes being plural is odd, the others are singular
      params = {permissionCode: 'Task', access: access_value}
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
        print_green_success "Role #{role['authority']} default task access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_task_access(args)
    options = {}
    task_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [task] [access]")
      opts.on( '--task ID', String, "Task ID, code or name" ) do |val|
        report_type_id = val
      end
      opts.on( nil, '--all', "Update all tasks at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a task or all tasks.\n" +
        "[role] is required. This is the name, code or id of a task.\n" +
        "--task or --all is required. This is the name, code or id of a task.\n" +
        "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      task_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !task_id && !do_all
      raise_command_error("missing required argument: [task] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      task_permissions = role_json['taskPermissions'] || role_json['tasks'] || []

      # hacky, but support name or code lookup via the list returned in the show payload
      task = nil
      if !do_all
        if task_id.to_s =~ /\A\d{1,}\Z/
          task = task_permissions.find {|b| b['id'] == task_id.to_i }
        else
          task = task_permissions.find {|b| b['name'] == task_id || b['code'] == task_id }
        end
        if task.nil?
          print_red_alert "Task not found: '#{task_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allTasks'] = true
      else
        params['taskId'] = task['id']
      end
      params['access'] = access_value == 'default' ? nil : access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_task(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_task(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all tasks"
        else
          print_green_success "Role #{role['authority']} access updated for task #{task['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_workflow_access(args)
    puts "#{yellow}DEPRECATED#{reset}"
    update_default_workflow_access(args)
  end

  def update_default_workflow_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default workflow access for a role.
[role] is required. This is the id of a role.
[access] is required. This is the access level to assign: full or none.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      params = {permissionCode: 'TaskSet', access: access_value}
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
        print_green_success "Role #{role['authority']} default workflow access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_workflow_access(args)
    options = {}
    workflow_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [workflow] [access]")
      opts.on( '--workflow ID', String, "Workflow ID, code or Name" ) do |val|
        workflow_id = val
      end
      opts.on( nil, '--all', "Update all workflows at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a workflow or all workflows.\n" +
        "[role] is required. This is the name or id of a role.\n" +
        "--workflow or --all is required. This is the name, code or id of a workflow.\n" +
        "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      workflow_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !workflow_id && !do_all
      raise_command_error("missing required argument: [workflow] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      workflow_permissions = role_json['taskSetPermissions'] || role_json['taskSets'] || []

      # hacky, but support name or code lookup via the list returned in the show payload
      workflow = nil
      if !do_all
        if workflow_id.to_s =~ /\A\d{1,}\Z/
          workflow = workflow_permissions.find {|b| b['id'] == workflow_id.to_i }
        else
          workflow = workflow_permissions.find {|b| b['name'] == workflow_id }
        end
        if workflow.nil?
          print_red_alert "Workflow not found: '#{workflow_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allTaskSets'] = true
      else
        params['taskSetId'] = workflow['id']
      end
      params['access'] = access_value == 'default' ? nil : access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_task_set(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_task_set(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all workflows"
        else
          print_green_success "Role #{role['authority']} access updated for workflow #{workflow['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_default_cluster_type_access(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [access]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update default cluster type access for a role.
[role] is required. This is the id of a role.
[access] is required. This is the access level to assign: full or none.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'none', 'custom'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      params = {permissionCode: 'ServerGroupType', access: access_value}
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
        print_green_success "Role #{role['authority']} default cluster type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_cluster_type_access(args)
    options = {}
    cluster_type_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none', 'default']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [cluster-type] [access]")
      opts.on( '--cluster-type ID', String, "Cluster Type ID, code or Name" ) do |val|
        cluster_type_id = val
      end
      opts.on( nil, '--all', "Update all cluster types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a cluster type or all cluster types.\n" +
        "[role] is required. This is the name or id of a role.\n" +
        "--cluster-type or --all is required. This is the name, code or id of a cluster type.\n" +
        "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      cluster_type_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !cluster_type_id && !do_all
      raise_command_error("missing required argument: [cluster-type] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'], {'includeDefaultAccess' => true})
      cluster_type_permissions = role_json['clusterTypePermissions'] || role_json['clusterTypes'] || []

      # hacky, but support name or code lookup via the list returned in the show payload
      cluster_type = nil
      if !do_all
        if cluster_type_id.to_s =~ /\A\d{1,}\Z/
          cluster_type = cluster_type_permissions.find {|b| b['id'] == cluster_type_id.to_i }
        else
          cluster_type = cluster_type_permissions.find {|b| b['name'] == cluster_type_id }
        end
        if cluster_type.nil?
          print_red_alert "Cluster Type not found: '#{cluster_type_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allClusterTypes'] = true
      else
        params['clusterTypeId'] = cluster_type['id']
      end
      params['access'] = access_value == 'default' ? nil : access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_cluster_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_cluster_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all cluster types"
        else
          print_green_success "Role #{role['authority']} access updated for cluster type #{cluster_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  
  def add_role_option_types
    [
      {'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'landingUrl', 'fieldLabel' => 'Landing URL', 'type' => 'text', 'description' => 'An optional override for the default landing page after login for a user.'},
      {'fieldName' => 'roleType', 'fieldLabel' => 'Role Type', 'type' => 'select', 'selectOptions' => [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}], 'defaultValue' => 'user'},
      {'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text'},
      {'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use'},
      {'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it.'},
      {'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'selectOptions' => get_persona_select_options(), 'description' => 'Default Persona'}
    ]
  end

  def update_role_option_types
    add_role_option_types.reject {|it| ['roleType', 'baseRole'].include?(it['fieldName']) }
  end

  def role_type_options
    [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}]
  end

  def get_persona_select_options
    [
      {'name'=>'Service Catalog','value'=>'serviceCatalog'},
      {'name'=>'Standard','value'=>'standard'},
      {'name'=>'Virtual Desktop','value'=>'vdi'}
    ]
  end

  def role_owner_options
    @options_interface.options_for_source("tenants", {})['data']
  end

  def base_role_options(role_payload)
    params = {"tenantId" => role_payload['owner'], "roleType" => role_payload['roleType'] }
    @options_interface.options_for_source("copyFromRole", params)['data']
  end


  def parse_access_csv(output, val)
    output ||= {}
    val.split(",").each do |value_pair|
      # split on '=' only because ':' is included in the permission name
      k,v = value_pair.include?("=") ? value_pair.strip.split("=") : [value_pair, ""]
      next if k.to_s.empty?
      k = k.to_s.strip
      v = v.to_s.strip
      if k.empty?
        # ignore blank values, extra comma maybe?
        next
      end
      if v == ""
        raise_command_error "permission '#{k}=#{v}' is invalid. The access value is required eg. [default|none|read|full]"
      end
      output[k] = v
    end
    return output
  end

  # role permission access options shared by add and update
  def build_role_access_options(opts, options, params)
    opts.on('--permissions CODE=ACCESS', String, "Set feature permission access by permission code. Example: dashboard=read,operations-wiki=full" ) do |val|
      options[:permissions] ||= {}
      parse_access_csv(options[:permissions], val)
    end
    opts.add_hidden_option('--permissions')
    opts.on('--feature-access CODE=ACCESS', String, "Set feature permission access by permission code. Example: dashboard=read,operations-wiki=full" ) do |val|
      options[:permissions] ||= {}
      parse_access_csv(options[:permissions], val)
    end
    opts.on('--global-group-access ACCESS', String, "Update the global group (site) access: [none|read|full]" ) do |val|
      params['globalSiteAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-group-access')
    opts.on('--default-group-access ACCESS', String, "Update the default group (site) access: [none|read|full]" ) do |val|
      params['globalSiteAccess'] = val.to_s.downcase
    end
    opts.on('--groups ID=ACCESS', String, "Set group (site) to a custom access by group id. Example: 1=none,2=full,3=read" ) do |val|
      options[:group_permissions] ||= {}
      parse_access_csv(options[:group_permissions], val)
    end
    opts.on('--global-cloud-access ACCESS', String, "Update the global cloud (zone) access: [none|read|full]" ) do  |val|
      params['globalZoneAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-cloud-access')
    opts.on('--default-cloud-access ACCESS', String, "Update the default cloud (zone) access: [none|read|full]" ) do  |val|
      params['globalZoneAccess'] = val.to_s.downcase
    end
    opts.on('--clouds ID=ACCESS', String, "Set cloud (zone) to a custom access by cloud id. Example: 1=none,2=full,3=read" ) do |val|
      options[:cloud_permissions] ||= {}
      parse_access_csv(options[:cloud_permissions], val)
    end
    opts.on('--global-instance-type-access ACCESS', String, "Update the global instance type access: [none|full]" ) do  |val|
      params['globalInstanceTypeAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-instance-type-access')
    opts.on('--default-instance-type-access ACCESS', String, "Update the default instance type access: [none|full]" ) do  |val|
      params['globalInstanceTypeAccess'] = val.to_s.downcase
    end
    opts.on('--instance-types CODE=ACCESS', String, "Set instance type to a custom access instance type code. Example: nginx=full,apache=none" ) do |val|
      options[:instance_type_permissions] ||= {}
      parse_access_csv(options[:instance_type_permissions], val)
    end
    opts.on('--global-blueprint-access ACCESS', String, "Update the global blueprint access: [none|full]" ) do  |val|
      params['globalAppTemplateAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-blueprint-access')
    opts.on('--default-blueprint-access ACCESS', String, "Update the default blueprint access: [none|full]" ) do  |val|
      params['globalAppTemplateAccess'] = val.to_s.downcase
    end
    opts.on('--blueprints ID=ACCESS', String, "Set blueprint to a custom access by blueprint id. Example: 1=full,2=none" ) do |val|
      options[:blueprint_permissions] ||= {}
      parse_access_csv(options[:blueprint_permissions], val)
    end
    opts.on('--global-catalog-item-type-access ACCESS', String, "Update the global catalog item type access: [none|full]" ) do  |val|
      params['globalCatalogItemTypeAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-catalog-item-type-access')
    opts.on('--default-catalog-item-type-access ACCESS', String, "Update the default catalog item type access: [none|full]" ) do  |val|
      params['globalCatalogItemTypeAccess'] = val.to_s.downcase
    end
    opts.on('--catalog-item-types CODE=ACCESS', String, "Set catalog item type to a custom access by catalog item type id. Example: 1=full,2=none" ) do |val|
      options[:catalog_item_type_permissions] ||= {}
      parse_access_csv(options[:catalog_item_type_permissions], val)
    end
    opts.on('--default-persona-access ACCESS', String, "Update the default persona access: [none|full]" ) do  |val|
      params['globalPersonaAccess'] = val.to_s.downcase
    end
    opts.on('--personas CODE=ACCESS', String, "Set persona to a custom access by persona code. Example: standard=full,serviceCatalog=full,vdi=full" ) do |val|
      options[:persona_permissions] ||= {}
      parse_access_csv(options[:persona_permissions], val)
    end
    opts.on('--global-vdi-pool-access ACCESS', String, "Update the global VDI pool access: [none|full]" ) do  |val|
      params['globalVdiPoolAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-vdi-pool-access')
    opts.on('--default-vdi-pool-access ACCESS', String, "Update the default VDI pool access: [none|full]" ) do  |val|
      params['globalVdiPoolAccess'] = val.to_s.downcase
    end
    opts.on('--vdi-pools ID=ACCESS', String, "Set VDI pool to a custom access by VDI pool id. Example: 1=full,2=none" ) do |val|
      options[:vdi_pool_permissions] ||= {}
      parse_access_csv(options[:vdi_pool_permissions], val)
    end
    opts.on('--global-report-type-access ACCESS', String, "Update the global report type access: [none|full]" ) do  |val|
      params['globalReportTypeAccess'] = val.to_s.downcase
    end
    opts.on('--default-report-type-access ACCESS', String, "Update the default report type access: [none|full]" ) do  |val|
      params['globalReportTypeAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--default-report-type-access')
    opts.on('--report-types CODE=ACCESS', String, "Set report type to a custom access by report type code. Example: appCost=none,guidance=full" ) do |val|
      options[:report_type_permissions] ||= {}
      parse_access_csv(options[:report_type_permissions], val)
    end
    opts.on('--global-task-access ACCESS', String, "Set the global task access: [none|full]" ) do  |val|
      params['globalTaskAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-task-access')
    opts.on('--default-task-access ACCESS', String, "Set the default task access: [none|full]" ) do  |val|
      params['globalTaskAccess'] = val.to_s.downcase
    end
    opts.on('--tasks ID=ACCESS', String, "Set task to a custom access by task id. Example: 1=none,2=full" ) do |val|
      options[:task_permissions] ||= {}
      parse_access_csv(options[:task_permissions], val)
    end
    opts.on('--global-workflow-access ACCESS', String, "Set the default workflow access: [none|full]" ) do  |val|
      params['globalTaskSetAccess'] = val.to_s.downcase
    end
    opts.add_hidden_option('--global-workflow-access')
    opts.on('--default-workflow-access ACCESS', String, "Set the default workflow access: [none|full]" ) do  |val|
      params['globalTaskSetAccess'] = val.to_s.downcase
    end
    opts.on('--workflows ID=ACCESS', String, "Set workflow to a custom access by workflow id. Example: 1=none,2=full" ) do |val|
      options[:workflow_permissions] ||= {}
      parse_access_csv(options[:workflow_permissions], val)
    end
    opts.on('--default-cluster-type-access ACCESS', String, "Set the default cluster type access: [none|full]" ) do  |val|
      params['globalTaskSetAccess'] = val.to_s.downcase
    end
    opts.on('--cluster-types CODE=ACCESS', String, "Set cluster type to a custom access by cluster type code. Example: kubernetes-cluster=none,mvm-cluster=full" ) do |val|
      options[:cluster_type_permissions] ||= {}
      parse_access_csv(options[:cluster_type_permissions], val)
    end
    opts.on('--reset-permissions', "Reset all feature permission access to none. This can be used in conjunction with --permissions to recreate the feature permission access for the role." ) do
      options[:reset_permissions] = true
    end
    opts.add_hidden_option('--reset-permissions')
    opts.on('--reset-feature-access', "Reset all feature permission access to none. This can be used in conjunction with --feature-access to recreate the feature permission access for the role." ) do
      options[:reset_permissions] = true
    end
    opts.on('--reset-all-access', "Reset all access to none including permissions, global groups, instance types, etc. This can be used in conjunction with --feature-access to recreate the feature permission access for the role." ) do
      options[:reset_all_access] = true
    end
  end

  # parse bulk permissions payload
  def parse_role_access_options(options, params)
    if options[:permissions]
      perms_array = []
      options[:permissions].each do |k,v|
        perm_code = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        perms_array << {"code" => perm_code, "access" => access_value}
      end
      params['permissions'] = perms_array
    end
    if options[:group_permissions]
      perms_array = []
      options[:group_permissions].each do |k,v|
        site_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if site_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => site_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => site_id, "access" => access_value}
        end
      end
      params['sites'] = perms_array
    end
    if options[:cloud_permissions]
      perms_array = []
      options[:cloud_permissions].each do |k,v|
        zone_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if zone_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => zone_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => zone_id, "access" => access_value}
        end
      end
      params['zones'] = perms_array
    end
    if options[:instance_type_permissions]
      perms_array = []
      options[:instance_type_permissions].each do |k,v|
        instance_type_code = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if instance_type_code =~ /\A\d{1,}\Z/
          perms_array << {"id" => instance_type_code.to_i, "access" => access_value}
        else
          perms_array << {"code" => instance_type_code, "access" => access_value}
        end
      end
      params['instanceTypes'] = perms_array
    end
    if options[:blueprint_permissions]
      perms_array = []
      options[:blueprint_permissions].each do |k,v|
        blueprint_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if blueprint_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => blueprint_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => blueprint_id, "access" => access_value}
        end
      end
      params['appTemplates'] = perms_array
    end
    if options[:catalog_item_type_permissions]
      perms_array = []
      options[:catalog_item_type_permissions].each do |k,v|
        catalog_item_type_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if catalog_item_type_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => catalog_item_type_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => catalog_item_type_id, "access" => access_value}
        end
      end
      params['catalogItemTypes'] = perms_array

    end
    if options[:persona_permissions]
      perms_array = []
      options[:persona_permissions].each do |k,v|
        persona_code = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        perms_array << {"code" => persona_code, "access" => access_value}
      end
      params['personas'] = perms_array
    end
    if options[:vdi_pool_permissions]
      perms_array = []
      options[:vdi_pool_permissions].each do |k,v|
        vdi_pool_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if vdi_pool_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => vdi_pool_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => vdi_pool_id, "access" => access_value}
        end
      end
      params['vdiPools'] = perms_array
    end
    if options[:report_type_permissions]
      perms_array = []
      options[:report_type_permissions].each do |k,v|
        report_type_code = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if report_type_code =~ /\A\d{1,}\Z/
          perms_array << {"id" => report_type_code.to_i, "access" => access_value}
        else
          perms_array << {"code" => report_type_code, "access" => access_value}
        end
      end
      params['reportTypes'] = perms_array
    end
    if options[:task_permissions]
      perms_array = []
      options[:task_permissions].each do |k,v|
        task_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if task_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => task_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => task_id, "access" => access_value}
        end
      end
      params['tasks'] = perms_array
    end
    if options[:workflow_permissions]
      perms_array = []
      options[:workflow_permissions].each do |k,v|
        workflow_id = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if workflow_id =~ /\A\d{1,}\Z/
          perms_array << {"id" => workflow_id.to_i, "access" => access_value}
        else
          perms_array << {"name" => workflow_id, "access" => access_value}
        end
      end
      params['taskSets'] = perms_array
    end
    if options[:cluster_type_permissions]
      perms_array = []
      options[:cluster_type_permissions].each do |k,v|
        cluster_type_code = k
        access_value = v.to_s.empty? ? "none" : v.to_s
        if cluster_type_code =~ /\A\d{1,}\Z/
          perms_array << {"id" => cluster_type_code.to_i, "access" => access_value}
        else
          perms_array << {"code" => cluster_type_code, "access" => access_value}
        end
      end
      params['clusterTypes'] = perms_array
    end
    if options[:reset_permissions]
      params["resetPermissions"] = true
    end
    if options[:reset_all_access]
      params["resetAllAccess"] = true
    end
  end

end
