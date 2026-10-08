require 'test/unit'
require 'stringio'
require 'json'
require 'morpheus'

# Unit tests for Morpheus::Cli::AffinityHelper
#
# These are pure unit tests of the shared affinity enums and formatters.
# They deliberately do NOT extend MorpheusTest::TestCase because they require
# no appliance, no remote and no authentication - they must always be runnable.
#
# These tests exist to guard a real regression: the affinity type enum was
# previously duplicated across clouds.rb and clusters.rb and the two drifted,
# leaving the cloud-scoped command able to offer only 2 of the 4 valid types
# and silently rendering mandatory _MUST constraints as soft ones.
class AffinityHelperTest < Test::Unit::TestCase

  # Bare host for the mixin under test
  class HelperHost
    include Morpheus::Cli::AffinityHelper
  end

  def setup
    @helper = HelperHost.new
  end

  ## Enums

  # The canonical list, per morpheus-ui. If this test fails, the CLI, the UI and
  # the OpenAPI affinity-type schema have drifted apart.
  def test_affinity_types_contains_all_four_values
    expected = %w[KEEP_TOGETHER KEEP_SEPARATE KEEP_TOGETHER_MUST KEEP_SEPARATE_MUST]
    actual = @helper.affinity_type_select_options.collect {|it| it['value'] }
    assert_equal expected.sort, actual.sort,
      "Affinity types drifted from morpheus-ui. Expected exactly: #{expected.sort.inspect}"
  end

  def test_affinity_types_includes_mandatory_must_variants
    values = @helper.affinity_type_select_options.collect {|it| it['value'] }
    assert values.include?('KEEP_TOGETHER_MUST'), "KEEP_TOGETHER_MUST must be offered"
    assert values.include?('KEEP_SEPARATE_MUST'), "KEEP_SEPARATE_MUST must be offered"
  end

  # Per HostVmGroup.HostVmGroupType, morpheus-ui rc-9.1.0
  # (morpheus-domains/grails-app/domain/com/morpheus/HostVmGroup.groovy:32).
  def test_host_vm_group_types
    expected = %w[SITE_GROUP HOST_GROUP VM_GROUP]
    actual = @helper.host_vm_group_type_select_options.collect {|it| it['value'] }
    assert_equal expected.sort, actual.sort
  end

  # Every select option must carry a display name, or the prompt renders blanks.
  def test_all_select_options_have_name_and_value
    [
      @helper.affinity_type_select_options,
      @helper.host_vm_group_type_select_options,
    ].each do |options|
      options.each do |opt|
        assert_not_nil opt['name'],  "select option missing 'name': #{opt.inspect}"
        assert_not_nil opt['value'], "select option missing 'value': #{opt.inspect}"
        assert !opt['name'].to_s.empty?,  "select option has empty 'name': #{opt.inspect}"
        assert !opt['value'].to_s.empty?, "select option has empty 'value': #{opt.inspect}"
      end
    end
  end

  # Callers mutate the hashes they get back (adding required/defaultValue),
  # so the frozen constants must never be handed out directly.
  def test_select_options_are_defensive_copies
    first = @helper.affinity_type_select_options
    first[0]['name'] = 'MUTATED'
    second = @helper.affinity_type_select_options
    assert_not_equal 'MUTATED', second[0]['name'],
      "select options leaked a reference to the shared constant"
  end

  ## Formatting

  def test_format_affinity_type_renders_all_four
    assert_equal 'Keep Together',        @helper.format_affinity_type('KEEP_TOGETHER')
    assert_equal 'Keep Separate',        @helper.format_affinity_type('KEEP_SEPARATE')
    assert_equal 'Keep Together (Must)', @helper.format_affinity_type('KEEP_TOGETHER_MUST')
    assert_equal 'Keep Separate (Must)', @helper.format_affinity_type('KEEP_SEPARATE_MUST')
  end

  # The original bug: a _MUST value rendered as the plain soft label, so a
  # mandatory constraint was displayed as if it were advisory.
  def test_format_affinity_type_distinguishes_must_from_should
    assert_not_equal @helper.format_affinity_type('KEEP_TOGETHER'),
                     @helper.format_affinity_type('KEEP_TOGETHER_MUST'),
      "KEEP_TOGETHER_MUST must not render identically to KEEP_TOGETHER"
    assert_not_equal @helper.format_affinity_type('KEEP_SEPARATE'),
                     @helper.format_affinity_type('KEEP_SEPARATE_MUST'),
      "KEEP_SEPARATE_MUST must not render identically to KEEP_SEPARATE"
  end

  # Unknown/future values must pass through rather than render blank.
  def test_format_affinity_type_passes_through_unknown
    assert_equal 'SOME_FUTURE_TYPE', @helper.format_affinity_type('SOME_FUTURE_TYPE')
  end

  def test_format_affinity_type_handles_nil_and_empty
    assert_equal '', @helper.format_affinity_type(nil)
    assert_equal '', @helper.format_affinity_type('')
  end

  def test_format_host_vm_group_type
    assert_equal 'Site Group', @helper.format_host_vm_group_type('SITE_GROUP')
    assert_equal 'Host Group', @helper.format_host_vm_group_type('HOST_GROUP')
    assert_equal 'VM Group',   @helper.format_host_vm_group_type('VM_GROUP')
    assert_equal 'OTHER',      @helper.format_host_vm_group_type('OTHER')
    assert_equal '',           @helper.format_host_vm_group_type(nil)
  end

  # Every enum value must round-trip to a human label, never fall through
  # to the raw passthrough branch.
  def test_every_enum_value_has_a_friendly_label
    @helper.affinity_type_select_options.each do |opt|
      assert_not_equal opt['value'], @helper.format_affinity_type(opt['value']),
        "#{opt['value']} has no friendly label"
    end
    @helper.host_vm_group_type_select_options.each do |opt|
      assert_not_equal opt['value'], @helper.format_host_vm_group_type(opt['value']),
        "#{opt['value']} has no friendly label"
    end
  end

  ## Error handling

  # Fake RestClient-style exception carrying a JSON body.
  class FakeResponse
    def initialize(body); @body = body; end
    def to_s; @body; end
  end
  class FakeRestException < StandardError
    attr_reader :response
    def initialize(body); @response = FakeResponse.new(body); end
  end

  # Errors are written to stderr (print_red_alert), so capture that stream.
  def capture_error_output(body)
    out = StringIO.new
    orig = $stderr
    $stderr = out
    begin
      @helper.handle_affinity_rest_exception(FakeRestException.new(body), {})
    ensure
      $stderr = orig
    end
    out.string
  end

  # Real payload shape from AffinityGroupService.validateCombinedRulePoolConsistency
  # (morpheus-ui rc-9.1.0). There is no top-level errorCode - the CLI must read
  # msg and the field-keyed errors map.
  def test_cross_pool_error_surfaces_server_message
    body = {
      'success' => false,
      'msg' => "VM Group 'VMG-1' and Host Group 'HG-1' belong to different clusters",
      'errors' => {'hostGroup' => 'affinityGroup.combinedRule.crossClusterHostGroup'}
    }.to_json
    output = capture_error_output(body)
    assert output.include?("belong to different clusters"),
      "cross-pool error must surface the server msg, got: #{output.inspect}"
    assert output.include?('affinityGroup.combinedRule.crossClusterHostGroup'),
      "cross-pool error must surface the field error key, got: #{output.inspect}"
  end

  # Real payload from VmwareComputeService.combinedRuleGroupSyncGuard.
  def test_unsynced_group_error_surfaces_server_message
    body = {
      'success' => false,
      'msg' => "Cannot save combined VM-to-Host rule 'r1' - referenced group(s) have not yet " \
               "synced to vSphere: VM Group 'VMG-local'. Wait for the next cloud refresh.",
      'errors' => {'affinityGroup' => 'errors.affinity.rule.group.not.synced'}
    }.to_json
    output = capture_error_output(body)
    assert output.include?("have not yet synced to vSphere"),
      "unsynced error must surface the server msg, got: #{output.inspect}"
    assert output.include?('errors.affinity.rule.group.not.synced'),
      "unsynced error must surface the field error key, got: #{output.inspect}"
  end

  # A body with errors but no msg must still report the field errors.
  def test_field_errors_are_reported_without_a_msg
    body = {
      'success' => false,
      'errors' => {'vmGroup' => 'affinityGroup.combinedRule.bothGroupsRequired'}
    }.to_json
    output = capture_error_output(body)
    assert output.include?('affinityGroup.combinedRule.bothGroupsRequired'),
      "field errors must be reported even with no msg, got: #{output.inspect}"
  end

  # HostVmGroupsController#save renders flat JSON with msg and no errors map
  # for the multiple-clusters / pool-mismatch guards. Must still surface.
  def test_msg_only_error_body_is_surfaced
    body = {
      'success' => false,
      'msg' => 'Selected servers span multiple clusters. A Host / VM Group must belong to a single cluster.'
    }.to_json
    output = capture_error_output(body)
    assert output.include?('span multiple clusters'),
      "a body with msg but no errors map must still be surfaced, got: #{output.inspect}"
  end

  ## Cluster-in-cloud narrowing

  # formOptions returns groups with a poolId; a cloud-scoped rule belongs to a
  # single cluster, so only groups in the chosen cluster may be offered.
  def test_filter_by_pool_keeps_only_matching_groups
    rows = [
      {'id' => 1, 'name' => 'vmg-a', 'poolId' => 10},
      {'id' => 2, 'name' => 'vmg-b', 'poolId' => 20},
    ]
    assert_equal [1], @helper.filter_by_pool(rows, 10).collect {|r| r['id'] }
    assert_equal [2], @helper.filter_by_pool(rows, 20).collect {|r| r['id'] }
  end

  # Groups with no poolId are kept -- the server did the narrowing already.
  def test_filter_by_pool_keeps_rows_without_a_pool_id
    rows = [{'id' => 1, 'poolId' => nil}, {'id' => 2, 'poolId' => 99}]
    assert_equal [1], @helper.filter_by_pool(rows, 7).collect {|r| r['id'] }
  end

  def test_filter_by_pool_is_a_noop_without_a_pool
    rows = [{'id' => 1, 'poolId' => 10}, {'id' => 2, 'poolId' => 20}]
    assert_equal rows, @helper.filter_by_pool(rows, nil)
  end

  # Pool ids may arrive as String from CLI flags and Integer from JSON.
  def test_filter_by_pool_compares_across_types
    rows = [{'id' => 1, 'poolId' => 10}]
    assert_equal 1, @helper.filter_by_pool(rows, '10').size
    assert_equal 1, @helper.filter_by_pool(rows, 10).size
  end

  ## Option types

  def test_affinity_type_option_type_defaults_to_optional
    opt = @helper.affinity_type_option_type
    assert_equal 'affinityType', opt['fieldName']
    assert_equal 'select', opt['type']
    assert_nil opt['required'],     "affinityType must be optional unless explicitly required"
    assert_nil opt['defaultValue'], "affinityType must have no default unless explicitly given"
  end

  def test_affinity_type_option_type_accepts_required_and_default
    opt = @helper.affinity_type_option_type(required: true, default: 'KEEP_TOGETHER')
    assert_equal true, opt['required']
    assert_equal 'KEEP_TOGETHER', opt['defaultValue']
  end

  # Any default must itself be a member of the enum.
  def test_option_type_defaults_are_valid_enum_members
    values = @helper.affinity_type_select_options.collect {|it| it['value'] }
    %w[KEEP_TOGETHER KEEP_SEPARATE].each do |default|
      opt = @helper.affinity_type_option_type(required: true, default: default)
      assert values.include?(opt['defaultValue']),
        "default #{default} is not a valid affinity type"
    end
  end

  def test_host_vm_group_type_option_type
    opt = @helper.host_vm_group_type_option_type(required: true, default: 'HOST_GROUP')
    assert_equal 'type', opt['fieldName']
    assert_equal true, opt['required']
    assert_equal 'HOST_GROUP', opt['defaultValue']
  end

  ## Wiring

  # affinityType must be editable on update, not create-only.
  # AffinityGroupService.updateAffinityGroup applies params.affinityGroup.affinityType,
  # so callers may switch between MUST and non-MUST behaviour during an edit.
  def test_affinity_type_is_editable_on_update_in_all_commands
    [
      Morpheus::Cli::AffinityGroupsCommand,
      Morpheus::Cli::Clouds,
      Morpheus::Cli::Clusters,
    ].each do |klass|
      cmd = klass.new
      method_name = all_own_methods(klass).find {|m|
        m.to_s =~ /\Aupdate_(cloud_)?affinity_group_option_types\z/
      }
      assert_not_nil method_name, "#{klass} has no update affinity option types method"
      option_types = cmd.send(method_name)
      field_names = option_types.collect {|it| it['fieldName'] }
      assert field_names.include?('affinityType'),
        "#{klass}##{method_name} omits affinityType - it is editable, not create-only"
    end
  end

  # Guards against a command re-introducing a local copy of the enum.
  def test_commands_offer_all_four_types_on_add_and_update
    expected = %w[KEEP_TOGETHER KEEP_SEPARATE KEEP_TOGETHER_MUST KEEP_SEPARATE_MUST].sort
    [
      [Morpheus::Cli::AffinityGroupsCommand, :add_affinity_group_option_types],
      [Morpheus::Cli::AffinityGroupsCommand, :update_affinity_group_option_types],
      [Morpheus::Cli::Clouds,   :add_cloud_affinity_group_option_types],
      [Morpheus::Cli::Clouds,   :update_cloud_affinity_group_option_types],
      [Morpheus::Cli::Clusters, :add_affinity_group_option_types],
      [Morpheus::Cli::Clusters, :update_affinity_group_option_types],
    ].each do |klass, method_name|
      option_types = klass.new.send(method_name)
      affinity_field = option_types.find {|it| it['fieldName'] == 'affinityType' }
      assert_not_nil affinity_field, "#{klass}##{method_name} has no affinityType field"
      actual = affinity_field['selectOptions'].collect {|it| it['value'] }.sort
      assert_equal expected, actual,
        "#{klass}##{method_name} does not offer all four affinity types"
    end
  end

  # The enums and formatters must exist in exactly one place.
  def test_commands_do_not_redefine_shared_helpers
    [
      Morpheus::Cli::AffinityGroupsCommand,
      Morpheus::Cli::HostVmGroupsCommand,
      Morpheus::Cli::Clouds,
      Morpheus::Cli::Clusters,
    ].each do |klass|
      own_methods = all_own_methods(klass)
      [:format_affinity_type, :format_host_vm_group_type, :handle_affinity_rest_exception].each do |shared|
        assert !own_methods.include?(shared),
          "#{klass} redefines #{shared} - use Morpheus::Cli::AffinityHelper instead to prevent drift"
      end
    end
  end

  def test_affinity_commands_include_the_shared_helper
    [
      Morpheus::Cli::AffinityGroupsCommand,
      Morpheus::Cli::HostVmGroupsCommand,
      Morpheus::Cli::Clouds,
      Morpheus::Cli::Clusters,
    ].each do |klass|
      assert klass.include?(Morpheus::Cli::AffinityHelper),
        "#{klass} does not include Morpheus::Cli::AffinityHelper"
    end
  end

  # Cloud-scoped affinity groups and host/VM groups both belong to exactly one
  # cluster, so both add forms must offer the cluster picker. Without it the
  # user can pick servers spanning clusters and the server rejects the create.
  def test_cloud_scoped_add_forms_offer_a_cluster_picker
    [
      :add_cloud_affinity_group_option_types,
      :add_cloud_host_vm_group_option_types,
    ].each do |method_name|
      option_types = Morpheus::Cli::Clouds.new.send(method_name)
      pool_field = option_types.find {|it| it['fieldName'] == 'pool.id' }
      assert_not_nil pool_field,
        "Morpheus::Cli::Clouds##{method_name} has no cluster picker (pool.id)"
      assert_equal true, pool_field['required'],
        "#{method_name}: the cluster picker must be required"
    end
  end

  protected

  # Option-type builders are private in the command classes, so reflection must
  # consider private methods too.
  def all_own_methods(klass)
    klass.instance_methods(false) + klass.private_instance_methods(false)
  end

end
