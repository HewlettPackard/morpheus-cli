require 'morpheus/cli/mixins/print_helper'

# Mixin for Morpheus::Cli command classes
# Single source of truth for affinity group / host-vm group enums and formatting.
#
# Keep this in sync with morpheus-ui and the OpenAPI shared affinity-type schema.
# Defining these values here (rather than inline in each command) prevents the
# definitions from drifting apart between cluster-scoped, cloud-scoped and
# top-level flat-by-ID commands.
module Morpheus::Cli::AffinityHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  # All affinity types supported by the API.
  # The _MUST variants are mandatory placement constraints and are what the
  # violations endpoint reports on.
  AFFINITY_TYPES = [
    {'name' => 'Keep Together (Should)', 'value' => 'KEEP_TOGETHER'},
    {'name' => 'Keep Separate (Should)', 'value' => 'KEEP_SEPARATE'},
    {'name' => 'Keep Together (Must)',   'value' => 'KEEP_TOGETHER_MUST'},
    {'name' => 'Keep Separate (Must)',   'value' => 'KEEP_SEPARATE_MUST'},
  ].freeze

  # Group types, per HostVmGroup.HostVmGroupType (morpheus-ui rc-9.1.0,
  # morpheus-domains/grails-app/domain/com/morpheus/HostVmGroup.groovy).
  # SITE_GROUP exists in the enum but is not valid on either side of a combined
  # VM-to-Host rule -- AffinityGroupService.applyRuleShapeFields rejects it.
  HOST_VM_GROUP_TYPES = [
    {'name' => 'Site Group', 'value' => 'SITE_GROUP'},
    {'name' => 'Host Group', 'value' => 'HOST_GROUP'},
    {'name' => 'VM Group',   'value' => 'VM_GROUP'},
  ].freeze

  def affinity_type_select_options
    AFFINITY_TYPES.map {|it| it.dup }
  end

  def host_vm_group_type_select_options
    HOST_VM_GROUP_TYPES.map {|it| it.dup }
  end

  # affinityType is editable on update as well as create.
  # AffinityGroupService.updateAffinityGroup applies params.affinityGroup.affinityType,
  # so callers may switch between MUST and non-MUST behaviour during an edit.
  def affinity_type_option_type(required: false, default: nil)
    opt = {
      'fieldName'     => 'affinityType',
      'fieldLabel'    => 'Type',
      'type'          => 'select',
      'selectOptions' => affinity_type_select_options,
      'description'   => 'Affinity type. The _MUST variants are mandatory placement constraints.',
    }
    opt['required']     = true    if required
    opt['defaultValue'] = default if default
    opt
  end

  def host_vm_group_type_option_type(required: false, default: nil)
    opt = {
      'fieldName'     => 'type',
      'fieldLabel'    => 'Group Type',
      'type'          => 'select',
      'selectOptions' => host_vm_group_type_select_options,
      'description'   => 'Choose group type.',
    }
    opt['required']     = true    if required
    opt['defaultValue'] = default if default
    opt
  end

  def format_affinity_type(affinity_type)
    found = AFFINITY_TYPES.find {|it| it['value'] == affinity_type.to_s }
    found ? found['name'].sub(' (Should)', '') : affinity_type.to_s
  end

  def format_host_vm_group_type(type)
    found = HOST_VM_GROUP_TYPES.find {|it| it['value'] == type.to_s }
    found ? found['name'] : type.to_s
  end

  # Groups carry poolId; keep only those in the chosen cluster.
  def filter_by_pool(rows, pool_id)
    return rows if pool_id.nil?
    rows.select {|r| r['poolId'].nil? || r['poolId'].to_s == pool_id.to_s }
  end

  # Surface the server's own error text for affinity failures.
  #
  # The API returns {success:false, msg:"<human text>", errors:{<field>:"<i18n key>"}}
  # -- there is no top-level errorCode. AffinityGroupService and
  # VmwareComputeService.combinedRuleGroupSyncGuard already compose actionable
  # messages (cross-cluster group refs, groups not yet synced to vSphere, rule
  # shape violations), so print them verbatim rather than restating them here.
  def handle_affinity_rest_exception(e, options)
    if e.respond_to?(:response) && e.response
      begin
        body = JSON.parse(e.response.to_s)
        if body.is_a?(Hash) && (body['msg'] || body['errors'])
          print_red_alert body['msg'] if body['msg']
          errors = body['errors']
          if errors.is_a?(Hash) && !errors.empty?
            # Same stream as print_red_alert, so msg and field detail stay together.
            errors.each do |field, message|
              $stderr.print "#{red}  #{field}: #{message}#{reset}\n"
            end
          end
          return
        end
      rescue TypeError, JSON::ParserError
        # fall through to the generic handler
      end
    end
    print_rest_exception(e, options)
  end

end
