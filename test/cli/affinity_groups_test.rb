require 'morpheus_test'

# Tests for Morpheus::Cli::AffinityGroupsCommand
#
# Scope note: these cover only client-side behaviour -- help output and argument
# validation -- both of which resolve before any API call is made.
#
# Tests that would exercise list/get/add/update/remove against the appliance are
# deliberately omitted until the /api/affinity-groups request and response
# contract is confirmed against the MORPH-14136 / MORPH-16074 server work.
# See test/cli/affinity_helper_test.rb for the offline coverage of the shared
# affinity enums and formatters.
class MorpheusTest::AffinityGroupsTest < MorpheusTest::TestCase

  def test_affinity_groups_help
    assert_execute %(affinity-groups --help)
    assert_execute %(affinity-groups list --help)
    assert_execute %(affinity-groups get --help)
    assert_execute %(affinity-groups add --help)
    assert_execute %(affinity-groups update --help)
    assert_execute %(affinity-groups remove --help)
  end

  ## Argument validation (fails during option parsing, before any request)

  def test_affinity_groups_unknown_subcommand
    assert_error %(affinity-groups nonsense-subcommand)
  end

  def test_affinity_groups_get_requires_an_id
    assert_error %(affinity-groups get)
  end

  def test_affinity_groups_update_requires_an_id
    assert_error %(affinity-groups update)
  end

  def test_affinity_groups_remove_requires_an_id
    assert_error %(affinity-groups remove -y)
  end

  def test_affinity_groups_list_rejects_unknown_option
    assert_error %(affinity-groups list --not-a-real-option)
  end

  # There is no unscoped list/create route -- morpheus-ui ApiV1UrlMappings
  # exposes only /api/affinity-groups/{id} at the top level, so list and add
  # must refuse to run without --cloud or --cluster rather than 404.
  def test_affinity_groups_list_requires_a_scope
    assert_error %(affinity-groups list)
  end

  def test_affinity_groups_add_requires_a_scope
    assert_error %(affinity-groups add --name cli-test --dry-run)
  end

end
