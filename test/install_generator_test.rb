# frozen_string_literal: true

require 'test_helper'

class InstallGeneratorTest < Rails::Generators::TestCase
  extend Minitest::Spec::DSL
  tests Hoardable::InstallGenerator
  destination tmp_dir
  setup :prepare_destination

  it 'generates hoardable initializer' do
    run_generator
    assert_file 'config/initializers/hoardable.rb', /Hoardable.enabled = true/
  end
end
