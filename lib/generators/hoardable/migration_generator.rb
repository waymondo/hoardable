# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration/migration_generator'

module Hoardable
  # Generates a migration to create an inherited uni-temporal table of a model including
  # {Hoardable::Model}, for the storage of +versions+.
  class MigrationGenerator < ActiveRecord::Generators::Base
    source_root File.expand_path('templates', __dir__)
    include Rails::Generators::Migration
    class_option :foreign_key_type, type: :string

    def create_versions_table
      migration_template 'migration.rb.erb', "db/migrate/create_#{singularized_table_name}_versions.rb"
    end

    no_tasks do
      def foreign_key_type
        options[:foreign_key_type] ||
          class_name.singularize.constantize.columns.find { |col| col.name == 'id' }.sql_type
      rescue StandardError
        'bigint'
      end

      def singularized_table_name
        @singularized_table_name ||= table_name.singularize
      end
    end
  end
end
