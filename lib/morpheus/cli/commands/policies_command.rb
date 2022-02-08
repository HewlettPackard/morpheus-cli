require 'morpheus/cli/cli_command'

class Morpheus::Cli::PoliciesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::AccountsHelper

  set_command_name :policies

  register_subcommands :list, :get, :add, :update, :remove #, :generate_pool
  register_subcommands :'list-types' => :list_types
  register_subcommands :'get-type' => :get_type
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @policies_interface = @api_client.policies
    @group_policies_interface = @api_client.group_policies
    @cloud_policies_interface = @api_client.cloud_policies
    @clouds_interface = @api_client.clouds
    @groups_interface = @api_client.groups
    @account_users_interface = @api_client.account_users
    @roles_interface = @api_client.roles
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-u', '--user USER', "Username or ID" ) do |val|
        options[:user] = val
      end
      opts.on( '--role ROLE', String, "Role Authority or ID" ) do |val|
        options[:role] = val
      end
      opts.on( '-G', '--global', "Global policies only" ) do
        params[:global] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List policies."
    end
    optparse.parse!(args)
    connect(options)
    begin
      group, cloud, user = nil, nil, nil
      if options[:group]
        group = find_group_by_name_or_id(options[:group])
      elsif options[:cloud]
        cloud = find_cloud_by_name_or_id(options[:cloud])
      elsif options[:user]
        user = find_user_by_username_or_id(nil, options[:user])
        return 1 if user.nil?
      elsif options[:role]
        role = find_role_by_name_or_id(nil, options[:role])
        return 1 if role.nil?
      end
      params.merge!(parse_list_options(options))
      if user
        params['refType'] = 'User'
        params['refId'] = user['id']
      end
      if role
        params['refType'] = 'Role'
        params['refId'] = role['id']
      end
      @policies_interface.setopts(options)
      @group_policies_interface.setopts(options)
      @cloud_policies_interface.setopts(options)
      if options[:dry_run]
        if group
          print_dry_run @group_policies_interface.dry.list(group['id'], params)
        elsif cloud
          print_dry_run @cloud_policies_interface.dry.list(cloud['id'], params)
        else
          print_dry_run @policies_interface.dry.list(params)
        end
        return 0
      end
      json_response = nil
      if group
        json_response = @group_policies_interface.list(group['id'], params)
      elsif cloud
        json_response = @cloud_policies_interface.list(cloud['id'], params)
      else
        json_response = @policies_interface.list(params)
      end
      policies = json_response["policies"]
      if options[:json]
        puts as_json(json_response, options, "policies")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "policies")
        return 0
      elsif options[:csv]
        puts records_as_csv(policies, options)
        return 0
      end
      title = "Morpheus Policies"
      subtitles = []
      if group
        subtitles << "Group: #{group['name']}".strip
      end
      if cloud
        subtitles << "Cloud: #{cloud['name']}".strip
      end
      if user
        subtitles << "User: #{user['username']}".strip
      end
      if role
        subtitles << "Role: #{role['authority']}".strip
      end
      if params[:global]
        subtitles << "(Global)".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if policies.empty?
        print cyan,"No policies found.",reset,"\n"
      else
        rows = policies.collect {|policy|
          # we got a policy.site and policy.zone now!
          # ref_type, ref_id = policy['refType'], policy['refId']
          # ref_str = ""
          # if ref_type == 'ComputeZone'
          #   ref_str = "Cloud #{ref_id}"
          # elsif ref_type == 'ComputeSite'
          #   ref_str = "Group #{ref_id}"
          # end
          config_str = JSON.generate(policy['config'] || {})
          row = {
            id: policy['id'],
            name: policy['name'], # always blank right now?
            description: policy['description'], # always blank right now?
            type: policy['policyType'] ? policy['policyType']['name'] : '',
            #for: ref_str,
            group: policy['site'] ? policy['site']['name'] : '',
            cloud: policy['zone'] ? policy['zone']['name'] : '',
            user: policy['user'] ? policy['user']['username'] : '',
            role: policy['role'] ? policy['role']['authority'] : '',
            tenants: truncate_string(format_tenants(policy['accounts']), 15),
            config: truncate_string(config_str, 50),
            enabled: policy['enabled'] ? 'Yes' : 'No',
          }
          row
        }
        columns = [:id, :name, :description, :group, :cloud, :user, :role, :tenants, :type, :config, :enabled]
        if group || cloud || user
          columns = columns - [:group, :cloud, :user]
        end
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "policy", :n_label => "policies"})
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
      opts.banner = subcommand_usage("[policy]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      # opts.on( '-u', '--user USER', "Username or ID" ) do |val|
      #   options[:user] = val
      # end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a policy." + "\n" +
                    "[policy] is required. This is the id of a policy."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      group, cloud, user = nil, nil, nil
      if options[:group]
        group = find_group_by_name_or_id(options[:group])
        return 1 if group.nil?
      elsif options[:cloud]
        cloud = find_cloud_by_name_or_id(options[:cloud])
        return 1 if cloud.nil?
      elsif options[:user]
        user = find_user_by_username_or_id(nil, options[:user])
        return 1 if user.nil?
      end
      @policies_interface.setopts(options)
      @group_policies_interface.setopts(options)
      @cloud_policies_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          if group
            print_dry_run @group_policies_interface.dry.get(group['id'], args[0].to_i)
          elsif cloud
            print_dry_run @cloud_policies_interface.dry.get(cloud['id'], args[0].to_i)
          else
            print_dry_run @policies_interface.dry.get(args[0].to_i)
          end
        else
          if group
            print_dry_run @group_policies_interface.dry.list(group['id'], {name:args[0]})
          elsif cloud
            print_dry_run @cloud_policies_interface.dry.list(cloud['id'], {name:args[0]})
          else
            print_dry_run @policies_interface.dry.list({name:args[0]})
          end
        end
        return
      end
      policy = find_policy_by_name_or_id(args[0], {cloud:cloud,group:group})
      return 1 if policy.nil?
      json_response = {'policy' => policy}  # skip redundant request
      # json_response = @policies_interface.get(policy['id'])
      policy = json_response['policy']
      if options[:json]
        puts as_json(json_response, options, "policy")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "policy")
        return 0
      elsif options[:csv]
        puts records_as_csv([policy], options)
        return 0
      end
      print_h1 "Policy Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Type" => lambda {|it| it['policyType'] ? it['policyType']['name'] : '' },
        "Group" => lambda {|it| it['site'] ? it['site']['name'] : '' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "User" => lambda {|it| it['user'] ? it['user']['username'] : '' },
        "Role" => lambda {|it| 
          str = ""
          if it['role']
            str << it['role']['authority']
          end
          str
        },
        "Each User" => lambda {|it| 
          #format_boolean it['eachUser']
          if it['eachUser']
            'Yes, Apply individually to each user in role'
          else
            'No'
          end
        },
        # "All Accounts" => lambda {|it| it['allAccounts'] ? 'Yes' : 'No' },
        # "Ref Type" => 'refType',
        # "Ref ID" => 'refId',
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
        "Tenants" => lambda {|it| format_tenants(policy["accounts"]) },
        "Enabled" => lambda {|it| it['enabled'] ? 'Yes' : 'No' }
      }
      if policy['site'].nil?
        description_cols.delete("Group")
      end
      if policy['zone'].nil?
        description_cols.delete("Cloud")
      end
      if policy['user'].nil?
        description_cols.delete("User")
      end
      if policy['role'].nil?
        description_cols.delete("Role")
        description_cols.delete("Each User")
      end
      print_description_list(description_cols, policy)
      # print reset,"\n"

      print_h2 "Policy Config"
      print cyan
      puts as_json(policy['config'])
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    policy_type_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("-t TYPE")
      opts.on( '-g', '--group GROUP', "Group Name or ID, for scoping the policy to a group." ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID, for scoping the policy to a cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-u', '--user USER', "Username or ID, for scoping the policy to a user" ) do |val|
        options[:user] = val
      end
      opts.on( '--role ROLE', String, "Role Authority or ID, for scoping the policy to a role" ) do |val|
        options[:role] = val
      end
      opts.on('--each-user [on|off]', String, "Apply individually to each user in role, for use with policy scoped by role.") do |val|
        options['eachUser'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      
      opts.on('-t', '--type ID', "Policy Type Name or ID") do |val|
        options['type'] = val
      end
      opts.on('--name VALUE', String, "Name for this policy") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of policy") do |val|
        options['description'] = val
      end
      opts.on('--accounts LIST', Array, "Tenant accounts, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['accounts'] = []
        else
          options['accounts'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        options['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      opts.on('--config JSON', String, "Policy Config JSON") do |val|
        options['config'] = JSON.parse(val.to_s)
      end
      opts.on('--config-yaml YAML', String, "Policy Config YAML") do |val|
        options['config'] = YAML.load(val.to_s)
      end
      opts.on('--config-file FILE', String, "Policy Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new policy." + "\n" +
                    "[name] is optional and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      else
        group, cloud, user, role = nil, nil, nil, nil
        if options[:group]
          group = find_group_by_name_or_id(options[:group])
        elsif options[:cloud]
          cloud = find_cloud_by_name_or_id(options[:cloud])
        elsif options[:user]
          user = find_user_by_username_or_id(nil, options[:user])
          return 1 if user.nil?
        elsif options[:role]
          role = find_role_by_name_or_id(nil, options[:role])
          return 1 if role.nil?
        end

        # merge -O options into normally parsed options
        options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && options[:options].keys.size > 0
        
        # support [name] as first argument
        if args[0]
          options['name'] = args[0]
        end

        # construct payload
        payload = {
          'policy' => {
            'config' => {}
          }
        }
        
        # prompt for policy options

        # Policy Type
        # allow user as id, name or code
        available_policy_types = @policies_interface.list_policy_types({})['policyTypes']
        if available_policy_types.empty?
          print_red_alert "No available policy types found!"
          return 1
        end
        policy_types_dropdown = available_policy_types.collect {|it| {'name' => it['name'], 'value' => it['id']} }
        policy_type_id = nil
        policy_type = nil
        if options['type']
          policy_type_id = options['type']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Policy Type', 'type' => 'select', 'selectOptions' => policy_types_dropdown, 'required' => true, 'description' => 'Choose a policy type.'}], options[:options])
          policy_type_id = v_prompt['type']
        end
        if !policy_type_id.to_s.empty?
          policy_type = available_policy_types.find {|it| 
            it['id'] == policy_type_id.to_i || it['name'] == policy_type_id.to_s || it['code'] == policy_type_id.to_s
          }
        end
        if !policy_type
          print_red_alert "Policy Type not found by id '#{policy_type_id}'"
          return 1
        end
        # payload['policy']['policyTypeId'] = policy_type['id']
        # payload['policy']['policyType'] = {'id' => policy_type['id']}
        payload['policy']['policyType'] = {'code' => policy_type['code']}

        # Scope
        if user
          payload['policy']['refType'] = 'User'
          payload['policy']['refId'] = user['id']
        elsif role
          payload['policy']['refType'] = 'Role'
          payload['policy']['refId'] = role['id']
        end
        
        # Apply To aach user (Role only)
        if payload['policy']['refType'] == 'Role'
          if options['eachUser'] != nil
            payload['policy']['eachUser'] = ['true','on'].include?(options['eachUser'].to_s)
          else
            #ref_apply_dropdown = [{'name' => 'Apply cumulatively to all users in role', 'value' => ''}, {'name' => "Apply individually to each user in role", 'value' => 'user'}]
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'eachUser', 'fieldLabel' => 'Apply individually to each user in role', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'Description' => 'Apply individually to each user in role. The default is to apply cumulatively to all users in the role.'}], options)
            payload['policy']['eachUser'] = ['true','on'].include?(v_prompt['eachUser'].to_s)
          end
        end        

        # Name (this is not even used at the moment!)
        if options['name']
          payload['policy']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'description' => 'Name for this policy.'}], options)
          payload['policy']['name'] = v_prompt['name']
        end

        # Description (this is not even used at the moment!)
        if options['description']
          payload['policy']['description'] = options['description']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description of policy.'}], options)
          payload['policy']['description'] = v_prompt['description']
        end

        # Enabled
        if options['enabled']
          payload['policy']['enabled'] = options['enabled']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'description' => 'Can be used to disable a policy', 'defaultValue' => true}], options)
          payload['policy']['enabled'] = v_prompt['enabled']
        end

        # Tenants
        if options['accounts']
          # payload['policy']['accounts'] = options['accounts'].collect {|it| {'id' => it } }
          payload['policy']['accounts'] = options['accounts']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'accounts', 'fieldLabel' => 'Tenants', 'type' => 'text', 'required' => false, 'description' => 'Tenant accounts, comma separated list of account IDs'}], options)
          payload['policy']['accounts'] = v_prompt['accounts']
        end

        # Config
        if options['config']
          payload['policy']['config'] = options['config']
        elsif options['configFile']
          config_file = File.expand_path(options['configFile'])
          if !File.exists?(config_file) || !File.file?(config_file)
            print_red_alert "File not found: #{config_file}"
            return false
          end
          if config_file =~ /\.ya?ml\Z/
            payload['policy']['config'] = YAML.load_file(config_file)
          else
            payload['policy']['config'] = JSON.parse(File.read(config_file))
          end
        else
          # prompt for policy specific options
          policy_type_option_types = policy_type['optionTypes']
          # puts "POLICY OPTION TYPES:\n #{policy_type_option_types.inspect}"
          if policy_type_option_types
            config_prompt = Morpheus::Cli::OptionTypes.prompt(policy_type_option_types, options, @api_client, {}, false, true, true)
            # everything should be under fieldContext:'config'
            # payload['policy'].deep_merge!(config_prompt)
            if config_prompt['config']
              payload['policy']['config'].deep_merge!(config_prompt['config'])
            end
          else
            puts "No options found for policy type! Proceeding without config options..."
          end
        end
      end

      @policies_interface.setopts(options)
      @group_policies_interface.setopts(options)
      @cloud_policies_interface.setopts(options)
      if options[:dry_run]
        if group
          print_dry_run @group_policies_interface.dry.create(group['id'], payload)
        elsif cloud
          print_dry_run @cloud_policies_interface.dry.create(cloud['id'], payload)
        else
          # global
          print_dry_run @policies_interface.dry.create(payload)
        end
        return
      end
      json_response = nil
      if group
        json_response = @group_policies_interface.create(group['id'], payload)
      elsif cloud
        json_response = @cloud_policies_interface.create(cloud['id'], payload)
      else
        # global
        json_response = @policies_interface.create(payload)
      end
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Added policy"
        # list([])
        policy = json_response['policy']
        get([policy['id']])
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
      opts.banner = subcommand_usage("[policy] [options]")
      # opts.on('-t', '--type ID', "Policy Type Name or ID") do |val|
      #   options['type'] = val
      # end
      opts.on('--name VALUE', String, "Name for this policy") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description of policy") do |val|
        options['description'] = val
      end
      opts.on('--accounts LIST', Array, "Tenant accounts, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['accounts'] = []
        else
          options['accounts'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--each-user [on|off]', String, "Apply individually to each user in role, for use with policy scoped by role.") do |val|
        options['eachUser'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable a policy") do |val|
        options['enabled'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--config JSON', String, "Policy Config JSON") do |val|
        options['config'] = JSON.parse(val.to_s)
      end
      opts.on('--config-yaml YAML', String, "Policy Config YAML") do |val|
        options['config'] = YAML.load(val.to_s)
      end
      opts.on('--config-file FILE', String, "Policy Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a policy." + "\n" +
                    "[policy] is required. This is the id of a policy."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      policy = find_policy_by_name_or_id(args[0])
      return 1 if policy.nil?
      group = policy['site'] || policy['group']
      cloud = policy['zone'] || policy['cloud']

      payload = {
        'policy' => {}
      }

      # no prompting, just collect all user passed options
      params = {}
      params.deep_merge!(options.reject {|k,v| k.is_a?(Symbol) })
      params.deep_merge!(options[:options]) if options[:options]

      if params.empty?
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "Specify at least one option to update\n#{optparse}"
        return 1
      end
      payload['policy'].deep_merge!(params)


      # Config
      if options['config']
        payload['policy']['config'] = options['config']
      elsif options['configFile']
        config_file = File.expand_path(options['configFile'])
        if !File.exists?(config_file) || !File.file?(config_file)
          print_red_alert "File not found: #{config_file}"
          return false
        end
        if config_file =~ /\.ya?ml\Z/
          payload['policy']['config'] = YAML.load_file(config_file)
        else
          payload['policy']['config'] = JSON.parse(File.read(config_file))
        end
      else
        # this allows adding/updating a single config setting.  
        # use --config or --configFile to overwrite the entire config
        if policy['config'] && payload['policy']['config']
          payload['policy']['config'] = policy['config'].merge(payload['policy']['config'])
        end
      end

      # if options[:dry_run]
      #   print_dry_run @policies_interface.dry.update(policy["id"], payload)
      #   return
      # end
      # json_response = @policies_interface.update(policy["id"], payload)
      @policies_interface.setopts(options)
      @group_policies_interface.setopts(options)
      @cloud_policies_interface.setopts(options)
      if options[:dry_run]
        if group
          print_dry_run @group_policies_interface.dry.update(group['id'], policy["id"], payload)
        elsif cloud
          print_dry_run @cloud_policies_interface.dry.update(cloud['id'], policy["id"], payload)
        else
          print_dry_run @policies_interface.dry.update(policy["id"], payload)
        end
        return
      end
      json_response = nil
      if group
        json_response = @group_policies_interface.update(group['id'], policy["id"], payload)
      elsif cloud
        json_response = @cloud_policies_interface.update(cloud['id'], policy["id"], payload)
      else
        json_response = @policies_interface.update(policy["id"], payload)
      end
      if options[:json]
        puts as_json(json_response)
      else
        print_green_success "Updated policy #{policy['id']}"
        get([policy['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[policy]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a policy." + "\n" +
                    "[policy] is required. This is the id of a policy."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      policy = find_policy_by_name_or_id(args[0])
      return 1 if policy.nil?
      group = policy['site'] || policy['group']
      cloud = policy['zone'] || policy['cloud']

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the policy: #{policy['id']}?")
        return 9, "aborted command"
      end
      # if options[:dry_run]
      #   print_dry_run @policies_interface.dry.destroy(policy['id'])
      #   return 0
      # end
      # json_response = @policies_interface.destroy(policy['id'])
      @policies_interface.setopts(options)
      @group_policies_interface.setopts(options)
      @cloud_policies_interface.setopts(options)
      if options[:dry_run]
        if group
          print_dry_run @group_policies_interface.dry.destroy(group['id'], policy["id"])
        elsif cloud
          print_dry_run @cloud_policies_interface.dry.destroy(cloud['id'], policy["id"])
        else
          print_dry_run @policies_interface.dry.destroy(policy["id"])
        end
        return
      end
      json_response = nil
      if group
        json_response = @group_policies_interface.destroy(group['id'], policy["id"])
      elsif cloud
        json_response = @cloud_policies_interface.destroy(cloud['id'], policy["id"])
      else
        json_response = @policies_interface.destroy(policy["id"])
      end
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Deleted policy #{policy['id']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_types(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List policy types."
    end
    optparse.parse!(args)

    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count}\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      @policies_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @policies_interface.dry.list_policy_types(params)
        return 0
      end
      json_response = @policies_interface.list_policy_types()
      policy_types = json_response['policyTypes']
      if options[:json]
        puts as_json(json_response, options, "policyTypes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "policyTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(policy_types, options)
        return 0
      else
        print_h1 "Morpheus Policy Types"
        rows = policy_types.collect {|policy_type| 
          row = {
            id: policy_type['id'],
            name: policy_type['name'],
            code: policy_type['code'],
            description: policy_type['description']
          }
          row
        }
        columns = [:id, :name]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print_results_pagination(json_response, {:label => "policy type", :n_label => "policy types"})
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_type(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[policy-type]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a policy type." + "\n" +
                    "[policy-type] is required. This is ID of a policy type."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      policy_type_id = args[0].to_s
      @policies_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @policies_interface.dry.get_policy_type(policy_type_id, params)
        return 0
      end
      json_response = @policies_interface.get_policy_type(policy_type_id, params)
      policy_type = json_response['policyType']
      if options[:json]
        puts as_json(json_response)
      else
        print_h1 "Policy Type Details"
        print cyan
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          # "Description" => 'description',
          "Code" => 'code',
          "Category" => 'category',
          # "Load Method" => 'loadMethod',
          # "Enforce Method" => 'enforceMethod',
          # "Prepare Method" => 'prepareMethod',
          # "Validate Method" => 'validateMethod',
          "Provision Enforced" => lambda {|it| it['enforceOnProvision'] ? 'Yes' : 'No'  },
          "Managed Enforced" => lambda {|it| it['enforceOnManaged'] ? 'Yes' : 'No'  },
        }
        print_description_list(description_cols, policy_type)
        print reset,"\n"

        # show option types
        print_h2 "Policy Type Options"
        policy_type_option_types = policy_type['optionTypes']
        if !policy_type_option_types || policy_type_option_types.size() == 0
          puts "No options found for policy type"
        else
          rows = policy_type_option_types.collect {|option_type|
            field_str = option_type['fieldName'].to_s
            if !option_type['fieldContext'].to_s.empty?
              field_str = option_type['fieldContext'] + "." + field_str
            end
            description_str = option_type['description'].to_s
            if option_type['helpBlock']
              if description_str.empty?
                description_str = option_type['helpBlock']
              else
                description_str += " " + option_type['helpBlock']
              end
            end
            row = {
              #code: option_type['code'],
              field: field_str,
              type: option_type['type'],
              description: description_str,
              default: option_type['defaultValue'],
              required: option_type['required'] ? 'Yes' : 'No'
            }
            row
          }
          columns = [:field, :type, :description, :default, :required]
          print cyan
          print as_pretty_table(rows, columns)
          print reset,"\n"
        end
        return 0
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    @policies_interface.list_policy_types
  end

  private

  def find_policy_by_name_or_id(val, scope_by={})
    if val.to_s =~ /\A\d{1,}\Z/
      return find_policy_by_id(val, scope_by)
    else
      return find_policy_by_name(val, scope_by)
    end
  end

  def find_policy_by_id(id, scope_by={})
    begin
      group = scope_by[:group]
      cloud = scope_by[:cloud]
      json_response = nil
      if group
        json_response = @group_policies_interface.get(group['id'], id.to_i)
      elsif cloud
        json_response = @cloud_policies_interface.get(cloud['id'], id.to_i)
      else
        json_response = @policies_interface.get(id.to_i)
      end
      return json_response['policy']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Policy not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_policy_by_name(name, scope_by={})
    group = scope_by[:group]
    cloud = scope_by[:cloud]
    json_response = nil
    if group
      json_response = @group_policies_interface.list(group['id'], {name: name.to_s})
    elsif cloud
      json_response = @cloud_policies_interface.list(cloud['id'], {name: name.to_s})
    else
      json_response = @policies_interface.list({name: name.to_s})
    end
    policies = json_response['policies']
    if policies.empty?
      print_red_alert "Policy not found by name #{name}"
      return nil
    elsif policies.size > 1
      print_red_alert "#{policies.size} policies found by name #{name}"
      # print_policies_table(policies, {color: red})
      rows = policies.collect do |policy|
        {id: policy['id'], name: policy['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      policy = policies[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][policy['id']]
        policy['tenants'] = json_response['tenants'][policy['id']]
      end
      return policy
    end
  end

  def find_policy_type_by_id(id)
    begin
      json_response = @policies_interface.get_type(id.to_s)
      return json_response['policyType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Policy Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def format_tenants(accounts)
    if accounts && accounts.size > 0
      accounts = accounts.sort {|a,b| a['name'] <=> b['name'] }.uniq {|it| it['id'] }
      account_ids = accounts.collect {|it| it['id'] }
      account_names = accounts.collect {|it| it['name'] }
      "(#{account_ids.join(',')}) #{account_names.join(',')}"
    else
      ""
    end
  end

end
