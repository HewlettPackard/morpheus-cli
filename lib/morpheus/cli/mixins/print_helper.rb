require 'uri'
require 'term/ansicolor'
require 'json'
require 'yaml'
require 'ostruct'
require 'io/console'
require 'morpheus/logging'
require 'fileutils'

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
    #$stderr.print "#{red}#{msg}#{reset}\n"
    print "#{red}#{msg}#{reset}\n"
    #puts_error "#{red}#{msg}#{reset}"
  end

  # puts green message to stdout
  def print_green_success(msg)
    print "#{green}#{msg}#{reset}\n"
  end

  # print_h1 prints a header title and optional subtitles
  # Output:
  #
  # title - subtitle1, subtitle2
  # ==================
  #
  def print_h1(title, subtitles=nil, options=nil)
    # ok, support all these formats for now:
    # print_h1(title, options={})
    # print_h1(title, subtitles, options={})
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
      out << "#{color} | #{subtitles.join(', ')}#{reset}"
    end
    out << "\n"
    if options[:border_style] == :thin
      out << "\n"
    else
      out << "#{color}#{bold}==================#{reset}\n\n"
    end
    print out
  end

  def print_h2(title, subtitles=nil, options=nil)
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
      out << "\n"
    else
      out << "#{color}---------------------#{reset}\n\n"
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
    
    # write to a file?
    if options[:outfile]
      output = ""
      if api_request[:curl] || options[:curl]
        output = format_curl_command(http_method, url, headers, payload, options)
      else
        # body payload
        output = payload
        if content_type == 'application/json'
          if payload.is_a?(String)
            begin
              payload = JSON.parse(payload)
            rescue => e
              #payload = "(unparsable) #{payload}"
            end
          end
          output = JSON.pretty_generate(payload)
        else
          if payload.is_a?(File)
            pretty_size = "#{payload.size} B"
            output = "File: #{payload.path} (#{pretty_size})"
          elsif payload.is_a?(String)
            output = payload
          else
            if content_type == 'application/x-www-form-urlencoded'
              body_str = payload.to_s
              begin
                body_str = URI.encode_www_form(payload)
              rescue => ex
                # raise ex
              end
              output = body_str
            else
              begin
                output = JSON.pretty_generate(payload)
              rescue
                output = payload.to_s
              end
            end
          end
        end
      end
      print_result = print_to_file(output, options[:outfile], options[:overwrite])
      return print_result
    end

    # curl output?
    if api_request[:curl] || options[:curl]
      print "\n"
      puts "#{cyan}#{bold}#{dark}CURL COMMAND#{reset}"
      print format_curl_command(http_method, url, headers, payload, options)
      print "\n"
      return
    end

    print "\n"
    puts "#{cyan}#{bold}#{dark}REQUEST#{reset}"
    request_string = "#{http_method.to_s.upcase} #{url}".strip
    print request_string, "\n"
    print cyan
    if payload
      print "\n"
      if content_type == 'application/json'
        if payload.is_a?(String)
          begin
            payload = JSON.parse(payload)
          rescue => e
            #payload = "(unparsable) #{payload}"
          end
        end
        puts "#{cyan}#{bold}#{dark}JSON#{reset}"
        print JSON.pretty_generate(payload)
      else
        print "Content-Type: #{content_type}", "\n"
        print reset
        if payload.is_a?(File)
          pretty_size = "#{payload.size} B"
          print "File: #{payload.path} (#{pretty_size})"
        elsif payload.is_a?(String)
          print payload
        else
          if content_type == 'application/x-www-form-urlencoded'
            body_str = payload.to_s
            begin
              body_str = URI.encode_www_form(payload)
            rescue => ex
              # raise ex
            end
            print body_str
          else
            print payload
          end
        end
      end
    end
    print "\n"
    print reset
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
    if payload && !payload.empty?
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
      else
        content_type = headers['Content-Type'] || 'application/x-www-form-urlencoded'
        
        if payload.is_a?(File)
          # pretty_size = Filesize.from("#{payload.size} B").pretty.strip
          pretty_size = "#{payload.size} B"
          # print "File: #{payload.path} (#{payload.size} bytes)"
          out << "  -d @#{payload.path}"
        elsif payload.is_a?(String)
          out << "  -d '#{payload}'"
        else
          if content_type == 'application/x-www-form-urlencoded'
            body_str = payload.to_s
            begin
              body_str = URI.encode_www_form(payload)
            rescue => ex
              # raise ex
            end
            out << "  -d '#{body_str}'"
          else
            out << "  -d '#{payload}'"
          end
        end
      end
      out << "\n"
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
    
    # options = OpenStruct.new(options) # laff, let's do this instead
    color = options.key?(:color) ? options[:color] : cyan
    label = options[:label]
    n_label = options[:n_label]
    # label = n_label if !label && n_label
    message = options[:message] || "Viewing %{start_index}-%{end_index} of %{total} %{label}"
    blank_message = options[:blank_message] || nil # "No %{label} found"

    # support lazy passing of common json_response {"meta": {"size": {25}, "total": 56} }
    # otherwise use the root values given
    meta = OpenStruct.new(json_response)
    if meta.meta
      meta = OpenStruct.new(meta.meta)
    end
    offset, size, total = meta.offset.to_i, meta.size.to_i, meta.total.to_i
    #objects = meta.objects || options[:objects_key] ? json_response[options[:objects_key]] : nil
    #objects ||= meta.instances || meta.servers || meta.users || meta.roles
    #size = objects.size if objects && size == 0
    if total == 0
      total = size
    end
    if total != 1
      label = n_label || label
    end
    out_str = ""
    string_key_values = {start_index: format_number(offset + 1), end_index: format_number(offset + size), total: format_number(total), size: format_number(size), offset: format_number(offset), label: label}
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
    if max_value.to_i == 0
      percent = 0
    else
      percent = ((used_value.to_f / max_value.to_f) * 100)
    end
    percent_label = ((used_value.nil? || max_value.to_f == 0.0) ? "n/a" : "#{percent.round(2)}%").rjust(6, ' ')
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
      cur_rainbow_color = white
      bars.each_with_index {|bar, i|
        reached_percent = (i / max_bars.to_f) * 100
        new_bar_color = cur_rainbow_color
        if reached_percent > 80
          new_bar_color = red
        elsif reached_percent > 50
          new_bar_color = yellow
        elsif reached_percent > 10
          new_bar_color = cyan
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
      bar_display = white + "[" + rainbow_bar + white + "]" + " #{cur_rainbow_color}#{percent_label}#{reset}"
      out << bar_display
    elsif opts[:bar_color] == :solid
      bar_color = cyan
      if percent > 80
        bar_color = red
      elsif percent > 50
        bar_color = yellow
      end
      bar_display = white + "[" + bar_color + bars.join.ljust(max_bars, ' ') + white + "]" + " #{percent_label}" + reset
      out << bar_display
    else
      bar_color = opts[:bar_color] || cyan
      bar_display = white + "[" + bar_color + bars.join.ljust(max_bars, ' ') + white + "]" + " #{percent_label}" + reset
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
      cpu_usage = stats['cpuUsageAvg']
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
    if do_wrap && value && Morpheus::Cli::PrintHelper.terminal_width
      value_width = Morpheus::Cli::PrintHelper.terminal_width - label_width
      if value_width > 0 && value.to_s.size > value_width
        wrap_indent = label_width + 1 # plus 1 needs to go away
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
  # @param pad_char [String] the character to pad with. Default is ' '
  def truncate_string(value, width, suffix="...")
    value = value.to_s
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
    if options[:responsive_table] != false && options[:include_fields].nil? && options[:all_fields] != true

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
      if do_wrap
        if value_width && value_width < value.size
          wrap_indent = label_width + 1
          value = wrap(value, value_width, wrap_indent)
        end
      end
      out << format_dt_dd(row[:label], value, label_width, justify) + "\n"
    end
    out << reset if color
    return out
  end

  # print_description_list() is an alias for `print generate_description_list()`
  def print_description_list(columns, obj, opts={})
    # raise "oh no.. replace with as_description_list()"
    print as_description_list(obj, columns, opts)
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
        elsif v.is_a?(Hash) || v.is_a?(OStruct)
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
    !!v ? 'Yes' : 'No'
  end

  def quote_csv_value(v)
    '"' + v.to_s.gsub('"', '""') + '"'
  end

  def as_csv(data, columns, options={})
    out = ""
    delim = options[:csv_delim] || options[:delim] || ","
    newline = options[:csv_newline] || options[:newline] || "\n"
    include_header = options[:csv_no_header] ? false : true
    do_quotes = options[:csv_quotes] || options[:quotes]

    column_defs = build_column_definitions(columns)
    #columns = columns.flatten.compact
    data_array = [data].flatten.compact

    if include_header
      headers = column_defs.collect {|column_def| column_def.label }
      if do_quotes
        headers = headers.collect {|it| quote_csv_value(it) }
      end
      out << headers.join(delim)
      out << newline
    end
    lines = []
    data_array.each do |obj|
      if obj
        cells = []
        column_defs.each do |column_def|
          label = column_def.label
          value = column_def.display_method.call(obj)
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

  def records_as_csv(records, options={}, default_columns=nil)
    out = ""
    if !records
      #raise "records_as_csv expects records as an Array of objects to render"
      return out
    end
    cols = []
    all_fields = records.first ? records.first.keys : []
    if options[:include_fields]
      if options[:include_fields] == 'all' || options[:include_fields].include?('all')
        cols = all_fields
      else
        cols = options[:include_fields]
      end
    elsif default_columns
      cols = default_columns
    else
      cols = all_fields
    end
    out << as_csv(records, cols, options)
    out
  end

  def as_json(data, options={}, object_key=nil)
    out = ""
    if !data
      return "null" # "No data"
    end

    if options[:include_fields]
      if object_key
        data[object_key] = filter_data(data[object_key], options[:include_fields])
      else
        data = filter_data(data, options[:include_fields])
      end
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
    if options[:include_fields]
      if object_key
        data[object_key] = filter_data(data[object_key], options[:include_fields])
      else
        data = filter_data(data, options[:include_fields])
      end
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

  def anded_list(items)
    items = items ? items.clone : []
    last_item = items.pop
    if items.empty?
      return "#{last_item}"
    else
      return items.join(", ") + " and #{last_item}"
    end
  end

  def sleep_with_dots(sleep_seconds, dots=3, dot_chr=".")
    dot_interval = (sleep_seconds.to_f / dots.to_i)
    dots.to_i.times do |dot_index|
      sleep dot_interval
      print dot_chr
    end
  end

  def print_to_file(txt, filename, overwrite=false, access_mode = 'w+')
    Morpheus::Logging::DarkPrinter.puts "Writing #{txt.to_s.bytesize} bytes to file #{filename} ..." if Morpheus::Logging.debug?
    outfile = nil
    begin
      full_filename = File.expand_path(filename)
      if File.exists?(full_filename)
        if !overwrite
          print "#{red}Output file '#{filename}' already exists.#{reset}\n"
          print "#{red}Use --overwrite to overwrite the existing file.#{reset}\n"
          return 1
        end
      end
      if Dir.exists?(full_filename)
        print "#{red}Output file '#{filename}' is invalid. It is the name of an existing directory.#{reset}\n"
        return 1
      end
      target_dir = File.dirname(full_filename)
      if !Dir.exists?(target_dir)
        FileUtils.mkdir_p(target_dir)
      end
      outfile = File.open(full_filename, access_mode)
      outfile.print(txt)
      print "#{cyan}Wrote #{txt.to_s.bytesize} bytes to file #{filename}\n"
      return 0
    rescue => ex
      # puts_error "Error writing to outfile '#{filename}'. Error: #{ex}"
      print "#{red}Error writing to file '#{filename}'.  Error: #{ex}#{reset}\n"
      return 1
    ensure
      outfile.close if outfile
    end
  end

end
