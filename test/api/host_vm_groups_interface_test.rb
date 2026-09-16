require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus/api/host_vm_groups_interface'

class HostVmGroupsInterfaceTest < Test::Unit::TestCase

  def setup
    @host_vm_groups_interface = Morpheus::HostVmGroupsInterface.new(access_token: 'token', url: 'https://example.test', verify_ssl: false)
  end

  def test_get_builds_bearer_authorization_header
    request = @host_vm_groups_interface.dry.get(415, details: true)
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/host-vm-groups/415', request[:url]
    assert_equal({details: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_update_builds_bearer_authorization_header
    request = @host_vm_groups_interface.dry.update(415, {name: 'group-a'})
    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/host-vm-groups/415', request[:url]
    assert_equal({name: 'group-a'}.to_json, request[:payload])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_destroy_builds_bearer_authorization_header
    request = @host_vm_groups_interface.dry.destroy(415, force: true)
    assert_equal :delete, request[:method]
    assert_equal 'https://example.test/api/host-vm-groups/415', request[:url]
    assert_equal({force: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

end
