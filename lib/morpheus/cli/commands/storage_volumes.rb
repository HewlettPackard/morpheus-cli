require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageVolumes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageVolumesHelper

  set_command_name :'storage-volumes'
  set_command_description "View and manage storage volumes."
  register_subcommands :list, :get, :add, :remove, :resize

  # RestCommand settings
  register_interfaces :storage_volumes, :storage_volume_types
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
      {'fieldContext' => 'storageGroup', 'fieldName' => 'id', 'fieldLabel' => 'Storage Group', 'type' => 'select', 'optionSource' => 'storageGroups', 'required' => true},
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
