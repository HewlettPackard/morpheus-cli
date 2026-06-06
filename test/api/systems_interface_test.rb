require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus/api/systems_interface'

class SystemsInterfaceTest < Test::Unit::TestCase

  def setup
    @systems_interface = Morpheus::SystemsInterface.new(access_token: 'token', url: 'https://example.test', verify_ssl: false)
  end

  def test_list_network_server_update_definitions_builds_expected_request
    request = @systems_interface.dry.list_network_server_update_definitions(2, 3, {phrase: 'fw'})
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/infrastructure/systems/2/network-servers/3/update-definitions', request[:url]
    assert_equal({phrase: 'fw'}, request[:params])
  end

  def test_apply_network_server_update_definition_builds_expected_request
    request = @systems_interface.dry.apply_network_server_update_definition(2, 3, 4, {dryRun: true}, {foo: 'bar'})
    assert_equal :post, request[:method]
    assert_equal 'https://example.test/api/infrastructure/systems/2/network-servers/3/update-definitions/4', request[:url]
    assert_equal({foo: 'bar'}, request[:params])
    assert_equal({dryRun: true}.to_json, request[:payload])
  end

end
