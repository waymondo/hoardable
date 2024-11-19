# frozen_string_literal: true

require "helper"

class TestInstallGenerator < Rails::Generators::TestCase
  tests Hoardable::InstallGenerator
  destination tmp_dir
  setup :prepare_destination

  test "generates hoardable initializer, enum, and database functions" do
    run_generator
    assert_file "config/initializers/hoardable.rb", /Hoardable.enabled = true/
    assert_migration "db/migrate/install_hoardable.rb" do |migration|
      assert_match(/create_enum :hoardable_operation, %w\[update delete insert\]/, migration)
      assert_no_match(/enable_extension :pgcrypto/, migration)
    end
  end
end
