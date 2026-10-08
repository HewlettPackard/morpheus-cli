require 'test/unit'
require 'stringio'
require 'morpheus'

# Unit tests for MORPH-15042: cluster uuid support in the clusters command.
#   - clusters get UUID resolves a single cluster via the path endpoint
#     (/api/clusters/{uuid}), not the name query filter.
#   - clusters list --uuid UUID [--uuid UUID ...] filters by one or more uuids.
#
# These follow the established pure-unit pattern (a fake ClustersInterface
# recording calls; Test::Unit::TestCase, no appliance/auth required). See
# test/cli/affinity_groups_cluster_scope_test.rb for the pattern this mirrors.
class ClustersUuidTest < Test::Unit::TestCase
  # Records every call so tests can assert exactly what the command requested.
  class FakeClustersInterface
    attr_reader :get_calls, :list_calls

    def initialize(clusters: [], get_result: nil)
      @clusters = clusters
      @get_result = get_result
      @get_calls = []
      @list_calls = []
      @dry = false
    end

    def setopts(_options)
      self
    end

    def dry
      @dry = true
      self
    end

    def get(arg)
      @get_calls << arg
      @get_result || {'cluster' => {'id' => 42, 'name' => 'k8s-1'}}
    end

    def list(params = {})
      @list_calls << params
      return {method: :get, url: '/api/clusters', params: params} if @dry
      {'clusters' => @clusters.select {|c| c['name'] == params[:name] }}
    end
  end

  def setup
    @uuid = 'a1b2c3d4-e5f6-4711-8899-0011223344ff'
  end

  ## find_cluster_by_name_or_id dispatch

  def test_uuid_resolves_via_path_get_not_name_list
    command, clusters = build_command
    cluster = command.send(:find_cluster_by_name_or_id, @uuid)
    assert_equal 42, cluster['id']
    # The uuid is handed to get as a String path segment, never a name list.
    assert_equal [@uuid], clusters.get_calls
    assert_empty clusters.list_calls
  end

  def test_numeric_id_still_resolves_via_path_get
    command, clusters = build_command
    command.send(:find_cluster_by_name_or_id, '7')
    assert_equal [7], clusters.get_calls
    assert_empty clusters.list_calls
  end

  def test_name_still_resolves_via_list_by_name
    managed = {'id' => 9, 'name' => 'prod'}
    command, clusters = build_command([managed])
    cluster = command.send(:find_cluster_by_name_or_id, 'prod')
    assert_equal 9, cluster['id']
    assert_equal [{name: 'prod'}], clusters.list_calls
    assert_empty clusters.get_calls
  end

  def test_cluster_uuid_predicate
    command, = build_command
    assert command.send(:cluster_uuid?, @uuid)
    assert command.send(:cluster_uuid?, @uuid.upcase)
    assert !command.send(:cluster_uuid?, '7')
    assert !command.send(:cluster_uuid?, 'prod')
    assert !command.send(:cluster_uuid?, 'a1b2c3d4-e5f6-4711-8899-0011223344')
  end

  ## clusters list --uuid

  def test_list_with_single_uuid_carries_uuid_param
    command, = build_command
    output = capture_stdout { command.list(['--uuid', @uuid, '--dry-run']) }
    assert_match(/#{Regexp.escape(@uuid)}/, output)
  end

  def test_list_with_multiple_uuids_carries_all_uuids
    command, = build_command
    other = 'ffeeddcc-bbaa-4998-8776-655443322110'
    output = capture_stdout { command.list(['--uuid', @uuid, '--uuid', other, '--dry-run']) }
    assert_match(/#{Regexp.escape(@uuid)}/, output)
    assert_match(/#{Regexp.escape(other)}/, output)
  end

  def test_list_without_uuid_has_no_uuid_param
    command, = build_command
    output = capture_stdout { command.list(['--dry-run']) }
    assert_no_match(/uuid/i, output)
  end

  private

  def build_command(managed_clusters = [], get_result: nil)
    clusters = FakeClustersInterface.new(clusters: managed_clusters, get_result: get_result)
    command = Morpheus::Cli::Clusters.new
    command.instance_variable_set(:@clusters_interface, clusters)
    command.define_singleton_method(:connect) do |_options|
      @clusters_interface = clusters
    end
    [command, clusters]
  end

  def capture_stdout
    terminal = Morpheus::Terminal.instance
    original = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    yield
    buffer.string
  ensure
    terminal.set_stdout(original)
  end
end
