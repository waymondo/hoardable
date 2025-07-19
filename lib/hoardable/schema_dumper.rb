# frozen_string_literal: true

module Hoardable
  module SchemaDumper
    def ignored?(table_name)
      super || @connection.inherited_table?(table_name)
    end

    def tables(stream)
      super
      dump_inherited_tables(stream)
      empty_line(stream)
      functions(stream)
      triggers(stream)
    end

    private def dump_inherited_tables(stream)
      sorted_tables = @connection.tables.filter { |table| @connection.inherited_table?(table) }.sort
      sorted_tables.each do |table_name|
        table(table_name, stream)
        foreign_keys(table_name, stream)
      end
    end
  end
  private_constant :SchemaDumper
end
