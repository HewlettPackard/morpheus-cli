require 'test/unit'
require 'tmpdir'
require 'socket'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/api/key_providers_interface'
require 'morpheus/cli/commands/key_providers_command'

class KeyProvidersInterfaceTest < Test::Unit::TestCase

  def setup
    @interface = Morpheus::KeyProvidersInterface.new(
      access_token: 'token',
      url: 'https://example.test',
      verify_ssl: false
    )
  end

  def test_list_builds_key_provider_collection_request
    request = @interface.dry.list({'name' => 'cluster', 'max' => 25, 'offset' => 5})

    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/key-providers', request[:url]
    assert_equal({'name' => 'cluster', 'max' => 25, 'offset' => 5}, request[:params])
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_get_builds_numeric_id_request
    request = @interface.dry.get(123)

    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/key-providers/123', request[:url]
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_create_sends_the_wrapped_key_provider_payload
    payload = {'keyProvider' => {'name' => 'cluster-a-keys', 'refType' => 'ComputeServerGroup', 'refId' => 42}}

    request = @interface.dry.create(payload)

    assert_equal :post, request[:method]
    assert_equal 'https://example.test/api/key-providers', request[:url]
    assert_equal payload.to_json, request[:payload]
    assert_equal 'application/json', request[:headers]['Content-Type']
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_update_sends_the_wrapped_key_provider_payload
    payload = {'keyProvider' => {'name' => 'renamed cluster keys'}}

    request = @interface.dry.update(123, payload)

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/key-providers/123', request[:url]
    assert_equal payload.to_json, request[:payload]
    assert_equal 'application/json', request[:headers]['Content-Type']
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_destroy_builds_delete_request
    request = @interface.dry.destroy(123)

    assert_equal :delete, request[:method]
    assert_equal 'https://example.test/api/key-providers/123', request[:url]
    assert_equal 'Bearer token', request[:headers][:authorization]
  end

  def test_dependents_builds_collection_request
    request = @interface.dry.dependents(123, {'max' => 10, 'offset' => 20})

    assert_equal :get, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/dependents', request[:url]
    assert_equal({'max' => 10, 'offset' => 20}, request[:params])
  end

  def test_promote_builds_put_request
    request = @interface.dry.promote(123)

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/promote', request[:url]
  end

  def test_rotate_builds_put_request
    request = @interface.dry.rotate(123)

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/rotate', request[:url]
  end

  def test_discard_pending_version_builds_put_request
    request = @interface.dry.discard_pending_version(123)

    assert_equal :put, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/versions/discard-pending', request[:url]
  end

  def test_delete_version_builds_version_delete_request
    request = @interface.dry.delete_version(123, 4)

    assert_equal :delete, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/versions/4', request[:url]
  end

  def test_delete_version_rejects_a_non_numeric_version
    assert_raise(RuntimeError) { @interface.delete_version(123, 'current') }
  end

  def test_export_builds_raw_post_request
    request = @interface.dry.export(123, 'test-passphrase', '/tmp/key-provider.mkpx')

    assert_equal :post, request[:method]
    assert_equal 'https://example.test/api/key-providers/123/export', request[:url]
    assert_equal({'passphrase' => 'test-passphrase'}.to_json, request[:payload])
    assert_equal false, request[:parse_json]
    assert_equal true, request[:raw_response]
  end

  def test_export_writes_the_file_and_exposes_the_export_headers
    export_id = '11111111-2222-3333-4444-555555555555'
    body = "{\"format\":\"morpheus-key-provider-export\"}\x00".b
    Dir.mktmpdir do |directory|
      outfile = File.join(directory, 'key-provider.mkpx')
      request = nil
      response = with_http_server(200, body, 'X-Key-Provider-Export-Id' => export_id,
                                  'X-Key-Provider-Export-Sha256' => 'ab' * 32) do |interface, received|
        result = interface.export(123, 'test-passphrase-123', outfile)
        request = received
        result
      end

      assert_equal body, File.binread(outfile)
      assert_equal 'POST /api/key-providers/123/export', request[:line]
      assert_equal({'passphrase' => 'test-passphrase-123'}, JSON.parse(request[:body]))
      command = Morpheus::Cli::KeyProvidersCommand.new
      assert_equal export_id, command.send(:key_provider_response_header, response, 'X-Key-Provider-Export-Id')
      assert_equal 'ab' * 32, command.send(:key_provider_response_header, response, 'X-Key-Provider-Export-Sha256')
      assert_equal ['key-provider.mkpx'], Dir.children(directory)
    end
  end

  def test_export_raises_on_an_http_error_and_writes_no_file
    error_body = {'success' => false, 'msg' => 'The key provider is being deleted', 'reason' => 'provider_deleting'}.to_json
    Dir.mktmpdir do |directory|
      outfile = File.join(directory, 'key-provider.mkpx')

      error = with_http_server(409, error_body) do |interface, _received|
        assert_raise(RestClient::Conflict) { interface.export(123, 'test-passphrase-123', outfile) }
      end

      assert_equal error_body, error.response.to_s
      assert_empty Dir.children(directory)
    end
  end

  def test_export_error_leaves_an_existing_file_untouched
    Dir.mktmpdir do |directory|
      outfile = File.join(directory, 'key-provider.mkpx')
      File.binwrite(outfile, 'previous export')

      with_http_server(422, {'success' => false, 'reason' => 'passphrase_invalid'}.to_json) do |interface, _received|
        assert_raise(RestClient::UnprocessableEntity) { interface.export(123, 'short', outfile) }
      end

      assert_equal 'previous export', File.binread(outfile)
      assert_equal ['key-provider.mkpx'], Dir.children(directory)
    end
  end

  def test_import_builds_multipart_request
    request = @interface.dry.import('provider.mkpx', 'test-passphrase', {'name' => 'restored'})

    assert_equal :post, request[:method]
    assert_equal 'https://example.test/api/key-providers/import', request[:url]
    assert_equal 'provider.mkpx', request[:payload]['file']
    assert_equal 'test-passphrase', request[:payload]['passphrase']
    assert_equal 'restored', request[:payload]['name']
    assert_equal true, request[:payload][:multipart]
  end

  def test_import_sends_file_part_and_passphrase
    Tempfile.create('key-provider-import') do |source|
      source.write('encrypted')
      source.flush
      uploaded_file = nil

      with_rest_client_execute_stub(->(request) {
        uploaded_file = request[:payload]['file']
        '{"success":true}'
      }) do
        assert_equal({'success' => true}, @interface.import(source.path, 'test-passphrase', {'name' => 'restored'}))
      end

      assert_instance_of File, uploaded_file
      assert_equal source.path, uploaded_file.path
      assert_predicate uploaded_file, :closed?
    end
  end

  def test_get_rejects_a_blank_id
    assert_raise(RuntimeError) { @interface.get(' ') }
  end

  private

  # Serves one HTTP response from a local socket so the real rest-client request path runs.
  def with_http_server(status, body, extra_headers={})
    server = TCPServer.new('127.0.0.1', 0)
    received = {}
    thread = Thread.new do
      client = server.accept
      received[:line] = client.gets.to_s.split(' ')[0, 2].join(' ')
      length = 0
      while (line = client.gets) && line != "\r\n"
        length = line.split(':', 2)[1].to_i if line.downcase.start_with?('content-length:')
      end
      received[:body] = client.read(length)
      headers = {'Content-Type' => 'application/json', 'Content-Length' => body.bytesize, 'Connection' => 'close'}.merge(extra_headers)
      client.write("HTTP/1.1 #{status} Status\r\n#{headers.collect { |k, v| "#{k}: #{v}\r\n" }.join}\r\n")
      client.write(body)
      client.close
    end
    interface = Morpheus::KeyProvidersInterface.new(access_token: 'token', url: "http://127.0.0.1:#{server.addr[1]}", verify_ssl: false)
    yield interface, received
  ensure
    thread.join(5) if thread
    server.close if server
  end

  def with_rest_client_execute_stub(handler)
    singleton = Morpheus::RestClient.singleton_class
    original_execute = singleton.instance_method(:execute)
    singleton.define_method(:execute, handler)
    yield
  ensure
    singleton.define_method(:execute, original_execute) if singleton && original_execute
  end

end
