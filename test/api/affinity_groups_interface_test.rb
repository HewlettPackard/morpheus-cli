require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus/api/affinity_groups_interface'

class AffinityGroupsInterfaceTest < Test::Unit::TestCase

  def setup
    @affinity_groups_interface = Morpheus::AffinityGroupsInterface.new(access_token: 'token', url: 'https://example.test', verify_ssl: false)
  end

  def test_get_builds_bearer_authorization_header
    request = @affinity_groups_interface.dry.get(123, details: true)
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/affinity-groups/123', request[:url]
    assert_equal({details: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_update_builds_bearer_authorization_header
    request = @affinity_groups_interface.dry.update(123, {name: 'rule-a'})
    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/affinity-groups/123', request[:url]
    assert_equal({name: 'rule-a'}.to_json, request[:payload])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_destroy_builds_bearer_authorization_header
    request = @affinity_groups_interface.dry.destroy(123, force: true)
    assert_equal :delete, request[:method]
    assert_equal 'https://example.test/api/affinity-groups/123', request[:url]
    assert_equal({force: true}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_violations_builds_bearer_authorization_header
    request = @affinity_groups_interface.dry.violations(scope: 'cloud')
    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/affinity-groups/violations', request[:url]
    assert_equal({scope: 'cloud'}, request[:headers][:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

end
