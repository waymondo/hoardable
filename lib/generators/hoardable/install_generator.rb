# frozen_string_literal: true

require 'rails/generators'

module Hoardable
  # Generates an initializer file for {Hoardable} configuration and a migration with a PostgreSQL
  # function.
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path('templates', __dir__)
    include Rails::Generators::Migration

    def create_initializer_file
      create_file(
        'config/initializers/hoardable.rb',
        <<~TEXT
          # Hoardable configuration defaults are below. Learn more at https://github.com/waymondo/hoardable#configuration
          #
          # Hoardable.enabled = true
          # Hoardable.version_updates = true
          # Hoardable.save_trash = true
        TEXT
      )
    end

    def create_migration_file
      migration_template 'functions.rb.erb', 'db/migrate/install_hoardable.rb'
    end

    def self.next_migration_number(dir)
      ::ActiveRecord::Generators::Base.next_migration_number(dir)
    end
  end
end
