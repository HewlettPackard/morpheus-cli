require 'uri'
require 'term/ansicolor'
require 'json'
require 'yaml'
require 'ostruct'
require 'io/console'
require 'morpheus/logging'
require 'fileutils'
require 'filesize'

module Morpheus::Cli::PrintHelper

  def self.included(klass)
    klass.send :include, Term::ANSIColor
  end

  def self.terminal_width
    @@terminal_width ||= 80
  end

  def self.terminal_width=(v)
    if v.nil? || v.to_i == 0
      @@terminal_width = nil
    else
      @@terminal_width = v.to_i
    end
    @@terminal_width
  end

  # for consistancy, maybe..
  unless defined?(ALL_LABELS_UPCASE)
    ALL_LABELS_UPCASE = false
  end

  def current_terminal_width
    return IO.console.winsize[1] rescue 0
  end

  # puts red message to stderr
  # why this not stderr yet?  use print_error or if respond_to?(:my_terminal)
  def print_red_alert(msg)
    $stderr.print "#{red}#{msg}#{reset}\n"
    #print_error "#{red}#{msg}#{reset}\n"
    #puts_error "#{red}#{msg}#{reset}"
  end

  # puts green message to stdout
  def print_green_success(msg=nil)
    if msg.nil?
      msg = "success"
    end
    print "#{green}#{msg}#{reset}\n"
  end

  # print_h1 prints a header title and optional subtitles
  # Output:
  #
  # title - subtitle1, subtitle2
  # ==================
  #
  def print_h1(title, subtitles=nil, options=nil, suffix_content="\n")
    # ok, support all these formats for now:
    # print_h1(title, options={})
    # print_h1(title, subtitles, options={})
    # this can go away when we have a dirty @current_options
    
    
    # auto include remote name in h1 titles
    # eg. Morpheus Instances [dev]
    # if title && @appliance_name
    #   title = "#{title} [#{@appliance_name}]"
    # end
    
    if subtitles.is_a?(Hash)
      options = subtitles
      subtitles = (options[:subtitles] || []).flatten
    end
    if subtitles.is_a?(String)
      subtitles = [subtitles]
    end
    subtitles = (subtitles || []).flatten
    options ||= {}
    color = options[:color] || cyan
    out = ""
    out << "\n"
    out << "#{color}#{bold}#{title}#{reset}"
    if !subtitles.empty?
      out << "#{color} | #{subtitles.join(', ')}#{reset}"
    end
    out << "\n"
    if options[:border_style] == :thin

    else
      out << "#{color}#{bold}==================#{reset}\n"
    end
    # Default suffix_content is typically one extra newline
    if !suffix_content.to_s.empty?
      out << suffix_content.to_s
    end
    print out
  end

  def print_h2(title, subtitles=nil, options=nil, suffix_content="\n")
    # ok, support all these formats for now:
    # print_h2(title={})
    # print_h2(title, options={})
    # print_h2(title, subtitles, options={})
    # this can go away when we have a dirty @current_options
    if subtitles.is_a?(Hash)
      options = subtitles
      subtitles = (options[:subtitles] || []).flatten
    end
    subtitles = (subtitles || []).flatten
    options ||= {}
    color = options[:color] || cyan
    out = ""
    out << "\n"
    out << "#{color}#{bold}#{title}#{reset}"
    if !subtitles.empty?
      out << "#{color} - #{subtitles.join(', ')}#{reset}"
    end
    out << "\n"
    if options[:border_style] == :thin

    else
      out << "#{color}---------------------#{reset}\n"
    end
    # Default suffix_content is typically one extra newline
    if !suffix_content.to_s.empty?
      out << suffix_content.to_s
    end
    print out
  end

  def print_rest_exception(e, options={})
    if respond_to?(:my_terminal)
      Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).print_rest_exception(e, options)
    else
      Morpheus::Cli::ErrorHandler.new.print_rest_exception(e, options)
    end
  end

  def print_rest_errors(errors, options={})
    if respond_to?(:my_terminal)
      Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).print_rest_errors(errors, options)
    else
      Morpheus::Cli::ErrorHandler.new.print_rest_errors(errors, options)
    end
  end

  def parse_rest_exception(e, options={})
    data = {}
    begin
      data = JSON.parse(e.response.to_s)
    rescue
      # Morpheus::Logging::DarkPrinter.puts "Failed to parse error response as JSON: #{ex}" if Morpheus::Logging.debug?
    end
    return data
  end
  
  def print_dry_run(api_request, options={})
    # 2nd argument used to be command_string (String)
    command_string = nil
    if options.is_a?(String)
      command_string = options
      options = {}
    end
    options ||= {}
    # api client injects common command options here
    if api_request[:command_options]
      options = options.merge(api_request[:command_options])
    end
    options ||= {}
    # parse params request arguments
    http_method = api_request[:method]
    url = api_request[:url]
    headers = api_request[:headers]
    params = nil
    if api_request[:params] && !api_request[:params].empty?
      params = api_request[:params]
    elsif headers && headers[:params]
      # params inside headers for restclient reasons..
      params = headers[:params]
    elsif api_request[:query] && !api_request[:query].empty?
      params = api_request[:query]
    end
    query_string = params
    if query_string.respond_to?(:map)
      query_string = URI.encode_www_form(query_string)
    end
    if query_string && !query_string.empty?
      url = "#{url}?#{query_string}"
    end
    request_string = "#{http_method.to_s.upcase} #{url}".strip
    payload = api_request[:payload] || api_request[:body]
    #Morpheus::Logging::DarkPrinter.puts "API payload is: (#{payload.class}) #{payload.inspect}"
    content_type = (headers && headers['Content-Type']) ? headers['Content-Type'] : 'application/x-www-form-urlencoded'
    # build output, either CURL or REQUEST
    output = ""
    if api_request[:curl] || options[:curl]
      output = format_curl_command(http_method, url, headers, payload, options)
    elsif options[:json]
      # --dry --json should print the payload only
      payload_object = payload.is_a?(String) ? JSON.parse(payload) : payload
      output = as_json(payload_object, options)
    elsif options[:yaml]
      # --dry --yaml should print the payload only as yaml
      payload_object = payload.is_a?(String) ? JSON.parse(payload) : payload
      output = as_yaml(payload_object, options)
    else
      # default format is 
      # DRY RUN
      # REQUEST
      # GET https://server/api/things
      #
      # JSON
      # {
      #    "thing": { ... }
      # }
      output = format_api_request(http_method, url, headers, payload, options)
    end
    # this is an extra scrub, should remove
    if options[:scrub]
      output = Morpheus::Logging.scrub_message(output)
    end
    # write to a file?
    if options[:outfile]
      print_result = print_to_file(output, options[:outfile], options[:overwrite])
      # with_stdout_to_file(options[:outfile], options[:overwrite]) { print output }
      print "#{cyan}Wrote output to file #{options[:outfile]} (#{format_bytes(File.size(options[:outfile]))})\n" unless options[:quiet]
      #return print_result
      return
    end
    # print output
    if api_request[:curl] || options[:curl]
      print "\n"
      print "#{cyan}#{bold}#{dark}CURL COMMAND#{reset}\n"
      print output
      print reset, "\n"
      print reset
    elsif options[:json] || options[:yaml]
      # print just the just payload
      print output, "\n"
    else
      print "\n"
      print "#{cyan}#{bold}#{dark}REQUEST#{reset}\n"
      print output
      print reset, "\n"
      print reset
    end
    return output
  end

  def print_system_command_dry_run(cmd, options={})
    print "\n"
    print "#{cyan}#{bold}#{dark}SYSTEM COMMAND#{reset}\n"
    print cmd
    print reset, "\n"
    return
  end

  def format_api_request(http_method, url, headers, payload=nil, options={})
    out = ""
    # out << "\n"
    # out << "#{cyan}#{bold}#{dark}REQUEST#{reset}\n"
    request_string = "#{http_method.to_s.upcase} #{url}".strip
    out << request_string + "\n"
    out << cyan
    if payload
      out << "\n"
      is_multipart = (payload.is_a?(Hash) && payload[:multipart] == true)
      content_type = (headers && headers['Content-Type']) ? headers['Content-Type'] : (is_multipart ? 'multipart/form-data' : 'application/x-www-form-urlencoded')
      if content_type == 'application/json'
        if payload.is_a?(String)
          begin
            payload = JSON.parse(payload)
          rescue => e
            #payload = "(unparsable) #{payload}"
          end
        end
        out << "#{cyan}#{bold}#{dark}JSON#{reset}\n"
        if options[:scrub]
          out << Morpheus::Logging.scrub_message(JSON.pretty_generate(payload))
        else
          out << JSON.pretty_generate(payload)
        end
      else
        out << "Content-Type: #{content_type}" + "\n"
        out << reset
        if payload.is_a?(File)
          #pretty_size = "#{payload.size} B"
          pretty_size = format_bytes(payload.size)
          out << "File: #{payload.path} (#{pretty_size})"
        elsif payload.is_a?(String)
          if options[:scrub]
            out << Morpheus::Logging.scrub_message(payload)
          else
            out << payload
          end
        else
          if content_type == 'application/x-www-form-urlencoded' || content_type.to_s.include?('multipart')
            body_str = payload.to_s
            begin
              payload.delete(:multipart) if payload.is_a?(Hash)
              # puts "grailsifying it!"
              payload = Morpheus::RestClient.grails_params(payload)
              payload.each do |k,v|
                if v.is_a?(File)
                  payload[k] = "@#{v.path}"
                  payload[k] = v.path
                end
              end
              body_str = URI.encode_www_form(payload)
            rescue => ex
              raise ex
            end
            if options[:scrub]
              out << Morpheus::Logging.scrub_message(body_str)
            else
              out << body_str
            end
          else
            if options[:scrub]
              out << Morpheus::Logging.scrub_message(payload)
            else
              out << payload.to_s
            end
          end
        end
      end
      out << "\n"
    end
    # out << "\n"
    out << reset
    return out
  end

  # format_curl_command generates a valid curl command for the given api request
  # @param api_request [Hash] api request, typically returned from api_client.dry.execute()
  # @param options [Hash] common cli options
  # formats command like:
  #
  # curl -XPOST "https://api.gomorpheus.com/api/cypher" \
  #   -H "Authorization: BEARER ******************" \
  #   -H "Content-Type: application/json" \
  #   -d '{
  #     "value": "mysecret"
  #   }'
  def format_curl_command(http_method, url, headers, payload=nil, options={})
    options ||= {}
    # build curl [options]
    out = ""
    out << "curl -X#{http_method.to_s.upcase} \"#{url}\""
    if headers
      headers.each do |k,v|
        # avoid weird [:headers][:params]
        unless k == :params
          header_value = v
          out <<  ' \\' + "\n"
          header_line = "  -H \"#{k.is_a?(Symbol) ? k.to_s.capitalize : k.to_s}: #{v}\""
          out << header_line
        end
      end
    end
    if payload #&& !payload.empty?
      out <<  + ' \\' + "\n"
      if headers && headers['Content-Type'] == 'application/json'
        if payload.is_a?(String)
          begin
            payload = JSON.parse(payload)
          rescue => e
            #payload = "(unparsable) #{payload}"
          end
        end
        if payload.is_a?(Hash)
          out << "  -d '#{as_json(payload, options)}'"
        else
          out << "  -d '#{payload}'"
        end
        out << "\n"
      else
        is_multipart = (payload.is_a?(Hash) && payload[:multipart] == true)
        content_type = headers['Content-Type'] || 'application/x-www-form-urlencoded'
        
        if payload.is_a?(File)
          # pretty_size = Filesize.from("#{payload.size} B").pretty.strip
          pretty_size = "#{payload.size} B"
          # print "File: #{payload.path} (#{payload.size} bytes)"
          out << "  --data-binary @#{payload.path}"
        elsif payload.is_a?(String)
          out << "  -d '#{payload}'"
        elsif payload.respond_to?(:map)
          payload.delete(:multipart) if payload.is_a?(Hash)
          # puts "grailsifying it!"
          payload = Morpheus::RestClient.grails_params(payload)
          payload.each do |k,v|
            if v.is_a?(File)
              out << "  -F '#{k}=@#{v.path}"
            else
              out << "  -d '#{URI.encode_www_form({(k) => v})}'"
            end
            out << "\n"
          end
          #body_str = URI.encode_www_form(payload)
          # out << "  -d '#{body_str}'"
        end
      end
    else
      out << "\n"
    end
    if options[:scrub]
      out = Morpheus::Logging.scrub_message(out)
    end
    return out
    
  end
  def print_results_pagination(json_response, options={})
    # print cyan,"\nViewing #{json_response['meta']['offset'].to_i + 1}-#{json_response['meta']['offset'].to_i + json_response['meta']['size'].to_i} of #{json_response['meta']['total']}\n", reset
    print format_results_pagination(json_response, options)
  end

  def format_results_pagination(json_response, options={})
    # no output for strange, empty data
    if json_response.nil? || json_response.empty?
      return ""
    end
    color = options.key?(:color) ? options[:color] : cyan
    label = options[:label]
    n_label = options[:n_label] || (label ? label.to_s.pluralize : nil)
    message = options[:message] || "Viewing %{start_index}-%{end_index} of %{total} %{label}"
    blank_message = options[:blank_message] || nil # "No %{label} found"

    # support lazy passing of common list json_response {"meta": {"size": 25, "total": 56} }
    # priority is:
    # 1. "meta" that api response contains for list endpoints
    # 2. "total" and "size" values if passed explicitely by the cli (pretty sure symbols are no longer used)
    # 3. examine the first array found in the response
    meta = nil
    records = nil
    # assume records is the first array in the response
    records_key = json_response.keys.find { |k| json_response[k].is_a?(Array) }
    if records_key
      records = json_response[records_key]
      meta = {'offset' => 0, 'size' => records.size, 'total' => records.size}
    end
    if json_response[:meta] || json_response["meta"]
      meta = json_response[:meta] || json_response["meta"]
    elsif json_response.key?('size') || json_response.key?('total')
      meta = json_response
    elsif json_response.key?(:size) || json_response.key?(:total)
      meta = {'size' => json_response[:size], 'total' => json_response[:total], 'offset' => json_response[:offset]}
    elsif records
      # just use the first key in the response
      meta = {'size' => records.size, 'total' => records.size}
    end
    # did not find pagination meta info?
    if meta.nil?
      return ""
    end
    # api should not need to return the size, just use records.size
    if meta["size"].nil? && records
      meta["size"] = records.size
    end
    offset = meta['offset'].to_i
    size = meta['size'].to_i
    total = meta['total'].to_i
    # perhaps no total count returned, let total be equal to size of list
    if total == 0 && size > 0
      total = size
    end
    # plural label?
    if total != 1
      label = n_label
    end
    out_str = ""
    string_key_values = {start_index: format_number(offset + 1), end_index: format_number(offset + size), 
      total: format_number(total), size: format_number(size), offset: format_number(offset), label: label}
    if size > 0
      if message
        out_str << message % string_key_values
      end
    else
      if blank_message
        out_str << blank_message % string_key_values
      else
        #out << "No records"
      end
    end
    out = ""
    out << "\n"
    out << color if color
    out << out_str.strip
    out << reset if color
    out << "\n"
    out
  end

  def required_blue_prompt
    "#{cyan}|#{reset}"
  end


  # shows cyan, yellow, red progress bar where 50% looks like [|||||     ]
  # todo: render units used / available here too maybe
  def generate_usage_bar(used_value, max_value, opts={})
    opts[:bar_color] ||= :rainbow # :rainbow, :solid, or a color eg. cyan
    max_bars = opts[:max_bars] || 50
    out = ""
    bars = []
    percent = 0
    percent_sigdig = opts[:percent_sigdig] || 2
    if max_value.nil?
      percent = 0
    elsif max_value == 0
      percent = used_value.to_f == 0 ? 0 : 100
    else
      percent = ((used_value.to_f / max_value.to_f) * 100)
    end
    unlimited_label = opts[:unlimited_label] || "n/a" 
    percent_label = (max_value.nil? ? unlimited_label : "#{percent.round(percent_sigdig)}%").rjust(6, ' ')
    bar_display = ""
    if percent > 100
      max_bars.times { bars << "|" }
      # percent = 100
    else
      n_bars = ((percent / 100.0) * max_bars).ceil
      n_bars.times { bars << "|" }
    end

    if opts[:bar_color] == :rainbow
      rainbow_bar = ""
      cur_rainbow_color = reset # default terminal color
      rainbow_bar << cur_rainbow_color
      bars.each_with_index {|bar, i|
        reached_percent = (i / max_bars.to_f) * 100
        new_bar_color = cur_rainbow_color
        if reached_percent > 80
          new_bar_color = red
        elsif reached_percent > 50
          new_bar_color = yellow
        elsif reached_percent > 10
          new_bar_color = cyan
        else
          new_bar_color = reset
        end
        if cur_rainbow_color != new_bar_color
          cur_rainbow_color = new_bar_color
          rainbow_bar << cur_rainbow_color
        end
        rainbow_bar << bar
      }
      padding = max_bars - bars.size
      if padding > 0
        padding.times { rainbow_bar << " " }
        #rainbow_bar <<  " " * padding
      end
      rainbow_bar << reset
      bar_display = cyan + "[" + rainbow_bar + cyan + "]" + " #{cur_rainbow_color}#{percent_label}#{reset}"
      out << bar_display
    elsif opts[:bar_color] == :solid
      bar_color = cyan
      if percent > 80
        bar_color = red
      elsif percent > 50
        bar_color = yellow
      elsif percent > 10
        bar_color = cyan
      else
        bar_color = reset
      end
      bar_display = cyan + "[" + bar_color + bars.join.ljust(max_bars, ' ') + cyan + "]" + " #{percent_label}" + reset
      out << bar_display
    else
      bar_color = opts[:bar_color] || reset
      bar_display = cyan + "[" + bar_color + bars.join.ljust(max_bars, ' ') + cyan + "]" + " #{percent_label}" + reset
      out << bar_display
    end
    return out
  end

  def print_stats_usage(stats, opts={})
    label_width = opts[:label_width] || 10
    out = ""
    if stats.nil? || stats.empty?
      out << cyan + "No data." +  "\n" + reset
      print out
      return
    end
    opts[:include] ||= [:cpu, :memory, :storage]
    if opts[:include].include?(:max_cpu)
      cpu_usage = stats['cpuUsagePeak']
      out << cyan + "Max CPU".rjust(label_width, ' ') + ": " + generate_usage_bar(cpu_usage.to_f, 100)  + "\n"
    end
    if opts[:include].include?(:avg_cpu)
      cpu_usage = stats['cpuUsageAvg'] || stats['cpuUsageAverage']
      out << cyan + "Avg. CPU".rjust(label_width, ' ') + ": " + generate_usage_bar(cpu_usage.to_f, 100)  + "\n"
    end
    if opts[:include].include?(:cpu)
      cpu_usage = stats['cpuUsage'] || stats['usedCpu']
      out << cyan + "CPU".rjust(label_width, ' ') + ": " + generate_usage_bar(cpu_usage.to_f, 100)  + "\n"
    end
    if opts[:include].include?(:memory)
      out << cyan + "Memory".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['usedMemory'], stats['maxMemory']) + cyan + Filesize.from("#{stats['usedMemory']} B").pretty.strip.rjust(15, ' ')           + " / " + Filesize.from("#{stats['maxMemory']} B").pretty.strip.ljust(15, ' ')  + "\n"
    end
    if opts[:include].include?(:storage)
      out << cyan + "Storage".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['usedStorage'], stats['maxStorage']) + cyan + Filesize.from("#{stats['usedStorage']} B").pretty.strip.rjust(15, ' ') + " / " + Filesize.from("#{stats['maxStorage']} B").pretty.strip.ljust(15, ' ') + "\n"
    end
    print out
  end

  def format_available_options(option_types)
    option_lines = option_types.collect {|it| "\t-O #{it['fieldContext'] ? it['fieldContext'] + '.' : ''}#{it['fieldName']}=\"value\"" }.join("\n")
    return "Available Options:\n#{option_lines}\n\n"
  end

  def format_dt_dd(label, value, label_width=10, justify="right", do_wrap=true)
    # JD: uncomment next line to do away with justified labels
    # label_width, justify = 0, "none"
    out = ""
    value = value.to_s
    if do_wrap && value && value.include?(" ") && Morpheus::Cli::PrintHelper.terminal_width
      value_width = Morpheus::Cli::PrintHelper.terminal_width - label_width
      if value_width > 0 && value.gsub(/\e\[(\d+)m/, '').to_s.size > value_width
        wrap_indent = label_width + 1
        value = wrap(value, value_width, wrap_indent)
      end
    end
    if justify == "right"
      out << "#{label}:".rjust(label_width, ' ') + " #{value}" 
    elsif justify == "left"
      out << "#{label}:".ljust(label_width, ' ') + " #{value}" 
    else
      # default is none
      out << "#{label}:" + " #{value}" 
    end
    out
  end

  # truncate_string truncates a string and appends the suffix "..."
  # @param value [String] the string to pad
  # @param width [Integer] the length to truncate to
  # @param suffix [String] the character to pad right side with. Default is '...'
  def truncate_string(value, width, suffix="...")
    value = value.to_s
    if !width
      return value
    end
    # JD: hack alerty.. this sux, but it's a best effort to preserve values containing ascii coloring codes
    #     it stops working when there are words separated by ascii codes, eg. two diff colors
    #     plus this is probably pretty slow...
    uncolored_value = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(value.to_s) : value.to_s
    if uncolored_value != value
      trimmed_value = nil
      if uncolored_value.size > width
        if suffix
          trimmed_value = uncolored_value[0..width-(suffix.size+1)] + suffix
        else
          trimmed_value = uncolored_value[0..width-1]
        end
        return value.gsub(uncolored_value, trimmed_value)
      else
        return value
      end
    else
      if value.size > width
        if suffix
          return value[0..width-(suffix.size+1)] + suffix
        else
          return value[0..width-1]
        end
      else
        return value
      end
    end
  end

  # truncate_string truncates a string and appends the prefix "..."
  # @param value [String] the string to pad
  # @param width [Integer] the length to truncate to
  # @param prefix [String] the character to pad left side with. Default is '...'
  def truncate_string_right(value, width, prefix="...")
    value = value.to_s
    # JD: hack alerty.. this sux, but it's a best effort to preserve values containing ascii coloring codes
    #     it stops working when there are words separated by ascii codes, eg. two diff colors
    #     plus this is probably pretty slow...
    uncolored_value = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(value.to_s) : value.to_s
    if uncolored_value != value
      trimmed_value = nil
      if uncolored_value.size > width
        if prefix
          trimmed_value = prefix + uncolored_value[(uncolored_value.size - width - prefix.size)..-1]
        else
          trimmed_value = uncolored_value[(uncolored_value.size - width)..-1]
        end
        return value.gsub(uncolored_value, trimmed_value)
      else
        return value
      end
    else
      if value.size > width
        if prefix
          return prefix + value[(value.size - width - prefix.size)..-1]
        else
          return value[(value.size - width)..-1]
        end
      else
        return value
      end
    end
  end

  # justified returns a left, center, or right aligned string. 
  # @param value [String] the string to pad
  # @param width [Integer] the length to truncate to
  # @param pad_char [String] the character to pad with. Default is ' '
  # @return [String]
  def justify_string(value, width, justify="left", pad_char=" ")
    # JD: hack alert! this sux, but it's a best effort to preserve values containing ascii coloring codes
    value = value.to_s
    uncolored_value = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(value.to_s) : value.to_s
    if value.size != uncolored_value.size
      width = width + (value.size - uncolored_value.size)
    end
    if justify == "right"
      return "#{value}".rjust(width, pad_char)
    elsif justify == "center"
      return "#{value}".center(width, pad_char)
    else
      return "#{value}".ljust(width, pad_char)
    end
  end

  def format_table_cell(value, width, justify="left", pad_char=" ", suffix="...")
    #puts "format_table_cell(#{value}, #{width}, #{justify}, #{pad_char.inspect})"
    cell = value.to_s
    cell = truncate_string(cell, width, suffix)
    cell = justify_string(cell, width, justify, pad_char)
    cell
  end

  # as_pretty_table generates a table with aligned columns and truncated values.
  # This can be used in place of TablePrint.tp()
  # @param data [Array] A list of objects to extract the data from.
  # @param columns - [Array of Objects] list of column definitions, A column definition can be a String, Symbol, or Hash
  # @return [String]
  # Usage: puts as_pretty_table(my_objects, [:id, :name])
  #        puts as_pretty_table(my_objects, ["id", "name", {"plan" => "plan.name" }], {color: white})
  #
  def as_pretty_table(data, columns, options={})
    data = [data].flatten
    if options[:reverse]
      if data.is_a?(Array)
        data.reverse!
      elsif data.is_a?(Hash)
        data.values.each {|v| v.reverse! if v.is_a?(Array) }
      end
    end
    # support --fields x,y,z and --all-fields or --fields all
    all_fields = data.first ? data.first.keys : []
    #todo: support --raw-fields   meh, not really needed..
    # if options[:include_fields] && options[:raw_fields]
    #   data = transform_data_for_field_options(data, options)
    #   data = data[options[:include_fields_context]] if options[:include_fields_context]
    # elsif options[:include_fields]
    if options[:include_fields]
      if (options[:include_fields].is_a?(Array) && options[:include_fields].size == 1 && options[:include_fields][0] == 'all') || options[:include_fields] == 'all'
        columns = all_fields
      else
        # so let's use the passed in column definitions instead of the raw data properties
        # columns = options[:include_fields]
        new_columns = {}
        options[:include_fields].each do |f|
          matching_column = nil
          # column definitions vary right now, array of symbols/strings/hashes or perhaps a single hash
          if columns.is_a?(Array) && columns[0] && columns[0].is_a?(Hash)
            matching_column = columns.find {|c| 
              if c.is_a?(Hash)
                c.keys[0].to_s.downcase == f.to_s.downcase
              else
                c && c.to_s.downcase == f.to_s.downcase
              end
            }
          elsif columns.is_a?(Hash)
            matching_key = columns.keys.find {|k| k.to_s.downcase == f.to_s.downcase }
            if matching_key
              matching_column = columns[matching_key]
            end
          end
          new_columns[f] = matching_column ? matching_column : f
        end
        columns = new_columns
      end
    elsif options[:all_fields]
      columns = all_fields
    else
      columns = columns
    end

    columns = build_column_definitions(columns)

    table_color = options[:color] || cyan
    cell_delim = options[:delim] || " | "

    header_row = []
    
    columns.each do |column_def|
      header_row << column_def.label
    end

    # generate rows matrix data for the specified columns
    rows = []
    data.each do |row_data|
      row = []
      columns.each do |column_def|
        # r << column_def.display_method.respond_to?(:call) ? column_def.display_method.call(row_data) : get_object_value(row_data, column_def.display_method)
        value = column_def.display_method.call(row_data)        
        value = JSON.fast_generate(value) if value.is_a?(Hash) || value.is_a?(Array)
        row << value
      end
      rows << row
    end

    # all rows (pre-formatted)
    data_matrix = [header_row] + rows
  
    # determine column meta info i.e. width    
    columns.each_with_index do |column_def, column_index|
      # column_def.meta = {
      #   max_value_size: (header_row + rows).max {|row| row[column_index] ? row[column_index].to_s.size : 0 }.size
      # }
      if column_def.fixed_width
        column_def.width = column_def.fixed_width.to_i
      else
        max_value_size = 0
        data_matrix.each do |row|
          v = row[column_index].to_s
          v_size = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(v).size : v.size
          if v_size > max_value_size
            max_value_size = v_size
          end
        end

        max_width = (column_def.max_width.to_i > 0) ? column_def.max_width.to_i : nil
        min_width = (column_def.min_width.to_i > 0) ? column_def.min_width.to_i : nil
        if min_width && max_value_size < min_width
          column_def.width = min_width
        elsif max_width && max_value_size > max_width
          column_def.width = max_width
        else
          # expand / contract to size of the value by default
          column_def.width = max_value_size
        end
        #puts "DEBUG: #{column_index} column_def.width:  #{column_def.width}"
      end
    end

    # responsive tables
    # pops columns off end until they all fit on the terminal
    # could use some options[:preferred_columns] logic here to throw away in some specified order
    # --all fields disables this
    trimmed_columns = []
    if options[:wrap] != true # && options[:include_fields].nil? && options[:all_fields] != true

      begin
        term_width = current_terminal_width()
        table_width = columns.inject(0) {|acc, column_def| acc + (column_def.width || 0) }
        table_width += ((columns.size-0) * (3)) # col border width
        if term_width && table_width
          # leave 1 column always...
          while table_width > term_width && columns.size > 1
            column_index = columns.size - 1
            removed_column = columns.pop
            trimmed_columns << removed_column
            if removed_column.width
              table_width -= removed_column.width
              table_width -= 3 # col border width
            end
            
            # clear from data_matrix
            # wel, nvm it just gets regenerated

          end
        end
      rescue => ex
        Morpheus::Logging::DarkPrinter.puts "Encountered error while applying responsive table sizing: (#{ex.class}) #{ex}"
      end

      if trimmed_columns.size > 0
        # data_matrix = generate_table_data(data, columns, options)
        header_row = []
        columns.each do |column_def|
          header_row << column_def.label
        end
        rows = []
        data.each do |row_data|
          row = []
          columns.each do |column_def|
            # r << column_def.display_method.respond_to?(:call) ? column_def.display_method.call(row_data) : get_object_value(row_data, column_def.display_method)
            value = column_def.display_method.call(row_data)        
            value = JSON.fast_generate(value) if value.is_a?(Hash) || value.is_a?(Array)
            row << value
          end
          rows << row
        end
        data_matrix = [header_row] + rows
      end
    end

    # format header row
    header_cells = []
    columns.each_with_index do |column_def, column_index|
      value = header_row[column_index] # column_def.label
      header_cells << format_table_cell(value, column_def.width, column_def.justify)
    end
    
    # format header spacer row
    if options[:border_style] == :thin
      # a simpler looking table
      cell_delim = "   "
      h_line = header_cells.collect {|cell| ("-" * cell.strip.size).ljust(cell.size, ' ') }.join(cell_delim)
    else
      # default border style
      h_line = header_cells.collect {|cell| ("-" * cell.size) }.join(cell_delim.gsub(" ", "-"))
    end
    
    # format data rows
    formatted_rows = []
    rows.each_with_index do |row, row_index|
      formatted_row = []
      row.each_with_index do |value, column_index|
        column_def = columns[column_index]
        formatted_row << format_table_cell(value, column_def.width, column_def.justify)
      end
      formatted_rows << formatted_row
    end
    
    

    table_str = ""
    table_str << header_cells.join(cell_delim) + "\n"
    table_str << h_line + "\n"
    formatted_rows.each do |row|
      table_str << row.join(cell_delim) + "\n"
    end

    out = ""
    out << table_color if table_color
    out << table_str
    out << reset if table_color
    out
  end


  # as_description_list() prints a a two column table containing
  # the name and value of a list of descriptions
  # @param columns - [Hash or Array or Hashes] list of column definitions, A column defintion can be a String, Symbol, Hash or Proc
  # @param obj [Object] an object to extract the data from, it is treated like a Hash.
  # @param opts [Map] rendering options for label :justify, :wrap
  # Usage: 
  # print_description_list([:id, :name, :status], my_instance, {})
  #
  def as_description_list(obj, columns, opts={})
    
    columns = build_column_definitions(columns)
    
    #label_width = opts[:label_width] || 10
    max_label_width = 0
    justify = opts.key?(:justify) ? opts[:justify] : "right"
    do_wrap = opts.key?(:wrap) ? !!opts[:wrap] : true
    color = opts.key?(:color) ? opts[:color] : cyan
    rows = []
    
    columns.flatten.each do |column_def|
      label = column_def.label
      label = label.upcase if ALL_LABELS_UPCASE
      # value = get_object_value(obj, column_def.display_method)
      value = column_def.display_method.call(obj)
      value = JSON.fast_generate(value) if value.is_a?(Hash) || value.is_a?(Array)
      if label.size > max_label_width
        max_label_width = label.size
      end
      rows << {label: label, value: value}
    end
    label_width = max_label_width + 1 # for a leading space ' ' ..ew
    value_width = nil
    if Morpheus::Cli::PrintHelper.terminal_width
      value_width = Morpheus::Cli::PrintHelper.terminal_width - label_width
    end

    out = ""
    out << color if color
    rows.each do |row|
      value = row[:value].to_s
      out << format_dt_dd(row[:label], value, label_width, justify, do_wrap) + "\n"
    end
    out << reset if color
    return out
  end

  # print_description_list() is an alias for `print generate_description_list()`
  def print_description_list(columns, obj, opts={})
    # raise "oh no.. replace with as_description_list()"
    print as_description_list(obj, columns, opts)
  end

  def print_pretty_details(obj, opts={})
    print as_pretty_details(obj, opts)
  end

  def as_pretty_details(obj, opts={})
    print as_pretty_details(obj, opts.merge({pretty: true}))
  end

  def print_details(obj, opts={})
    print as_details(obj, opts)
  end

  def as_details(obj, opts={})
    #return "" if obj.nil?
    columns = {}
    keys = obj.keys
    if opts[:sort]
      keys.sort!
    end
    keys.each do |key|
      display_proc = nil
      if opts[:column_format] && opts[:column_format].key?(key.to_sym)
        display_proc = opts[:column_format][key.to_sym]
      else
        display_proc = lambda {|it| format_detail_value(it[key]) }
      end
      label = opts[:pretty] ? key.to_s.titleize : key.to_s
      columns[label] = display_proc
    end
    as_description_list(obj, columns, opts)
  end

  def format_detail_value(value)
    rtn = value
    if value.is_a?(Array)
      # show the first three objects
      rtn = value.first(3).collect { |row| format_abbreviated_value(row) }.join(", ")
    elsif value.is_a?(Hash)
      # show the first three properties
      keys = values.keys.select { |key| value[key].is_a?(Numeric) || value[key].is_a?(String) }.first(3)
      rtn = keys.collect { |key|
        "#{key.to_s.titleize}: #{format_abbreviated_value(value[key])}"
      }.join(", ")
    elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
      rtn = format_boolean(value)
    else
      rtn = value.to_s
    end
    return rtn
  end

  def format_abbreviated_value(value)
    if value.is_a?(Hash)
      if value.keys.size == 0
        "{}"
      else
        # show the first three properties
        keys = value.keys.select { |key| value[key].is_a?(Numeric) || value[key].is_a?(String) }.first(3)
        keys.collect { |key|
          "#{key.to_s.titleize}: #{value[key]}"
        }.join(", ")
      end
    elsif value.is_a?(Array)
      if value.size == 0
        return "[]"
      elsif obj.size == 1
        "[(#{obj.size})]"
      else
        "[(#{obj.size})]"
      end
    elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
      format_boolean(value)
    else
      value.to_s
    end
  end

  # build_column_definitions constructs an Array of column definitions (OpenStruct)
  # Each column is defined by a label (String), and a display_method (Proc)
  #
  # @columns [Array] list of definitions. A column definition can be a String, Symbol, Proc or Hash
  # @return [Array of OpenStruct] list of column definitions (OpenStruct) like:
  #      [{label: "ID", display_method: 'id'}, {label: "Name", display_method: Proc}]
  # Usage:
  #   build_column_definitions(:id, :name)
  #   build_column_definitions({"Object Id" => 'id'}, :name)
  #   build_column_definitions({"ID" => 'id'}, "name", "plan.name", {status: lambda {|data| data['status'].upcase } })
  #
  def build_column_definitions(*columns)
    # allow passing a single hash instead of an array of hashes
    if columns.size == 1 && columns[0].is_a?(Hash)
      columns = columns[0].collect {|k,v| {(k) => v} }
    else
      columns = columns.flatten.compact
    end
    results = []
    columns.each do |col|
      # determine label
      if col.is_a?(String)
        # supports "field as Label"
        field_key, field_label = col.split(/\s+as\s+/)
        if field_key && field_label
          k = field_label.strip
          v = field_key.strip
        else
          k = col.strip
          v = col.strip
        end
        build_column_definitions([{(k) => v}]).each do |r|
          results << r if r
        end
      elsif col.is_a?(Symbol)
        k = col.to_s.upcase #.capitalize
        v = col.to_s
        build_column_definitions([{(k) => v}]).each do |r|
          results << r if r
        end
      elsif col.is_a?(Hash)
        column_def = OpenStruct.new
        k, v = col.keys[0], col.values[0]
        if k.is_a?(String)
          column_def.label = k
        elsif k.is_a?(Symbol)
          column_def.label = k
        else
          column_def.label = k.to_s
          # raise "invalid column definition label (#{k.class}) #{k.inspect}. Should be a String or Symbol."
        end

        # determine display_method
        if v.is_a?(String)
          column_def.display_method = lambda {|data| get_object_value(data, v) }
        elsif v.is_a?(Symbol)
          column_def.display_method = lambda {|data| get_object_value(data, v) }
        elsif v.is_a?(Proc)
          column_def.display_method = v
        elsif v.is_a?(Hash) || v.is_a?(OpenStruct)
          if v[:display_name] || v[:label]
            column_def.label = v[:display_name] || v[:label]
          end
          if v[:display_method]
            if v[:display_method].is_a?(Proc)
              column_def.display_method = v[:display_method]
            else
              # assume v[:display_method] is a String, Symbol
              column_def.display_method = lambda {|data| get_object_value(data, v[:display_method]) }
            end
          else
            # the default behavior is to use the key (undoctored) to find the data
            # column_def.display_method = k
            column_def.display_method = lambda {|data| get_object_value(data, k) }
          end
          
          # other column rendering options
          column_def.justify = v[:justify]
          if v[:max_width]
            column_def.max_width = v[:max_width]
          end
          if v[:min_width]
            column_def.min_width = v[:min_width]
          end
          # tp uses width to behave like max_width, but tp() is gone, remove this?
          if v[:width]
            column_def.width = v[:width]
            column_def.max_width = v[:width]
          end
          column_def.wrap = v[:wrap].nil? ? true :  v[:wrap] # only utlized in as_description_list() right now
          
        else
          raise "invalid column definition value (#{v.class}) #{v.inspect}. Should be a String, Symbol, Proc or Hash"
        end        

        # only upcase label for symbols, this is silly anyway, 
        # just pass the exact label (key) that you want printed..
        if column_def.label.is_a?(Symbol)
          column_def.label = column_def.label.to_s.upcase
        end

        results << column_def        

      else
        raise "invalid column definition (#{column_def.class}) #{column_def.inspect}. Should be a String, Symbol or Hash"
      end
      
    end

    return results
  end

  def wrap(s, width, indent=0)
    out = s
    if s.size > width
      if indent > 0
        out = s.gsub(/(.{1,#{width}})(\s+|\Z)/, "#{' ' * indent}\\1\n").strip
      else
        out = s.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n")
      end
    else
      return s
    end
  end

  def format_boolean(v)
    if v == true || v == "true" || v == "on"
      "Yes"
    else
      "No"
    end
  end

  def quote_csv_value(v)
    '"' + v.to_s.gsub('"', '""') + '"'
  end

  def as_csv(data, default_columns=nil, options={}, object_key=nil)
    out = ""
    delim = options[:csv_delim] || options[:delim] || ","
    newline = options[:csv_newline] || options[:newline] || "\n"
    include_header = options[:csv_no_header] ? false : true
    do_quotes = options[:csv_quotes] || options[:quotes]
    if options[:reverse]
      if data.is_a?(Array)
        data.reverse!
      elsif data.is_a?(Hash)
        data.values.each {|v| v.reverse! if v.is_a?(Array) }
      end
    end
    if options[:include_fields]
      data = transform_data_for_field_options(data, options, object_key)
      if data.is_a?(Hash)
        if options[:raw_fields]
          if options[:include_fields_context]
            data = data[options[:include_fields_context]]
          else
            # todo: could use a dynamic object_key, first Array or Hash in the data, can probably always do this...
            # if object_key.nil?
            #   object_key = data.keys.find {|k| data[k].is_a?(Array) || data[k].is_a?(Hash) }
            # end
            # if object_key && data[object_key]
            #   data = data[object_key]
            # end
          end
        else
          if object_key
            data = data[object_key]
          end
        end
      end
    else
      # need array of records, so always select the object/array here
      if object_key
        if data.is_a?(Hash)
          data = data[object_key]
        else
          Morpheus::Logging::DarkPrinter.puts "as_csv() expects data as an to fetch object key '#{object_key}' from, #{data.class}." if Morpheus::Logging.debug?
        end
      end
    end
    
    
    records = data

    # allow records as Array and Hash only..
    if records.is_a?(Array)
      # records = records
    elsif records.is_a?(Hash)
      records = [records]
    else
      #raise "records_as_csv expects records as an Array of objects to render"
      Morpheus::Logging::DarkPrinter.puts "as_csv() expects data as an Array of objects to render, got a #{records.class} instead" if Morpheus::Logging.debug?
      # return ""
      return out
    end

    # build column definitions, by default use all properties for the first record (Hash) in the array
    columns = []
    all_fields = records.first.is_a?(Hash) ? records.first.keys : []
    if options[:include_fields]
      if (options[:include_fields].is_a?(Array) && options[:include_fields].size == 1 && options[:include_fields][0] == 'all') || options[:include_fields] == 'all'
        columns = all_fields
      else
        columns = options[:include_fields]
      end
    elsif options[:all_fields]
      columns = all_fields
    elsif default_columns
      columns = default_columns
    else
      columns = all_fields
    end

    column_defs = build_column_definitions(columns)

    if include_header
      headers = column_defs.collect {|column_def| column_def.label }
      if do_quotes
        headers = headers.collect {|it| quote_csv_value(it) }
      end
      out << headers.join(delim)
      out << newline
    end
    lines = []
    records.each do |obj|
      if obj
        cells = []
        column_defs.each do |column_def|
          label = column_def.label
          value = column_def.display_method.call(obj)
          value = value.is_a?(String) ? value : JSON.fast_generate(value)
          # value = get_object_value(obj, column_def)
          if do_quotes
            cells << quote_csv_value(value)
          else
            cells << value.to_s
          end
        end
      end
      line = cells.join(delim)
      lines << line
    end
    out << lines.join(newline)
    #out << delim
    out

  end

  # deprecated, replaced by as_csv(records, columns, options, object_key)
  def records_as_csv(records, options={}, default_columns=nil)
    as_csv(records, default_columns, options)
  end

  def as_json(data, options={}, object_key=nil)
    out = ""
    if !data
      return "null" # "No data"
    end
    if options[:reverse]
      if data.is_a?(Array)
        data.reverse!
      elsif data.is_a?(Hash)
        data.values.each {|v| v.reverse! if v.is_a?(Array) }
      end
    end
    if options[:include_fields]
      data = transform_data_for_field_options(data, options, object_key)
    end

    do_pretty = options.key?(:pretty_json) ? options[:pretty_json] : true
    if do_pretty
      out << JSON.pretty_generate(data)
    else
      out << JSON.fast_generate(data)
    end
    #out << "\n"
    out
  end

  def as_yaml(data, options={}, object_key=nil)
    out = ""
    if !data
      return "null" # "No data"
    end
    if options[:reverse]
      if data.is_a?(Array)
        data.reverse!
      elsif data.is_a?(Hash)
        data.values.each {|v| v.reverse! if v.is_a?(Array) }
      end
    end
    if options[:include_fields]
      data = transform_data_for_field_options(data, options, object_key)
    end
    begin
      out << data.to_yaml
    rescue => err
      puts "failed to render YAML from data: #{data.inspect}"
      puts err.message
    end
    #out << "\n"
    out
  end


  # transform data for options --fields id,authority and --select id,authority
  # support traversing records with --raw-fields and the list command. Example: roles list --raw-fields roles.id,roles.authority
  def transform_data_for_field_options(data, options, object_key=nil)
    if options[:include_fields] && data.is_a?(Hash)
      if options[:raw_fields]
        row = (object_key && !options[:raw_fields]) ? data[object_key] : data
        records = [row].flatten()
        # look for an array in the first field only now...
        field_parts = options[:include_fields][0].to_s.split(".")
        field_context = field_parts[0]
        context_data = data[field_context]
        if field_parts.size > 1 && context_data.is_a?(Array)
          # inject all the root level properties to be selectable too..
          context_data = data.delete(field_context)
          # records = context_data
          records = context_data.collect {|it| it.is_a?(Hash) ? data.merge(it) : data }
          # hacky modifying options in place
          options[:include_fields_context] = field_context
          options[:include_fields] = options[:include_fields].collect {|it| it.sub(field_context+'.', '')}
          # data = filter_data(records, options[:include_fields])
          # data[field_context] = filter_data(records, options[:include_fields])
          data = {(field_context) => filter_data(records, options[:include_fields])}
        else
          data = filter_data(data, options[:include_fields])
        end
      else
        # By default, fields are relative to the object_key, so you can use -F id instead of requiring -F instance.id
        # So ironically it is the 'raw' options (:raw_fields == true) that has to do all this funny stuff to filter intuitively.
        if object_key
          # this removes everything but the object, makes sense when using --fields
          data = {(object_key) => filter_data(data[object_key], options[:include_fields])}
          # this preserves other fields eg. meta...
          # data[object_key] = filter_data(data[object_key], options[:include_fields])
        else
          data = filter_data(data, options[:include_fields])
        end
      end
    end
    return data
  end

  def sleep_with_dots(sleep_seconds, dots=3, dot_chr=".")
    dot_interval = (sleep_seconds.to_f / dots.to_i)
    dots.to_i.times do |dot_index|
      sleep dot_interval
      print dot_chr
    end
  end

  def print_to_file(txt, filename, overwrite=false, access_mode = 'w+')
    Morpheus::Logging::DarkPrinter.puts "Writing #{txt.to_s.bytesize} bytes to file #{filename}" if Morpheus::Logging.debug?
    outfile = nil
    begin
      full_filename = File.expand_path(filename)
      if File.exist?(full_filename)
        if !overwrite
          print "#{red}Output file '#{filename}' already exists.#{reset}\n"
          print "#{red}Use --overwrite to overwrite the existing file.#{reset}\n"
          return 1
        end
      end
      if Dir.exist?(full_filename)
        print "#{red}Output file '#{filename}' is invalid. It is the name of an existing directory.#{reset}\n"
        return 1
      end
      target_dir = File.dirname(full_filename)
      if !Dir.exist?(target_dir)
        FileUtils.mkdir_p(target_dir)
      end
      outfile = File.open(full_filename, access_mode)
      outfile.print(txt)
      return 0
    rescue => ex
      # puts_error "Error writing to outfile '#{filename}'. Error: #{ex}"
      print "#{red}Error writing to file '#{filename}'.  Error: #{ex}#{reset}\n"
      return 1
    ensure
      outfile.close if outfile
    end
  end

  def with_stdout_to_file(filename, overwrite=false, access_mode = 'w+', &block)
    Morpheus::Logging::DarkPrinter.puts "Writing output to file #{filename}" if Morpheus::Logging.debug?
    previous_stdout = my_terminal.stdout
    outfile = nil
    begin
      full_filename = File.expand_path(filename)
      if File.exist?(full_filename)
        if !overwrite
          print "#{red}Output file '#{filename}' already exists.#{reset}\n"
          print "#{red}Use --overwrite to overwrite the existing file.#{reset}\n"
          return 1
        end
      end
      if Dir.exist?(full_filename)
        print "#{red}Output file '#{filename}' is invalid. It is the name of an existing directory.#{reset}\n"
        return 1
      end
      target_dir = File.dirname(full_filename)
      if !Dir.exist?(target_dir)
        FileUtils.mkdir_p(target_dir)
      end
      outfile = File.open(full_filename, access_mode)
      # outfile.print(txt)
      # ok just redirect stdout to the file
      my_terminal.set_stdout(outfile)
      result = yield
      outfile.close if outfile
      my_terminal.set_stdout(previous_stdout)
      my_terminal.stdout.flush if my_terminal.stdout
      # this does not work here.. i dunno why yet, it works in ensure though...
      # print "#{cyan}Wrote #{File.size(full_filename)} bytes to file #{filename}\n"
      if result
        return result
      else
        return 0
      end
    rescue => ex
      # puts_error "Error writing to outfile '#{filename}'. Error: #{ex}"
      print_error "#{red}Error writing to file '#{filename}'.  Error: #{ex}#{reset}\n"
      return 1
    ensure
      outfile.close if outfile
      my_terminal.set_stdout(previous_stdout) if previous_stdout != my_terminal.stdout
    end
  end

  def format_percent(val, sig_dig=2, hide_zero=false)
    if val.nil?
      return ""
    end
    percent_value = val.to_f
    if percent_value == 0
      if hide_zero
        ""
      else
        return "0%"
      end
    else
      return percent_value.round(sig_dig).to_s + "%"
    end
  end

  # returns 0.50 / s ie {{value}} / {{unit}}
  def format_rate(amount, unit='s', sig_dig=2)
    if amount.to_f == 0
      return "0.00" + " / " + unit.to_s
    else
      rtn = amount.to_f.round(2).to_s
      parts = rtn.split('.')
      # number_str = format_number(parts[0])
      number_str = parts[0].to_s
      decimal_str = "#{parts[1]}".ljust(sig_dig, "0")
      number_str + "." + decimal_str
      return number_str + "." + decimal_str + " / " + unit.to_s
    end
  end

  # convert JSON or YAML string to a map
  def parse_json_or_yaml(config, parsers = [:json, :yaml])
    rtn = {success: false, data: nil, error: nil}
    error = nil
    config = config.strip
    if config[0..2] == "---"
      parsers = [:yaml]
    end
    # ok only parse json for strings that start with {, consolidated yaml can look like json and cause issues}
    if config[0] && config[0].chr == "{" && config[-1] && config[-1].chr == "}"
      parsers = [:json]
    end
    parsers.each do |parser|
      if parser == :yaml
        begin
          # todo: one method to parse and return Hash
          # load does not raise an exception, it just returns the bad string
          #YAML.parse(config)
          config_map = YAML.load(config)
          if !config_map.is_a?(Hash)
            raise "Failed to parse config as YAML"
          end
          rtn[:data] = config_map
          rtn[:success] = true
          break
        rescue => ex
          rtn[:error] = ex if rtn[:error].nil?
        end
      elsif parser == :json
        begin
          config_map = JSON.parse(config)
          rtn[:data] = config_map
          rtn[:success] = true
          break
        rescue JSON::ParserError => ex
          begin
            fixed_config = config.dup
            # Wrap bare ERB expressions (not already quoted) in quotes
            # Matches: value: <%=...%> but not "value": "<%=...%>"
            fixed_config.gsub!(/:\s*(<%[=:]([^%>]+)%>)(?=\s*[,}\]])/, ': "\1"')
            config_map = JSON.parse(fixed_config)
            rtn[:data] = config_map
            rtn[:success] = true
            break
          rescue => ex
            rtn[:error] = ex if rtn[:error].nil?
          end
        rescue => ex
          rtn[:error] = ex if rtn[:error].nil?
        end
      end

    end
    return rtn
  end

  def parse_yaml_or_json(config, parsers = [:yaml, :json])
    parse_json_or_yaml(config, parsers)
  end

  def format_option_types_table(option_types, options={}, domain_name=nil)
    show_option_source = option_types.find {|it| !it['optionList'].to_s.empty? || !it['optionSource'].to_s.empty? }
    show_default = option_types.find {|it| !it['defaultValue'].nil? }
    columns = [
      {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
      {"FIELD NAME" => lambda {|it| 
        if it['fieldContext'] && it['fieldContext'] != domain_name && it['fieldContext'] != 'domain'
          "#{it['fieldContext']}.#{it['fieldName']}"
        else
          "#{it['fieldName']}"
        end
      } },
      {"TYPE" => lambda {|it| it['type'] } },
      {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
      show_option_source ? {"OPTION SOURCE" => lambda {|it| 
        if it['optionList']
          it['optionList']['name']
        elsif it['optionSourceType']
          "#{it['optionSourceType']}/#{it['optionSource']}"
        else
          "#{it['optionSource']}"
        end
      } } : nil,
      show_default ? {"DEFAULT" => lambda {|it| it['defaultValue'] } } : nil,
    ].compact
    as_pretty_table(option_types, columns, options)
  end

  def format_simple_option_types_table(option_types, options={})
    as_pretty_table(option_types, {
      "LABEL" => lambda {|it| it['fieldLabel'] },
      "NAME" => lambda {|it| it['fieldName'] },
      "TYPE" => lambda {|it| it['type'] },
      "REQUIRED" => lambda {|it| format_boolean it['required'] },
      "DEFAULT" => lambda {|it| it['defaultValue'] },
    }, options)
  end
  
end
