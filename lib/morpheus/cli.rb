require "morpheus/cli/version"
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
      # Your new commands goes here...

    end

    load!
    
  end

end
