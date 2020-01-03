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

  def users_interface
    # @api_client.users
    raise "#{self.class} has not defined @users_interface" if @users_interface.nil?
    @users_interface
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
        print_red_alert "Account not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_account_by_name(name)
    accounts = accounts_interface.list({name: name.to_s})['accounts']
    if accounts.empty?
      print_red_alert "Account not found by name #{name}"
      return nil
    elsif accounts.size > 1
      print_red_alert "#{accounts.size} accounts found by name #{name}"
      print_accounts_table(accounts, {color: red})
      print_red_alert "Try using -A ID instead"
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
      print_red_alert "#{roles.size} roles by name #{name}"
      print_roles_table(roles, {color: red, thin: true})
      print reset,"\n\n"
      return nil
    else
      return roles[0]
    end
  end

  alias_method :find_role_by_authority, :find_role_by_name

  def find_user_by_username_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_user_by_id(account_id, val)
    else
      return find_user_by_username(account_id, val)
    end
  end

  def find_user_by_id(account_id, id)
    begin
      json_response = users_interface.get(account_id, id.to_i)
      return json_response['user']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "User not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_by_username(account_id, username)
    users = users_interface.list(account_id, {username: username.to_s})['users']
    if users.empty?
      print_red_alert "User not found by username #{username}"
      return nil
    elsif users.size > 1
      print_red_alert "#{users.size} users by username #{username}"
      print_users_table(users, {color: red, thin: true})
      print reset,"\n\n"
      return nil
    else
      return users[0]
    end
  end

  def find_all_user_ids(account_id, usernames)
    user_ids = []
    if usernames.is_a?(String)
      usernames = usernames.split(",").collect {|it| it.to_s.strip }.select {|it| it }.uniq
    else
      usernames = usernames.collect {|it| it.to_s.strip }.select {|it| it }.uniq
    end
    usernames.each do |username|
      # save a query
      #user = find_user_by_username_or_id(nil, username)
      if username.to_s =~ /\A\d{1,}\Z/
        user_ids << username.to_i
      else
        user = find_user_by_username(account_id, username)
        if user.nil?
          return nil
        else
          user_ids << user['id']
        end
      end
    end
    user_ids
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
      print_red_alert "#{user_groups.size} user groups found by name #{name}"
      print_user_groups_table(user_groups, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return user_groups[0]
    end
  end

  def print_accounts_table(accounts, options={})
    table_color = options.key?(:color) ? options[:color] : cyan
    rows = accounts.collect do |account|
      status_state = nil
      if account['active']
        status_state = "#{green}ACTIVE#{table_color}"
      else
        status_state = "#{red}INACTIVE#{table_color}"
      end
      {
        id: account['id'],
        name: account['name'],
        description: account['description'],
        role: account['role'] ? account['role']['authority'] : nil,
        status: status_state,
        dateCreated: format_local_dt(account['dateCreated'])
      }
    end
    print table_color if table_color
    print as_pretty_table(rows, [
      :id,
      :name,
      :description,
      :role,
      {:dateCreated => {:display_name => "Date Created"} },
      :status
    ], options.merge({color:table_color}))
    print reset if table_color
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

  def print_roles_table(roles, options={})
    table_color = options.key?(:color) ? options[:color] : cyan
    rows = roles.collect do |role|
      {
        id: role['id'],
        name: role['authority'],
        description: role['description'],
        scope: role['scope'],
        multitenant: role['multitenant'] ? 'Yes' : 'No',
        type: format_role_type(role),
        owner: role['owner'] ? role['owner']['name'] : "System",
        dateCreated: format_local_dt(role['dateCreated'])
      }
    end
    columns = [
      :id,
      :name,
      :description,
      # options[:is_master_account] ? :scope : nil,
      options[:is_master_account] ? :type : nil,
      options[:is_master_account] ? :multitenant : nil,
      options[:is_master_account] ? :owner : nil,
      {:dateCreated => {:display_name => "Date Created"} }
    ].compact
    if options[:include_fields]
      columns = options[:include_fields]
    end
    # print table_color if table_color
    print as_pretty_table(rows, columns, options)
    # print reset if table_color
  end

  def print_users_table(users, options={})
    table_color = options[:color] || cyan
    rows = users.collect do |user|
      {id: user['id'], username: user['username'], name: user['displayName'], first: user['firstName'], last: user['lastName'], email: user['email'], role: format_user_role_names(user), account: user['account'] ? user['account']['name'] : nil}
    end
    columns = [:id, :account, :first, :last, :username, :email, :role]
    if options[:include_fields]
      columns = options[:include_fields] 
    end
    #print table_color if table_color
    print as_pretty_table(rows, columns, options)
    #print reset if table_color
  end

  def format_user_role_names(user)
    role_names = ""
    if user && user['roles']
      roles = user['roles']
      roles = roles.sort {|a,b| a['authority'].to_s.downcase <=> b['authority'].to_s.downcase }
      role_names = roles.collect {|r| r['authority'] }.join(', ')
    end
    role_names
  end

  def get_access_string(val)
    val ||= 'none'
    if val == 'none'
      "#{white}#{val.to_s.capitalize}#{cyan}"
    # elsif val == 'read'
    #   "#{cyan}#{val.to_s.capitalize}#{cyan}"
    else
      "#{green}#{val.to_s.capitalize}#{cyan}"
    end
  end

end
