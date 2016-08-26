require "morpheus/cli/version"
require "morpheus/rest_client"
require 'morpheus/formatters'
require 'term/ansicolor'

module Morpheus
  module Cli
  	require 'morpheus/api/api_client'
    require 'morpheus/api/options_interface'
  	require 'morpheus/api/groups_interface'
  	require 'morpheus/api/clouds_interface'
  	require 'morpheus/api/servers_interface'
    require 'morpheus/api/tasks_interface'
    require 'morpheus/api/task_sets_interface'
  	require 'morpheus/api/instances_interface'
    require 'morpheus/api/instance_types_interface'
    require 'morpheus/api/provision_types_interface'
    require 'morpheus/api/apps_interface'
    require 'morpheus/api/deploy_interface'
    require 'morpheus/api/security_groups_interface'
    require 'morpheus/api/security_group_rules_interface'
    require 'morpheus/api/accounts_interface'
    require 'morpheus/api/users_interface'
    require 'morpheus/api/roles_interface'
  	
    require 'morpheus/cli/credentials'
  	require 'morpheus/cli/error_handler'
  	require 'morpheus/cli/remote'
  	require 'morpheus/cli/groups'
  	require 'morpheus/cli/clouds'
  	require 'morpheus/cli/hosts'
    require 'morpheus/cli/tasks'
    require 'morpheus/cli/workflows'
    require 'morpheus/cli/instances'
    require 'morpheus/cli/apps'
    require 'morpheus/cli/deploys'
    require 'morpheus/cli/instance_types'
    require 'morpheus/cli/security_groups'
    require 'morpheus/cli/security_group_rules'
    require 'morpheus/cli/accounts'
    require 'morpheus/cli/users'
    require 'morpheus/cli/roles'
    # Your code goes here...
  end
end
