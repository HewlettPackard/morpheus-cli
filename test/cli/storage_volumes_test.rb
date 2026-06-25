require 'morpheus_test'

# Tests for Morpheus::Cli::StorageVolumes
class MorpheusTest::StorageVolumesTest < MorpheusTest::TestCase

  def test_storage_volumes_list
    assert_execute %(storage-volumes list)
  end

  def test_storage_volumes_get
    storage_volume = client.storage_volumes.list({})['storageVolumes'][0]
    if storage_volume
      assert_execute %(storage-volumes get "#{storage_volume['id']}")
    else
      puts "No storage volumes found, unable to execute test `#{__method__}`"
    end
  end

  # CLI-side validation: --tenant is required (no network call needed).
  def test_storage_volumes_update_tenant_requires_tenant
    assert_error %(storage-volumes update-tenant 1), "Expected missing --tenant to fail with a usage error"
  end

  # Happy path is verified with --dry-run so the test never mutates real ownership.
  # Confirms the volume is resolved and the PUT payload is built as expected.
  def test_storage_volumes_update_tenant_dry_run
    storage_volume = client.storage_volumes.list({})['storageVolumes'].find {|it| it['status'] == 'unattached' }
    storage_volume ||= client.storage_volumes.list({})['storageVolumes'][0]
    if storage_volume
      tenant = client.accounts.list({})['accounts'][0]
      if tenant
        assert_execute %(storage-volumes update-tenant "#{storage_volume['id']}" --tenant "#{tenant['id']}" --dry-run)
      else
        puts "No tenants found, unable to execute test `#{__method__}`"
      end
    else
      puts "No storage volumes found, unable to execute test `#{__method__}`"
    end
  end

  # --include-tenants adds includeTenants=true to the list request (master tenant only).
  def test_storage_volumes_list_include_tenants_dry_run
    assert_execute %(storage-volumes list --include-tenants --dry-run)
    output = capture_terminal_stdout { terminal.execute %(storage-volumes list --include-tenants --dry-run) }
    assert_match(/includeTenants=true/, output, "Expected includeTenants=true in the dry-run request")
  end

  # --tenant with a numeric id resolves directly to tenantId without an account lookup.
  def test_storage_volumes_list_tenant_id_dry_run
    assert_execute %(storage-volumes list --tenant 1 --dry-run)
    output = capture_terminal_stdout { terminal.execute %(storage-volumes list --tenant 1 --dry-run) }
    assert_match(/tenantId=1/, output, "Expected tenantId=1 in the dry-run request")
  end

  # --tenant with a name resolves to an id via the accounts API, then sets tenantId.
  def test_storage_volumes_list_tenant_name_dry_run
    tenant = client.accounts.list({})['accounts'][0]
    if tenant
      output = capture_terminal_stdout { terminal.execute %(storage-volumes list --tenant "#{tenant['name']}" --dry-run) }
      assert_match(/tenantId=#{tenant['id']}/, output, "Expected tenantId=#{tenant['id']} resolved from tenant name")
    else
      puts "No tenants found, unable to execute test `#{__method__}`"
    end
  end

  private

  # Capture everything written to the terminal's stdout while the block runs.
  def capture_terminal_stdout
    original_stdout = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    yield
    buffer.string
  ensure
    terminal.set_stdout(original_stdout)
  end

end
