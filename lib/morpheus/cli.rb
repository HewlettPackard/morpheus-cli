require "morpheus/cli/version"
require 'morpheus/cli/command_error'
require "morpheus/rest_client"
require 'morpheus/formatters'
require 'morpheus/logging'
require 'term/ansicolor'

Dir[File.dirname(__FILE__)  + "/ext/*.rb"].each {|file| require file }

module Morpheus
  module Cli
  
    # the home directory, where morpheus-cli stores things
    def self.home_directory=(fn)
      @@home_directory = fn
    end

    def self.home_directory
      if @@home_directory
        @@home_directory
      elsif ENV['MORPHEUS_CLI_HOME']
        @@home_directory = ENV['MORPHEUS_CLI_HOME']
      else
        @@home_directory = File.join(Dir.home, ".morpheus")
      end
    end

    # load all the well known commands and utilties they need
    def self.load!()
      # load interfaces
      require 'morpheus/api/api_client.rb'
      Dir[File.dirname(__FILE__)  + "/api/*.rb"].each {|file| load file }

      # load mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/*.rb"].each {|file| load file }

      # load commands
      # Dir[File.dirname(__FILE__)  + "/cli/*.rb"].each {|file| load file }

      # utilites
      require 'morpheus/cli/cli_registry.rb'
      require 'morpheus/cli/dot_file.rb'
      require 'morpheus/cli/command_error'

      load 'morpheus/cli/cli_command.rb'
      load 'morpheus/cli/option_types.rb'
      load 'morpheus/cli/credentials.rb'
      
      # shell scripting commands
      load 'morpheus/cli/source_command.rb'
      load 'morpheus/cli/echo_command.rb'
      load 'morpheus/cli/coloring_command.rb'
      load 'morpheus/cli/log_level_command.rb'
      load 'morpheus/cli/ssl_verification_command.rb'

      # all the known commands
      load 'morpheus/cli/remote.rb'
      load 'morpheus/cli/login.rb'
      load 'morpheus/cli/logout.rb'
      load 'morpheus/cli/whoami.rb'
      load 'morpheus/cli/dashboard_command.rb'
      load 'morpheus/cli/recent_activity_command.rb'
      load 'morpheus/cli/groups.rb'
      load 'morpheus/cli/clouds.rb'
      load 'morpheus/cli/hosts.rb'
      load 'morpheus/cli/load_balancers.rb'
      load 'morpheus/cli/shell.rb'
      load 'morpheus/cli/tasks.rb'
      load 'morpheus/cli/workflows.rb'
      load 'morpheus/cli/deployments.rb'
      load 'morpheus/cli/instances.rb'
      load 'morpheus/cli/containers_command.rb'
      load 'morpheus/cli/apps.rb'
      load 'morpheus/cli/app_templates.rb'
      load 'morpheus/cli/deploys.rb'
      load 'morpheus/cli/license.rb'
      load 'morpheus/cli/instance_types.rb'
      load 'morpheus/cli/security_groups.rb'
      load 'morpheus/cli/security_group_rules.rb'
      load 'morpheus/cli/accounts.rb'
      load 'morpheus/cli/users.rb'
      load 'morpheus/cli/roles.rb'
      load 'morpheus/cli/key_pairs.rb'
      load 'morpheus/cli/virtual_images.rb'
      load 'morpheus/cli/library.rb'
      load 'morpheus/cli/version_command.rb'
      load 'morpheus/cli/alias_command.rb'
      # todo: combine checks, incidents, apps, and goups under monitoring?
      # `monitoring apps|groups` still needed, 
      # maybe they should go under the apps and groups commands instead?
      # load 'morpheus/cli/monitoring_command.rb'
      load 'morpheus/cli/monitoring_incidents_command.rb'
      load 'morpheus/cli/monitoring_checks_command.rb'
      load 'morpheus/cli/monitoring_contacts_command.rb'
      load 'morpheus/cli/monitoring_groups_command.rb'
      load 'morpheus/cli/monitoring_apps_command.rb'
      load 'morpheus/cli/policies_command.rb'
      load 'morpheus/cli/networks_command.rb'
      load 'morpheus/cli/network_groups_command.rb'
      load 'morpheus/cli/network_pools_command.rb'
      load 'morpheus/cli/network_services_command.rb'
      load 'morpheus/cli/network_pool_servers_command.rb'
      load 'morpheus/cli/network_domains_command.rb'
      load 'morpheus/cli/network_proxies_command.rb'
      # nice to have commands
      load 'morpheus/cli/curl_command.rb'
      load 'morpheus/cli/set_prompt_command.rb'
      load 'morpheus/cli/man_command.rb' # please implement me


      # Your new commands go here...

    end

    load!
    
  end

end
