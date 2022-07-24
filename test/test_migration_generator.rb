# frozen_string_literal: true

require 'test_helper'

class MigrationGeneratorTest < Rails::Generators::TestCase
  tests Archiversion::MigrationGenerator
  destination File.expand_path('../tmp', __dir__)
  setup :prepare_destination

  def test_it_generates_migration
    run_generator ['posts']
    assert_migration 'db/migrate/create_post_versions.rb' do |migration|
      assert_match(/create_table :post_versions/, migration)
    end
  end
end
