# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration/migration_generator'

module Hoardable
  # Generates a migration for an inherited temporal table of a model including {Hoardable::Model}
  class MigrationGenerator < ActiveRecord::Generators::Base
    source_root File.expand_path('templates', __dir__)
    include Rails::Generators::Migration

    def create_versions_table
      migration_template migration_template_name, "db/migrate/create_#{singularized_table_name}_versions.rb"
    end

    no_tasks do
      def migration_template_name
        if Gem::Version.new(ActiveRecord::Migration.current_version.to_s) < Gem::Version.new('7')
          'migration_6.rb.erb'
        else
          'migration.rb.erb'
        end
      end

      def singularized_table_name
        @singularized_table_name ||= table_name.singularize
      end
    end
  end
end
