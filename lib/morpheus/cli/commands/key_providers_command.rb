require 'morpheus/cli/cli_command'

class Morpheus::Cli::KeyProvidersCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'key-providers'
  register_subcommands :list, :get, :add, :update, :remove, :dependents, :promote, :rotate,
    :discard_pending_version, :delete_version, :export, :import

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @key_providers_interface = @api_client.key_providers
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--name NAME', String, 'Filter by provider name') do |value|
        options[:query_filters] ||= {}
        options[:query_filters]['name'] = value
      end
      build_standard_list_options(opts, options)
      opts.footer = 'List key providers.'
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 0)
    connect(options)

    params = parse_list_options(options)
    @key_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.list(params)
      return 0, nil
    end

    json_response = @key_providers_interface.list(params)
    render_response(json_response, options, 'keyProviders') do
      key_providers = json_response['keyProviders'] || []
      print_h1 'Morpheus Key Providers', parse_list_subtitles(options), options
      if key_providers.empty?
        print cyan, 'No key providers found.', reset, "\n"
      else
        print as_pretty_table(key_provider_rows(key_providers), key_provider_columns, options)
        print_results_pagination(json_response)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[id]')
      build_standard_get_options(opts, options)
      opts.footer = 'Get a key provider by its numeric database ID. Provider UUIDs are not URL IDs.'
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    validate_provider_id!(args[0])
    connect(options)

    @key_providers_interface.setopts(options)
    params = parse_query_options(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.get(args[0].to_i, params)
      return 0, nil
    end

    json_response = @key_providers_interface.get(args[0].to_i, params)
    render_response(json_response, options, 'keyProvider') do
      print_key_provider_details(json_response['keyProvider'], options)
    end
    return 0, nil
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[name] [options]')
      build_option_type_options(opts, options, create_key_provider_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<~TEXT
        Add a key provider. The API generates providerId.
        For cluster encryption, set --ref-id to the target cluster's numeric ID.
      TEXT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, max: 1)
    connect(options)

    options[:options] ||= {}
    options[:options]['name'] ||= args[0] if args[0]
    wrap_flat_key_provider_payload(options)
    payload = parse_payload(options, 'keyProvider')
    if payload.nil?
      provider_options = Morpheus::Cli::OptionTypes.prompt(
        create_key_provider_option_types, options[:options], @api_client, options[:params]
      )
      payload = {'keyProvider' => provider_options}
    end

    @key_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.create(payload)
      return 0, nil
    end

    json_response = @key_providers_interface.create(payload)
    render_response(json_response, options, 'keyProvider') do
      provider = json_response['keyProvider']
      print_green_success "Added key provider #{provider['name']}"
      print_key_provider_details(provider, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[id] [options]')
      build_option_type_options(opts, options, update_key_provider_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<~TEXT
        Update a key provider by its numeric database ID.
        Use --status active --export-id ID to confirm its latest export.
      TEXT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    validate_provider_id!(args[0])

    wrap_flat_key_provider_payload(options)
    payload = parse_payload(options, 'keyProvider')
    if payload.nil?
      provider_options = (options[:options] || {}).reject do |key, value|
        key.is_a?(Symbol) || value.to_s.empty?
      end
      if provider_options.empty?
        raise_command_error "Specify at least one key-provider field to update.\n#{optparse}"
      end
      payload = {'keyProvider' => provider_options}
    end

    connect(options)
    @key_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.update(args[0].to_i, payload)
      return 0, nil
    end

    json_response = @key_providers_interface.update(args[0].to_i, payload)
    render_response(json_response, options, 'keyProvider') do
      provider = json_response['keyProvider']
      print_green_success "Updated key provider #{provider['id']}"
      print_key_provider_details(provider, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[id]')
      build_standard_remove_options(opts, options)
      opts.footer = 'Delete a key provider by its numeric database ID.'
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    validate_provider_id!(args[0])
    connect(options)

    id = args[0].to_i
    unless confirm("Are you sure you want to delete key provider #{id}?", options)
      return 9, 'aborted command'
    end

    @key_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.destroy(id)
      return 0, nil
    end

    json_response = @key_providers_interface.destroy(id)
    render_response(json_response, options, 'success') do
      print_green_success "Removed key provider #{id}"
    end
    return 0, nil
  end

  def dependents(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[id] [options]')
      build_standard_list_options(opts, options)
      opts.footer = 'List volumes dependent on a key provider.'
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    validate_provider_id!(args[0])
    connect(options)

    params = parse_list_options(options)
    @key_providers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.dependents(args[0].to_i, params)
      return 0, nil
    end

    json_response = @key_providers_interface.dependents(args[0].to_i, params)
    render_response(json_response, options, 'dependents') do
      dependents = json_response['dependents'] || {}
      volume_summary = dependents['volumes'] || {}
      volumes = volume_summary['items'] || []
      hidden = dependents['hidden'].to_i
      print_h1 'Key Provider Dependents', parse_list_subtitles(options), options
      print cyan, "#{volume_summary['total'] || 0} dependent volume(s)", reset
      print cyan, "; #{hidden} hidden", reset if hidden.positive?
      print "\n"
      if volumes.empty?
        print cyan, 'No dependent volumes found.', reset, "\n"
      else
        rows = volumes.collect do |volume|
          {
            id: volume['id'],
            name: volume['name'],
            status: volume['status'],
            account: volume.dig('account', 'name'),
            server: volume.dig('server', 'name')
          }
        end
        print as_pretty_table(rows, [:id, :name, :status, :account, :server], options)
        print_results_pagination(json_response)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def promote(args)
    run_provider_action(
      args,
      :promote,
      'Promote a disabled provider; the active provider in its scope may be disabled.',
      ->(id, _version) { "Promote key provider #{id}? The active provider in its scope may be disabled." },
      ->(id, _version) { "Promoted key provider #{id}" }
    )
  end

  def rotate(args)
    run_provider_action(
      args,
      :rotate,
      'Generate a pending KDK version. Export and confirm it before distribution to hosts.',
      nil,
      ->(id, _version) { "Generated a pending key version for key provider #{id}" }
    )
  end

  def discard_pending_version(args)
    run_provider_action(
      args,
      :discard_pending_version,
      'Discard and permanently wipe the pending KDK version.',
      ->(id, _version) { "Discard the pending key version for provider #{id}? Its key material will be wiped." },
      ->(id, _version) { "Discarded the pending key version for key provider #{id}" }
    )
  end

  def delete_version(args)
    run_provider_action(
      args,
      :delete_version,
      'Delete a retired KDK version that is no longer used by any volume.',
      ->(id, version) { "Delete key version #{version} from provider #{id}? Its key material will be wiped." },
      ->(id, version) { "Deleted key version #{version} from key provider #{id}" },
      true
    )
  end

  def export(args)
    options = {}
    passphrase_file = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[id] [file] [options]')
      opts.on('--passphrase-file FILE', String, 'Read the export passphrase from a file.') do |value|
        passphrase_file = value
      end
      opts.on('-f', '--force', 'Overwrite an existing output file.') do
        options[:overwrite] = true
      end
      opts.on('--mkdir', 'Create missing output directories.') do
        options[:mkdir] = true
      end
      build_common_options(opts, options, [:json, :quiet, :dry_run, :remote])
      opts.footer = <<~TEXT
        Export a key provider to a passphrase-encrypted file. If no passphrase file is given,
        the passphrase is prompted for without echo. Confirm the export with:
        key-providers update [id] --status active --export-id [export-id]
      TEXT
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 2)
    validate_provider_id!(args[0])
    connect(options)

    outfile = File.expand_path(args[1])
    return 1 unless validate_outfile(outfile, options)

    @key_providers_interface.setopts(options)
    passphrase = options[:dry_run] ? '********' : key_provider_passphrase(passphrase_file, 'Export passphrase')
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.export(args[0].to_i, passphrase, outfile), options
      return 0, nil
    end

    response = @key_providers_interface.export(args[0].to_i, passphrase, outfile)
    export_id = key_provider_response_header(response, 'X-Key-Provider-Export-Id')
    checksum = key_provider_response_header(response, 'X-Key-Provider-Export-Sha256')
    result = {'success' => true, 'file' => outfile}
    result['exportId'] = export_id if export_id
    result['checksum'] = checksum if checksum
    render_response(result, options, 'success') do
      print_green_success "Exported key provider #{args[0]} to #{outfile}"
      print "Export ID: #{export_id}\n" if export_id
      print "SHA-256: #{checksum}\n" if checksum
      if export_id
        print "Confirm with: key-providers update #{args[0]} --status active --export-id #{export_id}\n"
      end
    end
    return 0, nil
  end

  def import(args)
    options = {}
    passphrase_file = nil
    fields = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage('[file] [options]')
      opts.on('--passphrase-file FILE', String, 'Read the import passphrase from a file.') do |value|
        passphrase_file = value
      end
      opts.on('--name NAME', String, 'Override the imported provider name.') do |value|
        fields['name'] = value
      end
      opts.on('--ref-type TYPE', String, 'Set the imported provider scope type.') do |value|
        fields['refType'] = value
      end
      opts.on('--ref-id ID', String, 'Set the imported provider scope ID.') do |value|
        fields['refId'] = value
      end
      opts.on('--visibility VALUE', String, 'Set the imported provider visibility.') do |value|
        fields['visibility'] = value
      end
      build_common_options(opts, options, [:json, :quiet, :dry_run, :remote])
      opts.footer = 'Import a passphrase-encrypted key-provider export file.'
    end
    optparse.parse!(args)
    verify_args!(args: args, optparse: optparse, count: 1)
    local_file = File.expand_path(args[0])
    raise_command_error "Key-provider export file not found or unreadable: #{args[0]}" unless File.file?(local_file) && File.readable?(local_file)
    connect(options)

    @key_providers_interface.setopts(options)
    passphrase = options[:dry_run] ? '********' : key_provider_passphrase(passphrase_file, 'Import passphrase')
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.import(local_file, passphrase, fields), options
      return 0, nil
    end

    json_response = @key_providers_interface.import(local_file, passphrase, fields)
    render_response(json_response, options, 'keyProvider') do
      provider = json_response['keyProvider']
      print_green_success "Imported key provider #{provider['name']} (#{provider['id']})"
      print_key_provider_details(provider, options)
    end
    return 0, nil
  end

  private

  # parse_payload merges flags under 'keyProvider' even into a flat payload, and the API ignores
  # flat fields once that key exists, so a flat --payload has to be wrapped before parse_payload runs.
  def wrap_flat_key_provider_payload(options)
    payload = options[:payload]
    options[:payload] = {'keyProvider' => payload} if payload.is_a?(Hash) && !payload.key?('keyProvider')
  end

  def validate_provider_id!(id)
    return if id.to_s =~ /\A\d+\z/
    raise_command_error 'Key provider ID must be a numeric database ID; providerId UUIDs are not URL IDs.'
  end

  def validate_key_version!(version)
    return if version.to_s =~ /\A\d+\z/
    raise_command_error 'Key version must be numeric.'
  end

  def run_provider_action(args, action, description, confirm_message, success_message, requires_version=false)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      usage = requires_version ? '[id] [key-version] [options]' : '[id] [options]'
      opts.banner = subcommand_usage(usage)
      build_common_options(opts, options, [:auto_confirm, :json, :quiet, :dry_run, :remote])
      opts.footer = description
    end
    optparse.parse!(args)
    count = requires_version ? 2 : 1
    verify_args!(args: args, optparse: optparse, count: count)
    validate_provider_id!(args[0])
    validate_key_version!(args[1]) if requires_version
    id = args[0].to_i
    key_version = args[1].to_i if requires_version
    connect(options)

    if confirm_message && !confirm(confirm_message.call(id, key_version), options)
      return 9, 'aborted command'
    end

    @key_providers_interface.setopts(options)
    request_args = requires_version ? [id, key_version] : [id]
    if options[:dry_run]
      print_dry_run @key_providers_interface.dry.public_send(action, *request_args), options
      return 0, nil
    end

    json_response = @key_providers_interface.public_send(action, *request_args)
    render_response(json_response, options, 'keyProvider') do
      print_green_success success_message.call(id, key_version)
      print_key_provider_details(json_response['keyProvider'], options)
    end
    return 0, nil
  end

  def key_provider_passphrase(passphrase_file, label)
    passphrase = if passphrase_file
      raise_command_error "Passphrase file not found or unreadable: #{passphrase_file}" unless File.file?(passphrase_file) && File.readable?(passphrase_file)
      File.read(passphrase_file).sub(/\r?\n\z/, '')
    else
      Morpheus::Cli::OptionTypes.prompt(
        [{'fieldName' => 'passphrase', 'fieldLabel' => label, 'type' => 'password', 'required' => true}],
        {},
        @api_client
      )['passphrase']
    end
    raise_command_error "#{label} must not be blank." if passphrase.to_s.empty?
    passphrase
  end

  def key_provider_response_header(response, name)
    return unless response.respond_to?(:headers)
    header = response.headers.find { |key, _value| key.to_s.downcase.tr('_', '-') == name.downcase }
    header && header.last
  end

  def key_provider_rows(key_providers)
    key_providers.collect do |provider|
      type = provider['type']
      {
        id: provider['id'],
        name: provider['name'],
        type: type.is_a?(Hash) ? type['code'] : type,
        status: provider['status'],
        scope: provider['refType'] ? "#{provider['refType']}:#{provider['refId']}" : nil,
        pendingVersion: provider['pendingVersion'],
        activeVersion: provider['activeVersion'],
        hostCount: provider['hostCount'],
        vmCount: provider['vmCount']
      }
    end
  end

  def key_provider_columns
    [:id, :name, :type, :status, :scope, :pendingVersion, :activeVersion, :hostCount, :vmCount]
  end

  def print_key_provider_details(provider, options)
    return unless provider

    print_h1 'Key Provider Details', [], options
    print_description_list({
      'ID' => 'id',
      'Provider ID' => 'providerId',
      'Name' => 'name',
      'Description' => 'description',
      'Type' => lambda { |item| item['type'].is_a?(Hash) ? item['type']['code'] : item['type'] },
      'Status' => 'status',
      'Visibility' => 'visibility',
      'Scope' => lambda { |item| item['refType'] ? "#{item['refType']}:#{item['refId']}" : '' },
      'Pending Version' => 'pendingVersion',
      'Active Version' => 'activeVersion',
      'Exported Date' => lambda { |item| format_local_dt(item['exportedDate']) },
      'Host Count' => 'hostCount',
      'VM Count' => 'vmCount'
    }, provider)
    locations = provider['locations'] || []
    unless locations.empty?
      print_h2 'Host KDK Locations', [], options
      rows = locations.collect do |location|
        {
          hostId: location['refId'],
          keyVersion: location['keyVersion'],
          status: location['status'],
          lastVerified: format_local_dt(location['lastVerified'])
        }
      end
      print as_pretty_table(rows, [:hostId, :keyVersion, :status, :lastVerified], options)
    end
    print reset, "\n"
  end

  def create_key_provider_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'text', 'required' => false, 'defaultValue' => 'internal', 'displayOrder' => 3},
      {'fieldName' => 'refType', 'fieldLabel' => 'Scope Type', 'type' => 'text', 'required' => false, 'defaultValue' => 'ComputeServerGroup', 'switch' => 'ref-type', 'displayOrder' => 4},
      {'fieldName' => 'refId', 'fieldLabel' => 'Scope ID', 'type' => 'text', 'required' => false, 'switch' => 'ref-id', 'displayOrder' => 5,
       'description' => 'Use the numeric cluster ID for HVM key providers.'},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'text', 'required' => false, 'defaultValue' => 'private', 'displayOrder' => 6},
      {'fieldName' => 'tpmRequired', 'fieldLabel' => 'TPM Required', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'switch' => 'tpm-required', 'displayOrder' => 7}
    ]
  end

  def update_key_provider_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'status', 'fieldLabel' => 'Status', 'type' => 'text', 'required' => false, 'displayOrder' => 4},
      {'fieldName' => 'exportId', 'fieldLabel' => 'Export ID', 'type' => 'text', 'required' => false, 'switch' => 'export-id', 'displayOrder' => 5}
    ]
  end

end
