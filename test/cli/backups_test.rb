require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/backups_command'

# Tests for Morpheus::Cli::BackupsCommand
#
# These tests focus on the human-readable backup detail rendering, which is
# pure formatting logic and does not require a live appliance. The detail view
# should prefer the nested API object names (backupType.name, backupProvider.name,
# storageProvider.name) and only fall back to legacy tag labels when absent.
class BackupsCommandTest < Test::Unit::TestCase
  class RecordingBackupsInterface
    attr_reader :created_payload

    def initialize(backup_type_code)
      @backup_type_code = backup_type_code
    end

    def setopts(_options)
    end

    def create_options(_payload)
      {
        'containers' => [{'id' => 101, 'name' => 'web'}],
        'backupTypes' => [{'code' => @backup_type_code, 'name' => 'Test Backup Type'}],
        'backup' => {},
        'backupSettings' => {},
      }
    end

    def create(payload)
      @created_payload = Marshal.load(Marshal.dump(payload))
      {'success' => true, 'backup' => {'id' => 99, 'name' => payload.dig('backup', 'name')}}
    end
  end

  class RecordingOptionsInterface
    attr_reader :requests

    def initialize(plugin_option_types)
      @plugin_option_types = plugin_option_types
      @requests = []
    end

    def options_for_source(source, params)
      @requests << [source, params]
      option_types = source == 'backupOptionTypes' ? @plugin_option_types : []
      {'success' => true, 'data' => {'optionTypes' => option_types}}
    end
  end

  class OfflineInstancesInterface
    def list(_params)
      {'instances' => [{'id' => 7, 'name' => 'test-instance'}]}
    end
  end

  class OfflineBackupsCommand < Morpheus::Cli::BackupsCommand
    attr_reader :backups_interface, :options_interface

    def initialize(backup_type_code, plugin_option_types)
      @backup_type_code = backup_type_code
      @plugin_option_types = plugin_option_types
    end

    def connect(_options)
      @api_client = Object.new
      @backups_interface = RecordingBackupsInterface.new(@backup_type_code)
      @options_interface = RecordingOptionsInterface.new(@plugin_option_types)
      @instances_interface = OfflineInstancesInterface.new
      @servers_interface = Object.new
      @backup_jobs_interface = Object.new
    end
  end

  def command
    @command ||= Morpheus::Cli::BackupsCommand.new
  end

  # snapshot backup with nested backupType/backupProvider/storageProvider names
  def sample_backup
    {
      'id' => 132614,
      'name' => 'vmware-snapshot-backup',
      'backupType' => {'id' => 13, 'code' => 'vmwareSnapshot', 'name' => 'VMware VM Snapshot'},
      'backupProvider' => {'id' => 543, 'code' => 'morpheus', 'name' => 'Internal Backup'},
      'storageProvider' => {'id' => 194, 'name' => 'Local Backups'},
    }
  end

  def test_backup_detail_prefers_nested_names
    columns = command.send(:backup_column_definitions)
    backup = sample_backup
    assert_equal 'VMware VM Snapshot', columns['Backup Type'].call(backup)
    assert_equal 'Internal Backup', columns['Backup Provider'].call(backup)
    assert_equal 'Local Backups', columns['Storage Provider'].call(backup)
  end

  # when backupType.name is absent, fall back to the legacy POLICY/MANUAL tag
  def test_backup_type_falls_back_to_legacy_tag
    columns = command.send(:backup_column_definitions)
    manual_backup = {'id' => 1, 'name' => 'manual'}
    assert_match(/MANUAL/, columns['Backup Type'].call(manual_backup))

    policy_backup = {'id' => 2, 'name' => 'policy', 'job' => {'id' => 5}}
    assert_match(/POLICY/, columns['Backup Type'].call(policy_backup))
  end

  # location tag should render the provider name instead of empty parens
  def test_backup_location_tag_uses_provider_name
    tag = command.send(:format_backup_location_tag, sample_backup)
    assert_match(/REMOTE/, tag)
    assert_match(/Local Backups/, tag)
    refute_match(/\(\)/, tag)
  end

  def test_add_continues_when_backup_type_has_no_plugin_options
    add_command = OfflineBackupsCommand.new('vmwareSnapshot', [])

    with_backup_add_prompts('vmwareSnapshot') do
      assert_equal [0, nil], add_command.add(['--quiet'])
    end

    backup_payload = add_command.backups_interface.created_payload['backup']
    assert_equal 'vmwareSnapshot', backup_payload['backupType']
    assert_equal 'addTo', backup_payload['jobAction']
    assert_equal 44, backup_payload['jobId']
    assert_equal ['backupOptionTypes', {'backupTypeCode' => 'vmwareSnapshot'}], add_command.options_interface.requests.first
  end

  def test_add_flattens_plugin_domain_options_into_backup_payload
    plugin_option_types = [
      {
        'fieldName' => 'pluginTarget',
        'fieldLabel' => 'Plugin Target',
        'fieldContext' => 'domain',
        'type' => 'text',
        'required' => true,
      },
    ]
    add_command = OfflineBackupsCommand.new('pluginBackup', plugin_option_types)

    with_backup_add_prompts('pluginBackup', {'backup' => {'pluginTarget' => 'archive'}}) do
      assert_equal [0, nil], add_command.add(['--quiet'])
    end

    backup_payload = add_command.backups_interface.created_payload['backup']
    assert_equal 'archive', backup_payload['pluginTarget']
    assert_false backup_payload.key?('backup')
  end

  def test_add_continues_when_all_plugin_options_are_skipped
    plugin_option_types = [
      {
        'fieldName' => 'pluginTarget',
        'fieldLabel' => 'Plugin Target',
        'fieldContext' => 'domain',
        'type' => 'text',
        'required' => false,
        'dependsOnCode' => 'missingToggle:on',
      },
    ]
    add_command = OfflineBackupsCommand.new('conditionalPluginBackup', plugin_option_types)

    with_backup_add_prompts('conditionalPluginBackup') do
      assert_equal [0, nil], add_command.add(['--quiet'])
    end

    backup_payload = add_command.backups_interface.created_payload['backup']
    assert_equal 'conditionalPluginBackup', backup_payload['backupType']
    assert_equal 44, backup_payload['jobId']
    assert_false backup_payload.key?('pluginTarget')
  end

  private

  def with_backup_add_prompts(backup_type_code, plugin_values = {})
    original_prompt = Morpheus::Cli::OptionTypes.method(:prompt)
    Morpheus::Cli::OptionTypes.define_singleton_method(:prompt) do |option_types, options = {}, api_client = nil, *args|
      if option_types.any? {|option_type| option_type['fieldContext'] == 'domain'}
        prompt_options = options.deep_merge(plugin_values).merge(:no_prompt => true)
        original_prompt.call(option_types, prompt_options, api_client, *args)
      else
        field_name = option_types.first && option_types.first['fieldName']
        case field_name
        when 'source'
          {'source' => 'instance'}
        when 'instanceId'
          {'instanceId' => 7}
        when 'name'
          {'name' => 'offline-backup'}
        when 'containerId'
          {'containerId' => 101}
        when 'backupType'
          {'backupType' => backup_type_code}
        when 'jobAction'
          {'jobAction' => 'addTo'}
        when 'jobId'
          {'jobId' => 44}
        when nil
          {}
        else
          raise "Unexpected option prompt for #{field_name}"
        end
      end
    end
    yield
  ensure
    Morpheus::Cli::OptionTypes.define_singleton_method(:prompt, original_prompt)
  end
end
