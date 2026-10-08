require 'test/unit'
require 'stringio'
require 'json'
require 'morpheus'

# Unit tests for the MORPH-17279 cloud-owned vSphere cluster resolver added to
# Morpheus::Cli::InfrastructureHelper:
#   find_resource_pool_cluster_by_name_or_id / _by_id / _by_name
#
# These are pure unit tests against a fake CloudResourcePoolsInterface. They
# deliberately do NOT extend MorpheusTest::TestCase because they require no
# appliance, no remote and no authentication - they must always be runnable.
# See test/cli/affinity_helper_test.rb for the established pattern this
# follows.
#
# Bug context: --cloud CLOUD --cluster CLUSTER must resolve CLUSTER as a
# ComputeZonePool(type='Cluster') owned by CLOUD, distinct from the managed
# cluster (ComputeServerGroup) namespace resolved via ClustersInterface. A
# name lookup that traverses ambiguous, wrong-cloud or wrong-type pools must
# fail loudly instead of returning nil silently or the wrong pool.
class InfrastructureHelperClusterResolverTest < Test::Unit::TestCase

  # Fake standing in for Morpheus::CloudResourcePoolsInterface. Records every
  # call so tests can assert exactly what was requested, mirroring the
  # dry-run request assertions used elsewhere in this suite.
  class FakeResourcePoolsInterface
    attr_reader :get_calls, :list_calls

    def initialize(get_result: nil, get_error: nil, list_result: nil)
      @get_result = get_result
      @get_error = get_error
      @list_result = list_result
      @get_calls = []
      @list_calls = []
    end

    def get(cloud_id, id, params = {})
      @get_calls << [cloud_id, id, params]
      raise @get_error if @get_error
      @get_result
    end

    def list(cloud_id, params = {})
      @list_calls << [cloud_id, params]
      @list_result
    end
  end

  class FakeClustersInterface
    def initialize(get_result: nil, get_error: nil, list_result: nil)
      @get_result = get_result
      @get_error = get_error
      @list_result = list_result || {'clusters' => []}
    end

    def get(id)
      raise @get_error if @get_error
      @get_result
    end

    def list(params = {})
      @list_result
    end
  end

  # Bare host for the mixin under test.
  class HelperHost
    include Morpheus::Cli::InfrastructureHelper

    def initialize(fake_interface, clusters_interface=nil)
      @cloud_resource_pools_interface = fake_interface
      @clusters_interface = clusters_interface if clusters_interface
    end
  end

  def fake_not_found_error
    response = Object.new
    def response.code; 404; end
    RestClient::Exception.new(response)
  end

  def fake_server_error
    response = Object.new
    def response.code; 500; end
    RestClient::Exception.new(response)
  end

  def cloud
    {'id' => 59, 'name' => 'vCenter Cloud'}
  end

  # print_red_alert writes straight to $stderr (print_helper.rb) - capture it.
  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  ## find_resource_pool_cluster_by_id

  def test_find_by_id_returns_the_pool_when_it_is_a_cluster_in_the_cloud
    fake = FakeResourcePoolsInterface.new(get_result: {
      'resourcePool' => {'id' => 501, 'name' => 'QA', 'type' => 'Cluster', 'zone' => {'id' => 59, 'name' => 'vCenter Cloud'}}
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_id(cloud, 501)
    assert_not_nil pool
    assert_equal 501, pool['id']
    assert_equal 'QA', pool['name']
    # Scoped to the cloud -- the server itself enforces ownership.
    assert_equal [[59, 501, {}]], fake.get_calls
  end

  # ZoneResourcePoolsController#show 404s when the pool's zone does not match
  # the requested cloud -- this is the server-side cloud-ownership check.
  def test_find_by_id_reports_not_found_on_404_without_raising
    fake = FakeResourcePoolsInterface.new(get_error: fake_not_found_error)
    helper = HelperHost.new(fake)
    pool = nil
    output = capture_stderr { pool = helper.find_resource_pool_cluster_by_id(cloud, 999) }
    assert_nil pool
    assert_match(/not found by id 999/i, output)
    assert_match(/vCenter Cloud/, output)
  end

  # A non-404 failure (auth, server error, etc.) must not be swallowed as a
  # not-found -- that would hide a real problem behind a wrong error message.
  def test_find_by_id_reraises_non_404_errors
    fake = FakeResourcePoolsInterface.new(get_error: fake_server_error)
    helper = HelperHost.new(fake)
    assert_raise(RestClient::Exception) { helper.find_resource_pool_cluster_by_id(cloud, 501) }
  end

  def test_find_by_id_rejects_a_non_cluster_resource_pool
    fake = FakeResourcePoolsInterface.new(get_result: {
      'resourcePool' => {'id' => 501, 'name' => 'Folder A', 'type' => 'ResourcePool', 'zone' => {'id' => 59, 'name' => 'vCenter Cloud'}}
    })
    helper = HelperHost.new(fake)
    pool = nil
    output = capture_stderr { pool = helper.find_resource_pool_cluster_by_id(cloud, 501) }
    assert_nil pool
    assert_match(/not a Cluster/i, output)
    assert_match(/ResourcePool/, output)
  end

  ## find_resource_pool_cluster_by_name

  def test_find_by_name_returns_the_single_match
    fake = FakeResourcePoolsInterface.new(list_result: {
      'resourcePools' => [
        {'id' => 501, 'name' => 'QA', 'type' => 'Cluster'},
      ]
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_name(cloud, 'QA')
    assert_not_nil pool
    assert_equal 501, pool['id']
    assert_equal [[59, {name: 'QA', type: 'Cluster'}]], fake.list_calls
  end

  def test_find_by_name_matches_on_display_name
    fake = FakeResourcePoolsInterface.new(list_result: {
      'resourcePools' => [
        {'id' => 501, 'name' => 'internal-qa-01', 'displayName' => 'QA', 'type' => 'Cluster'},
      ]
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_name(cloud, 'QA')
    assert_not_nil pool
    assert_equal 501, pool['id']
  end

  def test_find_by_name_reports_not_found_with_a_managed_cluster_hint
    fake = FakeResourcePoolsInterface.new(list_result: {'resourcePools' => []})
    helper = HelperHost.new(fake)
    pool = nil
    output = capture_stderr { pool = helper.find_resource_pool_cluster_by_name(cloud, 'QA') }
    assert_nil pool
    assert_match(/not found by name 'QA'/i, output)
    assert_match(/vCenter Cloud/, output)
    assert_match(/--cluster 'QA' without --cloud/, output)
  end

  # The cloud-scoped resource-pools endpoint returns a pool *tree*: when the
  # matched pool has a parent folder, ancestor entries are backfilled into the
  # result so the hierarchy renders, even though they do not match the
  # name/type filter. The resolver must not misreport this as ambiguity.
  def test_find_by_name_ignores_ancestor_tree_padding
    fake = FakeResourcePoolsInterface.new(list_result: {
      'resourcePools' => [
        {'id' => 10, 'name' => 'Datacenter Folder', 'type' => 'Folder', 'depth' => 0},
        {'id' => 501, 'name' => 'QA', 'type' => 'Cluster', 'depth' => 1},
      ]
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_name(cloud, 'QA')
    assert_not_nil pool, "the ancestor folder must not be counted as a second match"
    assert_equal 501, pool['id']
  end

  def test_find_by_name_reports_ambiguity_with_candidates_and_requires_numeric_id
    fake = FakeResourcePoolsInterface.new(list_result: {
      'resourcePools' => [
        {'id' => 501, 'name' => 'QA', 'type' => 'Cluster'},
        {'id' => 502, 'name' => 'QA', 'type' => 'Cluster'},
      ]
    })
    helper = HelperHost.new(fake)
    pool = nil
    output = capture_stderr { pool = helper.find_resource_pool_cluster_by_name(cloud, 'QA') }
    assert_nil pool
    assert_match(/2 clusters found by name 'QA'/i, output)
    assert_match(/numeric cluster id/i, output)
  end

  ## find_resource_pool_cluster_by_name_or_id dispatch

  def test_find_by_name_or_id_dispatches_numeric_strings_to_by_id
    fake = FakeResourcePoolsInterface.new(get_result: {
      'resourcePool' => {'id' => 501, 'name' => 'QA', 'type' => 'Cluster', 'zone' => {'id' => 59}}
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_name_or_id(cloud, '501')
    assert_not_nil pool
    assert_equal 1, fake.get_calls.size
    assert_equal 0, fake.list_calls.size
  end

  def test_find_by_name_or_id_dispatches_non_numeric_strings_to_by_name
    fake = FakeResourcePoolsInterface.new(list_result: {
      'resourcePools' => [{'id' => 501, 'name' => 'QA', 'type' => 'Cluster'}]
    })
    helper = HelperHost.new(fake)
    pool = helper.find_resource_pool_cluster_by_name_or_id(cloud, 'QA')
    assert_not_nil pool
    assert_equal 0, fake.get_calls.size
    assert_equal 1, fake.list_calls.size
  end

  def test_managed_cluster_lookup_reraises_non_404_errors
    pools = FakeResourcePoolsInterface.new
    clusters = FakeClustersInterface.new(get_error: fake_server_error)
    helper = HelperHost.new(pools, clusters)
    assert_raise(RestClient::Exception) { helper.find_managed_cluster_by_name_or_id('8') }
  end

end
