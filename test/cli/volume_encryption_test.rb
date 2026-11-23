require 'test/unit'
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'morpheus'
require 'morpheus/cli/commands/hosts'

# The API needs volumes[i].encrypted as a JSON boolean and rejects anything else with a 400,
# so the CLI sends the field only when asked and always as true or false.
# These are pure unit tests: no appliance, remote or authentication is needed.
class VolumeEncryptionTest < Test::Unit::TestCase

  PLAN = {
    'maxStorage' => 20 * 1024 * 1024 * 1024,
    'addVolumes' => true,
    'maxDisk' => 5,
    'storageTypes' => [{'id' => 1, 'name' => 'Standard', 'displayOrder' => 1}],
    'rootStorageTypes' => []
  }.freeze

  def setup
    @command = Morpheus::Cli::Hosts.new
  end

  def create_volumes(passed={})
    options = {options: {no_prompt: true}.merge(passed)}
    @command.prompt_volumes(Marshal.load(Marshal.dump(PLAN)), {}, options)
  end

  def test_create_sends_no_encrypted_field_by_default
    volumes = create_volumes

    assert_equal 1, volumes.size
    assert_false volumes[0].key?('encrypted')
  end

  def test_create_encrypts_the_root_volume_when_asked
    volumes = create_volumes('rootVolume' => {'encrypted' => true})

    assert_equal true, volumes[0]['encrypted']
  end

  def test_create_encrypts_only_the_data_volume_that_asked
    volumes = create_volumes('dataVolume1' => {'storageType' => '1', 'encrypted' => true},
                             'dataVolume2' => {'storageType' => '1'})

    assert_equal 3, volumes.size
    assert_false volumes[0].key?('encrypted')
    assert_equal true, volumes[1]['encrypted']
    assert_false volumes[2].key?('encrypted')
  end

  def test_create_keeps_an_explicit_false
    volumes = create_volumes('rootVolume' => {'encrypted' => false})

    assert_equal false, volumes[0]['encrypted']
  end

  def test_create_coerces_string_spellings_to_booleans
    assert_equal true, create_volumes('rootVolume' => {'encrypted' => 'yes'})[0]['encrypted']
    assert_equal false, create_volumes('rootVolume' => {'encrypted' => 'off'})[0]['encrypted']
  end

  def test_create_coerces_a_volumes_entry_passed_whole
    volumes = create_volumes('volumes' => [{'id' => -1, 'rootVolume' => true, 'name' => 'root', 'size' => 20, 'encrypted' => 'on'}])

    assert_equal true, volumes[0]['encrypted']
  end

  def test_create_rejects_a_value_that_is_not_a_boolean
    error = assert_raise(Morpheus::Cli::CommandError) { create_volumes('rootVolume' => {'encrypted' => 'maybe'}) }

    assert_match(/rootVolume\.encrypted/, error.message)
  end

  CURRENT = [
    {'id' => 10, 'name' => 'root', 'size' => 20, 'storageType' => 1, 'datastoreId' => 5},
    {'id' => 11, 'name' => 'data-1', 'size' => 10, 'storageType' => 1, 'datastoreId' => 5}
  ].freeze

  def resize_volumes(passed={})
    options = {options: {no_prompt: true, 'dataVolume1' => {'action' => 'keep'}}.merge(passed)}
    @command.prompt_resize_volumes(Marshal.load(Marshal.dump(CURRENT)), Marshal.load(Marshal.dump(PLAN)), {}, options)
  end

  def test_resize_leaves_existing_volumes_untouched_by_default
    volumes = resize_volumes

    assert_equal [10, 11], volumes.collect { |it| it['id'] }
    assert volumes.none? { |it| it.key?('encrypted') }
  end

  def test_resize_encrypts_a_volume_added_on_reconfigure
    volumes = resize_volumes('dataVolume2' => {'storageType' => '1', 'encrypted' => true})

    assert_equal 3, volumes.size
    assert_equal(-1, volumes[2]['id'])
    assert_equal true, volumes[2]['encrypted']
    assert_false volumes[0].key?('encrypted')
    assert_false volumes[1].key?('encrypted')
  end

  def test_resize_forwards_an_explicit_value_for_an_existing_volume_so_the_api_can_judge_it
    volumes = resize_volumes('dataVolume1' => {'action' => 'keep', 'encrypted' => false},
                             'rootVolume' => {'encrypted' => true})

    assert_equal true, volumes[0]['encrypted']
    assert_equal false, volumes[1]['encrypted']
  end

  def test_resize_rejects_a_value_that_is_not_a_boolean
    assert_raise(Morpheus::Cli::CommandError) do
      resize_volumes('dataVolume2' => {'storageType' => '1', 'encrypted' => 'maybe'})
    end
  end

end
