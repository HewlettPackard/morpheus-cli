require 'test/unit'
require 'stringio'
require 'json'
require 'morpheus'

# Command-level offline exercise of the MORPH-17279 --cloud + --cluster
# (vSphere cluster) scope for AffinityGroupsCommand and HostVmGroupsCommand
# list/add. Runs the real command methods end-to-end (option parsing, scope
# resolution, --dry-run request construction) against fake interfaces, so no
# live appliance or credentials are required.
#
# This complements infrastructure_helper_cluster_resolver_test.rb (which
# unit-tests the resolver in isolation) by proving the resolved pool actually
# flows into list (poolId query param) and add (pool.id in the create
# payload), exactly as it would against a real appliance.
class AffinityGroupsCloudClusterScopeTest < Test::Unit::TestCase

  # Fake for Morpheus::CloudsInterface -- records every call, answers cloud
  # name/id lookups, and answers .dry.* calls with a print_dry_run-compatible
  # request hash (mirrors how Morpheus::APIClient#dry / #execute behave).
  class FakeCloudsInterface
    attr_reader :calls

    def initialize(cloud:)
      @cloud = cloud
      @calls = []
      @dry = false
    end

    def setopts(options); self; end
    def dry; @dry = true; self; end

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
      respond({'affinityGroups' => []}) { {method: :get, url: "/api/zones/#{id}/affinity-groups", params: params} }
    end

    def create_affinity_group(id, payload)
      @calls << [:create_affinity_group, id, payload]
      respond({'affinityGroup' => {'id' => 1}}) { {method: :post, url: "/api/zones/#{id}/affinity-groups", payload: payload.to_json} }
    end

    def affinity_group_form_options(id, params = {})
      @calls << [:affinity_group_form_options, id, params]
      {'supportsCombinedRules' => true, 'availableVmGroups' => [], 'availableHostGroups' => []}
    end

    def list_host_vm_groups(id, params = {})
      @calls << [:list_host_vm_groups, id, params]
      respond({'hostVmGroups' => []}) { {method: :get, url: "/api/zones/#{id}/host-vm-groups", params: params} }
    end

    def create_host_vm_group(id, payload)
      @calls << [:create_host_vm_group, id, payload]
      respond({'hostVmGroup' => {'id' => 1}}) { {method: :post, url: "/api/zones/#{id}/host-vm-groups", payload: payload.to_json} }
    end

    def host_vm_group_form_options(id, params = {})
      @calls << [:host_vm_group_form_options, id, params]
      {'availableServers' => []}
    end

    private

    def respond(real_result)
      @dry ? yield : real_result
    end
  end

  # Fake for Morpheus::CloudResourcePoolsInterface -- used by
  # find_resource_pool_cluster_by_name_or_id.
  class FakeResourcePoolsInterface
    attr_reader :calls

    def initialize(pool:)
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

    def initialize(clusters: [])
      @clusters = clusters
      @calls = []
      @dry = false
    end

    def setopts(options); self; end
    def dry; @dry = true; self; end

    def get(id, params = {})
      @calls << [:get, id, params]
      {'cluster' => @clusters.find {|cluster| cluster['id'].to_i == id.to_i}}
    end

    def list(params = {})
      @calls << [:list, params]
      {'clusters' => @clusters.select {|cluster| cluster['name'] == params[:name]}}
    end

    def list_affinity_groups(id, params = {})
      @calls << [:list_affinity_groups, id, params]
      respond({'affinityGroups' => []}) { {method: :get, url: "/api/clusters/#{id}/affinity-groups", params: params} }
    end

    def list_host_vm_groups(id, params = {})
      @calls << [:list_host_vm_groups, id, params]
      respond({'hostVmGroups' => []}) { {method: :get, url: "/api/clusters/#{id}/host-vm-groups", params: params} }
    end

    private

    def respond(real_result)
      @dry ? yield : real_result
    end
  end

  def cloud
    {'id' => 59, 'name' => 'vCenter Cloud'}
  end

  def pool
    {'id' => 501, 'name' => 'QA', 'type' => 'Cluster', 'zone' => {'id' => 59, 'name' => 'vCenter Cloud'}}
  end

  def build_affinity_command(managed_clusters: [])
    cmd = Morpheus::Cli::AffinityGroupsCommand.new
    fake_clouds = FakeCloudsInterface.new(cloud: cloud)
    fake_pools = FakeResourcePoolsInterface.new(pool: pool)
    fake_clusters = FakeClustersInterface.new(clusters: managed_clusters)
    cmd.define_singleton_method(:connect) do |opts|
      instance_variable_set(:@affinity_groups_interface, nil)
      instance_variable_set(:@clouds_interface, fake_clouds)
      instance_variable_set(:@clusters_interface, fake_clusters)
      instance_variable_set(:@cloud_resource_pools_interface, fake_pools)
    end
    [cmd, fake_clouds, fake_pools, fake_clusters]
  end

  def build_host_vm_command(managed_clusters: [])
    cmd = Morpheus::Cli::HostVmGroupsCommand.new
    fake_clouds = FakeCloudsInterface.new(cloud: cloud)
    fake_pools = FakeResourcePoolsInterface.new(pool: pool)
    fake_clusters = FakeClustersInterface.new(clusters: managed_clusters)
    cmd.define_singleton_method(:connect) do |opts|
      instance_variable_set(:@host_vm_groups_interface, nil)
      instance_variable_set(:@clouds_interface, fake_clouds)
      instance_variable_set(:@clusters_interface, fake_clusters)
      instance_variable_set(:@cloud_resource_pools_interface, fake_pools)
    end
    [cmd, fake_clouds, fake_pools, fake_clusters]
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

  ## AffinityGroupsCommand

  def test_affinity_groups_list_cloud_cluster_combo_sends_pool_id
    cmd, _fake_clouds, fake_pools, _fake_clusters = build_affinity_command
    output = capture_stdout { cmd.list(['--cloud', 'vCenter Cloud', '--cluster', 'QA', '--dry-run']) }
    assert_match(/poolId=501/, output, "dry-run request must carry the resolved poolId, got: #{output}")
    assert_match(%r{/api/zones/59/affinity-groups}, output)
    # Name resolution stayed scoped to the cloud and to type=Cluster.
    assert_equal [[:list, 59, {name: 'QA', type: 'Cluster'}]], fake_pools.calls
  end

  def test_affinity_groups_add_cloud_cluster_combo_sets_pool_id_payload
    cmd, fake_clouds, _fake_pools, _fake_clusters = build_affinity_command
    payload_json = '{"affinityGroup":{"name":"cli-test","affinityType":"KEEP_TOGETHER","servers":[{"id":1}]}}'
    output = capture_stdout do
      cmd.add(['--cloud', 'vCenter Cloud', '--cluster', 'QA', '--payload-json', payload_json, '--dry-run'])
    end
    assert_match(%r{/api/zones/59/affinity-groups}, output, "must POST to the zone endpoint, not a cluster endpoint")
    create_call = fake_clouds.calls.find {|c| c[0] == :create_affinity_group }
    assert_not_nil create_call, "create_affinity_group must be called on the clouds interface"
    payload = create_call[2].is_a?(String) ? JSON.parse(create_call[2]) : create_call[2]
    assert_equal({'id' => 501}, payload['affinityGroup']['pool'])
    assert_nil payload['affinityGroup']['cloudId']
    assert_nil payload['affinityGroup']['clusterId']
  end

  def test_affinity_groups_list_cluster_name_falls_back_to_unique_vsphere_cluster
    cmd, _fake_clouds, fake_pools, fake_clusters = build_affinity_command
    output = capture_stdout { cmd.list(['--cluster', 'QA', '--dry-run']) }
    assert_match(%r{/api/zones/59/affinity-groups}, output)
    assert_match(/poolId=501/, output)
    assert_equal [[:list, {name: 'QA'}]], fake_clusters.calls
    assert_equal [[:list_without_cloud, {name: 'QA', type: 'Cluster', max: 1000}]], fake_pools.calls
  end

  def test_affinity_groups_list_cluster_name_preserves_managed_cluster_precedence
    managed_cluster = {'id' => 8, 'name' => 'QA'}
    cmd, _fake_clouds, fake_pools, fake_clusters = build_affinity_command(managed_clusters: [managed_cluster])
    output = capture_stdout { cmd.list(['--cluster', 'QA', '--dry-run']) }
    assert_match(%r{/api/clusters/8/affinity-groups}, output)
    assert_equal [[:list, {name: 'QA'}], [:list_affinity_groups, 8, {}]], fake_clusters.calls
    assert_empty fake_pools.calls
  end

  ## HostVmGroupsCommand

  def test_host_vm_groups_list_cloud_cluster_combo_sends_pool_id
    cmd, _fake_clouds, fake_pools, _fake_clusters = build_host_vm_command
    output = capture_stdout { cmd.list(['--cloud', 'vCenter Cloud', '--cluster', 'QA', '--dry-run']) }
    assert_match(/poolId=501/, output, "dry-run request must carry the resolved poolId, got: #{output}")
    assert_match(%r{/api/zones/59/host-vm-groups}, output)
    assert_equal [[:list, 59, {name: 'QA', type: 'Cluster'}]], fake_pools.calls
  end

  def test_host_vm_groups_add_cloud_cluster_combo_sets_pool_id_payload
    cmd, fake_clouds, _fake_pools, _fake_clusters = build_host_vm_command
    payload_json = '{"hostVmGroup":{"name":"cli-test","type":"HOST_GROUP","servers":[{"id":1}]}}'
    output = capture_stdout do
      cmd.add(['--cloud', 'vCenter Cloud', '--cluster', 'QA', '--payload-json', payload_json, '--dry-run'])
    end
    assert_match(%r{/api/zones/59/host-vm-groups}, output, "must POST to the zone endpoint, not a cluster endpoint")
    create_call = fake_clouds.calls.find {|c| c[0] == :create_host_vm_group }
    assert_not_nil create_call, "create_host_vm_group must be called on the clouds interface"
    payload = create_call[2].is_a?(String) ? JSON.parse(create_call[2]) : create_call[2]
    assert_equal({'id' => 501}, payload['hostVmGroup']['pool'])
    assert_nil payload['hostVmGroup']['cloudId']
    assert_nil payload['hostVmGroup']['clusterId']
  end

  def test_host_vm_groups_list_cluster_name_falls_back_to_unique_vsphere_cluster
    cmd, _fake_clouds, fake_pools, fake_clusters = build_host_vm_command
    output = capture_stdout { cmd.list(['--cluster', 'QA', '--dry-run']) }
    assert_match(%r{/api/zones/59/host-vm-groups}, output)
    assert_match(/poolId=501/, output)
    assert_equal [[:list, {name: 'QA'}]], fake_clusters.calls
    assert_equal [[:list_without_cloud, {name: 'QA', type: 'Cluster', max: 1000}]], fake_pools.calls
  end

end
