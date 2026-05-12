require 'morpheus/logging'
require 'morpheus/benchmarking'
require 'morpheus/terminal'
require 'morpheus/cli/cli_registry'
require 'morpheus/cli/option_parser'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/credentials'
#require 'morpheus/cli/commands/shell'
#require 'morpheus/cli/commands/remote'
require 'morpheus/api/api_client'

module Morpheus
  module Cli
    # Module to be included by every CLI command so that commands get registered
    # This mixin defines a print and puts method, and delegates
    # todo: use delegate
    module CliCommand

      def self.included(base)
        base.send :include, Morpheus::Cli::PrintHelper
        base.send :include, Morpheus::Cli::PromptHelper
        base.send :include, Morpheus::Benchmarking::HasBenchmarking
        base.extend ClassMethods
        Morpheus::Cli::CliRegistry.add(base, base.command_name)
      end

      # the beginning of instance variables from optparse !

      # this setting makes it easy for the called to disable prompting
      attr_reader :no_prompt

      # @return [Morpheus::Terminal] the terminal this command is being executed inside of
      def my_terminal
        @my_terminal ||= Morpheus::Terminal.instance
      end

      # set the terminal running this command.
      # @param term [MorpheusTerminal] the terminal this command is assigned to
      # @return the Terminal this command is being executed inside of
      def my_terminal=(term)
        if !term.is_a?(Morpheus::Terminal)
          raise "CliCommand (#{self.class}) my_terminal= expects object of type Terminal and instead got a #{term.class}"
        end
        @my_terminal = term
      end


      # delegate :print, to: :my_terminal
      # delegate :puts, to: :my_terminal
      # or . . . bum  bum bummm
      # a paradigm shift away from include and use module functions instead.
      # module_function :print, puts
      # delegate :puts, to: :my_terminal
      
      def print(*msgs)
        my_terminal.stdout.print(*msgs)
      end

      def println(*msgs)
        print(*msgs)
        print "\n"
      end

      def puts(*msgs)
        my_terminal.stdout.puts(*msgs)
      end

      def print_error(*msgs)
        my_terminal.stderr.print(*msgs)
      end

      def puts_error(*msgs)
        my_terminal.stderr.puts(*msgs)
      end

      # todo: customizable output color, other than cyan.
      # def terminal_fg
      # end
      # def cyan
      #   Term::ANSIColor.black
      # end

      # todo: use terminal.stdin
      # def readline(*msgs)
      #   @my_terminal.stdin.readline(*msgs)
      # end

      # todo: maybe...
      # disabled prompting for this command
      # def noninteractive()
      #   @no_prompt = true
      #   self
      # end

      # whether to prompt or not, this is true by default.
      def interactive?
        @no_prompt != true
      end

      def raise_command_error(msg, args=[], optparse=nil, exit_code=nil)
        raise Morpheus::Cli::CommandError.new(msg, args, optparse, exit_code)
      end

      def raise_args_error(msg, args=[], optparse=nil, exit_code=nil)
        raise Morpheus::Cli::CommandArgumentsError.new(msg, args, optparse, exit_code)
      end

      # parse_id_list splits returns the given id_list with its values split on a comma
      #               your id values cannot contain a comma, atm...
      # @param id_list [String or Array of Strings]
      # @param delim [String] Default is a comma and any surrounding white space.
      # @return array of values
      def parse_id_list(id_list, delim=/\s*\,\s*/)
        [id_list].flatten.collect {|it| it ? it.to_s.split(delim) : nil }.flatten.compact
      end

      def parse_bytes_param(bytes_param, option, assumed_unit = nil, allow_zero = false)
        if bytes_param && ( bytes_param.to_f > 0 || ( allow_zero && bytes_param.to_i == 0 ))
          bytes_param.upcase!
          multiplier = 1
          unit = nil
          number = (bytes_param.to_f == bytes_param.to_i ? bytes_param.to_i : bytes_param.to_f)
          if (bytes_param.end_with? 'GB') || ((!bytes_param.end_with? 'MB') && assumed_unit == 'GB')
            unit = 'GB'
            multiplier = 1024 * 1024 * 1024
          elsif (bytes_param.end_with? 'MB') || assumed_unit == 'MB'
            unit = 'MB'
            multiplier = 1024 * 1024
          end
          return {:bytes_param => bytes_param, :bytes => number * multiplier, :number => number, :multiplier => multiplier, :unit => unit}
        end
        raise_command_error "Invalid value for #{option} option"
      end

      # this returns all the options passed in by -O, parsed all nicely into objects.
      def parse_passed_options(options, parse_opts={})
        excludes = [parse_opts[:exclude], parse_opts[:excludes]].flatten.compact
        passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) || excludes.include?(k) } : {}
        return passed_options
      end

      # Appends Array of OptionType definitions to an OptionParser instance
      # This adds an option like --fieldContext.fieldName="VALUE"
      # @param opts [OptionParser]
      # @param options [Hash] output map that is being constructed
      # @param option_types [Array] list of OptionType definitions to add
      # @return void, this modifies the opts in place.
      def build_option_type_options(opts, options, option_types=[])
        #opts.separator ""
        #opts.separator "Options:"
        options[:options] ||= {} # this is where these go..for now
        options[:option_types] = (options[:option_types] || []) + option_types
        custom_options = options[:options]
        
        # add each one to the OptionParser
        option_types.each do |option_type|
          # skip hidden types
          if option_type['type'] == 'hidden'
            next
          end
          if option_type['fieldName'].empty?
            puts_error "Missing fieldName for option type: #{option_type}" if Morpheus::Logging.debug?
            next
          end
          full_field_name = option_type['fieldContext'].to_s.empty? ? option_type['fieldName'] : "#{option_type['fieldContext']}.#{option_type['fieldName']}"
          field_namespace = full_field_name.split(".")
          field_name = field_namespace.pop

          description = "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}"
          if option_type['description']
            # description << "\n                                     #{option_type['description']}"
            description << " - #{option_type['description']}"
          end
          if option_type['defaultValue']
            description << ". Default: #{option_type['defaultValue']}"
          end
          if option_type['helpBlock']
            description << "\n                                     #{option_type['helpBlock']}"
          end

          # description = option_type['description'].to_s
          # if option_type['defaultValue']
          #   description = "#{description} Default: #{option_type['defaultValue']}"
          # end
          # if option_type['required'] == true
          #   description = "(Required) #{description}"
          # end
          
          value_label = "VALUE"
          if option_type['placeHolder']
            value_label = option_type['placeHolder']
          elsif option_type['type'] == 'checkbox'
            value_label = '[on|off]' # or.. true|false
          elsif option_type['type'] == 'number'
            value_label = 'NUMBER'
          elsif option_type['type'] == 'multiSelect'
            value_label = 'LIST'
          # elsif option_type['type'] == 'select'
          #   value_label = 'SELECT'
          # elsif option['type'] == 'select'
          end
          if option_type['optionalValue']
            value_label = "[#{value_label}]"
          end
          full_option = "--#{full_field_name} #{value_label}"
          # switch is an alias for the full option name, fieldName is the default
          if option_type['switch']
            full_option = "--#{option_type['switch']} #{value_label}"
          end
          arg1, arg2 = full_option, String
          if option_type['shorthand']
            arg1, arg2 = full_option, option_type['shorthand']
          end
          opts.on(arg1, arg2, description) do |val|
            if option_type['type'] == 'checkbox'
              val = (val.to_s != 'false' && val.to_s != 'off')
            elsif option_type['dataType'] != 'string'
              # 'dataType': 'string' added to cli to avoid auto conversion to JSON
              # attempt to parse JSON, this allows blank arrays for multiSelect like --tenants []
              if (val.to_s[0] == '{' && val.to_s[-1] == '}') || (val.to_s[0] == '[' && val.to_s[-1] == ']')
                begin
                  val = JSON.parse(val)
                rescue
                  Morpheus::Logging::DarkPrinter.puts "Failed to parse option value '#{val}' as JSON" if Morpheus::Logging.debug?
                end
              end
            end
            cur_namespace = custom_options
            field_namespace.each do |ns|
              next if ns.empty?
              cur_namespace[ns.to_s] ||= {}
              cur_namespace = cur_namespace[ns.to_s]
            end
            cur_namespace[field_name] = val
          end

          # todo: all the various types
          # number 
          # checkbox [on|off]
          # select for optionSource and selectOptions

        end
        opts
      end

      ## the standard options for a command that makes api requests (most of them)

      def build_standard_get_options(opts, options, includes=[], excludes=[])
        build_common_options(opts, options, includes + [:query, :json, :yaml, :csv, :fields, :select, :delim, :quiet, :dry_run, :remote], excludes)
      end

      def build_standard_post_options(opts, options, includes=[], excludes=[])
        build_common_options(opts, options, includes + [:options, :payload, :json, :quiet, :dry_run, :remote], excludes)
      end

      def build_standard_put_options(opts, options, includes=[], excludes=[])
        build_standard_post_options(opts, options, includes, excludes)
      end

      def build_standard_delete_options(opts, options, includes=[], excludes=[])
        build_common_options(opts, options, includes + [:auto_confirm, :query, :json, :quiet, :dry_run, :remote], excludes)
      end

      # list is GET that supports phrase,max,offset,sort,direction
      def build_standard_list_options(opts, options, includes=[], excludes=[])
        build_standard_get_options(opts, options, [:list] + includes, excludes)
      end

      def build_standard_add_options(opts, options, includes=[], excludes=[])
        build_standard_post_options(opts, options, includes, excludes)
      end

      def build_standard_add_many_options(opts, options, includes=[], excludes=[])
        build_standard_post_options(opts, options, includes + [:payloads], excludes)
      end

      def build_standard_update_options(opts, options, includes=[], excludes=[])
        build_standard_put_options(opts, options, includes, excludes)
      end

      def build_standard_remove_options(opts, options, includes=[], excludes=[])
        build_standard_delete_options(opts, options, includes, excludes)
      end
      
      def build_standard_api_options(opts, options, includes=[], excludes=[])
        build_common_options(opts, options, includes + [:query, :options, :payload, :json, :yaml, :csv, :fields, :select, :delim, :quiet, :dry_run, :remote], excludes)
      end

      # number of decimal places to show with curreny
      def default_sigdig
        2
      end

      # appends to the passed OptionParser all the generic options
      # @param opts [OptionParser] the option parser object being constructed
      # @param options [Hash] the output Hash that is to being modified
      # @param includes [Array] which options to include eg. :options, :json, :remote
      # @return opts
      def build_common_options(opts, options, includes=[], excludes=[])
        #opts.separator ""
        # opts.separator "Common options:"
        option_keys = includes.clone
        all_option_keys = option_keys.dup
        # todo: support --quiet everywhere
        # turn on some options all the time..
        # unless command_name == "shell"
        #   option_keys << :quiet unless option_keys.include?(:quiet)
        # end

        # ensure commands can always access options[:options], until we can deprecate it...
        options[:options] ||= {}

        while (option_key = option_keys.shift) do
          case option_key.to_sym

          when :tenant, :account
            # todo: let's deprecate this in favor of :tenant --tenant to keep -a reserved for --all perhaps?
            opts.on('--tenant TENANT', String, "Tenant (Account) Name or ID") do |val|
              options[:account] = val
            end
            opts.on('--tenant-id ID', String, "Tenant (Account) ID") do |val|
              options[:account_id] = val
            end
            # todo: let's deprecate this in favor of :tenant --tenant to keep -a reserved for --all perhaps?
            opts.on('-a','--account ACCOUNT', "Alias for --tenant") do |val|
              options[:account] = val
            end
            opts.on('-A','--account-id ID', "Tenant (Account) ID") do |val|
              options[:account_id] = val
            end
            opts.add_hidden_option('--tenant-id') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.add_hidden_option('-a, --account') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.add_hidden_option('-A, --account-id') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :details
            opts.on('-a', '--all', "Show all details." ) do
              options[:details] = true
            end
            opts.on('--details', '--details', "Show more details" ) do
              options[:details] = true
            end
            opts.add_hidden_option('--details')

          when :sigdig
            opts.on('--sigdig DIGITS', "Significant digits to display for prices (currency). Default is #{default_sigdig}.") do |val|
              options[:sigdig] = val.to_i
            end

          when :options
            options[:options] ||= {}
            opts.on( '-O', '--option OPTION', "Option in the format -O field=\"value\"" ) do |option|
              # todo: look ahead and parse ALL the option=value args after -O switch
              #custom_option_args = option.split('=')
              custom_option_args = option.sub(/\s?\=\s?/, '__OPTION_DELIM__').split('__OPTION_DELIM__')
              custom_options = options[:options]
              option_name_args = custom_option_args[0].split('.')
              option_type = (options[:option_types] || []).find {|it| it['fieldName'] == custom_option_args[0]} || {}
              if option_name_args.count > 1
                nested_options = custom_options
                option_name_args.each_with_index do |name_element,index|
                  if index < option_name_args.count - 1
                    nested_options[name_element] = nested_options[name_element] || {}
                    nested_options = nested_options[name_element]
                  else
                    val = custom_option_args[1]
                    unless option_type['noParse']
                      if (val.to_s[0] == '{' && val.to_s[-1] == '}') || (val.to_s[0] == '[' && val.to_s[-1] == ']')
                        begin
                          val = JSON.parse(val)
                        rescue
                          Morpheus::Logging::DarkPrinter.puts "Failed to parse option value '#{val}' as JSON" if Morpheus::Logging.debug?
                        end
                      end
                    end
                    nested_options[name_element] = val
                  end
                end
              else
                val = custom_option_args[1]
                unless option_type['noParse']
                  if (val.to_s[0] == '{' && val.to_s[-1] == '}') || (val.to_s[0] == '[' && val.to_s[-1] == ']')
                    begin
                      val = JSON.parse(val)
                    rescue
                      Morpheus::Logging::DarkPrinter.puts "Failed to parse option value '#{val}' as JSON" if Morpheus::Logging.debug?
                    end
                  end
                end
                custom_options[custom_option_args[0]] = val
              end
              # convert "true","on" and "false","off" to true and false
              unless options[:skip_booleanize]
                custom_options.booleanize!
              end
              options[:options] = custom_options
            end
            # --always-prompt can be used with for update commands where it normally defaults to --no-prompt
            opts.on('--prompt', "Always prompt for input on every option, even those not prompted for by default.") do
              options[:always_prompt] = true
              options[:options][:always_prompt] = true
            end
            opts.on('-N','--no-prompt', "No prompt, skips all input prompting.") do |val|
              options[:no_prompt] = true
              options[:options][:no_prompt] = true
            end
            # opts.on('--skip-prompt x,y,z', String, "Skip prompt, do not prompt for input of the specified options.") do |val|
            #   options[:skip_prompt] ||= []
            #   options[:skip_prompt] += parse_array(val)
            #   options[:options][:skip_prompt] = options[:skip_prompt]
            # end
            # opts.on('--only-prompt x,y,z', String, "Only prompt for input on the specified options.") do |val|
            #   options[:only_prompt] ||= []
            #   options[:only_prompt] += parse_array(val)
            #   options[:options][:only_prompt] = options[:only_prompt]
            # end
            opts.on('--no-options', String, "No options, skips all option parsing so no options are required and no default values are used.") do
              options[:no_options] = true
              options[:options][:no_options] = options[:no_options]
            end
            opts.on('--skip-options x,y,z', String, "Skip parsing of the specified options so that they are not required and their default value is not used.") do |val|
              options[:skip_options] ||= []
              options[:skip_options] += parse_array(val)
              options[:options][:skip_options] = options[:skip_options]
            end
            # opts.on('--only-options x,y,z', String, "Only parse the specified options and skip all others.") do |val|
            #   options[:only_options] ||= []
            #   options[:only_options] += parse_array(val)
            #   options[:options][:only_options] = options[:only_options]
            # end
            
            # hide these while incubating
            opts.add_hidden_option('--skip-prompt')
            opts.add_hidden_option('--only-prompt')
            opts.add_hidden_option('--no-options')
            opts.add_hidden_option('--skip-options')
            opts.add_hidden_option('--only-options')

          when :payload
            opts.on('--payload FILE', String, "Payload from a local JSON or YAML file, skip all prompting") do |val|
              options[:payload_file] = val.to_s
              begin
                payload_file = File.expand_path(options[:payload_file])
                if !File.exist?(payload_file) || !File.file?(payload_file)
                  raise ::OptionParser::InvalidOption.new("File not found: #{payload_file}")
                  #return false
                end
                if payload_file =~ /\.ya?ml\Z/
                  options[:payload] = YAML.load_file(payload_file)
                else
                  options[:payload] = JSON.parse(File.read(payload_file))
                end
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload file: #{payload_file} Error: #{ex.message}")
              end
            end
            opts.on('--payload-dir DIRECTORY', String, "Payload from a local directory containing 1-N JSON or YAML files, skip all prompting. This makes one request, merging all the files into a single payload.") do |val|
              print_error yellow,"[DEPRECATED] The option `--payload-dir` is deprecated and will be removed. Use `--payloads` to make requests for each file in a directory.",reset,"\n"
              options[:payload_dir] = val.to_s
              payload_dir = File.expand_path(options[:payload_dir])
              if !Dir.exist?(payload_dir) || !File.directory?(payload_dir)
                raise ::OptionParser::InvalidOption.new("Directory not found: #{payload_dir}")
              end
              payload = {}
              begin
                merged_payload = {}
                payload_files = []
                payload_files += Dir["#{payload_dir}/*.json"]
                payload_files += Dir["#{payload_dir}/*.yml"]
                payload_files += Dir["#{payload_dir}/*.yaml"]
                if payload_files.empty?
                  raise ::OptionParser::InvalidOption.new("No .json/yaml files found in config directory: #{payload_dir}")
                end
                payload_files.each do |payload_file|
                  Morpheus::Logging::DarkPrinter.puts "parsing payload file: #{payload_file}" if Morpheus::Logging.debug?
                  config_payload = {}
                  if payload_file =~ /\.ya?ml\Z/
                    config_payload = YAML.load_file(payload_file)
                  else
                    config_payload = JSON.parse(File.read(payload_file))
                  end
                  merged_payload.deep_merge!(config_payload)
                end
                options[:payload] = merged_payload
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload file: #{payload_file} Error: #{ex.message}")
              end
            end
            opts.add_hidden_option('--payload-dir')
            opts.on('--payload-json JSON', String, "Payload JSON, skip all prompting") do |val|
              begin
                options[:payload] = JSON.parse(val.to_s)
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload as JSON. Error: #{ex.message}")
              end
            end
            opts.on('--payload-yaml YAML', String, "Payload YAML, skip all prompting") do |val|
              begin
                options[:payload] = YAML.load(val.to_s)
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload as YAML. Error: #{ex.message}")
              end
            end
            # --payloads test-data/item*.json
            opts.on('--payloads PATH', String, "Payload(s) from one or more local JSON or YAML files, skip all prompting and execute the request 1-N times, once for each file. PATH can be a directory or a file pattern.") do |val|
              # maybe use parse_array(val) to support csv..
              # find files matching PATH
              # todo: probably support recursive... can be done with '**/*.json' now though.
              if val.to_s.strip.empty?
                raise ::OptionParser::InvalidOption.new("PATH must be provided as directory, file or pattern to find JSON or YAML files.")
              end
              filepath = File.expand_path(val.to_s.strip)
              files = []
              if File.directory?(filepath)
                # passed the name of a directory, include all the JSON and YAML files directly under it
                Dir.glob(File.join(filepath, "*")).each do |file| 
                  if File.file?(file) && ['.json','.yaml','.yml'].include?(File.extname(file))
                    files << file
                  end
                end
                if files.empty?
                  raise ::OptionParser::InvalidOption.new("Failed to find any .json or .yaml files under the directory: #{filepath}")
                end
              elsif File.file?(filepath)
                # passed the name of a file
                files << filepath
              else
                # assume it is a pattern to find files with
                files = Dir.glob(filepath)
                if files.empty?
                  raise ::OptionParser::InvalidOption.new("Failed to find any files matching path: #{filepath}")
                end
              end
              # parse files as JSON or YAML
              options[:payload_files] ||= []
              options[:payloads] ||= []
              files.each do |file|
                if options[:payload_files].include?(file)
                  next
                else
                  options[:payload_files] << file
                end
                payload = nil
                begin
                  payload_file = File.expand_path(file)
                  if !File.exist?(payload_file) || !File.file?(payload_file)
                    raise ::OptionParser::InvalidOption.new("File not found: #{payload_file}")
                  end
                  # todo: could use parse_json_or_yaml()
                  payload = nil
                  if payload_file =~ /\.ya?ml\Z/
                    payload = YAML.load_file(payload_file)
                  else
                    payload = JSON.parse(File.read(payload_file))
                  end
                  options[:payloads] << payload
                rescue => ex
                  raise ::OptionParser::InvalidOption.new("Failed to parse payload file: #{payload_file} Error: #{ex.message}")
                end
              end
            end if all_option_keys.include?(:payloads)
            opts.on('--ignore-payload-errors', "Continue processing any remaining payloads if an error occurs. The default behavior is to stop processing when an error occurs.") do
              options[:ignore_payload_errors] = true
            end if all_option_keys.include?(:payloads)
          when :payloads
            # added with :payload too... just need it here to avoid unknown key error
            # todo: remove this when every command supporting :payload is updated to use parse_payload(options) and execute_api(options)
          when :list
            opts.on( '-m', '--max MAX', "Max Results" ) do |val|
              # api supports max=-1 for all at the moment..
              if val.to_s == "all" || val.to_s == "-1"
                options[:max] = "-1"
              else
                max = val.to_i
                if max <= 0
                  raise ::OptionParser::InvalidArgument.new("must be a positive integer")
                end
                options[:max] = max
              end
            end

            opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |val|
              offset = val.to_i
              if offset <= 0
                raise ::OptionParser::InvalidArgument.new("must be a positive integer")
              end
              options[:offset] = offset
            end

            if excludes.include?("search") == false
              opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
                options[:phrase] = phrase
              end
            end

            opts.on( '-S', '--sort ORDER', "Sort Order. DIRECTION may be included as \"ORDER [asc|desc]\"." ) do |v|
              if v.to_s.include?(",")
                # sorting on multiple properties, just pass it as is, newer api supports multiple fields
                options[:sort] = v
              else
                v_parts = v.to_s.split(" ")
                if v_parts.size > 1
                  options[:sort] = v_parts[0]
                  options[:direction] = (v_parts[1].strip == "desc") ? "desc" : "asc"
                else
                  options[:sort] = v
                end
              end
            end

            opts.on( '-D', '--desc', "Descending Sort Direction." ) do |v|
              options[:direction] = "desc"
            end

            opts.on( "--reverse", "Reverse order of results. This invert is done by the client, not necessarily the entire dataset." ) do
              options[:reverse] = true
            end

            # arbitrary query parameters in the format -Q "category=web&phrase=nginx"
            # opts.on( '-Q', '--query PARAMS', "Query parameters. PARAMS format is 'foo=bar&category=web'" ) do |val|
            #   options[:query_filters_raw] = val
            #   options[:query_filters] = {}
            #   # todo: smarter parsing
            #   val.split('&').each do |filter| 
            #     k, v = filter.split('=')
            #     # allow "woot:true instead of woot=true"
            #     if (k.include?(":") && v == nil)
            #       k, v = k.split(":")
            #     end
            #     if (!k.to_s.empty?)
            #       options[:query_filters][k.to_s.strip] = v.to_s.strip
            #     end
            #   end
            # end

          when :query, :query_filters
            # arbitrary query parameters in the format -Q "category=web&phrase=nginx"
            # or pass it many times like -Q foo=bar -Q hello=world
            opts.on( '-Q', '--query PARAMS', "Query parameters. PARAMS format is 'foo=bar&category=web'" ) do |val|
              if options[:query_filters_raw] && !options[:query_filters_raw].empty?
                options[:query_filters_raw] += ("&" + val)
              else
                options[:query_filters_raw] = val
              end
              options[:query_filters] ||= {}
              val.split('&').each do |filter| 
                k, v = filter.split('=')
                # allow woot:true instead of woot=true
                if (k.include?(":") && v == nil)
                  k, v = k.split(":")
                end
                if (!k.to_s.empty?)
                  if options[:query_filters].key?(k.to_s.strip)
                    cur_val = options[:query_filters][k.to_s.strip]
                    if cur_val.instance_of?(Array)
                      options[:query_filters][k.to_s.strip] << v.to_s.strip
                    else
                      options[:query_filters][k.to_s.strip] = [cur_val, v.to_s.strip]
                    end
                  else
                    options[:query_filters][k.to_s.strip] = v.to_s.strip
                  end
                end
              end
            end

          when :last_updated
            # opts.on("--last-updated TIME", Time, "Filter by gte last updated") do |time|
            opts.on("--last-updated TIME", String, "Filter by Last Updated (gte)") do |time|
              begin
                options[:lastUpdated] = parse_time(time)
              rescue => e
                raise OptionParser::InvalidArgument.new "Failed to parse time '#{time}'. Error: #{e}"
              end
            end

          when :find_by_name
            opts.on('--find-by-name', "Always treat the identifier argument as a name, never an ID. Useful for specifying names that look like numbers. eg. '1234'" ) do
              options[:find_by_name] = true
            end
            # opts.add_hidden_option('--find-by-name') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :remote
            opts.on( '-r', '--remote REMOTE', "Remote name. The current remote is used by default." ) do |val|
              options[:remote] = val
            end
            opts.on( '--remote-url URL', '--remote-url URL', "Remote url. This allows adhoc requests instead of using a configured remote." ) do |val|
              options[:remote_url] = val
            end
            opts.on( '-T', '--token TOKEN', "Access token for authentication with --remote. Saved credentials are used by default." ) do |val|
              options[:remote_token] = val
            end unless excludes.include?(:remote_token)
            opts.on( '--token-file FILE', String, "Token File, read a file containing the access token." ) do |val|
              token_file = File.expand_path(val)
              if !File.exist?(token_file) || !File.file?(token_file)
                raise ::OptionParser::InvalidOption.new("File not found: #{token_file}")
              end
              options[:remote_token] = File.read(token_file).to_s.split("\n").first.strip
            end
            opts.add_hidden_option('--token-file') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on( '-U', '--username USERNAME', "Username for authentication." ) do |val|
              options[:remote_username] = val
            end unless excludes.include?(:remote_username)
            

            unless excludes.include?(:remote_password)
              opts.on( '-P', '--password PASSWORD', "Password for authentication." ) do |val|
                options[:remote_password] = val
              end
              opts.on( '--password-file FILE', String, "Password File, read a file containing the password for authentication." ) do |val|
                password_file = File.expand_path(val)
                if !File.exist?(password_file) || !File.file?(password_file)
                  raise ::OptionParser::InvalidOption.new("File not found: #{password_file}")
                end
                file_content = File.read(password_file) #.strip
                options[:remote_password] = File.read(password_file).to_s.split("\n").first
              end
              opts.add_hidden_option('--password-file') if opts.is_a?(Morpheus::Cli::OptionParser)
            end

            # todo: also require this for talking to plain old HTTP
            opts.on('-I','--insecure', "Allow insecure HTTPS communication.  i.e. bad SSL certificate.") do |val|
              options[:insecure] = true
              Morpheus::RestClient.enable_ssl_verification = false
            end
          
          #when :header, :headers
            opts.on( '-H', '--header HEADER', "Additional HTTP header to include with requests." ) do |val|
              options[:headers] ||= {}
              # header_list = val.to_s.split(',')
              header_list = [val.to_s]
              header_list.each do |h|
                header_parts = val.to_s.split(":")
                header_key, header_value = header_parts[0], header_parts[1..-1].join(":").strip
                if header_parts.size() < 2
                  header_parts = val.to_s.split("=")
                  header_key, header_value = header_parts[0], header_parts[1..-1].join("=").strip
                end
                if header_parts.size() < 2
                  raise_command_error "Invalid HEADER value '#{val}'. HEADER should contain a key and a value. eg. -H 'X-Morpheus-Lease: $MORPHEUS_LEASE_TOKEN'"
                end
                options[:headers][header_key] = header_value
              end
            end
            # opts.add_hidden_option('-H') if opts.is_a?(Morpheus::Cli::OptionParser)
            # opts.add_hidden_option('--header') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.add_hidden_option('-H, --header') if opts.is_a?(Morpheus::Cli::OptionParser)

          #when :timeout
            opts.on( '--timeout SECONDS', "Timeout for api requests. Default is typically 30 seconds." ) do |val|
              options[:timeout] = val ? val.to_f : nil
            end
            opts.add_hidden_option('--timeout') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :auto_confirm
            opts.on( '-y', '--yes', "Auto Confirm" ) do
              options[:yes] = true
            end

          when :json
            opts.on('-j','--json', "JSON Output") do
              options[:json] = true
              options[:format] = :json
            end

            opts.on('--json-raw', String, "JSON Output that is not so pretty.") do |val|
              options[:json] = true
              options[:format] = :json
              options[:pretty_json] = false
            end
            opts.add_hidden_option('json-raw') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :yaml
            # -y for --yes and for --yaml
            if includes.include?(:auto_confirm)
              opts.on(nil, '--yaml', "YAML Output") do
                options[:yaml] = true
                options[:format] = :yaml
              end
            else
              opts.on('-y', '--yaml', "YAML Output") do
                options[:yaml] = true
                options[:format] = :yaml
              end
            end
            opts.on(nil, '--yml', "alias for --yaml") do
              options[:yaml] = true
              options[:format] = :yaml
            end
            opts.add_hidden_option('yml') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :csv
            opts.on(nil, '--csv', "CSV Output") do
              options[:csv] = true
              options[:format] = :csv
              #options[:csv_delim] = options[:csv_delim] || ","
            end
            # deprecated --csv-delim, use --delimiter instead
            opts.on('--csv-delim CHAR', String, "Delimiter for CSV Output values. Default: ','") do |val|
              options[:csv] = true
              options[:format] = :csv
              val = val.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
              options[:csv_delim] = val
            end
            opts.add_hidden_option('--csv-delim') if opts.is_a?(Morpheus::Cli::OptionParser)

            # deprecated --csv-newline, use --newline instead
            opts.on('--csv-newline [CHAR]', String, "Delimiter for CSV Output rows. Default: '\\n'") do |val|
              options[:csv] = true
              options[:format] = :csv
              if val == "no" || val == "none"
                options[:csv_newline] = ""
              else
                val = val.to_s.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
                options[:csv_newline] = val
              end
            end
            opts.add_hidden_option('--csv-newline') if opts.is_a?(Morpheus::Cli::OptionParser)

            opts.on(nil, '--csv-quotes', "Wrap CSV values with \". Default: false") do
              options[:csv] = true
              options[:format] = :csv
              options[:csv_quotes] = true
            end
            opts.add_hidden_option('--csv-quotes') if opts.is_a?(Morpheus::Cli::OptionParser)

            opts.on(nil, '--csv-no-header', "Exclude header for CSV Output.") do
              options[:csv] = true
              options[:format] = :csv
              options[:csv_no_header] = true
            end
            opts.add_hidden_option('--csv-no-header') if opts.is_a?(Morpheus::Cli::OptionParser)

            opts.on(nil, '--quotes', "Wrap CSV values with \". Default: false") do
              options[:csv_quotes] = true
            end
            opts.add_hidden_option('--csv-quotes') if opts.is_a?(Morpheus::Cli::OptionParser)

            opts.on(nil, '--no-header', "Exclude header for CSV Output.") do
              options[:csv_no_header] = true
            end

          when :fields
            opts.on('-f', '--fields x,y,z', Array, "Filter Output to a limited set of fields. Default is all fields for json,csv,yaml.") do |val|
              if val.size == 1 && val[0].downcase == 'all'
                options[:all_fields] = true
              else
                options[:include_fields] = val
              end
            end
            opts.on('-F', '--old-fields x,y,z', Array, "alias for -f, --fields") do |val|
              if val.size == 1 && val[0].downcase == 'all'
                options[:all_fields] = true
              else
                options[:include_fields] = val
              end
            end
            opts.add_hidden_option('-F, --old-fields') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--raw-fields [x,y,z]', String, "Raw fields filters output like --fields except the properties [x,y,z] must be specified from the root of the response instead of relative to the the list or object context for this particular resource.") do |val|
              if val.size == 1 && val[0].downcase == 'all'
                options[:all_fields] = true
              else
                options[:include_fields] = val.split(',').collect {|r| r.strip}.compact
              end
              options[:raw_fields] = true
            end
            opts.add_hidden_option('--raw-fields') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on(nil, '--all-fields', "Show all fields present in the data.") do
              options[:all_fields] = true
            end
            opts.on(nil, '--wrap', "Wrap table columns instead hiding them when terminal is not wide enough.") do
              options[:wrap] = true
            end
          when :select
            #opts.add_hidden_option('--all-fields') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--select x,y,z', String, "Filter Output to just print the value(s) of specific fields.") do |val|
              options[:select_fields] = val.split(',').collect {|r| r.strip}
            end
            opts.on('--raw-select x,y,z', String, "Raw select works like --select except the properties [x,y,z] must be specified from the root of the response instead of relative to the the list or object context for this particular resource.") do |val|
              options[:select_fields] = val.split(',').collect {|r| r.strip}
              options[:raw_fields] = true
            end
            opts.add_hidden_option('--raw-select') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :delim
            opts.on('--delimiter [CHAR]', String, "Delimiter for output values. Default: ',', use with --select and --csv") do |val|
              options[:csv] = true
              options[:format] = :csv
              val = val.to_s
              val = val.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
              options[:delim] = val
            end

            opts.on('--newline [CHAR]', String, "Delimiter for output rows. Default: '\\n', use with --select and --csv") do |val|
              options[:csv] = true
              options[:format] = :csv
              val = val.to_s
              if val == "no" || val == "none"
                options[:newline] = ""
              else
                val = val.to_s.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
                options[:newline] = val
              end
            end
          when :thin
            opts.on( '--thin', '--thin', "Format headers and columns with thin borders." ) do |val|
              options[:border_style] = :thin
            end
            
          

          when :dry_run
            opts.on('-d','--dry-run', "Dry Run, print the API request instead of executing it.") do
              # todo: this should print after parsing obv..
              # need a hook after parse! or a standard_handle(options) { ... } paradigm
              # either that or hook it up in every command somehow, maybe a hook on connect()
              #puts "#{cyan}#{dark} #=> DRY RUN#{reset}"
              # don't print this for --json combined with -d
              # print once and dont munge json
              if !options[:curl] && !options[:json]
                puts "#{cyan}#{bold}#{dark}DRY RUN#{reset}"
              end
              options[:dry_run] = true
            end
            opts.on(nil,'--curl', "Curl, print the API request as a curl command instead of executing it.") do
              # print once and dont munge json
              if !options[:dry_run] && !options[:json]
                puts "#{cyan}#{bold}#{dark}DRY RUN#{reset}"
              end
              options[:dry_run] = true
              options[:curl] = true
            end
            opts.on(nil,'--scrub', "Mask secrets in output, such as the Authorization header. For use with --curl and --dry-run.") do
              options[:scrub] = true
            end
            # dry run comes with hidden outfile options
            #opts.add_hidden_option('--scrub') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--out FILE', String, "Write standard output to a file instead of the terminal.") do |val|
              # could validate directory is writable..
              options[:outfile] = val
            end
            opts.add_hidden_option('--out') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--overwrite', '--overwrite', "Overwrite output file if it already exists.") do
              options[:overwrite] = true
            end
            opts.add_hidden_option('--overwrite') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :outfile
            opts.on('--out FILE', String, "Write standard output to a file instead of the terminal.") do |val|
              options[:outfile] = val
            end
            opts.on('--overwrite', '--overwrite', "Overwrite output file if it already exists.") do |val|
              options[:overwrite] = true
            end
          when :quiet
            opts.on('-q','--quiet', "No Output, do not print to stdout") do
              options[:quiet] = true
            end

          else
            raise "Unknown common_option key: #{option_key}"
          end
        end

        # options that are always included

        # always support thin, but hidden because mostly not hooked up at the moment...
        unless includes.include?(:thin)
          opts.on( '--thin', '--thin', "Format headers and columns with thin borders." ) do |val|
            options[:border_style] = :thin
          end
          opts.add_hidden_option('--thin') if opts.is_a?(Morpheus::Cli::OptionParser)
        end

        # disable ANSI coloring
        opts.on('-C','--nocolor', "Disable ANSI coloring") do
          Term::ANSIColor::coloring = false
        end


        # Benchmark this command?
        # Also useful for seeing exit status for every command.
        opts.on('-B','--benchmark', "Print benchmark time and exit/error after the command is finished.") do
          options[:benchmark] = true
          # this is hacky, but working!  
          # shell handles returning to false
          #Morpheus::Benchmarking.enabled = true
          #my_terminal.benchmarking = true
          #start_benchmark(args.join(' '))
          # ok it happens outside of handle() alltogether..
          # wow, simplify me plz
        end

        opts.on('-V','--debug', "Print extra output for debugging.") do
          options[:debug] = true
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
          # perhaps...
          # create a new logger instance just for this command instance
          # this way we don't elevate the global level for subsequent commands in a shell
          # @logger = Morpheus::Logging::Logger.new(STDOUT)
          # if !@logger.debug?
          #   @logger.log_level = Morpheus::Logging::Logger::DEBUG
          # end
        end

        # A way to ensure debugging is off, it should go back on after the command is complete.
        opts.on('--no-debug','--no-debug', "Disable debugging.") do
          options[:debug] = false
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::INFO)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
        end
        opts.add_hidden_option('--no-debug') if opts.is_a?(Morpheus::Cli::OptionParser)

        opts.on('--hidden-help', "Print help that includes all the hidden options, like this one." ) do
          puts opts.full_help_message({show_hidden_options:true})
          exit 0 # return 0 maybe?
        end
        opts.add_hidden_option('--hidden-help') if opts.is_a?(Morpheus::Cli::OptionParser)
        opts.on('-h', '--help', "Print this help" ) do
          puts opts
          exit 0 # return 0 maybe?
        end

        opts
      end

      def prog_name
        self.class.prog_name
      end

      def command_name
        self.class.command_name
      end

      def command_description
        self.class.command_description
      end

      def subcommands
        self.class.subcommands
      end

      def visible_subcommands
        self.class.visible_subcommands
      end

      def subcommand_aliases
        self.class.subcommand_aliases
      end

      # def subcommand_descriptions
      #   self.class.subcommand_descriptions
      # end

      def get_subcommand_description(subcmd)
        self.class.get_subcommand_description(subcmd)
      end

      def subcommand_description()
        calling_method = caller[0][/`([^']*)'/, 1].to_s.sub('block in ', '')
        subcommand_name = subcommands.key(calling_method)
        subcommand_name ? get_subcommand_description(subcommand_name) : nil
      end

      def default_subcommand
        self.class.default_subcommand
      end

      def default_refresh_interval
        self.class.default_refresh_interval
      end

      def usage
        if !subcommands.empty?
          "Usage: #{prog_name} #{command_name} [command] [options]"
        else
          "Usage: #{prog_name} #{command_name} [options]"
        end
      end

      def my_help_command
        "#{prog_name} #{command_name} --help"
      end

      def subcommand_usage(*extra)
        calling_method = caller[0][/`([^']*)'/, 1].to_s.sub('block in ', '')
        subcommand_name = subcommands.key(calling_method)
        extra = extra.flatten
        if !subcommand_name.empty? && extra.first == subcommand_name
          extra.shift
        end
        #extra = ["[options]"] if extra.empty?
        "Usage: #{prog_name} #{command_name} #{subcommand_name} #{extra.join(' ')}".squeeze(' ').strip
      end

      # a string to describe the usage of your command
      # this is what the --help option
      # feel free to override this in your commands
      def full_command_usage
        out = ""
        out << usage.to_s.strip if usage
        out << "\n"
        my_subcommands = visible_subcommands
        if !my_subcommands.empty?
          out << "Commands:"
          out << "\n"
          my_subcommands.sort.each {|subcmd, method|
            desc = get_subcommand_description(subcmd)
            out << "\t#{subcmd.to_s}"
            out << "\t#{desc}" if desc
            out << "\n"
          }
        end
        if command_description && !command_description.to_s.strip.empty?
          out << "\n"
          out << "#{command_description.strip}\n"
        end
        # out << "\n"
        out
      end

      # a default handler
      def handle_subcommand(args)
        commands = subcommands
        if subcommands.empty?
          raise "#{self.class} has no available subcommands"
        end
        # meh, could deprecate and make subcommand define handle() itself
        # if args.count == 0 && default_subcommand
        #   # p "using default subcommand #{default_subcommand}"
        #   return send(default_subcommand, args || [])
        # end
        subcommand_name = args[0]
        if args.empty?
          print_error Morpheus::Terminal.angry_prompt
          puts_error "[command] argument is required"
          puts full_command_usage
          exit 127
        end
        if args[0] == "-h" || args[0] == "--help" || args[0] == "help"
          puts full_command_usage
          return 0
        end
        if subcommand_aliases[subcommand_name]
          subcommand_name = subcommand_aliases[subcommand_name]
        end
        cmd_method = subcommands[subcommand_name]
        if !cmd_method
          error_msg = "'#{command_name} #{subcommand_name}' is not a #{prog_name} command.\n#{full_command_usage}"
          raise CommandNotFoundError.new(error_msg)
        end
        send(cmd_method, args[1..-1])
      end

      def handle(args)
        raise "#{self} has not defined handle()!"
      end

      # executes block with each argument in the list
      # @return [0|1] 0 if they were all successful, else 1
      def run_command_for_each_arg(args, &block)
        cmd_results = []
        args.each do |arg|
          begin
            cur_result = yield arg
          rescue SystemExit => err
            cur_result = err.success? ? 0 : 1
          end
          cmd_results << cur_result
        end
        # find a bad result and return it
        cmd_results = cmd_results.collect do |cmd_result| 
          if cmd_result.is_a?(Array)
            cmd_result
          else
            [cmd_result, nil]
          end
        end
        failed_result = cmd_results.find {|cmd_result| cmd_result[0] == false || (cmd_result[0].is_a?(Integer) && cmd_result[0] != 0) }
        return failed_result ? failed_result : cmd_results.last
      end

      # def connect(options={})
      #   Morpheus::Logging::DarkPrinter.puts "#{command_name} has not defined connect()" if Morpheus::Logging.debug?
      # end

      # This supports the simple remote option eg. `instances add --remote "qa"`
      # It will establish a connection to the pre-configured appliance named "qa"
      # By default it will connect to the active (current) remote appliance
      # This returns a new instance of Morpheus::APIClient (and sets @access_token, and @appliance)
      # Your command should be ready to make api requests after this.
      # This will prompt for credentials if none are found, use :skip_login
      # Credentials will be saved unless --remote-url or --token is being used.
      def establish_remote_appliance_connection(options)
        # todo: probably refactor and don't rely on this method to set these instance vars
        @remote_appliance = nil
        @appliance_name, @appliance_url, @access_token = nil, nil, nil
        @api_client = nil
        @do_save_credentials = true
        # skip saving if --remote-url or --username or --password are passed in
        if options[:remote_url] || options[:remote_token] || options[:remote_username] || options[:remote_password]
          @do_save_credentials = false
        end
        appliance = nil
        if options[:remote_url]
          # --remote-url means use an arbitrary url, do not save any appliance config
          # appliance = {name:'remote-url', url:options[:remote_url]}
          appliance = {url:options[:remote_url]}
          appliance[:temporary] = true
          #appliance[:status] = "ready" # or  "unknown"
          # appliance[:last_check] = nil
        elsif options[:remote]
          # --remote means use the specified remote
          appliance = ::Morpheus::Cli::Remote.load_remote(options[:remote])
          if appliance.nil?
            if ::Morpheus::Cli::Remote.appliances.empty?
              raise_command_error "No remote appliances exist, see the command `remote add`."
            else
              raise_command_error "Remote appliance not found by the name '#{options[:remote]}', see `remote list`"
            end
          end
        else
          # use active remote
          appliance = ::Morpheus::Cli::Remote.load_active_remote()
          if !appliance
            if ::Morpheus::Cli::Remote.appliances.empty?
              raise_command_error "No remote appliances exist, see the command `remote add`"
            else
              raise_command_error "#{command_name} requires a remote to be specified, try the option -r [remote] or see the command `remote use`"
            end
          end
        end
        @remote_appliance = appliance
        @appliance_name = appliance[:name]
        @appliance_url = appliance[:url] || appliance[:host] # it used to store :host in the YAML
        # set enable_ssl_verification
        # instead of toggling this global value
        # this should just be an attribute of the api client
        # for now, this fixes the issue where passing --insecure or --remote
        # would then apply to all subsequent commands...
        allow_insecure = false
        if options[:insecure] || appliance[:insecure] || Morpheus::Cli::Shell.insecure
          allow_insecure = true
        end
        @verify_ssl = !allow_insecure
        # Morpheus::RestClient.enable_ssl_verification = allow_insecure != true
        if allow_insecure && Morpheus::RestClient.ssl_verification_enabled?
          Morpheus::RestClient.enable_ssl_verification = false
        elsif !allow_insecure && !Morpheus::RestClient.ssl_verification_enabled?
          Morpheus::RestClient.enable_ssl_verification = true
        end

        # always support accepting --username and --password on the command line
        # it's probably better not to do that tho, just so it stays out of history files

        # if !@appliance_name && !@appliance_url
        #   raise_command_error "Please specify a remote appliance with -r or see the command `remote use`"
        # end

        Morpheus::Logging::DarkPrinter.puts "establishing connection to remote #{display_appliance(@appliance_name, @appliance_url)}" if Morpheus::Logging.debug? # && !options[:quiet]

        if options[:no_authorization]
          # maybe handle this here..
          options[:skip_login] = true
          options[:skip_verify_access_token] = true
        end

        # ok, get some credentials.
        # use saved credentials by default or prompts for username, password.
        # passing --remote-url will skip loading saved credentials and prompt for login to use with the url
        # passing --token skips login prompting and uses the provided token.
        # passing --token or --username will skip saving credentials to appliance config, they are just used for one command
        # ideally this should not prompt now and wait until the client is used on a protected endpoint.
        # @wallet = nil
        if options[:remote_token]
          @wallet = {'access_token' => options[:remote_token]} #'username' => 'anonymous'
        elsif options[:remote_url]
          credentials = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url)
          unless options[:skip_login]
            @wallet = credentials.request_credentials(options.merge({dry_run:false}), @do_save_credentials)
          end
        else
          credentials = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url)
          # use saved credentials unless --username or passed
          unless options[:remote_username]
            @wallet = credentials.load_saved_credentials()
          end
          # using active remote OR --remote flag
          # used saved credentials or login
          # ideally this sould not prompt now and wait  until the client is used on a protected endpoint.

          
          if @wallet.nil? || @wallet['access_token'].nil?
            unless options[:skip_login]
              @wallet = credentials.request_credentials(options.merge({dry_run:false}), @do_save_credentials)
            end
          end
          
        end
        @access_token = @wallet ? @wallet['access_token'] : nil

        # validate we have a token
        # hrm...
        unless options[:skip_verify_access_token]
          if @access_token.empty?
            raise AuthorizationRequiredError.new("Failed to acquire access token for #{display_appliance(@appliance_name, @appliance_url)}. Verify your credentials are correct.")  
          end
        end

        # ok, connect to the appliance.. actually this just instantiates an ApiClient
        api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url, @verify_ssl)
        @api_client = api_client # meh, just return w/o setting instance attrs
        return api_client
      end

      # verify_args! verifies that the right number of commands were passed
      # and raises a command error if not.
      # Example: verify_args!(args:args, count:1, optparse:optparse)
      # this could go be done in optparse.parse instead perhaps
      def verify_args!(opts={})
        args = opts[:args] || []
        count = opts[:count]
        # simplify output for verify_args!(min:2, max:2) or verify_args!(max:0)
        if opts[:min] && opts[:max] && opts[:min] == opts[:max]
          count = opts[:min]
        elsif opts[:max] == 0
          count = 0
        end
        if count
          if args.count < count
            raise_args_error("not enough arguments, expected #{count} and got #{args.count == 0 ? '0' : args.count.to_s + ': '}#{args.join(', ')}", args, opts[:optparse])
          elsif args.count > count
            raise_args_error("too many arguments, expected #{count} and got #{args.count == 0 ? '0' : args.count.to_s + ': '}#{args.join(', ')}", args, opts[:optparse])
          end
        else
          if opts[:min]
            if args.count < opts[:min]
              raise_args_error("not enough arguments, expected #{opts[:min] || '0'}-#{opts[:max] || 'N'} and got #{args.count == 0 ? '0' : args.count.to_s + ': '}#{args.join(', ')}", args, opts[:optparse])
            end
          end
          if opts[:max]
            if args.count > opts[:max]
              raise_args_error("too many arguments, expected #{opts[:min] || '0'}-#{opts[:max] || 'N'} and got #{args.count == 0 ? '0' : args.count.to_s + ': '}#{args.join(', ')}", args, opts[:optparse])
            end
          end
        end
        true
      end

      def confirm(msg, options)
        options[:yes] or ::Morpheus::Cli::OptionTypes::confirm(msg, options)
      end

      def confirm!(msg, options)
        confirm(msg, options) or raise CommandAborted.new("confirmation declined: #{msg}")
      end

      # The default way to build options for the list command
      # @param [OptionParser] opts
      # @param [Hash] options
      # @param [Hash] params
      def build_list_options(opts, options, params)
        build_standard_list_options(opts, options)
      end

      # The default way to parse options for the list command
      # @param [Array] args
      # @param [Hash] options
      # @param [Hash] params
      def parse_list_options!(args, options, params)
        if args.count > 0
          options[:phrase] = args.join(" ")
          # params['phrase'] =  = args.join(" ")
        end
        params.merge!(parse_list_options(options))
        # query parameters are stored in :params
        # preserve anything already set in :params by the OptionParser or command specific logic..
        options[:params] ||= {}
        options[:params].deep_merge!(params)
        return options
      end

      # The default way to build options for the list command
      # @param [OptionParser] opts
      # @param [Hash] options
      # @param [Hash] params
      def build_get_options(opts, options, params)
        build_standard_get_options(opts, options)
      end
      
      # The default way to parse options for the get command
      # @param [OptionParser] opts
      # @param [Hash] options
      # @param [Hash] params
      def parse_get_options!(args, options, params)
        params.merge!(parse_query_options(options))
      end

      # Add a name=value query parameter, building an array if there is more than one
      # @param [Hash] params the query parameter map to append to
      # @param [String] key the parameter name
      # @param [Object] value the parameter value
      def add_query_parameter(params, key, value)
        # key = key.to_s
        if params.key?(key) && !params[key].nil?
          if !params[key].is_a?(Array)
            params[key] = [params[key]]
          end
          params[key] << value
        else
          params[key] = value
        end
        params
      end

      # The default way to parse options for the get command
      # @param type [string]
      # @param options [Hash] The command options
      # @param params [Hash] The query parameters the output is being appended to
      # @param param_name [String]
      # @param lookup_ids [Boolean] Also lookup ids to make sure they exist or else error
      # @return 
      def parse_parameter_as_resource_id!(type, options, params, param_name=nil, lookup_ids=false)
        # type = type.to_s.singularize
        if options.key?(type)
          val = options[type].to_s
          param_name ||= "#{type.to_s.camelcase}Id"
          if val
            if val.to_s !~ /\A\d{1,}\Z/ || lookup_ids
              record = find_by_name(type, val)
              if record.nil?
                 # avoid double error render by exiting here, ew
                exit 1
                raise_command_error "#{type.titleize} not found for '#{val}'"
              end
              params[param_name] = record['id']
            else
              params[param_name] = val
            end
            return params[param_name]
          end
        end
        return nil
      end

      # parse the parameters provided by the common :list options
      # this includes the :query options too via parse_query_options().
      # returns Hash of params the format {"phrase": => "foobar", "max": 100}
      def parse_list_options(options={})
        list_params = {}
        [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
          if options.key?(k)
            list_params[k.to_s] = options[k]
          elsif options.key?(k.to_s)
            list_params[k.to_s] = options[k.to_s]
          end
        end
        # arbitrary filters
        list_params.merge!(parse_query_options(options))
        # ok, any string keys in options can become query parameters, eg. options['name'] = 'foobar'
        # do it!
        # options.each do |k, v|
        #   list_params[k] = v
        # end
        return list_params
      end

      # parse the parameters provided by the common :query (:query_filters) options
      # returns Hash of params the format {"phrase": => "foobar", "max": 100}
      def parse_query_options(options={})
        list_params = {}
        # arbitrary filters
        if options[:query_filters]
          options[:query_filters].each do |k, v|
            if k
              list_params[k] = v
            end
          end
        end
        return list_params
      end

      # parse the subtitles provided by the common :list options
      # returns Array of subtitles as strings in the format ["Phrase: blah", "Max: 100"]
      def parse_list_subtitles(options={})
        subtitles = []
        if options[:tenant]
          subtitles << "Tenant: #{options[:tenant]}".strip
        end
        if options[:include_tenants]
          subtitles << "Include Tenants: true".strip
        end
        [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
          if options.key?(k)
            subtitles << "#{k.to_s}: #{options[k]}"
          elsif options.key?(k.to_s)
            subtitles << "#{k.to_s}: #{options[k.to_s]}"
          end
        end
        # arbitrary filters
        if options[:query_filters]
          formatted_filters = options[:query_filters].collect {|k,v| "#{k.to_s}=#{v}" }.join('&')
          subtitles << "Query: #{formatted_filters}"
          # options[:query_filters].each do |k, v|
          #   subtitles << "#{k.to_s}: #{v}"
          # end
        end
        return subtitles
      end

      # Construct the request query parameters from the standard command options
      # This populates :params with a map of parameters.
      # This should replace the use of parse_query_options, parse_list_options and parse_list_options! and parse_get_options
      # which are used everywhere eg. params.merge!(parse_query_options(options))
      def parse_options(options, params={})
        params = params ? params.dup : {}
        # parse_list_options!(args, options, params)
        # merge in options set with -Q max=3, --query max=3&sort=id
        params.deep_merge!(options[:query_filters]) if options[:query_filters]
        # query parameters are stored in :params
        # preserve anything already set in :params by the OptionParser or command specific logic..
        options[:params] ||= {}
        options[:params].deep_merge!(params)
        # (JSON) body parameters (JSON) are stored in :payload
        # if options[:payload]
        # end
        # ok now call execute_request(@api_client.whoami, :get, nil, options)
        return options
      end

      # Parse payload(s) from the standard command options or else invoke the given block. 
      # First looks for --payload or --payload options and  if they are nil then the block is executed to establish the payload
      # By default this also merges all the values passed with -O, --options foo="bar" into payload under the object_key context.
      # and they are merged under the object_key context (if passed). This can be disabled with apply_options: false
      #
      # @param options [Hash] standard command options
      # @option options [Hash] :payload is a Hash of objects to serialize as the payload
      # @option options [Hash] :payloads is an array of payload objects@yield [street_name] Invokes the block with a street name for eac
      #                        This is silly and should go away, instead you should iterate in the terminal environment
      # @option options [Boolean] :apply_options can be set to false to skip -O options merge
      # @param object_key [String] The name of the object being constructed, -O --options will be merged under this context.
      # @return array of payloads
      # @yield [payload] Invokes the block to establish :payload (only when --payload(s) is not used)
      def parse_payload(options, object_key=nil, &block)
        # populate options[:params] here too
        parse_options(options)
        payloads = []
        # todo: only need to support a a single payload here, :payloads is silly and is going away
        if options[:payload]
          # --payload option was used
          payload = options[:payload]
          # support -O OPTION switch on top of --payload
          apply_options(payload, options, object_key) unless options[:apply_options] == false
          payloads << payload
        elsif options[:payloads]
          # --payloads option was used
          payloads = options[:payloads]
          # support -O OPTION switch on top of --payloads
          payloads.each do |payload|
            apply_options(payload, options, object_key) unless options[:apply_options] == false
          end
        #else
        # should always do this, but a lot of methods rely on this returning nil right now, not {}
        # so for now only do it if block is given
        elsif block_given?
          # yield to block to construct the payload, 
          # this is typically where prompting for inputs with optionTypes happens
          payload = {}
          apply_options(payload, options, object_key) unless options[:apply_options] == false
          if block_given?
            yield payload
          end
          payloads << payload
          options[:payload] = payload
        end
        return payloads.first
      end

      # support -O OPTION switch
      def apply_options(payload, options, object_key=nil)
        payload ||= {}
        if options[:options]
          # allow options[:object_key] to be used
          object_key = object_key ? object_key : options[:object_key]
          # could use parse_passed_options() here to support exclusion of certain options
          #passed_options = parse_passed_options(options, options[:apply_options] || {})
          passed_options = options[:options].reject {|k,v| k.is_a?(Symbol)}
          if options[:apply_options_exclude]
            passed_options = options[:options].reject {|k,v| options[:skip_apply_options].include?(k.to_s) || options[:skip_apply_options].include?(k.to_sym) }
          end
          if object_key
            payload.deep_merge!({object_key => passed_options})
          else
            payload.deep_merge!(passed_options)
          end
        end
        payload
      end

      # Executes the block with each payload (:payload or :payloads as parsed from --payload FILE and --payloads --PATH)
      # This is a wrapper to support execution on 1-N payloads 
      # It also looks for --ignore-payload-errors behavior to continue processing
      # It is up to the block to actually make the api request
      # @param options [Hash] standard command options
      # @raise [Error] if there is no :payload or :payloads defined.
      # @yield [payload] Yields each payload to the block
      # @return parsed command result of the last return value of the block ie. [0, nil]
      def handle_each_payload(options, &block)
        payloads = []
        if options[:payloads]
          payloads = options[:payloads]
        elsif options[:payload]
          payloads << options[:payload]
        else
          raise "handle_each_payload() requires :payload or :payloads"
        end
        if !payloads.is_a?(Array) || payloads.compact.empty?
          raise "handle_each_payload() requires a payload"
        end
        if !block_given?
          raise "handle_each_payload() requires a block to process the payload(s) with"
        end
        results = []
        payloads.each do |payload|
          begin
            result = yield payload
            results << Morpheus::Cli::CliRegistry.parse_command_result(result)
            #results << [0, nil]
          rescue => e
            if options[:payloads_ignore_error]
              # results << [1, e.message]
              result = Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) # lol
              results << result
              # continue
            else
              raise e
            end
          end
        end
        return results.last
      end

      # Standard handler for all commands that execute an api request.
      # This looks for a payload that can be set with --payload or --payloads or the default prompting
      # It is up to the block to handle the rendering behavior
      # @param api_interface [APIClient] An APIClient instance
      # @param api_method [String or Symbol] api method to invoke eg. :get, :create, :update, :destroy
      # @param args [Array] Array of arguments to be passed to the api method, usually just the [payload] or [payload, query_params]
      # @param options [Hash] options
      # @param object_key [String or Symbol] name of object being constructed, used by default rendering eg. --fields id,name
      # @yield [json_response] Invokes the block with the json response to handle rendering.
      # @return parsed command result of the last block.call(json_response)
      #
      # @example Fetch first 100 backups
      #   execute_api(@api_client.backups, :list, [{"max" => 100}], options) do |json_response|
      #     print_green_success "Fetched first #{json_response['backups'].size} of #{json_response['meta']['total']} backups"
      #   end
      #
      # @example Create a backup, uses POST with options[:payload] as the body
      #   @options[:payload] = {"backup" => { }}
      #   execute_api(@api_client.backups, :create, nil, options, 'backup') do |json_response|
      #     print_green_success "Added backup #{json_response['backup']['name']}"
      #   end
      #
      def execute_api(api_interface, api_method, args, options, object_key=nil, &block)
        args = args.is_a?(Array) ? args : [args].compact
        if options[:payload] || options[:payloads]
          execute_api_payload(api_interface, api_method, args, options, object_key, &block)
        else
          execute_api_request(api_interface, api_method, args, options, object_key, &block)
        end
      end

      # Standard handler for all POST commands that send a request for a payload
      # This supports the --payloads option for 1-N payloads, that is silly and will probably go away
      def execute_api_payload(api_interface, api_method, args, options, object_key=nil, &block)
        handle_each_payload(options) do |payload|
          execute_api_request(api_interface, api_method, (args || []) + [payload], options, object_key, &block)
        end
      end

      # Standard handler for executing any API request
      # Supports the --dry-run option and standard rendering options --json, --yaml, --fields, --select, etc.
      def execute_api_request(api_interface, api_method, args, options, object_key=nil, &block)
        args = args.is_a?(Array) ? args : [args].compact # allow caller to pass [payload] or payload
        api_interface.setopts(options) # this is needed to support --timeout and --headers
        # this assumes the interface parameter order is: [payload, params] and not vice versa
        if options[:params] && !options[:params].empty?
          args << options[:params]
        end
        if options[:dry_run]
          # this is a dry run
          dry_response = api_interface.dry.send(api_method, *args)
          print_dry_run(dry_response, options)
          return 0, nil
        else
          # execute the request and render the result
          json_response = api_interface.send(api_method, *args)
          return render_response(json_response, options, object_key, &block)
        end
      end

      # Parse an array from a string (csv)
      def parse_array(val, opts={})
        opts = {strip:true, allow_blank:false}.merge(opts)
        values = []
        if val.is_a?(Array)
          values = val
        else
          # parse csv and strip white space by default
          values = val.to_s.split(",")#.collect {|it| it.to_s.strip }
          if opts[:strip]
            values = values.collect {|it| it.to_s.strip }
          end
          if !opts[:allow_blank]
            values.reject! {|it| it.to_s.strip.empty? }
          end
        end
        values
      end

      def parse_labels(val)
        parse_array(val, {strip:true, allow_blank:false})
      end

      def validate_outfile(outfile, options)
        full_filename = File.expand_path(outfile)
        outdir = File.dirname(full_filename)
        if Dir.exist?(full_filename)
          print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
          return false
        end
        if !Dir.exist?(outdir)
          if options[:mkdir]
            print cyan,"Creating local directory #{outdir}",reset,"\n"
            FileUtils.mkdir_p(outdir)
          else
            print_red_alert "[local-file] is invalid. Directory not found: #{outdir}"
            return false
          end
        end
        if File.exist?(full_filename) && !options[:overwrite]
          print_red_alert "[local-file] is invalid. File already exists: #{outfile}\nUse -f to overwrite the existing file."
          return false
        end
        return true
      end

      # basic rendering for options :json, :yml, :csv, :quiet, and :outfile
      # returns the string rendered, or nil if nothing was rendered.
      def render_response(json_response, options, object_key=nil, &block)
        # allow options[:object_key] to be used
        object_key = object_key ? object_key : options[:object_key]
        output = nil
        if options[:select_fields]
          # support foos get --raw-select foo.x,foo.y,foo.z
          # and foos list --raw-select foos.x,foos.y,foos.z
          row = (object_key && !options[:raw_fields]) ? json_response[object_key] : json_response
          records = [row].flatten()
          # look for an array in the first field only now...
          field_parts = options[:select_fields][0].to_s.split(".")
          field_context = field_parts[0]
          context_data = json_response[field_context]
          if field_parts.size > 1 && context_data.is_a?(Array)
            # inject all the root level properties to be selectable too..
            context_data = json_response.delete(field_context)
            # records = context_data
            records = context_data.collect {|it| it.is_a?(Hash) ? json_response.merge(it) : json_response }
            options[:select_fields] = options[:select_fields].collect {|it| it.sub(field_context+'.', '')}
          end
          output = records.collect { |record| 
            options[:select_fields].collect { |field| 
              value = get_object_value(record, field)
              if value.is_a?(String)
                value
              else
                if options[:json]
                  as_json(value, options)
                elsif options[:yaml]
                  output = as_yaml(value, options)
                elsif options[:csv]
                  as_csv(value, nil, options)
                else
                  # default behavior
                  # value.is_a?(String) ? value : as_json(value, options)
                  do_pretty = options.key?(:pretty_json) ? options[:pretty_json] : false # or true?
                  do_pretty ? JSON.pretty_generate(value) : JSON.fast_generate(value)
                end
              end
            }.join(options[:delim] || ",")
          }.join(options[:newline] || "\n")
        elsif options[:json]
          output = as_json(json_response, options, object_key)
        elsif options[:yaml]
          output = as_yaml(json_response, options, object_key)
        elsif options[:csv]
          output = as_csv(json_response, nil, options, object_key)
        end
        if options[:outfile]
          full_outfile = File.expand_path(options[:outfile])
          if output
            print_to_file(output, options[:outfile], options[:overwrite])
            print "#{cyan}Wrote output to file #{options[:outfile]} (#{format_bytes(File.size(full_outfile))})\n" unless options[:quiet]
          else
            # uhhh ok lets try this
            Morpheus::Logging::DarkPrinter.puts "using experimental feature: --out without a common format like json, yml or csv" if Morpheus::Logging.debug?
            result = with_stdout_to_file(options[:outfile], options[:overwrite], 'w+', &block)
            if result && result != 0
              return result
            end
            print "#{cyan}Wrote output to file #{options[:outfile]} (#{format_bytes(File.size(full_outfile))})\n" unless options[:quiet]
            return 0, nil
          end
        else
          # --quiet means do not render, still want to print to outfile though
          if options[:quiet]
            return 0, nil
          end
          # render ouput generated above
          if output
            puts output
            return 0, nil
          else
            # no render happened, so calling the block if given
            if block_given?
              result = yield json_response
              if result
                return result
              else
                return 0, nil
              end
            else
              # nil means nothing was rendered, some methods still using render_with_format() are relying on this
              return nil
            end
          end
        end
      end

      alias :render_with_format :render_response

      # Dynamic find methods to load a record of any type
      # def find_by_name_or_id(type, val)
      #   interface = instance_variable_get "@#{type}s_interface"
      #   typeCamelCase = type.gsub(/(?:^|_)([a-z])/) do $1.upcase end
      #   typeCamelCase = typeCamelCase[0, 1].downcase + typeCamelCase[1..-1]
      #   (val.to_s =~ /\A\d{1,}\Z/) ? interface.get(val.to_i)[typeCamelCase] : interface.list({'name' => val})["#{typeCamelCase}s"].first
      # end

      # Find a resource by type and name or id
      # @param type [String of Symbol] Type of resource formatted as singular, lowerscore with underscores.
      # @param *id [String or Numeric] ID of resource, multiple arguments may be passed when using a secondary interface where parent_id, id is required.
      # Example: find_by_name_or_id("instance", "K2")
      #          find_by_name_or_id("storage_volume", 42)
      #          find_by_name_or_id("instance", "My Instance")
      #          find_by_name_or_id("load_balancer_pool", load_balancer_id, id)
      def find_by_name_or_id(*args)
        val = args.last
        if val.to_s =~ /\A\d{1,}\Z/
          return find_by_id(*args)
        else
          return find_by_name(*args)
        end
      end

      
      # Find a resource by type and id
      # Usage: find_by_name_or_id("app", 3)
      def find_by_id(*args)
        #Morpheus::Logging::DarkPrinter.puts "find_by_id(#{args.join(', ')})" if Morpheus::Logging.debug?
        # type, ids = args.first, args[1..-1]
        type, *ids = args
        type = type.to_s.singularize.underscore
        # still relying on the command or helper to define these _label and _key methods
        # label = send("#{type}_label")
        # object_key = send("#{type}_object_key")
        # ^ nope, not for long!
        object_key = respond_to?("#{type}_object_key", true) ? send("#{type}_object_key") : type.camelcase.singularize
        label = respond_to?("#{type}_label", true) ? send("#{type}_label") : type.titleize
        interface_name = "@#{type.pluralize}_interface"
        interface = instance_variable_get(interface_name)
        if interface.nil?
          api_client = instance_variable_get("@api_client")
          if api_client
            if api_client.respond_to?(type.pluralize)
              interface = api_client.send(type.pluralize)
            else
              raise "@api_client.#{type.pluralize} is not a recognized interface"
            end
          else
            raise "#{self.class} has not defined interface #{interface_name} or @api_client"
          end
        end
        begin
          json_response = interface.get(*ids)
          if !json_response.key?(object_key)
            # maybe just use the first key like this:
            # object_key = json_response.keys.find { |k| json_response[k].is_a?(Hash) }
            #puts_error(json_response) if Morpheus::Logging.debug?
            raise "API response is missing object property '#{object_key}'"
          end
          record = json_response[object_key]
          if record.nil?
            print_red_alert "#{label} not found in API response (#{object_key})"
            return nil
          else
            return json_response[object_key]
          end
        rescue ::RestClient::Exception => e
          if e.response && e.response.code == 404
            print_red_alert "#{label} not found by id #{ids.last}"
            return nil
          else
            raise e
          end
        end
      end

      # Find a record by type and name
      # Usage: find_by_name_or_id("network", "Skynet")
      def find_by_name(*args)
        #Morpheus::Logging::DarkPrinter.puts "find_by_name(#{args.join(', ')})" if Morpheus::Logging.debug?
        # type, ids = args.first, args[1..-1]
        type, *ids = args
        type = type.to_s.singularize.underscore
        val = ids.pop
        params = {}
        name_property = 'name'
        if type == 'user'
          name_property = 'username'
          params['global'] = 'true'
        end
        params[name_property] = val.to_s
        request_args = ids + [params]
        request_args.unshift(type)
        records = find_all(*request_args)
        # still relying on the command or helper to define these _label and _key methods
        label = respond_to?("#{type}_label", true) ? send("#{type}_label") : type.titleize
        if records.empty?
          print_red_alert "#{label} not found by name '#{val}'"
          return nil
        elsif records.size > 1
          print_red_alert "More than one #{label.downcase} found by #{name_property} '#{val}'"
          print_error "\n"
          if type == "user"
            puts_error as_pretty_table(records, [:id, :username, {"FIRST NAME" => "firstName"}, {"LAST NAME" => "lastName"}, {"TENANT" => lambda {|it| it['account']['name'] rescue ''}}], {color:red})
          else
            puts_error as_pretty_table(records, [:id, :name], {color:red})
          end
          print_red_alert "Try using ID instead"
          print_error reset,"\n"
          return nil
        else
          return records[0]
        end
      end

      # Load a list of records by type
      # @example Find an app by id
      # find_record(:app, 1)
      # report_types = find_all("reportTypes", {phrase:"amazon"})
      # pools = find_all("loadBalancerPool", load_balancer_id)
      # @return Array of records
      def find_all(*args)
        #Morpheus::Logging::DarkPrinter.puts "find_all(#{args.join(', ')})" if Morpheus::Logging.debug?
        type, *request_args = args
        type = type.to_s.singularize.underscore
        list_key = respond_to?("#{type}_list_key", true) ? send("#{type}_list_key") : get_list_key(type)
        json_response = find_all_json(*args)
        if !json_response.key?(list_key)
          # maybe just use the first key like this:
          # list_key = json_response.keys.find { |k| json_response[k].is_a?(Array) }
          # puts_error(json_response) if Morpheus::Logging.debug?
          raise "API response is missing list property '#{list_key}'"
        end
        return json_response[list_key]
      end

      # Load json response for a list of records by type
      # @return Hash of JSON data
      def find_all_json(*args)
        type, *request_args = args
        get_interface(type).list(*request_args)
      end

      alias :find_all_records :find_all
      alias :find_all_records_json :find_all_json

      # Load a single record (Hash) by type and id and optional parameters
      # Examples:
      # apps = find_record(:app)
      # report_types = find_record("reportTypes", {phrase:"amazon"})
      # pools = find_record("loadBalancerPool", balancer_id)
      # @return [Hash] of the object that was found or raises an exception if 404 not found encountered.
      def find_record(*args)
        #Morpheus::Logging::DarkPrinter.puts "find_record(#{args.join(', ')})" if Morpheus::Logging.debug?
        type, *request_args = args
        type = type.to_s.singularize.underscore
        object_key = respond_to?("#{type}_object_key", true) ? send("#{type}_object_key") : get_object_key(type)
        json_response = find_record_json(*args)
        if !json_response.key?(object_key)
          # maybe just use the first key like this:
          # object_key = json_response.keys.find { |k| json_response[k].is_a?(Hash) }
          # puts_error(json_response) if Morpheus::Logging.debug?
          raise "API response is missing object property '#{object_key}'"
        end
        return json_response[object_key]
      end

      # Load list of records by type and (optional) parameters
      # Examples:
      # apps = find_record(:app, 1)
      # report_types = find_record("reportType", 1)
      # pools = find_all("loadBalancerPool", load_balancer_id)
      def find_record_json(*args)
        #Morpheus::Logging::DarkPrinter.puts "find_record_json(#{args.join(', ')})" if Morpheus::Logging.debug?
        type, *request_args = args
        get_interface(type).get(*request_args)
      end

       # Load json response for a list of records by type
      def get_interface(type)
        #Morpheus::Logging::DarkPrinter.puts "get_interface(#{type})" if Morpheus::Logging.debug?
        # todo: can probably just do @api_client ? @api_client.interface(interface_name) : nil
        type = type.to_s.singularize.underscore
        interface_name = "@#{type.pluralize}_interface"
        interface = nil
        if instance_variable_defined?(interface_name)
          interface = instance_variable_get(interface_name)
          if interface.nil?
            # Fix is to update connect() to do @apps_interface = @api_client.apps
            raise "API Interface #{interface_name} is nil"
          end
        else
          if @api_client.is_a?(Morpheus::APIClient)
            interface = @api_client.interface(type.pluralize)
          else
            raise "#{self.class} has not initalized @api_client"
          end
        end
        return interface
      end

      def get_list_key(type)
        return get_object_key(type).pluralize
      end

      def get_object_key(type)
        key = type.camelcase.singularize
        # add aliases here as needed
        if key == "cloud"
          key = "zone"
        elsif key == "site"
          key = "group"
        elsif key == "backupJob"
          key = "job"
        elsif key == "backupResult"
          key = "result"
        elsif key == "backupRestore"
          key = "restore"
        end
        return key
      end

      module ClassMethods

        # attr_writer :command_name, :command_description, :hidden_command, :default_refresh_interval,
        #             :subcommands, :hidden_subcommands, :default_subcommand, :subcommand_aliases, :subcommand_descriptions

        def prog_name
          "morpheus"
        end

        def set_command_name(cmd_name)
          @command_name = cmd_name.to_sym
          Morpheus::Cli::CliRegistry.add(self, self.command_name)
        end

        def default_command_name
          class_name = self.name.split('::')[-1]
          #class_name.sub!(/Command$/, '')
          Morpheus::Cli::CliRegistry.cli_ize(class_name).to_sym
        end
        
        def command_name
          @command_name ||= default_command_name
          @command_name
        end

        def set_command_hidden(val=true)
          @hidden_command = val
        end
        # alias :command_name= :set_command_name

        def hidden_command
          defined?(@hidden_command) && @hidden_command == true
        end

        def hidden_subcommands
          @hidden_subcommands ||= []
        end

        def set_subcommands_hidden(*cmds)
          @hidden_subcommands ||= []
          cmds.flatten.each do |cmd|
            @hidden_subcommands << cmd.to_sym
          end
          @hidden_subcommands
        end

        def command_description
          @command_description ||= ""
        end

        def set_command_description(val)
          @command_description = val
        end
        # alias :command_description= :set_command_description

        def default_refresh_interval
          @default_refresh_interval ||= 30
        end

        def set_default_refresh_interval(seconds)
          @default_refresh_interval = seconds
        end
        #alias :default_refresh_interval= :set_default_refresh_interval
        

        # construct map of command name => instance method
        def register_subcommands(*cmds)
          @subcommands ||= {}
          cmds.flatten.each {|cmd| 
            if cmd.is_a?(Hash)
              cmd.each {|k,v| 
                # @subcommands[k] = v
                add_subcommand(k.to_s, v.to_s)
              }
            elsif cmd.is_a?(Array) 
              cmd.each {|it| register_subcommands(it) }
            elsif cmd.is_a?(String) || cmd.is_a?(Symbol)
              #k = Morpheus::Cli::CliRegistry.cli_ize(cmd)
              k = cmd.to_s.gsub('_', '-')
              v = cmd.to_s.gsub('-', '_')
              register_subcommands({(k) => v})
            else
              raise Morpheus::Cli::CliRegistry::BadCommandDefinition.new("Unable to register command of type: #{cmd.class} #{cmd}")
            end
          }
          return
        end

        # this might be the new hotness
        # register_subcommand(:show) # do not do this, always define a description!
        # register_subcommand(:list, "List things")
        # register_subcommand("update-all", "update_all", "Update all things")
        # If the command name =~ method, no need to pass both
        # command names will have "-" swapped in for "_" and vice versa for method names.
        def register_subcommand(*args)
          args = args.flatten
          cmd_name = args[0]
          cmd_method = nil
          cmd_desc = nil
          if args.count == 1
            cmd_method = cmd_name
          elsif args.count == 2
            if args[1].is_a?(Symbol)
              cmd_method = args[1]
            else
              cmd_method = cmd_name
              cmd_desc = args[1]
            end
          elsif args.count == 3
            cmd_method = args[1]
            cmd_desc = args[2]
          else
            raise Morpheus::Cli::CliRegistry::BadCommandDefinition.new("register_subcommand expects 1-3 arguments, got #{args.size} #{args.inspect}")
          end
          cmd_name = cmd_name.to_s.gsub("_", "-").to_sym
          cmd_method = (cmd_method || cmd_name).to_s.gsub("-", "_").to_sym
          cmd_definition = {(cmd_name) => cmd_method}
          register_subcommands(cmd_definition)
          add_subcommand_description(cmd_name, cmd_desc)
          return
        end

        def set_default_subcommand(cmd)
          @default_subcommand = cmd
        end

        def default_subcommand
          @default_subcommand
        end

        def subcommands
          @subcommands ||= {}
        end

        def visible_subcommands
          cmds = subcommands.clone
          hidden_subcommands.each do |hidden_cmd|
            cmds.delete(hidden_cmd.to_s.gsub('_', '-'))
          end
          cmds
        end

        def has_subcommand?(cmd_name)
          return false if cmd_name.empty?
          @subcommands && @subcommands[cmd_name.to_s]
        end

        def add_subcommand(cmd_name, method)
          @subcommands ||= {}
          @subcommands[cmd_name.to_s] = method
        end

        def remove_subcommand(cmd_name)
          @subcommands ||= {}
          @subcommands.delete(cmd_name.to_s)
        end

        # register an alias for a command
        def alias_subcommand(alias_cmd_name, cmd_name)
          add_subcommand_alias(alias_cmd_name.to_s, cmd_name.to_s.gsub('_', '-'))
          return
        end

        def subcommand_aliases
          @subcommand_aliases ||= {}
        end

        def add_subcommand_alias(alias_cmd_name, cmd_name)
          @subcommand_aliases ||= {}
          @subcommand_aliases[alias_cmd_name.to_s] = cmd_name
        end

        def remove_subcommand_alias(alias_cmd_name)
          @subcommand_aliases ||= {}
          @subcommand_aliases.delete(alias_cmd_name.to_s)
        end

        def subcommand_descriptions
          @subcommand_descriptions ||= {}
        end

        def add_subcommand_description(cmd_name, description)
          @subcommand_descriptions ||= {}
          @subcommand_descriptions[cmd_name.to_s.gsub('_', '-')] = description
        end

        def get_subcommand_description(cmd_name)
          desc = subcommand_descriptions[cmd_name.to_s.gsub('_', '-')]
          if desc
            return desc
          else
            cmd_method = subcommands.key(cmd_name)
            return cmd_method ? subcommand_descriptions[cmd_method.to_s.gsub('_', '-')] : nil
          end
        end

        def set_subcommand_descriptions(cmd_map)
          cmd_map.each do |cmd_name, description|
            add_subcommand_description(cmd_name, description)
          end
        end

      end
    end
  end
end
