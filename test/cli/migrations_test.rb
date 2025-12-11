require 'morpheus_test'

class MorpheusTest::MigrationsTest < MorpheusTest::TestCase
  
  def test_migrations_list
    assert_execute %(migrations list)
    assert_execute %(migrations list "apitest")
  end

  def test_migrations_get
    # migration = client.migrations.list({})['migrations'][0]
    migration = client.migrations.list({})['migrations'].find {|r| r['authority'] !~ /\A\d+\Z/}
    if migration
      assert_execute %(migrations get "#{migration['id']}")
      # beware that duplicates may exist
      name_arg = migration['name']
      assert_execute %(migrations get "#{escape_arg name_arg}")
    else
      puts "No migration found, unable to execute test `#{__method__}`"
    end
  end


  # todo: test all the other commands

  # def test_migrations_add
  #   assert_execute %(migrations add "test_migration_#{random_id}" -N)
  # end

  # def test_migrations_update
  #   #skip "Test needs to be added"
  #   assert_execute %(migrations update "test_migration_#{random_id}" --description "neat")
  # end

  # def test_migrations_remove
  #   assert_execute %(migrations remove "test_migration_#{random_id}" -y")
  # end

end