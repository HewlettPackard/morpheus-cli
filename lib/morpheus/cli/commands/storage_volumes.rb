require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageVolumes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageVolumesHelper
  include Morpheus::Cli::AccountsHelper

  set_command_name :'storage-volumes'
  set_command_description "View and manage storage volumes."
  register_subcommands :list, :get, :add, :remove, :resize, :update_tenant

  # RestCommand settings
  register_interfaces :storage_volumes, :storage_volume_types, :accounts
  set_rest_has_type true

  protected

  def build_list_options(opts, options, params)
    opts.on('--storage-server VALUE', String, "Storage Server Name or ID") do |val|
      options[:storage_server] = val
    end
    opts.on('-t', '--type TYPE', "Filter by type") do |val|
      params['type'] = val
    end
    opts.on('--name VALUE', String, "Filter by name") do |val|
      params['name'] = val
    end
    opts.on('--category VALUE', String, "Filter by category") do |val|
      params['category'] = val
    end
    # build_standard_list_options(opts, options)
    super
  end

  def parse_list_options!(args, options, params)
    parse_parameter_as_resource_id!(:storage_server, options, params)
    super
  end

  def storage_volume_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Source" => lambda {|it| format_storage_volume_source(it) },
      "Storage" => lambda {|it| format_bytes(it['maxStorage']) },
      "Status" => lambda {|it| format_storage_volume_status(it) },
    }
  end

  def storage_volume_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : (it['account'] ? it['account']['name'] : nil) },
      "Cloud" => lambda {|it| it['zone']['name'] rescue '' },
      "Datastore" => lambda {|it| it['datastore']['name'] rescue '' },
      "Storage Group" => lambda {|it| it['storageGroup']['name'] rescue '' },
      "Storage Server" => lambda {|it| it['storageServer']['name'] rescue '' },
      "Source" => lambda {|it| format_storage_volume_source(it) },
      "Storage" => lambda {|it| format_bytes(it['maxStorage']) },
      "Status" => lambda {|it| format_storage_volume_status(it) },
    }
  end

  def add_storage_volume_option_types()
    [
      {'fieldContext' => 'storageServer', 'fieldName' => 'id', 'fieldLabel' => 'Storage Server', 'type' => 'select', 'optionSource' => 'storageServers', 'optionParams' => {'createType' => 'block'}, 'required' => true},
      {'fieldContext' => 'storageGroup', 'fieldName' => 'id', 'fieldLabel' => 'Storage Group', 'type' => 'select', 'optionSource' => 'storageGroups', 'required' => false},
      {'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Storage Volume Type', 'type' => 'select', 'optionSource' => 'storageVolumeTypes', 'required' => true},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
    ]
  end

  def update_storage_volume_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
    ]
  end

  def resize_storage_volume_option_types()
    [
      {'fieldName' => 'maxStorage', 'fieldLabel' => 'New Size', 'type' => 'number', 'required' => true},
    ]
  end

  def load_option_types_for_storage_volume(type_record, parent_record)
    storage_volume_type = type_record
    option_types = storage_volume_type['optionTypes']
    # ughhh, all this to change a label for API which uses bytes and not MB
    if option_types
      size_option_type = option_types.find {|it| it['fieldName'] == 'maxStorage' }
      if size_option_type
        #size_option_type['fieldLabel'] = "Volume Size (bytes)"
        size_option_type['fieldAddOn'] = "bytes"
      end
    end
    return option_types
  end

  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      volume = find_volume_by_name_or_id(args[0])
      payload = {}
      id = volume['id'].to_i
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'size', 'type' => 'number', 'fieldLabel' => "Volume Size (bytes)", 'required' => true, 'description' => 'Enter a volume size (bytes).', 'defaultValue' => volume['maxStorage']}], options[:options])
      payload['maxStorage'] = v_prompt['size'].to_i
      @storage_volumes_interface.resize(id, payload)
    end
  end

  def update_tenant(args)
    options = {}
    params = {}
    tenant_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[volume] --tenant TENANT")
      opts.on('--tenant TENANT', String, "Target Tenant (Account) Name or ID to transfer ownership to.") do |val|
        tenant_id = val
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Transfer ownership of a storage volume to another tenant.
[volume] is required. This is the name or id of a storage volume.
--tenant is required unless provided via --payload. This is the name or id of the target tenant.
Only an unattached volume may be transferred. All authorization and business-rule
validation is performed by the server; its message is shown verbatim on failure.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    # CLI-side validation: require a target tenant unless a full payload is supplied.
    # All other authorization and business rules are validated server-side.
    if !options[:payload] && tenant_id.nil?
      raise_command_error "--tenant is required to transfer ownership.\n#{optparse}"
    end
    connect(options)
    volume = find_volume_by_name_or_id(args[0])
    return 1 if volume.nil?
    id = volume['id']
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({storage_volume_object_key => passed_options}) unless passed_options.empty?
    else
      account = find_account_by_name_or_id(tenant_id)
      return 1 if account.nil?
      payload[storage_volume_object_key] = {'tenant' => {'id' => account['id']}}
      payload.deep_merge!({storage_volume_object_key => passed_options}) unless passed_options.empty?
    end
    @storage_volumes_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @storage_volumes_interface.dry.update_tenant(id, payload)
      return 0, nil
    end
    json_response = @storage_volumes_interface.update_tenant(id, payload)
    render_response(json_response, options, storage_volume_object_key) do
      record = json_response[storage_volume_object_key]
      owner_name = (record && record['owner'] ? record['owner']['name'] : (record && record['account'] ? record['account']['name'] : tenant_id))
      print_green_success "Transferred storage volume #{record ? record['name'] : id} to tenant #{owner_name}"
      print_h1 rest_label, [], options
      print cyan
      print_description_list(storage_volume_column_definitions(options), record, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def find_volume_by_id(id)
    begin
      json_response = @storage_volumes_interface.get(id.to_i)
      return json_response['storageVolume']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Volume not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_volume_by_name(name)
    results = @storage_volumes_interface.list({name: name})
    if results['storageVolumes'].empty?
      print_red_alert "Volume not found by name #{name}"
      exit 1
    elsif results['storageVolumes'].size > 1
      print_red_alert "Multiple Volumes exist with the name '#{name}'"
      puts_error as_pretty_table(results['storageVolumes'], [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      exit 1
    end
    return results['storageVolumes'][0]
  end

  def find_volume_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_volume_by_id(val)
    else
      return find_volume_by_name(val)
    end
  end

end
