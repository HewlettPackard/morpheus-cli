require 'morpheus_test'

# Tests for Morpheus::Cli::DistributedWorkers
class MorpheusTest::DistributedWorkersTest < MorpheusTest::TestCase

  def test_distributed_workers_list
    assert_execute %(distributed-workers list)
  end

  def test_distributed_workers_crud
    worker_name = "cli-test-dw-#{rand(1000000)}"
    created_id = nil
    begin
      # add and capture output to assert the apiKey is surfaced once
      add_output = capture_stdout do
        assert_execute %(distributed-workers add "#{worker_name}" --description "cli test worker" --enabled -N)
      end
      created_id = client.distributed_workers.list({name: worker_name})['distributedWorkers'].first['id']
      assert_not_nil created_id, "Expected distributed worker to be created"

      api_key = client.distributed_workers.list({name: worker_name})['distributedWorkers'].first['apiKey']
      assert_nil api_key, "Expected apiKey to be omitted from list responses"
      assert_match(/API Key/i, add_output, "Expected add output to surface the API Key")

      # appears in list
      assert_match(/#{Regexp.escape(worker_name)}/, capture_stdout { assert_execute %(distributed-workers list --json) })

      # get by id and by name, apiKey must not be shown
      get_output = capture_stdout do
        assert_execute %(distributed-workers get "#{created_id}")
        assert_execute %(distributed-workers get "#{escape_arg worker_name}")
      end
      refute_match(/API Key/i, get_output, "Expected get output to omit the API Key")

      # update the description
      assert_execute %(distributed-workers update "#{created_id}" --description "updated description")
      updated = client.distributed_workers.get(created_id)['distributedWorker']
      assert_equal "updated description", updated['description']

      # remove and confirm it is gone
      assert_execute %(distributed-workers remove "#{created_id}" -y)
      assert_empty client.distributed_workers.list({name: worker_name})['distributedWorkers'],
        "Expected distributed worker to be removed"
      created_id = nil
    ensure
      if created_id
        begin
          client.distributed_workers.destroy(created_id)
        rescue => e
          puts "Failed to clean up distributed worker #{created_id}: #{e.message}"
        end
      end
    end
  end

  protected

  def capture_stdout
    original = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    yield
    buffer.string
  ensure
    terminal.set_stdout(original)
  end

end
