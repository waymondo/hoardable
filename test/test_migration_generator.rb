# frozen_string_literal: true

require 'helper'

class MigrationGeneratorTest < Rails::Generators::TestCase
  extend Minitest::Spec::DSL
  tests Hoardable::MigrationGenerator
  destination tmp_dir
  setup :prepare_destination

  def shared_post_assertions
    assert_migration 'db/migrate/create_post_versions.rb' do |migration|
      assert_match(/create_table\(\n(\s)*:post_versions/, migration)
      assert_match(/:hoardable_id, :bigint/, migration)
      assert_match(/create_trigger :posts_set_hoardable_id, on: :posts/, migration)
    end
  end

  def shared_book_assertions(foreign_key_type = 'uuid')
    assert_migration 'db/migrate/create_book_versions.rb' do |migration|
      assert_match(/create_table\(\n(\s)*:book_versions/, migration)
      assert_match(":hoardable_id, :#{foreign_key_type}", migration)
    end
  end

  it 'generates post migration with pluralized resource' do
    run_generator ['posts']
    shared_post_assertions
  end

  it 'generates post migration with singularized resource' do
    run_generator ['post']
    shared_post_assertions
  end

  it 'generates post migration with capitalized resource' do
    run_generator ['Post']
    shared_post_assertions
  end

  it 'generates book migration with pluralized resource' do
    run_generator ['books']
    shared_book_assertions
  end

  it 'generates book migration with singularized resource' do
    run_generator ['book']
    shared_book_assertions
  end

  it 'generates book migration with specified foreign_key_type' do
    run_generator ['book', '--foreign-key-type', 'foo']
    shared_book_assertions('foo')
  end

  it 'generates migration with namespaced model name' do
    run_generator ['ActionText::RichText']
    assert_migration 'db/migrate/create_action_text_rich_text_versions.rb' do |migration|
      assert_match(/create_table\(\n(\s)*:action_text_rich_text_versions/, migration)
      assert_match(':hoardable_id, :bigint', migration)
    end
  end

  it 'seeds hoardable_id during migration' do
    tag = Tag.create!(name: 'one')
    assert_nil tag.hoardable_id
    run_generator ['Tag']
    refute_nil tag.reload.hoardable_id
  end
end
