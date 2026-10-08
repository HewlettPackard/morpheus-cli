require 'test/unit'
require 'stringio'
require 'morpheus'

class AffinityGroupsClusterScopeTest < Test::Unit::TestCase
  class FakeCloudsInterface
    attr_reader :calls

    def initialize(cloud)
      @cloud = cloud
      @calls = []
      @dry = false
    end

    def setopts(_options)
      self
    end

    def dry
      @dry = true
      self
    end

    def get(id, params = {})
      @calls << [:get, id, params]
      {'zone' => @cloud}
    end

    def list(params = {})
      @calls << [:list, params]
      {'zones' => [@cloud]}
    end

    def list_affinity_groups(id, params = {})
      @calls << [:list_affinity_groups, id, params]
      return {'affinityGroups' => []} unless @dry

      {method: :get, url: "/api/zones/#{id}/affinity-groups", params: params}
    end
  end

  class FakeResourcePoolsInterface
    attr_reader :calls

    def initialize(pool)
      @pool = pool
      @calls = []
    end

    def get(cloud_id, id, params = {})
      @calls << [:get, cloud_id, id, params]
      {'resourcePool' => @pool}
    end

    def list(cloud_id, params = {})
      @calls << [:list, cloud_id, params]
      {'resourcePools' => [@pool]}
    end

    def list_without_cloud(params = {})
      @calls << [:list_without_cloud, params]
      {'resourcePools' => [@pool]}
    end
  end

  class FakeClustersInterface
    attr_reader :calls

    def initialize(clusters = [])
      @clusters = clusters
      @calls = []
      @dry = false
    end

    def setopts(_options)
      self
    end

    def dry
      @dry = true
      self
    end

    def list(params = {})
      @calls << [:list, params]
      {'clusters' => @clusters.select {|cluster| cluster['name'] == params[:name]}}
    end

    def list_affinity_groups(id, params = {})
      @calls << [:list_affinity_groups, id, params]
      return {'affinityGroups' => []} unless @dry

      {method: :get, url: "/api/clusters/#{id}/affinity-groups", params: params}
    end
  end

  def setup
    @cloud = {'id' => 59, 'name' => 'vCenter Cloud'}
    @pool = {
      'id' => 501,
      'name' => 'QA',
      'type' => 'Cluster',
      'zone' => @cloud
    }
  end

  def test_cloud_qualified_cluster_sends_pool_id
    command, pools, = build_command

    output = capture_stdout do
      command.list(['--cloud', 'vCenter Cloud', '--cluster', 'QA', '--dry-run'])
    end

    assert_match(%r{/api/zones/59/affinity-groups}, output)
    assert_match(/poolId=501/, output)
    assert_equal [[:list, 59, {name: 'QA', type: 'Cluster'}]], pools.calls
  end

  def test_cluster_name_falls_back_to_unique_vsphere_cluster
    command, pools, clusters = build_command

    output = capture_stdout { command.list(['--cluster', 'QA', '--dry-run']) }

    assert_match(%r{/api/zones/59/affinity-groups}, output)
    assert_match(/poolId=501/, output)
    assert_equal [[:list, {name: 'QA'}]], clusters.calls
    assert_equal [
      [:list_without_cloud, {name: 'QA', type: 'Cluster', max: 1000}]
    ], pools.calls
  end

  def test_managed_cluster_takes_precedence
    managed_cluster = {'id' => 8, 'name' => 'QA'}
    command, pools, clusters = build_command([managed_cluster])

    output = capture_stdout { command.list(['--cluster', 'QA', '--dry-run']) }

    assert_match(%r{/api/clusters/8/affinity-groups}, output)
    assert_equal [
      [:list, {name: 'QA'}],
      [:list_affinity_groups, 8, {}]
    ], clusters.calls
    assert_empty pools.calls
  end

  private

  def build_command(managed_clusters = [])
    clouds = FakeCloudsInterface.new(@cloud)
    pools = FakeResourcePoolsInterface.new(@pool)
    clusters = FakeClustersInterface.new(managed_clusters)
    command = Morpheus::Cli::AffinityGroupsCommand.new
    command.define_singleton_method(:connect) do |_options|
      @clouds_interface = clouds
      @clusters_interface = clusters
      @cloud_resource_pools_interface = pools
    end
    [command, pools, clusters]
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
