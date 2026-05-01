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

  def test_update_dry_run_with_components_payload
    command = Morpheus::Cli::Systems.new
    captured_request = nil
    interface = Object.new
    interface.define_singleton_method(:get) do |id|
      {'system' => {'id' => id, 'name' => "system-#{id}"}}
    end
    interface.define_singleton_method(:dry) { self }
    interface.define_singleton_method(:update) do |id, payload|
      {method: :put, id: id, payload: payload}
    end
    command.define_singleton_method(:connect) do |options|
    end
    command.define_singleton_method(:rest_interface) do
      interface
    end
    command.define_singleton_method(:print_dry_run) do |request|
      captured_request = request
    end

    result = command.send(:update, ['--dry-run', '1', '--description', 'updated', '--component', '{"id":17,"name":"CN-CLI-1"}', '--component', '{"typeCode":"dummy-storage-controller","name":"SC-CLI-1"}'])

    assert_nil result
    assert_equal :put, captured_request[:method]
    assert_equal 1, captured_request[:id]
    assert_equal 'updated', captured_request[:payload]['system']['description']
    assert_equal 2, captured_request[:payload]['system']['components'].size
    assert_equal 17, captured_request[:payload]['system']['components'][0]['id']
    assert_equal 'dummy-storage-controller', captured_request[:payload]['system']['components'][1]['typeCode']
  end

  def test_update_dry_run_allows_empty_components_array
    command = Morpheus::Cli::Systems.new
    captured_request = nil
    interface = Object.new
    interface.define_singleton_method(:get) do |id|
      {'system' => {'id' => id, 'name' => "system-#{id}"}}
    end
    interface.define_singleton_method(:dry) { self }
    interface.define_singleton_method(:update) do |id, payload|
      {method: :put, id: id, payload: payload}
    end
    command.define_singleton_method(:connect) do |options|
    end
    command.define_singleton_method(:rest_interface) do
      interface
    end
    command.define_singleton_method(:print_dry_run) do |request|
      captured_request = request
    end

    result = command.send(:update, ['--dry-run', '1', '--components', '[]'])

    assert_nil result
    assert_equal :put, captured_request[:method]
    assert_equal [], captured_request[:payload]['system']['components']
  end

  def test_render_response_for_get_includes_components_table
    command = Morpheus::Cli::Systems.new
    captured_rows = nil
    command.define_singleton_method(:render_response) do |json_response, options, key, &block|
      block.call if block
    end
    command.define_singleton_method(:print_h1) do |*args|
    end
    command.define_singleton_method(:print_h2) do |*args|
    end
    command.define_singleton_method(:print_description_list) do |*args|
    end
    command.define_singleton_method(:print) do |*args|
    end
    command.define_singleton_method(:as_pretty_table) do |rows, columns, options|
      captured_rows = rows
      "TABLE"
    end

    command.send(:render_response_for_get, {
      'system' => {
        'id' => 1,
        'name' => 'system-1',
        'components' => [
          {'id' => 17, 'name' => 'CN-CLI-1', 'externalId' => 'ext-17', 'type' => {'code' => 'dummy-compute-node', 'name' => 'Compute Node'}}
        ]
      }
    }, {})

    assert_equal 1, captured_rows.size
    assert_equal 17, captured_rows[0][:id]
    assert_equal 'dummy-compute-node', captured_rows[0][:type_code]
    assert_equal 'ext-17', captured_rows[0][:external_id]
  end

  def test_list_layouts_renders_component_types_when_present
    command = Morpheus::Cli::Systems.new
    h2_headers = []
    table_calls = []
    stub_interface = Object.new
    stub_interface.define_singleton_method(:setopts) { |opts| }
    stub_interface.define_singleton_method(:list_layouts) do |type_id, params|
      {
        'systemTypeLayouts' => [
          {
            'id'   => 10,
            'name' => 'Demo Layout',
            'code' => 'demo-layout',
            'componentTypes' => [
              {'id' => 1, 'code' => 'compute-node', 'name' => 'Compute Node', 'category' => 'compute'},
              {'id' => 2, 'code' => 'storage-controller', 'name' => 'Storage Controller', 'category' => 'storage'}
            ]
          }
        ]
      }
    end
    command.define_singleton_method(:connect) do |options|
      api_client = Object.new
      api_client.define_singleton_method(:system_types) { stub_interface }
      @api_client = api_client
    end
    command.define_singleton_method(:render_response) do |json_response, options, key, &block|
      block.call if block
    end
    command.define_singleton_method(:print_h1) { |*args| }
    command.define_singleton_method(:print_results_pagination) { |*args| }
    command.define_singleton_method(:print) { |*args| }
    command.define_singleton_method(:print_h2) do |header, *rest|
      h2_headers << header
    end
    command.define_singleton_method(:as_pretty_table) do |rows, columns, options|
      table_calls << {rows: rows, columns: columns}
      "TABLE"
    end

    command.send(:list_layouts, ['2'])

    assert_equal 1, h2_headers.size
    assert_equal 'Components for Demo Layout', h2_headers[0]
    component_table = table_calls.find { |t| t[:columns] == [:id, :code, :name, :category] }
    assert_not_nil component_table
    assert_equal 2, component_table[:rows].size
    assert_equal 1, component_table[:rows][0][:id]
    assert_equal 'compute-node', component_table[:rows][0][:code]
    assert_equal 'Compute Node', component_table[:rows][0][:name]
    assert_equal 'compute', component_table[:rows][0][:category]
  end

  def test_list_layouts_skips_component_section_when_no_component_types
    command = Morpheus::Cli::Systems.new
    h2_headers = []
    stub_interface = Object.new
    stub_interface.define_singleton_method(:setopts) { |opts| }
    stub_interface.define_singleton_method(:list_layouts) do |type_id, params|
      {
        'systemTypeLayouts' => [
          {'id' => 10, 'name' => 'Empty Layout', 'code' => 'empty-layout', 'componentTypes' => []},
          {'id' => 11, 'name' => 'No Key Layout', 'code' => 'no-key-layout'}
        ]
      }
    end
    command.define_singleton_method(:connect) do |options|
      api_client = Object.new
      api_client.define_singleton_method(:system_types) { stub_interface }
      @api_client = api_client
    end
    command.define_singleton_method(:render_response) do |json_response, options, key, &block|
      block.call if block
    end
    command.define_singleton_method(:print_h1) { |*args| }
    command.define_singleton_method(:print_results_pagination) { |*args| }
    command.define_singleton_method(:print) { |*args| }
    command.define_singleton_method(:print_h2) do |header, *rest|
      h2_headers << header
    end
    command.define_singleton_method(:as_pretty_table) { |*args| "TABLE" }

    command.send(:list_layouts, ['2'])

    assert_equal 0, h2_headers.size
  end

  def test_list_layouts_preserves_summary_table_columns
    command = Morpheus::Cli::Systems.new
    captured_summary_rows = nil
    stub_interface = Object.new
    stub_interface.define_singleton_method(:setopts) { |opts| }
    stub_interface.define_singleton_method(:list_layouts) do |type_id, params|
      {
        'systemTypeLayouts' => [
          {'id' => 5, 'name' => 'My Layout', 'code' => 'my-layout', 'componentTypes' => []}
        ]
      }
    end
    command.define_singleton_method(:connect) do |options|
      api_client = Object.new
      api_client.define_singleton_method(:system_types) { stub_interface }
      @api_client = api_client
    end
    command.define_singleton_method(:render_response) do |json_response, options, key, &block|
      block.call if block
    end
    command.define_singleton_method(:print_h1) { |*args| }
    command.define_singleton_method(:print_results_pagination) { |*args| }
    command.define_singleton_method(:print) { |*args| }
    command.define_singleton_method(:print_h2) { |*args| }
    command.define_singleton_method(:as_pretty_table) do |rows, columns, options|
      captured_summary_rows = rows if columns.is_a?(Hash)
      "TABLE"
    end

    command.send(:list_layouts, ['1'])

    assert_not_nil captured_summary_rows
    assert_equal 1, captured_summary_rows.size
    assert_equal 5, captured_summary_rows[0]['id']
    assert_equal 'My Layout', captured_summary_rows[0]['name']
    assert_equal 'my-layout', captured_summary_rows[0]['code']
  end

end
