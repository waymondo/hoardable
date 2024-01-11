# frozen_string_literal: true

module Hoardable
  module SchemaStatements
    def table_options(table_name)
      options = super || {}
      if inherited_table_names = parent_table_names(table_name)
        options[:options] = "INHERITS (#{inherited_table_names.join(", ")})"
      end
      options
    end

    private def parent_table_names(table_name)
      scope = quoted_scope(table_name, type: "BASE TABLE")

      query_values(<<~SQL.presence, "SCHEMA").presence
        SELECT parent.relname
        FROM pg_catalog.pg_inherits i
          JOIN pg_catalog.pg_class child ON i.inhrelid = child.oid
          JOIN pg_catalog.pg_class parent ON i.inhparent = parent.oid
          LEFT JOIN pg_namespace n ON n.oid = child.relnamespace
        WHERE child.relname = #{scope[:name]}
          AND child.relkind IN (#{scope[:type]})
          AND n.nspname = #{scope[:schema]}
      SQL
    end

    def inherited_table?(table_name)
      parent_table_names(table_name).present?
    end
  end
  private_constant :SchemaStatements
end
