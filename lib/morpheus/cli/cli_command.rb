require 'morpheus/cli/cli_registry'
require 'morpheus/cli/mixins/print_helper'

module Morpheus
  module Cli
    # Module to be included by every CLI command so that commands get registered
    module CliCommand

      def self.included(klass)
        Morpheus::Cli::CliRegistry.add(klass)
        klass.include Morpheus::Cli::PrintHelper
        klass.extend ClassMethods
      end

      def build_common_options(opts, options, includes=[])
        includes = includes.clone
        while (option_key = includes.shift) do
          case option_key.to_sym

          when :account
            opts.on('-a','--account ACCOUNT', "Account Name") do |val|
              options[:account_name] = val
            end
            opts.on('-A','--account-id ID', "Account ID") do |val|
              options[:account_id] = val
            end

          when :options
            opts.on( '-O', '--option OPTION', "Option" ) do |option|
              custom_option_args = option.split('=')
              custom_options = options[:options] || {}
              option_name_args = custom_option_args[0].split('.')
              if option_name_args.count > 1
                nested_options = custom_options
                option_name_args.each_with_index do |name_element,index|
                  if index < option_name_args.count - 1
                    nested_options[name_element] = nested_options[name_element] || {}
                    nested_options = nested_options[name_element]
                  else
                    nested_options[name_element] = custom_option_args[1]
                  end
                end
              else
                custom_options[custom_option_args[0]] = custom_option_args[1]
              end
              
              options[:options] = custom_options
            end

          when :list
            
            opts.on( '-m', '--max MAX', "Max Results" ) do |max|
              options[:max] = max.to_i
            end

            opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |offset|
              options[:offset] = offset.to_i
            end

            opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
              options[:phrase] = phrase
            end

            opts.on( '-S', '--sort ORDER', "Sort Order" ) do |v|
              options[:sort] = v
            end

            opts.on( '-D', '--desc', "Reverse Sort Order" ) do |v|
              options[:direction] = "desc"
            end

          when :remote
            opts.on( '-r', '--remote REMOTE', "Remote Appliance" ) do |remote|
              options[:remote] = remote
            end

            opts.on( '-U', '--url REMOTE', "API Url" ) do |remote|
              options[:remote_url] = remote
            end

            opts.on( '-u', '--username USERNAME', "Username" ) do |remote|
              options[:remote_username] = remote
            end

            opts.on( '-p', '--password PASSWORD', "Password" ) do |remote|
              options[:remote_password] = remote
            end

            opts.on( '-T', '--token ACCESS_TOKEN', "Access Token" ) do |remote|
              options[:remote_token] = remote
            end
          
          when :auto_confirm
            opts.on( '-y', '--yes', "Auto Confirm" ) do
              options[:yes] = true
            end
          
          when :json
            opts.on('-j','--json', "JSON Output") do |json|
              options[:json] = true
            end
          
          else
            raise "Unknown common_option key: #{option_key}"
          end
        end

        # options that are always included
        opts.on('-C','--nocolor', "ANSI") do
          Term::ANSIColor::coloring = false
        end
        opts.on('-h', '--help', "Prints this help" ) do
          puts opts
          exit
        end

      end
      

      module ClassMethods
        def cli_command_name(cmd_name)
          Morpheus::Cli::CliRegistry.add(self, cmd_name)
        end

        
      end
    end
  end
end
