require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/systems'

class SystemsCommandTest < Test::Unit::TestCase

  def test_systems_registers_network_update_subcommands
    command_names = Morpheus::Cli::Systems.subcommands.keys.collect(&:to_s)
    assert command_names.include?('list-available-network-updates')
    assert command_names.include?('apply-network-update')
    assert command_names.include?('list-available-network-server-updates')
    assert command_names.include?('apply-network-server-update')
  end

  def test_list_available_network_server_updates_dry_run
    command = Morpheus::Cli::Systems.new
    captured_request = nil
    command.define_singleton_method(:connect) do |options|
      @systems_interface = Object.new
      @systems_interface.define_singleton_method(:setopts) { |opts| }
      @systems_interface.define_singleton_method(:dry) { self }
      @systems_interface.define_singleton_method(:list_network_server_update_definitions) do |system_id, server_id, params|
        {method: :get, system_id: system_id, server_id: server_id, params: params}
      end
    end
    command.define_singleton_method(:find_by_name_or_id) do |type, value|
      {'id' => (type == :systems ? 1 : 2), 'name' => value.to_s}
    end
    command.define_singleton_method(:print_dry_run) do |request|
      captured_request = request
    end

    result = command.send(:list_available_network_server_updates, ['--dry-run', 'system-1', 'network-1'])

    assert_nil result
    assert_equal :get, captured_request[:method]
    assert_equal 1, captured_request[:system_id]
    assert_equal 2, captured_request[:server_id]
  end

  def test_apply_network_server_update_dry_run
    command = Morpheus::Cli::Systems.new
    captured_request = nil
    command.define_singleton_method(:connect) do |options|
      @systems_interface = Object.new
      @systems_interface.define_singleton_method(:setopts) { |opts| }
      @systems_interface.define_singleton_method(:dry) { self }
      @systems_interface.define_singleton_method(:apply_network_server_update_definition) do |system_id, server_id, update_definition_id, payload, params|
        {method: :post, system_id: system_id, server_id: server_id, update_definition_id: update_definition_id, payload: payload, params: params}
      end
    end
    command.define_singleton_method(:find_by_name_or_id) do |type, value|
      {'id' => (type == :systems ? 1 : 2), 'name' => value.to_s}
    end
    command.define_singleton_method(:print_dry_run) do |request|
      captured_request = request
    end

    result = command.send(:apply_network_server_update, ['--dry-run', 'system-1', 'network-1', '3'])

    assert_nil result
    assert_equal :post, captured_request[:method]
    assert_equal 1, captured_request[:system_id]
    assert_equal 2, captured_request[:server_id]
    assert_equal '3', captured_request[:update_definition_id]
  end

end
