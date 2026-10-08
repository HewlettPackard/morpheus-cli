require 'test/unit'
require 'stringio'
require 'morpheus'

# Offline exercise of the MORPH-17279 --cluster scope for
# AffinityGroupsCommand#violations. Unlike list/add, the violations endpoint
# (AffinityGroupsController#violations) only accepts clusterId or cloudId -- it
# has no poolId path and no vSphere-pool-scoped violation data. So a managed
# cluster name resolves to clusterId, while a cloud-owned vSphere cluster name
# must produce a clear error instead of silently exiting 1 or broadening scope.
class AffinityGroupsViolationsScopeTest < Test::Unit::TestCase
  class FakeAffinityGroupsInterface
    attr_reader :calls

    def initialize
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

    def violations(params = {})
      @calls << [:violations, params]
      return {'violations' => []} unless @dry

      {method: :get, url: "/api/affinity-groups/violations", params: params}
    end
  end

  class FakeCloudsInterface
    def initialize(cloud)
      @cloud = cloud
    end

    def setopts(_options); self; end
    def dry; self; end
    def get(id, params = {}); {'zone' => @cloud}; end
    def list(params = {}); {'zones' => [@cloud]}; end
  end

  class FakeResourcePoolsInterface
    def initialize(pools)
      @pools = pools
    end

    def get(cloud_id, id, params = {})
      {'resourcePool' => @pools.find {|p| p['id'].to_i == id.to_i }}
    end

    def list(cloud_id, params = {})
      {'resourcePools' => @pools}
    end

    def list_without_cloud(params = {})
      {'resourcePools' => @pools}
    end
  end

  class FakeClustersInterface
    def initialize(clusters = [])
      @clusters = clusters
    end

    def list(params = {})
      {'clusters' => @clusters.select {|cluster| cluster['name'] == params[:name]}}
    end
  end

  def setup
    @cloud = {'id' => 59, 'name' => 'vCenter Cloud'}
    @pool = {'id' => 501, 'name' => 'QA', 'type' => 'Cluster', 'zone' => @cloud}
  end

  def test_managed_cluster_name_scopes_violations_by_cluster_id
    command, affinity = build_command([{'id' => 8, 'name' => 'QA'}])

    output = capture_stdout { command.violations(['--cluster', 'QA', '--dry-run']) }

    assert_match(%r{/api/affinity-groups/violations}, output)
    assert_match(/clusterId=8/, output)
    assert_equal [[:violations, {'clusterId' => 8}]], affinity.calls
  end

  def test_vsphere_cluster_name_reports_clear_error_without_calling_violations
    command, affinity = build_command([])

    result = nil
    err = capture_stderr do
      capture_stdout { result = command.violations(['--cluster', 'QA', '--dry-run']) }
    end

    assert_equal 1, (result.is_a?(Array) ? result[0] : result)
    assert_match(/only available for Morpheus managed clusters/i, err)
    assert_match(/vCenter Cloud/, err)
    assert_empty affinity.calls
  end

  private

  def build_command(managed_clusters = [])
    affinity = FakeAffinityGroupsInterface.new
    clouds = FakeCloudsInterface.new(@cloud)
    pools = FakeResourcePoolsInterface.new([@pool])
    clusters = FakeClustersInterface.new(managed_clusters)
    command = Morpheus::Cli::AffinityGroupsCommand.new
    command.define_singleton_method(:connect) do |_options|
      @affinity_groups_interface = affinity
      @clouds_interface = clouds
      @clusters_interface = clusters
      @cloud_resource_pools_interface = pools
    end
    [command, affinity]
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
