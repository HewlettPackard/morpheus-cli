require 'term/ansicolor'
require 'readline'
module Morpheus
  module Cli
    module OptionTypes
      include Term::ANSIColor


      def self.confirm(message,options={})
        if options[:yes] == true
          return true
        end
        default_value = options[:default]
        value_found = false
        while value_found == false do
          if default_value.nil?
            print "#{message} (yes/no): "
          else
            print "#{message} (yes/no) [#{!!default_value ? 'yes' : 'no'}]: "
          end
          input = $stdin.gets.chomp!
          if input.empty? && !default_value.nil?
            return !!default_value
          end
          if input.downcase == 'yes' || input.downcase == 'y'
            return true
          elsif input.downcase == 'no' || input.downcase == 'n'
            return false
          else
            puts "Invalid Option... Please try again."
          end
        end
      end

      def self.no_prompt(option_types, options={}, api_client=nil,api_params={})
        prompt(option_types, options, api_client, api_params, true)
      end

      def self.prompt(option_types, options={}, api_client=nil,api_params={}, no_prompt=false)
        results = {}
        options = options || {}
        # puts "Options Prompt #{options}"
        option_types.sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |option_type|
          context_map = results
          value = nil
          value_found=false
          if option_type['fieldContext']
            cur_namespace = options
            namespaces = option_type['fieldContext'].split(".")
            namespaces.each do |ns|
              next if ns.empty?
              cur_namespace[ns.to_s] ||= {}
              cur_namespace = cur_namespace[ns.to_s]
              context_map[ns.to_s] ||= {}
              context_map = context_map[ns.to_s]
            end
            # use the value passed in the options map
            if cur_namespace.key?(option_type['fieldName'])
              value = cur_namespace[option_type['fieldName']]
              if option_type['type'] == 'number'
                value = value.to_s.include?('.') ? value.to_f : value.to_i
              elsif option_type['type'] == 'select'
                # this should just fall down through below, with the extra params no_prompt, use_value
                value = select_prompt(option_type, api_client, api_params, true, value)
              end
              value_found = true
            end
          else
            # no fieldContext
            if value_found == false && options.key?(option_type['fieldName'])
              value = options[option_type['fieldName']]
              if option_type['type'] == 'number'
                value = value.to_s.include?('.') ? value.to_f : value.to_i
              end
              value_found = true
            end
          end

          # no_prompt means skip prompting and instead
          # use default value or error if a required option is not present
          no_prompt = no_prompt || options[:no_prompt]
          if no_prompt
            if !value_found
              if option_type['defaultValue'] != nil
                value = option_type['defaultValue']
                value_found = true
              end
              if !value_found
                # select type is special because it supports skipSingleOption
                # and prints the available options on error
                if option_type['type'] == 'select'
                  value = select_prompt(option_type, api_client, api_params, true)
                  value_found = !!value
                end
                if !value_found
                  if option_type['required']
                    print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
                    print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - #{option_type['description']}\n", Term::ANSIColor.reset
                    print "\n"
                    exit 1
                  else
                    next
                  end
                end
              end
            end
          end

          if !value_found
            if option_type['type'] == 'number'
              value = number_prompt(option_type)
            elsif option_type['type'] == 'password'
              value = password_prompt(option_type)
            elsif option_type['type'] == 'checkbox'
              value = checkbox_prompt(option_type)
            elsif option_type['type'] == 'radio'
              value = radio_prompt(option_type)
            elsif option_type['type'] == 'textarea'
              value = multiline_prompt(option_type)
            elsif option_type['type'] == 'code-editor'
              value = multiline_prompt(option_type)
            elsif option_type['type'] == 'select'
              # so, the /api/options/source is may need ALL the previously
              # selected values that are being accumulated in options
              # api_params is just extra params to always send
              # I suppose the entered value should take precedence
              # api_params = api_params.merge(options) # this might be good enough
              # dup it
              select_api_params = {}.merge(api_params || {})
              results.each do |k,v|
                if v.is_a?(Hash)
                  # grailsify params k.k2, otherwise you'll get bracked param names like k[k2]
                  v.each {|k2, v2| 
                    select_api_params["#{k}.#{k2}"] = v2
                  }
                else
                  # could be String/Symbol duplication issues here.
                  select_api_params.delete(k.to_sym)
                  select_api_params[k.to_s] = v
                end
              end
            value = select_prompt(option_type,api_client, select_api_params)
          elsif option_type['type'] == 'hidden'
            value = option_type['defaultValue']
            input = value
          elsif option_type['type'] == 'file'
            value = file_prompt(option_type)
          else
            value = generic_prompt(option_type)
          end
        end
        context_map[option_type['fieldName']] = value
      end

      return results
    end


    def self.radio_prompt(option_type)
      value_found = false
      value = nil
      options = []
      if option_type['config'] and option_type['config']['radioOptions']
        option_type['config']['radioOptions'].each do |radio_option|
          options << {key: radio_option['key'], checked: radio_option['checked']}
        end
      end
      optionString = options.collect{ |b| b[:checked] ? "(#{b[:key]})" : b[:key]}.join(', ')
      while !value_found do
        print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }[#{optionString}]: "
        input = $stdin.gets.chomp!
        if input == '?'
          help_prompt(option_type)
        else
          if input.nil? || input.empty?
            selectedOption = options.find{|o| o[:checked] == true}
          else
            selectedOption = options.find{|o| o[:key].downcase == input.downcase}
          end
          if selectedOption
            value = selectedOption[:key]
          else
            puts "Invalid Option. Please select from #{optionString}."
          end
          if !value.nil? || option_type['required'] != true
            value_found = true
          end
        end
      end
      return value
    end

      def self.number_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input
          value = value.to_s.include?('.') ? value.to_f : value.to_i
          if input == '?'
            help_prompt(option_type)
          elsif !value.nil? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end

      def self.select_prompt(option_type,api_client, api_params={}, no_prompt=false, use_value=nil)
        value_found = false
        value = nil
        # local array of options
        if option_type['selectOptions']
          select_options = option_type['selectOptions']
        # remote optionSource aka /api/options/$optionSource?
        elsif option_type['optionSource']
          # /api/options/list is a special action for custom OptionTypeLists, just need to pass the optionTypeId parameter
          if option_type['optionSource'] == 'list'
            select_options = load_source_options(option_type['optionSource'], api_client, {'optionTypeId' => option_type['id']})
          else
            select_options = load_source_options(option_type['optionSource'], api_client, api_params)
          end          
        else
          raise "select_prompt() requires selectOptions or optionSource!"
        end
        # ensure the preselected value (passed as an option) is in the dropdown
        if !use_value.nil?
          matched_value = select_options.find {|opt| opt['value'].to_s == use_value.to_s }
          if !matched_value.nil?
            value = use_value
            value_found = true
          else
            print Term::ANSIColor.red, "\nInvalid Option #{option_type['fieldLabel']}: [#{use_value}]\n\n", Term::ANSIColor.reset
            print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - #{option_type['description']}\n", Term::ANSIColor.reset
            display_select_options(select_options)
            print "\n"
            exit 1
          end
        elsif !select_options.nil? && select_options.count == 1 && option_type['skipSingleOption'] == true
          value_found = true
          value = select_options[0]['value']
        end

        if no_prompt
          if !value_found
            if option_type['required']
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - #{option_type['description']}\n", Term::ANSIColor.reset
              display_select_options(select_options)
              print "\n"
              exit 1
            else
              return nil
            end
          end
        end
        while !value_found do
          Readline.completion_append_character = ""
          Readline.basic_word_break_characters = ''
          Readline.completion_proc = proc {|s| select_options.clone.collect{|opt| opt['name']}.grep(/^#{Regexp.escape(s)}/)}
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''} ['?' for options]: ", false).to_s
          input = input.chomp.strip
          if input.empty?
            value = option_type['defaultValue']
          else
            select_option = select_options.find{|b| b['name'] == input || (!b['value'].nil? && b['value'].to_s == input) || (b['value'].nil? && input.empty?)}
            if select_option
              value = select_option['value']
            elsif !input.nil?  && !input.empty?
              input = '?'
            end
          end
          if input == '?'
            help_prompt(option_type)
            display_select_options(select_options)
          elsif !value.nil? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end

      # this is a funky one, the user is prompted for yes/no
      # but the return value is 'on','off',nil
      # todo: maybe make this easier to use, and have the api's be flexible too..
      # @param option_type [Hash] option type object with type,fieldName,fieldLabel,etc..
      # @return 'on', 'off' or nil
      def self.checkbox_prompt(option_type)
        value_found = false
        value = nil
        has_default = option_type['defaultValue'] != nil
        default_yes = has_default ? ['on', 'true', 'yes', '1'].include?(option_type['defaultValue'].to_s.downcase) : false
        while !value_found do
          print "#{option_type['fieldLabel']} (yes/no)#{has_default ? ' ['+(default_yes ? 'yes' : 'no')+']' : ''}: "
          input = $stdin.gets.chomp!
          if input == '?'
            help_prompt(option_type)
            next
          end
          if input.downcase == 'yes'
            value_found = true
            value = 'on'
          elsif input.downcase == 'no'
            value_found = true
            value = 'off'
          elsif input == '' && has_default
            value_found = true
            value = default_yes ? 'on' : 'off'
          end
          if value.nil? && option_type['required']
            puts "Invalid Option... Please try again."
            next
          end
          if value.nil? && !option_type['required']
            value_found = true
          end
        end
        return value
      end

      def self.generic_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input
          if input == '?'
            help_prompt(option_type)
          elsif !value.nil? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end

      def self.multiline_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          if value.nil?
            print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''} [Type 'EOF' to stop input]: \n"
          end
          input = $stdin.gets.chomp!
          # value = input.empty? ? option_type['defaultValue'] : input
          if input == '?' && value.nil?
            help_prompt(option_type)
          elsif (!value.nil? || option_type['required'] != true) && input.chomp == 'EOF'
            value_found = true
          else
            if value.nil?
              value = ''
            end
            value << input + "\n"
          end
        end
        return value
      end

      def self.password_prompt(option_type)
        value_found = false
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}: "
          input = $stdin.noecho(&:gets).chomp!
          value = input
          print "\n"
          if input == '?'
            help_prompt(option_type)
          elsif !value.empty? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end

      def self.file_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          Readline.completion_append_character = ""
          Readline.basic_word_break_characters = ''
          Readline.completion_proc = proc {|s| Readline::FILENAME_COMPLETION_PROC.call(s) }
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''} ['?' for options]: ", false).to_s
          input = input.chomp.strip
          #input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input.to_s
          if input == '?'
            help_prompt(option_type)
          elsif value.empty? && option_type['required'] != true
            value = nil
            value_found = true
          elsif value
            filename = File.expand_path(value)
            if !File.exists?(filename)
              # print_red_alert "File not found: #{filename}"
              # exit 1
              print Term::ANSIColor.red,"  File not found: #{filename}",Term::ANSIColor.reset, "\n"
            elsif !File.file?(filename)
              print Term::ANSIColor.red,"  Argument is not a file: #{filename}",Term::ANSIColor.reset, "\n"
            else
              value = filename
              value_found = true
            end
          end
        end
        return value
      end

      def self.help_prompt(option_type)
        print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - ", Term::ANSIColor.reset , "#{option_type['description']}\n"
      end


      def self.load_source_options(source,api_client,params)
        api_client.options.options_for_source(source,params)['data']
      end

      def self.display_select_options(select_options = [])
        puts "\nOptions"
        puts "==============="
        select_options.each do |option|
          puts " * #{option['name']} [#{option['value']}]"
        end
      end

      def self.format_option_types_help(option_types)
        if option_types.empty?
          "Available Options:\nNone\n\n"
        else
          option_lines = option_types.collect {|it| "    -O #{it['fieldName']}=\"value\"" }.join("\n")
          "Available Options:\n#{option_lines}\n\n"
        end
      end
        
      def self.display_option_types_help(option_types)
        puts self.format_option_types_help(option_types)
      end

    end
  end
end
