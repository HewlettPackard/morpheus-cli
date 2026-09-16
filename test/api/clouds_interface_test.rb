require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus/api/clouds_interface'

class CloudsInterfaceTest < Test::Unit::TestCase

  def setup
    @clouds_interface = Morpheus::CloudsInterface.new(access_token: 'token', url: 'https://example.test', verify_ssl: false)
  end

  def test_affinity_group_form_options_builds_bearer_authorization_header
    request = @clouds_interface.dry.affinity_group_form_options(59, phase: 'create')
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/zones/59/affinity-groups/form-options', request[:url]
    assert_equal({phase: 'create'}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_list_host_vm_groups_builds_bearer_authorization_header
    request = @clouds_interface.dry.list_host_vm_groups(59, phrase: 'group')
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups', request[:url]
    assert_equal({phrase: 'group'}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_get_host_vm_group_builds_bearer_authorization_header
    request = @clouds_interface.dry.get_host_vm_group(59, 415, details: true)
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups/415', request[:url]
    assert_equal({details: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_create_host_vm_group_builds_bearer_authorization_header
    request = @clouds_interface.dry.create_host_vm_group(59, {name: 'group-a'})
    assert_equal :post, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups', request[:url]
    assert_equal({name: 'group-a'}.to_json, request[:payload])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_update_host_vm_group_builds_bearer_authorization_header
    request = @clouds_interface.dry.update_host_vm_group(59, 415, {name: 'group-b'})
    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups/415', request[:url]
    assert_equal({name: 'group-b'}.to_json, request[:payload])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_destroy_host_vm_group_builds_bearer_authorization_header
    request = @clouds_interface.dry.destroy_host_vm_group(59, 415, force: true)
    assert_equal :delete, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups/415', request[:url]
    assert_equal({force: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_host_vm_group_form_options_builds_bearer_authorization_header
    request = @clouds_interface.dry.host_vm_group_form_options(59, scope: 'qa')
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/zones/59/host-vm-groups/form-options', request[:url]
    assert_equal({scope: 'qa'}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

end
