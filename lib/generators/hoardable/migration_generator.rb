# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration/migration_generator'

module Hoardable
  # Generates a migration for an inherited temporal table of a model including {Hoardable::Model}
  class MigrationGenerator < ActiveRecord::Generators::Base
    source_root File.expand_path('templates', __dir__)
    include Rails::Generators::Migration

    def create_versions_table
      migration_template 'migration.rb.erb', "db/migrate/create_#{singularized_table_name}_versions.rb"
    end

    def singularized_table_name
      @singularized_table_name ||= table_name.singularize
    end
  end
end
