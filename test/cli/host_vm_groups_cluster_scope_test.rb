require 'test/unit'
require 'stringio'
require 'morpheus'

# Command-level offline exercise of the MORPH-17279 --cluster scope for
# HostVmGroupsCommand#list. Parallels affinity_groups_cluster_scope_test.rb:
# a bare --cluster name must resolve either to a managed cluster (POST/GET under
# /api/clusters/{id}/...) or, failing that, fall back to a cloud-owned vSphere
# cluster (ComputeZonePool type=Cluster) and scope the zone request with poolId.
# A name that matches neither must fail loudly, not exit 1 silently.
class HostVmGroupsClusterScopeTest < Test::Unit::TestCase
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

    def list_host_vm_groups(id, params = {})
      @calls << [:list_host_vm_groups, id, params]
      return {'hostVmGroups' => []} unless @dry

      {method: :get, url: "/api/zones/#{id}/host-vm-groups", params: params}
    end
  end

  class FakeResourcePoolsInterface
    attr_reader :calls

    def initialize(pools)
      @pools = pools
      @calls = []
    end

    def get(cloud_id, id, params = {})
      @calls << [:get, cloud_id, id, params]
      {'resourcePool' => @pools.find {|p| p['id'].to_i == id.to_i }}
    end

    def list(cloud_id, params = {})
      @calls << [:list, cloud_id, params]
      {'resourcePools' => @pools}
    end

    def list_without_cloud(params = {})
      @calls << [:list_without_cloud, params]
      {'resourcePools' => @pools}
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

    def list_host_vm_groups(id, params = {})
      @calls << [:list_host_vm_groups, id, params]
      return {'hostVmGroups' => []} unless @dry

      {method: :get, url: "/api/clusters/#{id}/host-vm-groups", params: params}
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

  def test_cluster_name_falls_back_to_unique_vsphere_cluster
    command, pools, clusters = build_command

    output = capture_stdout { command.list(['--cluster', 'QA', '--dry-run']) }

    assert_match(%r{/api/zones/59/host-vm-groups}, output)
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

    assert_match(%r{/api/clusters/8/host-vm-groups}, output)
    assert_equal [
      [:list, {name: 'QA'}],
      [:list_host_vm_groups, 8, {}]
    ], clusters.calls
    assert_empty pools.calls
  end

  def test_unknown_cluster_name_fails_loudly
    command, _pools, _clusters = build_command([], [])

    result = nil
    err = capture_stderr do
      capture_stdout { result = command.list(['--cluster', 'nope', '--dry-run']) }
    end

    assert_equal 1, (result.is_a?(Array) ? result[0] : result)
    assert_match(/No managed or vSphere cluster found by name 'nope'/i, err)
  end

  private

  def build_command(managed_clusters = [], pools = nil)
    pools = [@pool] if pools.nil?
    clouds = FakeCloudsInterface.new(@cloud)
    pools_interface = FakeResourcePoolsInterface.new(pools)
    clusters = FakeClustersInterface.new(managed_clusters)
    command = Morpheus::Cli::HostVmGroupsCommand.new
    command.define_singleton_method(:connect) do |_options|
      @clouds_interface = clouds
      @clusters_interface = clusters
      @cloud_resource_pools_interface = pools_interface
    end
    [command, pools_interface, clusters]
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

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end
