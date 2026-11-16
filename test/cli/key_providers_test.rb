require 'test/unit'
require 'stringio'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/key_providers_command'

class KeyProvidersCommandTest < Test::Unit::TestCase

  class FakeKeyProvidersInterface
    attr_reader :calls

    def initialize
      @calls = []
    end

    def setopts(_options)
      self
    end

    def create(payload)
      @calls << [:create, payload]
      {'success' => true, 'keyProvider' => {'id' => 9}.merge(payload['keyProvider'] || {})}
    end

    def update(id, payload)
      @calls << [:update, id, payload]
      {'success' => true, 'keyProvider' => {'id' => id}.merge(payload['keyProvider'] || {})}
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
    terminal.set_stdout(StringIO.new)
    yield
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

end
