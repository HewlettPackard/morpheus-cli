require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageVolumes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageVolumesHelper

  set_command_name :'storage-volumes'
  set_command_description "View and manage storage volumes."
  register_subcommands %w{list get add remove}

  # RestCommand settings
  register_interfaces :storage_volumes, :storage_volume_types
  set_rest_has_type true

  protected

  def build_list_options(opts, options, params)
    opts.on('-t', '--type TYPE', "Filter by type") do |val|
      params['type'] = val
    end
    opts.on('--name VALUE', String, "Filter by name") do |val|
      params['name'] = val
    end
    # build_standard_list_options(opts, options)
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

  # overridden to work with name or code
  # nope, api works with name=code now too
  # def find_storage_volume_type_by_name_or_id(name)
  #   storage_volume_type_for_name_or_id(name)
  # end

  def add_storage_volume_option_types()
    [
      {'fieldContext' => 'storageServer', 'fieldName' => 'id', 'fieldLabel' => 'Storage Server', 'type' => 'select', 'optionSource' => 'storageServers', 'required' => true},
      {'fieldContext' => 'storageGroup', 'fieldName' => 'id', 'fieldLabel' => 'Storage Group', 'type' => 'select', 'optionSource' => 'storageGroups'},
      {'fieldName' => 'type', 'fieldLabel' => 'Storage Server Type', 'type' => 'select', 'optionSource' => 'storageVolumeTypes', 'required' => true},
      #{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
    ]
  end

  def update_storage_volume_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
    ]
  end

end
