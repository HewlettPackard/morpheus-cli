require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'

# Request shape of the move (migrate) and volume attach/detach calls. Pure unit tests using dry-run requests.
class ServersMoveAttachInterfaceTest < Test::Unit::TestCase

  def setup
    options = {access_token: 'token', url: 'https://example.test', verify_ssl: false}
    @servers = Morpheus::ServersInterface.new(options)
    @instances = Morpheus::InstancesInterface.new(options)
  end

  def test_server_bulk_move_puts_ids_and_move_options_in_the_body
    payload = {'targetClusterId' => 3, 'targetHostId' => 9, 'datastoreMap' => {'12' => 34}}

    request = @servers.dry.bulk_move([7, 8], payload)

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/servers/bulk-move', request[:url]
    assert_equal payload.merge('ids' => [7, 8]), JSON.parse(request[:payload])
    assert_equal 'application/json', request[:headers]['Content-Type']
  end

  def test_server_bulk_move_sends_force_as_a_query_parameter_not_in_the_body
    request = @servers.dry.bulk_move([7], {'targetClusterId' => 3}, {'force' => true})

    assert_equal({'force' => true}, request[:headers][:params])
    assert_false JSON.parse(request[:payload]).key?('force')
  end

  def test_server_bulk_move_does_not_modify_the_payload_it_was_given
    payload = {'targetClusterId' => 3}

    @servers.dry.bulk_move([7], payload)

    assert_equal({'targetClusterId' => 3}, payload)
  end

  def test_instance_bulk_move_uses_the_instances_route
    request = @instances.dry.bulk_move([1, 2], {'targetClusterId' => 3}, {'force' => true})

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/instances/bulk-move', request[:url]
    assert_equal({'targetClusterId' => 3, 'ids' => [1, 2]}, JSON.parse(request[:payload]))
    assert_equal({'force' => true}, request[:headers][:params])
  end

  def test_attach_volume_puts_to_the_volume_attach_route
    request = @servers.dry.attach_volume(7, 55, {'rootVolume' => true})

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/servers/7/volumes/55/attach', request[:url]
    assert_equal({'rootVolume' => true}, JSON.parse(request[:payload]))
  end

  def test_attach_volume_accepts_a_volume_uuid_and_escapes_it
    request = @servers.dry.attach_volume(7, 'a b/c')

    assert_equal 'https://example.test/api/servers/7/volumes/a+b%2Fc/attach', request[:url]
  end

  def test_detach_volume_sends_force_as_a_query_parameter
    request = @servers.dry.detach_volume(7, 55, {'force' => true})

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/servers/7/volumes/55/detach', request[:url]
    assert_equal({'force' => true}, request[:headers][:params])
  end

  def test_attach_and_detach_reject_a_blank_volume
    assert_raise(RuntimeError) { @servers.attach_volume(7, ' ') }
    assert_raise(RuntimeError) { @servers.detach_volume(7, '') }
  end

end
