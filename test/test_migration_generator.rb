# frozen_string_literal: true

require 'test_helper'

class MigrationGeneratorTest < Rails::Generators::TestCase
  extend Minitest::Spec::DSL
  tests Hoardable::MigrationGenerator
  destination File.expand_path('../tmp', __dir__)
  setup :prepare_destination

  def shared_assertions
    assert_migration 'db/migrate/create_post_versions.rb' do |migration|
      assert_match(/create_table :post_versions/, migration)
    end
  end

  it 'generates migration with pluralized resource' do
    run_generator ['posts']
    shared_assertions
  end

  it 'generates migration with singularized resource' do
    run_generator ['post']
    shared_assertions
  end
end
