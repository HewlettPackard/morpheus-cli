require 'morpheus/cli/cli_command'

class Morpheus::Cli::SupportBundlesCommand
  include Morpheus::Cli::CliCommand

  set_command_description "View and manage support bundles"
  set_command_name :'support-bundles'
  register_subcommands :list, :get, :generate, :remove, :cancel, :download

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @support_bundles_interface = @api_client.support_bundles
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.footer = "List support bundles."
    end
    optparse.parse!(args)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    connect(options)
    @support_bundles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.list(params)
      return 0
    end
    json_response = @support_bundles_interface.list(params)
    support_bundles = json_response['supportBundles']
    render_response(json_response, options, 'supportBundles') do
      print_h1 "Morpheus Support Bundles", parse_list_subtitles(options), options
      if support_bundles.empty?
        print cyan, "No support bundles found.", reset, "\n"
      else
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          {"STATUS" => lambda {|it| format_support_bundle_status(it) } },
          {"DELIVERY" => lambda {|it| it['deliveryStatus'] ? format_support_bundle_delivery_status(it) : '' } },
          {"SIZE" => lambda {|it| it['contentLength'] ? format_bytes(it['contentLength']) : '' } },
          {"CREATED" => lambda {|it| format_local_dt(it['startedAt']) } },
        ]
        print as_pretty_table(support_bundles, columns, options)
        print_results_pagination(json_response)
      end
      print reset, "\n"
    end
    return support_bundles.empty? ? [3, "no support bundles found"] : [0, nil]
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a support bundle.
[id] is required. This is the id of a support bundle.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    return _get(args[0], params, options)
  end

  def _get(id, params, options)
    @support_bundles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.get(id, params)
      return 0
    end
    bundle = find_support_bundle_by_id(id)
    return 1 if bundle.nil?
    json_response = {'supportBundle' => bundle}
    render_response(json_response, options, 'supportBundle') do
      print_h1 "Support Bundle Details", [], options
      print cyan
      columns = {
        "ID" => 'id',
        "Name" => 'name',
        "UUID" => 'uuid',
        "Status" => lambda {|it| format_support_bundle_status(it) },
        "Status Message" => 'statusMessage',
        "Categories" => 'categories',
        "Log Window Start" => lambda {|it| format_local_dt(it['startDate']) },
        "Log Window End" => lambda {|it| format_local_dt(it['endDate']) },
        "Started At" => lambda {|it| format_local_dt(it['startedAt']) },
        "Completed At" => lambda {|it| format_local_dt(it['completedAt']) },
        "File Path" => 'filePath',
        "Size" => lambda {|it| it['contentLength'] ? format_bytes(it['contentLength']) : '' },
        "Content Type" => 'contentType',
        "Checksum" => 'checksum',
        "Storage Provider" => lambda {|it| it['storageProvider'] ? it['storageProvider']['name'] : '' },
        "Delivery Status" => lambda {|it| it['deliveryStatus'] ? format_support_bundle_delivery_status(it) : nil },
        "Delivered File" => lambda {|it| it['deliveredFilename'] },
      }
      print_description_list(columns, bundle, options)
      print reset, "\n"
    end
    return 0
  end

  def generate(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--all', "Include all eligible contents without being prompted to select them.") do
        options[:all] = true
      end
      opts.on('--storage-provider ID', String, "Storage bucket to write the bundle to.") do |val|
        options[:storage_provider_id] = val
      end
      opts.on('--start-date DATE', String, "Start of the log collection window (required). Accepts ISO 8601 formats like '2026-01-15' or '2026-01-15T00:00:00Z'.") do |val|
        options[:start_date] = val
      end
      opts.on('--end-date DATE', String, "End of the log collection window. Accepts formats like '2026-01-15' or '2026-01-15T23:59:59'. Defaults to now.") do |val|
        options[:end_date] = val
      end
      opts.on('--refresh [SECONDS]', String, "Poll until bundle generation is complete. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_finished] = true
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      build_standard_add_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Generate a new support bundle. Bundle generation is asynchronous -- the bundle
will be queued and processed in the background.

Without --all, you will be prompted to select one or more categories,
then for each category you will select either specific content types
(standalone categories) or specific resource instances (resource-backed
categories). Pass --all to include every eligible content type
automatically without being prompted.

Use --start-date and --end-date to restrict the log collection window.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 0)
    connect(options)
    @support_bundles_interface.setopts(options)
    payload = parse_payload(options) || {}

    # startDate is required — either via --start-date flag or payload
    if options[:start_date].nil? && payload['startDate'].to_s.empty?
      print_red_alert "--start-date is required"
      return 1
    end

    # Optional storage provider -- prompt unless supplied via flag
    if options[:storage_provider_id]
      payload['storageProviderId'] = options[:storage_provider_id].to_i
    elsif payload['storageProviderId'].to_s != ''
      # honor payload-provided storage provider
    elsif options[:options] && options[:options]['storageProviderId'].to_s != ''
      payload['storageProviderId'] = options[:options]['storageProviderId'].to_i
    else
      buckets = @api_client.storage_providers.list({max: 10000})['storageBuckets'] rescue []
      if buckets && !buckets.empty?
        bucket_choices = buckets.collect { |it| {'name' => it['name'], 'value' => it['id']} }
        storage_opt_type = {
          'fieldName'     => 'storageProviderId',
          'fieldLabel'    => 'Storage Provider',
          'type'          => 'select',
          'description'   => 'Storage bucket to write the bundle to. Leave blank to use the default.',
          'required'      => false,
          'selectOptions' => bucket_choices,
        }
        storage_prompt = Morpheus::Cli::OptionTypes.prompt([storage_opt_type], options[:options], @api_client)
        payload['storageProviderId'] = storage_prompt['storageProviderId'].to_i if storage_prompt['storageProviderId'].to_s != ''
      end
    end

    if options[:start_date]
      t = parse_time(options[:start_date])
      if t.nil?
        print_red_alert "Invalid --start-date value: #{options[:start_date]}"
        return 1
      end
      payload['startDate'] = t.utc.iso8601
    end
    if options[:end_date]
      t = parse_time(options[:end_date])
      if t.nil?
        print_red_alert "Invalid --end-date value: #{options[:end_date]}"
        return 1
      end
      payload['endDate'] = t.utc.iso8601
    end

    if options[:all]
      # empty contents = include everything; no payload key needed
    elsif payload['contents'].is_a?(Array)
      # honor payload-provided contents and skip interactive selection
    else
      # Fetch categories once up front
      category_options = @api_client.options.options_for_source('supportBundles/supportBundleCategories', {})['data'] || []
      if category_options.empty?
        print yellow, "No support bundle categories are available.", reset, "\n"
        return 1
      end
      category_select_options = category_options.map { |it| {'name' => it['label'] || it['name'], 'value' => it['value']} }

      # Cache combined item lists per category so repeated visits don't re-fetch
      combined_options_cache = {}

      payload_contents = []
      add_another_row = true

      while add_another_row do
        # Step 1: pick a category for this row
        category_opt_type = {
          'fieldName'     => 'row_category',
          'fieldLabel'    => 'Category',
          'type'          => 'select',
          'required'      => true,
          'description'   => 'Select a category.',
          'selectOptions' => category_select_options,
        }
        category_result = Morpheus::Cli::OptionTypes.prompt([category_opt_type], options[:options], @api_client)
        category_value = category_result['row_category'].to_s.strip
        break if category_value.empty?

        category_label = (category_options.find { |c| c['value'].to_s == category_value } || {})['label'] || category_value

        # Step 2: build (or retrieve cached) combined item list for this category
        unless combined_options_cache.key?(category_value)
          content_type_data = @api_client.options.options_for_source('supportBundles/contentTypes', {category: category_value})['data'] || []
          opts = []         # select options shown to the user
          full_value_map = {} # user-visible value -> full internal value
          # Standalone entries: user types/sees the code
          content_type_data.reject { |ct| ct['isResourceBacked'] }.each do |ct|
            code = ct['code'] || ct['value']
            opts << {'name' => ct['label'] || ct['name'], 'value' => code}
            full_value_map[code] = code
          end
          # Resource instances: user types/sees the numeric resourceId
          if content_type_data.any? { |ct| ct['isResourceBacked'] }
            resources = @api_client.options.options_for_source('supportBundles/contentTypeResources', {category: category_value})['data'] || []
            resources.each do |r|
              rid = r['resourceId'].to_s
              opts << {'name' => r['label'], 'value' => rid}
              full_value_map[rid] = "#{r['code']}|#{r['resourceId']}"
            end
          end
          combined_options_cache[category_value] = {opts: opts, map: full_value_map}
        end

        cached        = combined_options_cache[category_value]
        combined_opts = cached[:opts]
        full_value_map = cached[:map]
        if combined_opts.empty?
          print yellow, "No items found for category '#{category_label}', skipping.", reset, "\n"
        else
          # Step 3: pick one item from the combined list
          item_opt_type = {
            'fieldName'     => 'row_item',
            'fieldLabel'    => category_label,
            'type'          => 'select',
            'required'      => true,
            'description'   => "Select an item from '#{category_label}'.",
            'selectOptions' => combined_opts,
          }
          item_result = Morpheus::Cli::OptionTypes.prompt([item_opt_type], options[:options], @api_client)
          item_key = item_result['row_item'].to_s.strip
          item_value = full_value_map[item_key] || item_key

          unless item_value.empty?
            if item_value.include?('|')
              # Resource-backed: "code|resourceId"
              code, resource_id = item_value.split('|', 2)
              payload_contents << {'code' => code, 'resourceId' => resource_id.to_i} unless code.to_s.empty? || resource_id.to_s.strip.empty?
            else
              # Standalone
              payload_contents << {'code' => item_value}
            end
          end
        end

        add_another_row = Morpheus::Cli::OptionTypes.confirm("Add another item?", {default: false})
      end

      if payload_contents.empty?
        print yellow, "No items selected.", reset, "\n"
        return 1
      end

      payload['contents'] = payload_contents
    end

    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.create(payload, params)
      return 0
    end

    confirm!("Are you sure you want to generate a support bundle?", options)

    json_response = @support_bundles_interface.create(payload, params)
    bundle = json_response['supportBundle']
    render_response(json_response, options, 'supportBundle') do
      print_green_success "Support bundle generation queued (ID: #{bundle['id']}, Status: #{bundle['status']})"
      unless options[:refresh_until_finished]
        print cyan, "Use `support-bundles get #{bundle['id']}` to check status.", reset, "\n"
      end
    end

    if options[:refresh_until_finished]
      bundle = refresh_until_bundle_complete(bundle, options)
      return 0 if bundle.nil?
      _get(bundle['id'], {}, options)
    end
    return 0
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('--force', "Force delete even if the bundle is active (PENDING, IN_PROGRESS, or CANCELLING).") do
        params['force'] = true
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a support bundle.
[id] is required. This is the id of the support bundle to delete.
Active bundles are rejected unless --force is passed.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    @support_bundles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.destroy(args[0], params)
      return 0
    end
    bundle = find_support_bundle_by_id(args[0])
    return 1 if bundle.nil?
    confirm!("Are you sure you want to delete the support bundle #{bundle['name']} (#{bundle['id']})?", options)
    json_response = @support_bundles_interface.destroy(bundle['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed support bundle #{bundle['name']} (#{bundle['id']})"
    end
    return 0
  end

  def cancel(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Cancel a support bundle.
[id] is required. This is the id of the support bundle to cancel.
EOT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    connect(options)
    @support_bundles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.cancel(args[0], {}, params)
      return 0
    end
    bundle = find_support_bundle_by_id(args[0])
    return 1 if bundle.nil?
    confirm!("Are you sure you want to cancel support bundle #{bundle['name']} (#{bundle['id']})?", options)
    json_response = @support_bundles_interface.cancel(bundle['id'], {}, params)
    render_response(json_response, options) do
      print_green_success "Support bundle #{bundle['id']} cancellation requested."
    end
    return 0
  end

  def download(args)
    options = {}
    params = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [file]")
      opts.on('--file FILE', String, "Local destination path for the downloaded file.") do |val|
        outfile = val
      end
      opts.on('-f', '--force', "Overwrite existing [file] if it exists.") do
        do_overwrite = true
      end
      opts.on('-p', '--mkdir', "Create missing directories for [file] if they do not exist.") do
        do_mkdir = true
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Download a support bundle file.
[id] is required. This is the id of a support bundle.
[file] is the destination filepath. Defaults to the bundle name in the current directory.
EOT
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 1-2 and got #{args.count}\n#{optparse}"
      return 1
    end
    bundle_id = args[0]
    outfile = args[1] if args[1]
    connect(options)
    @support_bundles_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @support_bundles_interface.dry.download(bundle_id, outfile || "support-bundle-#{bundle_id}.zip", params)
      return 0
    end

    bundle = find_support_bundle_by_id(bundle_id)
    return 1 if bundle.nil?

    bundle_status = bundle['status'].to_s.downcase
    unless ['completed', 'warning'].include?(bundle_status)
      print_red_alert "Support bundle is not ready for download (status: #{bundle['status']})"
      return 1
    end

    # Resolve output filepath. Use the basename of filePath from the server (preserves
    # the correct extension, e.g. .zip or .tar.gz). Fall back to deriving a name from
    # the bundle name or id with an extension inferred from contentType.
    if outfile.nil?
      if bundle['filePath'].to_s != ''
        outfile = File.basename(bundle['filePath'])
      else
        ext = case bundle['contentType'].to_s
              when 'application/x-gzip' then '.tar.gz'
              else '.zip'
              end
        outfile = "#{bundle['name'] || "support-bundle-#{bundle_id}"}#{ext}"
      end
    end
    outfile = File.expand_path(outfile)

    if Dir.exist?(outfile)
      print_red_alert "[file] is invalid. It is the name of an existing directory: #{outfile}"
      return 1
    end
    destination_dir = File.dirname(outfile)
    if !Dir.exist?(destination_dir)
      if do_mkdir
        print cyan, "Creating local directory #{destination_dir}", reset, "\n"
        FileUtils.mkdir_p(destination_dir)
      else
        print_red_alert "[file] is invalid. Directory not found: #{destination_dir}"
        return 1
      end
    end
    if File.exist?(outfile)
      unless do_overwrite
        print_error Morpheus::Terminal.angry_prompt
        puts_error "[file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
        return 1
      end
    end

    unless options[:quiet]
      print cyan, "Downloading support bundle #{bundle_id} to #{outfile} ... "
    end

    begin
      http_response = @support_bundles_interface.download(bundle_id, outfile, params)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    rescue => e
      if File.exist?(outfile) && File.file?(outfile)
        Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
        File.delete(outfile)
      end
      raise e
    end

    success = http_response.code.to_i == 200
    if success
      unless options[:quiet]
        print green, "SUCCESS", reset, "\n"
      end
      return 0
    else
      unless options[:quiet]
        print red, "ERROR", reset, " HTTP #{http_response.code}", "\n"
      end
      if File.exist?(outfile) && File.file?(outfile)
        Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
        File.delete(outfile)
      end
      if options[:debug]
        puts_error http_response.inspect
      end
      return 1, "Error downloading file"
    end
  end

  private

  def default_refresh_interval
    5
  end

  def default_refresh_timeout
    300
  end

  def refresh_until_bundle_complete(bundle, options)
    if options[:refresh_interval].nil? || options[:refresh_interval].to_f <= 0
      options[:refresh_interval] = default_refresh_interval
    end
    refresh_display_seconds = options[:refresh_interval] % 1.0 == 0 ? options[:refresh_interval].to_i : options[:refresh_interval]
    print cyan, "Refreshing every #{refresh_display_seconds} seconds until complete...", reset, "\n" unless options[:quiet]
    max_attempts = (default_refresh_timeout / options[:refresh_interval]).ceil
    attempt = 0
    while ['pending', 'in_progress', 'cancelling'].include?(bundle['status'].to_s.downcase) do
      sleep(options[:refresh_interval])
      print cyan, ".", reset unless options[:quiet]
      bundle = @support_bundles_interface.get(bundle['id'])['supportBundle']
      attempt += 1
      if attempt >= max_attempts
        print "\n" unless options[:quiet]
        print yellow, "Timed out after #{default_refresh_timeout} seconds. Bundle is still #{bundle['status']}.", reset, "\n" unless options[:quiet]
        print cyan, "Use `support-bundles get #{bundle['id']}` to check status.", reset, "\n" unless options[:quiet]
        return nil
      end
    end
    print "\n" unless options[:quiet]
    bundle
  end

  def find_support_bundle_by_id(id)
    begin
      json_response = @support_bundles_interface.get(id.to_i)
      return json_response['supportBundle']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Support bundle not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def format_support_bundle_delivery_status(bundle, return_color = cyan)
    out = ""
    status_str = bundle['deliveryStatus'].to_s.upcase
    case status_str
    when 'DELIVERED'
      out << "#{green}DELIVERED#{return_color}"
    when 'IN_PROGRESS'
      out << "#{cyan}IN PROGRESS#{return_color}"
    when 'FAILED'
      out << "#{red}FAILED#{return_color}"
    when 'SUPERSEDED'
      out << "#{yellow}SUPERSEDED#{return_color}"
    else
      out << "#{yellow}#{bundle['deliveryStatus']}#{return_color}"
    end
    out
  end

  def format_support_bundle_status(bundle, return_color = cyan)
    out = ""
    status_str = bundle['status'].to_s.downcase
    case status_str
    when 'completed'
      out << "#{green}COMPLETED#{return_color}"
    when 'warning'
      out << "#{yellow}COMPLETED WITH WARNINGS#{return_color}"
    when 'in_progress'
      out << "#{cyan}IN PROGRESS#{return_color}"
    when 'pending'
      out << "#{cyan}PENDING#{return_color}"
    when 'failed'
      out << "#{red}FAILED#{return_color}"
    when 'cancelling'
      out << "#{yellow}CANCELLING#{return_color}"
    when 'cancelled'
      out << "#{yellow}CANCELLED#{return_color}"
    else
      out << "#{yellow}#{bundle['status']}#{return_color}"
    end
    out
  end

end
