require 'test/unit'
require 'stringio'
require 'tmpdir'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/key_providers_command'

class KeyProvidersCommandTest < Test::Unit::TestCase

  class FakeKeyProvidersInterface
    attr_reader :calls
    attr_accessor :provider

    def initialize
      @calls = []
    end

    def setopts(_options)
      self
    end

    def get(id, params={})
      @calls << [:get, id, params]
      {'keyProvider' => provider || {'id' => id}}
    end

    def create(payload)
      @calls << [:create, payload]
      {'success' => true, 'keyProvider' => {'id' => 9}.merge(payload['keyProvider'] || {})}
    end

    def update(id, payload)
      @calls << [:update, id, payload]
      {'success' => true, 'keyProvider' => {'id' => id}.merge(payload['keyProvider'] || {})}
    end

    def import(local_file, passphrase, fields)
      @calls << [:import, local_file, passphrase, fields]
      {'keyProvider' => {'id' => 12, 'name' => 'imported'}}
    end
  end

  def command_with(interface)
    Morpheus::Cli::KeyProvidersCommand.new.tap do |command|
      command.define_singleton_method(:connect) do |_opts|
        @key_providers_interface = interface
      end
    end
  end

  def run_capturing_output
    terminal = Morpheus::Terminal.instance
    original = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    yield
    buffer.string
  ensure
    terminal.set_stdout(original)
  end

  def test_key_providers_command_is_registered
    assert_equal Morpheus::Cli::KeyProvidersCommand,
      Morpheus::Cli::CliRegistry.instance.get(:'key-providers')
  end

  def test_key_providers_help_lists_crud_subcommands
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_equal :'key-providers', command.command_name
    assert_equal ['add', 'delete-version', 'dependents', 'discard-pending-version', 'export', 'get',
      'import', 'list', 'promote', 'remove', 'rotate', 'update'], command.subcommands.keys.sort_by(&:to_s)
  end

  def test_get_requires_a_numeric_database_id
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandError) { command.get(['provider-uuid']) }
  end

  def test_update_requires_a_numeric_database_id
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandError) { command.update(['provider-uuid', '--name', 'renamed']) }
  end

  def test_remove_requires_a_numeric_database_id
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandError) { command.remove(['provider-uuid', '-y']) }
  end

  def test_lifecycle_commands_require_a_numeric_database_id
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandError) { command.dependents(['provider-uuid']) }
    assert_raise(Morpheus::Cli::CommandError) { command.promote(['provider-uuid', '-y']) }
    assert_raise(Morpheus::Cli::CommandError) { command.rotate(['provider-uuid']) }
    assert_raise(Morpheus::Cli::CommandError) { command.discard_pending_version(['provider-uuid', '-y']) }
    assert_raise(Morpheus::Cli::CommandError) { command.delete_version(['provider-uuid', '1', '-y']) }
    assert_raise(Morpheus::Cli::CommandError) { command.export(['provider-uuid', 'backup.mkpx']) }
  end

  def test_delete_version_requires_a_numeric_key_version
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandError) { command.delete_version(['123', 'latest', '-y']) }
  end

  def test_import_requires_an_export_file
    command = Morpheus::Cli::KeyProvidersCommand.new

    assert_raise(Morpheus::Cli::CommandArgumentsError) { command.import([]) }
  end

  def test_add_wraps_a_flat_payload_under_key_provider
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).add(['--payload-json', '{"name":"kp-flat","refId":"2"}']) }

    assert_equal [[:create, {'keyProvider' => {'name' => 'kp-flat', 'refId' => '2'}}]], interface.calls
  end

  def test_add_keeps_an_already_wrapped_payload
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).add(['--payload-json', '{"keyProvider":{"name":"kp-wrapped","refId":"2"}}']) }

    assert_equal [[:create, {'keyProvider' => {'name' => 'kp-wrapped', 'refId' => '2'}}]], interface.calls
  end

  def test_add_merges_option_flags_into_a_flat_payload
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).add(['--payload-json', '{"name":"kp-flat"}', '--description', 'from flag']) }

    assert_equal [[:create, {'keyProvider' => {'name' => 'kp-flat', 'description' => 'from flag'}}]], interface.calls
  end

  def test_update_wraps_a_flat_payload_under_key_provider
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).update(['5', '--payload-json', '{"name":"renamed"}']) }

    assert_equal [[:update, 5, {'keyProvider' => {'name' => 'renamed'}}]], interface.calls
  end

  def test_update_keeps_an_already_wrapped_payload
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).update(['5', '--payload-json', '{"keyProvider":{"name":"renamed"}}']) }

    assert_equal [[:update, 5, {'keyProvider' => {'name' => 'renamed'}}]], interface.calls
  end

  def test_update_builds_the_payload_from_option_flags
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).update(['5', '--name', 'renamed']) }

    assert_equal [[:update, 5, {'keyProvider' => {'name' => 'renamed'}}]], interface.calls
  end

  def test_update_disables_through_status
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).update(['5', '--status', 'disabled']) }

    assert_equal [[:update, 5, {'keyProvider' => {'status' => 'disabled'}}]], interface.calls
  end

  def test_update_confirms_an_export
    interface = FakeKeyProvidersInterface.new

    run_capturing_output { command_with(interface).update(['5', '--status', 'active', '--export-id', 'exp-1']) }

    assert_equal [[:update, 5, {'keyProvider' => {'status' => 'active', 'exportId' => 'exp-1'}}]], interface.calls
  end

  def test_get_shows_tpm_required_and_key_versions
    interface = FakeKeyProvidersInterface.new
    interface.provider = {'id' => 5, 'name' => 'kp', 'status' => 'active', 'tpmRequired' => false,
      'keyVersions' => [{'keyVersion' => 1, 'status' => 'retired'}, {'keyVersion' => 2, 'status' => 'active'}]}

    output = run_capturing_output { command_with(interface).get(['5', '--wrap']) }

    assert_equal [[:get, 5, {}]], interface.calls
    assert_match(/TPM Required: No/, output)
    assert_match(/Key Versions/, output)
    assert_match(/2\s+\|\s+active/, output)
    assert_match(/retired/, output)
  end

  def test_get_leaves_owner_only_fields_blank_for_a_granted_provider
    interface = FakeKeyProvidersInterface.new
    interface.provider = {'id' => 5, 'name' => 'shared', 'status' => 'active'}

    output = run_capturing_output { command_with(interface).get(['5']) }

    assert_no_match(/TPM Required: No/, output)
    assert_no_match(/Key Versions/, output)
  end

  def test_import_defaults_the_scope_type_for_a_scope_id
    interface = FakeKeyProvidersInterface.new
    with_import_files do |export_file, passphrase_file|
      run_capturing_output { command_with(interface).import([export_file, '--passphrase-file', passphrase_file, '--ref-id', '4']) }

      assert_equal [[:import, export_file, 'secret', {'refId' => '4', 'refType' => 'ComputeServerGroup'}]], interface.calls
    end
  end

  def test_import_keeps_an_explicit_scope_type
    interface = FakeKeyProvidersInterface.new
    with_import_files do |export_file, passphrase_file|
      run_capturing_output do
        command_with(interface).import([export_file, '--passphrase-file', passphrase_file, '--ref-type', 'Account', '--ref-id', '1'])
      end

      assert_equal({'refType' => 'Account', 'refId' => '1'}, interface.calls[0][3])
    end
  end

  def test_import_sends_no_scope_by_default
    interface = FakeKeyProvidersInterface.new
    with_import_files do |export_file, passphrase_file|
      run_capturing_output { command_with(interface).import([export_file, '--passphrase-file', passphrase_file]) }

      assert_equal({}, interface.calls[0][3])
    end
  end

  def with_import_files
    Dir.mktmpdir do |dir|
      export_file = File.join(dir, 'provider.mkpx')
      passphrase_file = File.join(dir, 'passphrase.txt')
      File.write(export_file, '{}')
      File.write(passphrase_file, "secret\n")
      yield export_file, passphrase_file
    end
  end

end
