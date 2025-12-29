require 'time'
require 'filesize'
require 'cgi'
require 'morpheus/currency'

DEFAULT_DATE_FORMAT = "%x"
DEFAULT_TIME_FORMAT = "%x %I:%M %p"
ALTERNATE_TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss'Z'"

# returns an instance of Time
def parse_time(dt, format=nil)
  if dt.nil? || dt == '' || dt.to_i == 0
    return nil
  elsif dt.is_a?(Time)
    return dt
  elsif dt.is_a?(String)
    result = nil
    err = nil
    
    if !result
      format ||= DEFAULT_TIME_FORMAT
      if format
        begin
          result = Time.strptime(dt, format)
        rescue => e
          err = e
        end
      end
    end
    if !result
      begin
        result = Time.strptime(dt, ALTERNATE_TIME_FORMAT)
      rescue => e
        # err = e
      end
    end
    if !result
      begin
        result = Time.strptime(dt, DEFAULT_DATE_FORMAT)
      rescue => e
        # err = e
      end
    end
    if !result
      begin
        result = Time.parse(dt)
      rescue => e
        err = e
      end
    end
    if result
      return result
    else
      raise "unable to parse time '#{dt}'. #{err}"
    end
    
  elsif dt.is_a?(Numeric)
    return Time.at(dt)
  else
    raise "bad argument type for parse_time() #{dt.class} #{dt.inspect}"
  end
end

def format_dt(dt, options={})
  dt = parse_time(dt)
  return "" if dt.nil?
  if options[:local]
    dt = dt.getlocal
  end
  format = options[:format] || DEFAULT_TIME_FORMAT
  return dt.strftime(format)
end

def format_local_dt(dt, options={})
  format_dt(dt, {local: true}.merge(options))
end

def format_date(dt, options={})
  format_dt(dt, {format: DEFAULT_DATE_FORMAT}.merge(options))
end

def format_local_date(dt, options={})
  format_dt(dt, {local: true, format: DEFAULT_DATE_FORMAT}.merge(options))
end

def format_dt_as_param(dt)
  dt = dt.getutc
  format_dt(dt, {format: "%Y-%m-%d %X"})
end

def format_duration(start_time, end_time=nil, format="human")
  if !start_time
    return ""
  end
  start_time = parse_time(start_time)
  if end_time
    end_time = parse_time(end_time)
  else
    end_time = Time.now
  end
  seconds = (end_time - start_time).abs
  format_duration_seconds(seconds, format)
end

def format_duration_ago(start_time, end_time=nil)
  if !start_time
    return ""
  end
  start_time = parse_time(start_time)
  if end_time
    end_time = parse_time(end_time)
  else
    end_time = Time.now
  end
  seconds = (end_time - start_time).abs
  format_human_duration(seconds, true)
end

def format_duration_seconds(seconds, format="human")
  seconds = seconds.abs
  out = ""
  # interval = Math.abs(interval)
  if format == "human"
    out = format_human_duration(seconds)
  elsif format
    interval_time = Time.mktime(0) + seconds
    out = interval_time.strftime(format)
  else
    interval_time = Time.mktime(0) + seconds
    out = interval_time.strftime("%H:%M:%S")
  end
  out
end

def format_duration_milliseconds(milliseconds, format="human", ms_threshold=1000)
  out = ""
  milliseconds = milliseconds.to_i.abs
  if ms_threshold && ms_threshold > milliseconds
    out = "#{milliseconds}ms"
  else
    out = format_duration_seconds((milliseconds.to_f / 1000).floor, format)
  end
  out
end

# returns a human readable time duration
# @param seconds - duration in seconds
def format_human_duration(seconds, show_relative=false)
  out = ""
  #seconds = seconds.round
  days, hours, minutes = (seconds / (60*60*24)).floor, (seconds / (60*60)).floor, (seconds / (60)).floor
  if days > 365
    out << "#{days.floor} days"
  elsif days > 61
    out << "#{days.floor} days"
  elsif days > 31
    out << "#{days.floor} days"
  elsif days > 0
    if days.floor == 1
      out << "1 day"
    else
      out << "#{days.floor} days"
    end
  elsif hours > 1
    if hours == 1
      out << "1 hour"
    else
      out << "#{hours.floor} hours"
    end
  elsif minutes > 1
    if minutes == 1
      out << "1 minute"
    else
      out << "#{minutes.floor} minutes"
    end
  elsif seconds > 0 && seconds < 1
    ms = (seconds.to_f * 1000).to_i
    out << "#{ms}ms"
  else
    if seconds.floor == 1
      out << "1 second"
    else
      out << "#{seconds.floor} seconds"
    end
  end
  if show_relative
    if seconds < 1
      out = "just now"
    else
      out << " ago"
    end
  end
  out
end

def display_appliance(name, url)
  if name.to_s == "" || name == 'remote-url'
    # "#{url}"
    "#{url}"
  else
    # "#{name} #{url}"
    "[#{name}] #{url}"
  end
end

def iso8601(dt)
  dt.instance_of(Time) ? dt.iso8601 : "#{dt}"
end

# get_object_value returns a value within a Hash like object
# Usage: get_object_value(host, "plan.name")
def get_object_value(data, key)
  value = nil
  if key.is_a?(Proc)
    return key.call(data)
  end
  key = key.to_s
  if key.include?(".")
    namespaces = key.split(".")
    value = data
    namespaces.each do |ns|
      if value.respond_to?("key?")
        if value.key?(ns.to_s)
          value = value[ns]
        elsif value.key?(ns.to_sym)
          value = value[ns.to_sym]
        else
          value = nil
        end
      else
        value = nil
      end
    end
  else
    # value = data.key?(key) ? data[key] : data[key.to_sym]
    if data.respond_to?("key?")
      if data.key?(key.to_s)
        value = data[key.to_s]
      elsif data.key?(key.to_sym)
        value = data[key.to_sym]
      end
    end
  end
  return value
end

# filter_data filters Hash-like data to only the specified fields
# To specify fields of child objects, use a "."
# Usage: filter_data(instance, ["id", "name", "plan.name"])
def filter_data(data, include_fields=nil, exclude_fields=nil)
  if !data
    return data
  elsif data.is_a?(Array)
    new_data = data.collect { |it| filter_data(it, include_fields, exclude_fields) }
    return new_data
  elsif data.is_a?(Hash)
    if include_fields
      #new_data = data.select {|k, v| include_fields.include?(k.to_s) || include_fields.include?(k.to_sym) }
      # allow extracting dot pathed fields, just like get_object_value
      my_data = {}
      include_fields.each do |field|
        if field.nil?
          next
        end
        field = field.to_s
        if field.empty?
          next
        end

        # supports "field as Label"
        field_key = field.strip
        field_label = field_key

        if field.index(/\s+as\s+/)
          field_key, field_label = field.split(/\s+as\s+/)
          if !field_label
            field_label = field_key
          end
        end

        if field.include?(".")
          #if field.index(/\s+as\s+/)
          if field_label != field_key
            # collapse to a value
            my_data[field_label] = get_object_value(data, field_key)
          else
            # keep the full object structure
            namespaces = field.split(".")
            cur_data = data
            cur_filtered_data = my_data
            namespaces.each_with_index do |ns, index|
              if index != namespaces.length - 1
                if cur_data && cur_data.respond_to?("key?")
                  cur_data = cur_data.key?(ns) ? cur_data[ns] : cur_data[ns.to_sym]
                else
                  cur_data = nil
                end
                cur_filtered_data[ns] ||= {}
                cur_filtered_data = cur_filtered_data[ns]
              else
                if cur_data && cur_data.respond_to?("key?")
                  cur_filtered_data[ns] = cur_data.key?(ns) ? cur_data[ns] : cur_data[ns.to_sym]
                else
                  cur_filtered_data[ns] = nil
                end
              end
            end
          end
        else
          #my_data[field] = data[field] || data[field.to_sym]
          my_data[field_label] = data.key?(field_key) ? data[field_key] : data[field_key.to_sym]
        end
      end
      return my_data
    elsif exclude_fields
      new_data = data.reject {|k, v| exclude_fields.include?(k.to_s) || exclude_fields.include?(k.to_sym) }
      return new_data
    end
  else
    return data # .clone
  end
end

def format_bytes(bytes, units="B", round=nil)
  out = ""
  if bytes
    if bytes < 1024 && units == "B"
      out = "#{bytes.to_i} B"
    else
      out = Filesize.from("#{bytes}#{units == 'auto' ? '' : " #{units}"}").pretty.strip
      out = out.split(' ')[0].to_f.round(round).to_s + ' ' + out.split(' ')[1] if round
    end
  end
  out
end

# returns bytes in an abbreviated format
# eg. 3.1K instead of 3.10 KiB
def format_bytes_short(bytes)
  out = format_bytes(bytes)
  if out.include?(" ")
    val, units = out.split(" ")
    val = val.to_f
    # round to 0 or 1 decimal point
    if val % 1 == 0
      val = val.round(0).to_s
    else
      val = val.round(1).to_s
    end
    # K instead of KiB
    units = units[0].chr
    out = "#{val}#{units}"
  end
  return out
end

def no_colors(str)
  str.to_s.gsub(/\e\[\d+m/, "")
end


def format_number(n, opts={})
  delim = opts[:delimiter] || ','
  out = ""
  parts = n.to_s.split(".")
  whole_number = parts[0].to_s
  decimal = parts[1] ? parts[1..-1].join('.') : nil
  i = 0
  whole_number.reverse.each_char do |c|
    if c == "-"
      out = "#{c}#{out}"
    else
      out = (i > 0 && i % 3 == 0) ? "#{c}#{delim}#{out}" : "#{c}#{out}"
    end
    i+= 1
  end
  if decimal
    out << "." + decimal
  end
  return out
end

def format_sig_dig(n, sigdig=3, min_sigdig=nil, pad_zeros=false)
  v = ""
  if sigdig && sigdig > 0
    # v = n.to_i.round(sigdig).to_s
    v = sprintf("%.#{sigdig}f", n)
  else
    v = n.to_i.round().to_s
  end
  # if pad_zeros != true
  #   v = v.to_f.to_s
  # end
  if min_sigdig
    v_parts =  v.split(".")
    decimal_str = v_parts[1]
    if decimal_str == nil
      v = v + "." + ('0' * min_sigdig)
    elsif decimal_str.size < min_sigdig
      v = v + ('0' * (min_sigdig - decimal_str.size))
    end
  end
  v
end

def currency_symbol(currency)
  Morpheus::Currency.get_symbol(currency) || Morpheus::Currency.get_symbol("USD")
end

# returns currency amount formatted like "$4,5123.00". 0.00 is formatted as "$0"
# this is not ideal
def format_currency(amount, currency='USD', opts={})
  # currency '' should probably error, like money gem does
  if currency.to_s.empty?
    currency = 'USD'
  end
  currency = currency.to_s.upcase

  amount = amount.to_f
  if amount == 0
    return currency_symbol(currency).to_s + "0"
  # elsif amount.to_f < 0.01
  #   # return exponent notation like 3.4e-09
  #   return currency_symbol(currency).to_s + "#{amount}"
  else
    sigdig = opts[:sigdig] ? opts[:sigdig].to_i : 2 # max decimal digits
    min_sigdig = opts[:min_sigdig] ? opts[:min_sigdig].to_i : (sigdig || 2) # min decimal digits
    display_value = format_sig_dig(amount, sigdig, min_sigdig, opts[:pad_zeros])
    display_value = format_number(display_value) # commas
    rtn = currency_symbol(currency).to_s + display_value
    if amount.to_i < 0
      rtn = "(#{rtn})"
      if opts[:minus_color]
        rtn = "#{opts[:minus_color]}#{rtn}#{opts[:return_color] || cyan}"
      end
    end
    rtn
  end
end

alias :format_money :format_currency

# def format_money(amount, currency='usd', opts={})
#   format_currency(amount, currency, opts)
# end

def format_list(items, conjunction="", limit=nil)
  items = items ? items.clone : []
  num_items = items.size
  if limit
    items = items.first(limit)
  end
  last_item = items.pop
  if items.empty?
    return "#{last_item}"
  else
    if limit && limit < num_items
      items << last_item
      last_item = "(#{num_items - items.size} more)"
    end
    return items.join(", ") + (conjunction.to_s.empty? ? ", " : " #{conjunction} ") + "#{last_item}"
  end
end

def anded_list(items, limit=nil)
  format_list(items, "and", limit)
end

def ored_list(items, limit=nil)
  format_list(items, "or", limit)
end

def format_name_values(obj)
  if obj.is_a?(Hash)
    obj.collect {|k,v| "#{k}: #{v}"}.join(", ")
  else
    ""
  end
end

def format_name_and_id(obj)
  if(obj.is_a?(Array))
    return "" if obj.empty? # && hide_empty
    names, ids = obj.collect {|it| it['name'] rescue "" }, obj.collect {|it| it['id'] rescue "" }
    "#{names.join(", ")} [#{ids.join(",")}]"
  elsif(obj.is_a?(Hash))
    "#{obj['name']} [#{obj['id']}]" rescue ""
  else
    obj.to_s
  end
end

def a_or_an(v)
  v.to_s =~ /^[aeiou]/i ? "an" : "a"
end

def format_ok_status(status)
  color = cyan
  if ['ok'].include? status
    color = green
  elsif ['error'].include? status
    color = red
  elsif ['warning'].include? status
    color = yellow
  end
  "#{color}#{status.to_s.upcase}#{cyan}"
end

def escape_filepath(filepath)
  filepath.to_s.split("/").select {|it| !it.to_s.empty? }.collect {|it| CGI::escape(it) }.join("/")
end
