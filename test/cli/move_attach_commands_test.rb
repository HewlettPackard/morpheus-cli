require 'test/unit'
require 'stringio'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/hosts'
require 'morpheus/cli/commands/instances'

# hosts move|attach-volume|detach-volume and instances move, run against fake API objects.
# Pure unit tests: no appliance, remote or authentication is needed.
class MoveAttachCommandsTest < Test::Unit::TestCase

  class FakeInterface
    attr_reader :calls

    def initialize(records={})
      @records = records
      @calls = []
    end

    def setopts(_options)
      self
    end

    def get(id, *_rest)
      key = @records[:one]
      {key => (@records[:by_id] || {}).fetch(id.to_i) { raise "unexpected get(#{id.inspect})" }}
    end

    def list(params={})
      key = @records[:many]
      {key => (@records[:all] || []).select { |it| params[:name].nil? || it['name'].include?(params[:name]) }}
    end

    def bulk_move(ids, payload, params)
      @calls << [:bulk_move, ids, payload, params]
      {'success' => true, 'msg' => "#{ids.size} queued for move"}
    end

    def attach_volume(id, volume_id, payload)
      @calls << [:attach_volume, id, volume_id, payload]
      {'success' => true, 'executionId' => 'abc'}
    end

    def detach_volume(id, volume_id, params)
      @calls << [:detach_volume, id, volume_id, params]
      {'success' => true, 'executionId' => 'abc'}
    end

    # a real interface produces the dry-run request so the printed output is realistic
    def dry
      Morpheus::ServersInterface.new(access_token: 'token', url: 'https://example.test', verify_ssl: false).dry
    end
  end

  class FakeApi
    attr_reader :servers, :instances, :clusters

    def initialize
      @servers = FakeInterface.new(one: 'server', many: 'servers',
        by_id: {7 => {'id' => 7, 'name' => 'host-a'}, 8 => {'id' => 8, 'name' => 'host-b'}, 11 => {'id' => 11, 'name' => 'target-host'}},
        all: [{'id' => 7, 'name' => 'host-a'}, {'id' => 11, 'name' => 'target-host'}])
      @instances = FakeInterface.new(one: 'instance', many: 'instances',
        by_id: {1 => {'id' => 1, 'name' => 'web-1'}, 2 => {'id' => 2, 'name' => 'web-2'}},
        all: [{'id' => 1, 'name' => 'web-1'}])
      @clusters = FakeInterface.new(one: 'cluster', many: 'clusters',
        by_id: {3 => {'id' => 3, 'name' => 'cluster-a'}},
        all: [{'id' => 5, 'name' => 'cluster-b'}, {'id' => 6, 'name' => 'cluster-b-dr'}])
    end
  end

  def setup
    @api = FakeApi.new
  end

  def command(klass)
    api = @api
    klass.new.tap do |cmd|
      cmd.define_singleton_method(:connect) do |_opts|
        @api_client = api
        @servers_interface = api.servers
        @instances_interface = api.instances
        @clusters_interface = api.clusters
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

  def test_the_new_subcommands_are_registered
    hosts = Morpheus::Cli::Hosts.new.subcommands.keys
    instances = Morpheus::Cli::Instances.new.subcommands.keys

    assert_include hosts, 'move'
    assert_include hosts, 'attach-volume'
    assert_include hosts, 'detach-volume'
    assert_include instances, 'move'
  end

  def test_host_move_requires_a_host
    assert_raise(Morpheus::Cli::CommandArgumentsError) { command(Morpheus::Cli::Hosts).move(['--target-cluster', '3', '-y']) }
  end

  def test_host_move_requires_a_target_cluster
    error = assert_raise(Morpheus::Cli::CommandError) { command(Morpheus::Cli::Hosts).move(['7', '-y']) }

    assert_match(/--target-cluster is required/, error.message)
  end

  def test_instance_move_requires_a_target_cluster
    assert_raise(Morpheus::Cli::CommandError) { command(Morpheus::Cli::Instances).move(['1', '-y']) }
  end

  def test_move_rejects_a_malformed_datastore_map
    error = assert_raise(Morpheus::Cli::CommandError) do
      command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '--datastore-map', '12-34', '-y'])
    end

    assert_match(/datastore-map/, error.message)
  end

  def test_move_rejects_a_network_map_that_is_not_numeric
    assert_raise(Morpheus::Cli::CommandError) do
      command(Morpheus::Cli::Instances).move(['1', '--target-cluster', '3', '--network-map', 'lan=9', '-y'])
    end
  end

  def test_host_move_sends_the_target_and_every_move_option
    run_capturing_output do
      command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', 'cluster-b', '--target-host', '11',
        '--datastore-map', '12=34,13=35', '--network-map', '3=9', '--migration-timeout', '300',
        '--cpu-throttling', '--force', '-y'])
    end

    expected = {'targetClusterId' => 5, 'targetHostId' => 11, 'datastoreMap' => {'12' => 34, '13' => 35},
                'networkMap' => {'3' => 9}, 'migrationTimeout' => 300, 'enableCpuThrottling' => true}
    assert_equal [[:bulk_move, [7], expected, {'force' => true}]], @api.servers.calls
  end

  def test_host_move_sends_only_the_target_cluster_by_default
    run_capturing_output { command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '-y']) }

    assert_equal [[:bulk_move, [7], {'targetClusterId' => 3}, {}]], @api.servers.calls
  end

  def test_host_move_can_turn_cpu_throttling_off_explicitly
    run_capturing_output { command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '--cpu-throttling', 'off', '-y']) }

    assert_equal false, @api.servers.calls[0][2]['enableCpuThrottling']
  end

  def test_host_move_accepts_several_hosts
    run_capturing_output { command(Morpheus::Cli::Hosts).move(['7,8', '--target-cluster', '3', '-y']) }

    assert_equal [7, 8], @api.servers.calls[0][1]
  end

  def test_move_prefers_an_exact_cluster_name_over_a_partial_match
    run_capturing_output { command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', 'cluster-b', '-y']) }

    assert_equal 5, @api.servers.calls[0][2]['targetClusterId']
  end

  def test_move_with_a_payload_needs_no_target_cluster_option
    run_capturing_output do
      command(Morpheus::Cli::Hosts).move(['7', '--payload-json', '{"targetClusterId": 9}', '-y'])
    end

    assert_equal [[:bulk_move, [7], {'targetClusterId' => 9}, {}]], @api.servers.calls
    assert_empty @api.clusters.calls
  end

  def test_move_option_passes_extra_fields_through
    run_capturing_output do
      command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '-O', 'migrationTimeout=120', '-y'])
    end

    assert_equal '120', @api.servers.calls[0][2]['migrationTimeout']
  end

  def test_move_reports_the_message_the_api_returned
    output = run_capturing_output { command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '-y']) }

    assert_match(/1 queued for move/, output)
  end

  def test_move_dry_run_prints_the_request_and_sends_nothing
    output = run_capturing_output { command(Morpheus::Cli::Hosts).move(['7', '--target-cluster', '3', '--dry-run', '-y']) }

    assert_match(%r{PUT https://example.test/api/servers/bulk-move}, output)
    assert_match(/"targetClusterId": 3/, output)
    assert_empty @api.servers.calls
  end

  def test_instance_move_uses_the_instances_interface
    run_capturing_output { command(Morpheus::Cli::Instances).move(['1', '--target-cluster', '3', '--force', '-y']) }

    assert_equal [[:bulk_move, [1], {'targetClusterId' => 3}, {'force' => true}]], @api.instances.calls
    assert_empty @api.servers.calls
  end

  def test_instance_move_accepts_several_instances
    run_capturing_output { command(Morpheus::Cli::Instances).move(['1', '2', '--target-cluster', '3', '-y']) }

    assert_equal [1, 2], @api.instances.calls[0][1]
  end

  def test_attach_volume_requires_a_host_and_a_volume
    assert_raise(Morpheus::Cli::CommandArgumentsError) { command(Morpheus::Cli::Hosts).attach_volume(['7']) }
    assert_raise(Morpheus::Cli::CommandArgumentsError) { command(Morpheus::Cli::Hosts).attach_volume(['7', '55', 'extra']) }
  end

  def test_attach_volume_queues_the_attach
    output = run_capturing_output { command(Morpheus::Cli::Hosts).attach_volume(['7', '55']) }

    assert_equal [[:attach_volume, 7, '55', {}]], @api.servers.calls
    assert_match(/Attaching volume 55 to host host-a/, output)
  end

  def test_attach_volume_passes_options_through_such_as_root_volume
    run_capturing_output { command(Morpheus::Cli::Hosts).attach_volume(['7', '55', '-O', 'rootVolume=true']) }

    assert_equal [[:attach_volume, 7, '55', {'rootVolume' => true}]], @api.servers.calls
  end

  def test_attach_volume_accepts_a_volume_uuid
    run_capturing_output { command(Morpheus::Cli::Hosts).attach_volume(['7', '3f2a9c1e-1111-2222-3333-444455556666']) }

    assert_equal '3f2a9c1e-1111-2222-3333-444455556666', @api.servers.calls[0][2]
  end

  def test_detach_volume_requires_a_host_and_a_volume
    assert_raise(Morpheus::Cli::CommandArgumentsError) { command(Morpheus::Cli::Hosts).detach_volume(['7', '-y']) }
  end

  def test_detach_volume_queues_the_detach
    run_capturing_output { command(Morpheus::Cli::Hosts).detach_volume(['7', '55', '-y']) }

    assert_equal [[:detach_volume, 7, '55', {}]], @api.servers.calls
  end

  def test_detach_volume_sends_force_as_a_query_parameter
    run_capturing_output { command(Morpheus::Cli::Hosts).detach_volume(['7', '55', '--force', '-y']) }

    assert_equal [[:detach_volume, 7, '55', {'force' => true}]], @api.servers.calls
  end

  def test_detach_volume_dry_run_sends_nothing
    output = run_capturing_output { command(Morpheus::Cli::Hosts).detach_volume(['7', '55', '--dry-run', '-y']) }

    assert_match(%r{PUT https://example.test/api/servers/7/volumes/55/detach}, output)
    assert_empty @api.servers.calls
  end

end
