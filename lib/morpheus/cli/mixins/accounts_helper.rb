require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Provides common methods for fetching and printing accounts, roles, and users.
# The including class must establish @accounts_interface, @roles_interface, @users_interface
module Morpheus::Cli::AccountsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def accounts_interface
    # @api_client.accounts
    raise "#{self.class} has not defined @accounts_interface" if @accounts_interface.nil?
    @accounts_interface
  end

  def account_users_interface
    # @api_client.users
    raise "#{self.class} has not defined @account_users_interface" if @account_users_interface.nil?
    @account_users_interface
  end

  def user_groups_interface
    # @api_client.users
    raise "#{self.class} has not defined @user_groups_interface" if @user_groups_interface.nil?
    @user_groups_interface
  end

  def roles_interface
    # @api_client.roles
    raise "#{self.class} has not defined @roles_interface" if @roles_interface.nil?
    @roles_interface
  end

  ## Tenants (Accounts)

  def account_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      # "Name" => lambda {|it| it['name'].to_s + (it['master'] ? " (Master Tenant)" : '') },
      "Description" => 'description',
      "Subdomain" => 'subdomain',
      "# Instances" => 'stats.instanceCount',
      "# Users" => 'stats.userCount',
      "Role" => lambda {|it| it['role']['authority'] rescue nil },
      "Parent Tenant" => lambda {|it| it['parent']['name'] rescue nil },
      "Master" => lambda {|it| format_boolean(it['master']) },
      "Currency" => 'currency',
      "Status" => lambda {|it| 
        status_state = nil
        if it['active']
          status_state = "#{green}ACTIVE#{cyan}"
        else
          status_state = "#{red}INACTIVE#{cyan}"
        end
        status_state
      },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def list_account_column_definitions()
    columns = account_column_definitions
    columns.delete("Subdomain")
    columns.delete("Master")
    columns.delete("Currency")
    return columns.upcase_keys!
  end


  def find_account_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_account_by_id(val)
    else
      return find_account_by_name(val)
    end
  end

  def find_account_by_id(id)
    begin
      json_response = accounts_interface.get(id.to_i)
      return json_response['account']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Tenant not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_account_by_name(name)
    accounts = accounts_interface.list({name: name.to_s})['accounts']
    if accounts.empty?
      print_red_alert "Tenant not found by name #{name}"
      return nil
    elsif accounts.size > 1
      print_red_alert "Found #{accounts.size} tenants by name '#{name}'. Try using ID instead: #{format_list(accounts.collect {|it| it['id']}, 'or', 3)}"
      print "\n"
      print as_pretty_table(accounts, [:id, :name, :description], {color: red, thin: true})
      print reset,"\n"
      return nil
    else
      return accounts[0]
    end
  end

  def find_account_from_options(options)
    account = nil
    if options[:account]
      account = find_account_by_name_or_id(options[:account])
      exit 1 if account.nil?
    elsif options[:account_name]
      account = find_account_by_name(options[:account_name])
      exit 1 if account.nil?
    elsif options[:account_id]
      account = find_account_by_id(options[:account_id])
      exit 1 if account.nil?
    else
      account = nil # use current account
    end
    return account
  end

  ## Roles

  def role_column_definitions(options={})
    {
      "ID" => 'id',
      "Name" => 'authority',
      "Description" => 'description',
      "Landing URL" => 'landingUrl',
      #"Scope" => lambda {|it| it['scope'] },
      "Type" => lambda {|it| format_role_type(it) },
      "Multitenant" => lambda {|it| 
        format_boolean(it['multitenant']).to_s + (it['multitenantLocked'] ? " (LOCKED)" : "")
      },
      "Default Persona" => lambda {|it| it['defaultPersona'] ? it['defaultPersona']['name'] : '' },
      "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      #"Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def subtenant_role_column_definitions(options={})
    {
      "ID" => 'id',
      "Name" => 'authority',
      "Description" => 'description',
      "Landing URL" => 'landingUrl',
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def find_role_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_role_by_id(account_id, val)
    else
      return find_role_by_name(account_id, val)
    end
  end

  def find_role_by_id(account_id, id)
    begin
      json_response = roles_interface.get(account_id, id.to_i)
      return json_response['role']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Role not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_role_by_name(account_id, name)
    roles = roles_interface.list(account_id, {authority: name.to_s})['roles']
    if roles.empty?
      print_red_alert "Role not found by name #{name}"
      return nil
    elsif roles.size > 1
      print_red_alert "Found #{roles.size} roles by name '#{name}'. Try using ID instead: #{format_list(roles.collect {|it| it['id']}, 'or', 3)}"
      print "\n"
      # print as_pretty_table(accounts, [:id, :name, :description], {color: red, thin: true})
      print as_pretty_table(roles, {"ID" => 'id', "Name" => 'authority',"Description" => 'description'}.upcase_keys!, {color: red, thin: true})
      print reset,"\n"
      return nil
    else
      return roles[0]
    end
  end

  alias_method :find_role_by_authority, :find_role_by_name


  ## Users

  def user_column_definitions(opts={})
    {
      "ID" => 'id',
      "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      "First Name" => 'firstName',
      "Last Name" => 'lastName',
      "Username" => 'username',
      "Email" => 'email',
      "Role" => lambda {|it| format_user_role_names(it) },
      "Notifications" => lambda {|it| it['receiveNotifications'].nil? ? '' : format_boolean(it['receiveNotifications']) },
      "Status" => lambda {|it| format_user_status(it, opts[:color] || cyan) },
      "Last Login" => lambda {|it| format_duration_ago(it['lastLoginDate']) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def list_user_column_definitions(opts={})
    columns = user_column_definitions(opts)
    columns.delete("Notifications")
    return columns.upcase_keys!
  end

  def format_user_status(user, return_color=cyan)
    if user["enabled"] != true
      red + "DISABLED" + return_color
    elsif user["accountLocked"]
      red + "ACCOUNT LOCKED" + return_color
    elsif user["accountExpired"]
      yellow + "ACCOUNT EXPIRED" + return_color
    elsif user["passwordExpired"]
      yellow + "PASSWORD EXPIRED" + return_color
    else
      green + "ACTIVE" + return_color
    end
  end

  def find_user_by_username_or_id(account_id, val, params={})
    if val.to_s =~ /\A\d{1,}\Z/
      return find_user_by_id(account_id, val, params)
    else
      return find_user_by_username(account_id, val, params)
    end
  end

  def find_user_by_id(account_id, id, params={})
    begin
      json_response = account_users_interface.get(account_id, id.to_i, params)
      return json_response['user']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "User not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_by_username(account_id, username, params={})
    users = account_users_interface.list(account_id, params.merge({username: username.to_s}))['users']
    if users.empty?
      print_red_alert "User not found by username #{username}"
      return nil
    elsif users.size > 1
      print_red_alert "Found #{users.size} users by username '#{username}'. Try using ID instead: #{format_list(users.collect {|it| it['id']}, 'or', 3)}"
      print_error "\n"
      print_error as_pretty_table(users, list_user_column_definitions({color: red}), {color: red, thin: true})
      print reset,"\n"
      return nil
    else
      return users[0]
    end
  end

  def find_all_user_ids(account_id, usernames, params={})
    user_ids = []
    if usernames.is_a?(String)
      usernames = usernames.split(",").collect {|it| it.to_s.strip }.select {|it| it }.uniq
    else
      usernames = usernames.collect {|it| it.to_s.strip }.select {|it| it }.uniq
    end
    usernames.each do |username|
      # save a query
      #user = find_user_by_username_or_id(nil, username, params)
      if username.to_s =~ /\A\d{1,}\Z/
        user_ids << username.to_i
      else
        user = find_user_by_username(account_id, username, params)
        if user.nil?
          return nil
        else
          user_ids << user['id']
        end
      end
    end
    user_ids
  end


  ## User Groups

  def user_group_column_definitions()
    {
      "ID" => lambda {|it| it['id'] },
      #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      "Name" => lambda {|it| it['name'] },
      "Description" => lambda {|it| it['description'] },
      "Server Group" => lambda {|it| it['serverGroup'] },
      "Sudo Access" => lambda {|it| format_boolean it['sudoAccess'] },
      # "Shared User" => lambda {|it| format_boolean it['sharedUser'] },
      "# Users" => lambda {|it| it['users'].size rescue nil },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def list_user_group_column_definitions()
    columns = user_group_column_definitions
    columns.delete("Sudo Access")
    columns.delete("Server Group")
    columns.delete("Updated")
    return columns.upcase_keys!
  end

  def find_user_group_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_user_group_by_id(account_id, val)
    else
      return find_user_group_by_name(account_id, val)
    end
  end

  def find_user_group_by_id(account_id, id)
    begin
      json_response = @user_groups_interface.get(account_id, id.to_i)
      return json_response['userGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "User Group not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_group_by_name(account_id, name)
    user_groups = @user_groups_interface.list(account_id, {name: name.to_s})['userGroups']
    if user_groups.empty?
      print_red_alert "User Group not found by name #{name}"
      return nil
    elsif user_groups.size > 1
      print_red_alert "Found #{user_groups.size} user groups by name '#{name}'. Try using ID instead: #{format_list(user_groups.collect {|it| it['id']}, 'or', 3)}"
      print as_pretty_table(user_groups, [:id, :name, :description], {color: red, thin: true})
      print reset,"\n"
      return nil
    else
      return user_groups[0]
    end
  end

  def format_role_type(role)
    str = ""
    if role['roleType'] == "account"
      str = "Account"
    elsif role['roleType'] == "user"
      str = "User"
    else
      if role['scope'] == 'Account'
        str = "Legacy"
      else
        str = "Admin" # System Admin
      end
    end
    # if role['scope'] && role['filterType'] != 'Account'
    #   str = "(System) #{str}"
    # end
    return str
  end

  ## These user access formatted methods should probably move up to PrintHelper to be more ubiquitous.

  def format_user_role_names(user)
    role_names = ""
    if user && user['roles']
      roles = user['roles']
      roles = roles.sort {|a,b| a['authority'].to_s.downcase <=> b['authority'].to_s.downcase }
      role_names = roles.collect {|r| r['authority'] }.join(', ')
    end
    role_names
  end

  def get_access_color(access)
    access ||= 'default'
    if access == 'none'
      # maybe reset instead of white?
      white
    elsif access.include? 'full'
      green
    else
      cyan
    end
  end

  def get_access_string(access, return_color=cyan)
    access ||= 'default'
    get_access_color(access) + access.to_s + return_color.to_s
    # access ||= 'none'
    # if access == 'none'
    #   "#{white}#{access.to_s}#{return_color}"
    # elsif access == 'read'
    #   "#{cyan}#{access.to_s.capitalize}#{return_color}"
    # else
    #   "#{green}#{access.to_s}#{return_color}"
    # end
  end

  # this outputs a string that matches the length of all available access levels
  # for outputting in a grid that looks like this:
  #
  #  none
  #              full
  #              full
  #          user
  #      read
  #              full
  #  none
  #
  # Examples: format_permission_access("read")
  #           format_permission_access("custom", "full,custom,none")
  def format_access_string(access, access_levels=nil, return_color=cyan)
    # nevermind all this, just colorized access level
    return get_access_string(access, return_color)
    
    access = access.to_s.downcase.strip
    if access.empty?
      access = "none"
    end

    if access_levels.nil?
      access_levels = ["none","read","user","full"]
    elsif access_levels.is_a?(Array)
      # access_levels = access_levels
    else
      # parse values like "full,custom,none"
      access_levels = [access_levels].flatten.collect {|it| it.strip.split(",") }.flatten.collect {|it| it.strip }.compact
    end
    # build padded string that contains access eg. 'full' or '    read'
    access_levels_string = access_levels.join(",")
    padded_value = ""
    access_levels.each do |a|
      # handle some unusual access values
      # print custom, and provision where 'user' normally is at index 1
      if (access == "custom" || access == "provision") && a == "user"
        padded_value << access
      else
        if access == a
          padded_value << access
        else
          padded_value << " " * a.size
        end
      end
    end
    # no matching access was found, so just print it in one slot
    if padded_value == ""
      padded_value = " " * access_levels[0].to_s.size
      padded_value << access
    end
    # strip any extra whitespace off the end
    if padded_value.size > access_levels_string.size
      padded_value = padded_value.rstrip
    end
    # ok build out string
    out = ""
    access_color = get_access_color(access || 'default')
    out << access_color if access_color
    out << padded_value
    out << reset if access_color
    out << return_color if return_color
    return out
  end

end
