require 'morpheus_test'

# Tests for Morpheus::Cli::HostVmGroupsCommand and the cloud-scoped
# host-vm-group subcommands added to Morpheus::Cli::Clouds for MORPH-16326.
#
# Scope note: these cover only client-side behaviour -- help output and argument
# validation -- both of which resolve before any API call is made.
#
# Tests that would exercise list/get/add/update/remove against the appliance are
# deliberately omitted until the /api/host-vm-groups request and response
# contract is confirmed against the MORPH-14136 / MORPH-16074 server work.
class MorpheusTest::HostVmGroupsTest < MorpheusTest::TestCase

  def test_host_vm_groups_help
    assert_execute %(host-vm-groups --help)
    assert_execute %(host-vm-groups list --help)
    assert_execute %(host-vm-groups get --help)
    assert_execute %(host-vm-groups add --help)
    assert_execute %(host-vm-groups update --help)
    assert_execute %(host-vm-groups remove --help)
  end

  # The cloud-scoped subcommands must be registered on the clouds command.
  def test_clouds_host_vm_group_subcommands_help
    assert_execute %(clouds list-host-vm-groups --help)
    assert_execute %(clouds get-host-vm-group --help)
    assert_execute %(clouds add-host-vm-group --help)
    assert_execute %(clouds update-host-vm-group --help)
    assert_execute %(clouds remove-host-vm-group --help)
  end

  ## Argument validation (fails during option parsing, before any request)

  def test_host_vm_groups_unknown_subcommand
    assert_error %(host-vm-groups nonsense-subcommand)
  end

  def test_host_vm_groups_get_requires_an_id
    assert_error %(host-vm-groups get)
  end

  def test_host_vm_groups_remove_requires_an_id
    assert_error %(host-vm-groups remove -y)
  end

  def test_clouds_list_host_vm_groups_requires_a_cloud
    assert_error %(clouds list-host-vm-groups)
  end

  def test_clouds_get_host_vm_group_requires_both_args
    assert_error %(clouds get-host-vm-group 1)
  end

  # No unscoped list/create route at /api/host-vm-groups.
  def test_host_vm_groups_list_requires_a_scope
    assert_error %(host-vm-groups list)
  end

  def test_host_vm_groups_add_requires_a_scope
    assert_error %(host-vm-groups add --name cli-test --dry-run)
  end

end
