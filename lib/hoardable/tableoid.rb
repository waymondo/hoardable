# frozen_string_literal: true

module Hoardable
  # This concern provides support for PostgreSQL's tableoid system column
  module Tableoid
    extend ActiveSupport::Concern

    included do
      attr_writer :tableoid

      default_scope do
        where(
          arel_table[:tableoid].eq(
            Arel::Nodes::NamedFunction.new('CAST', [Arel::Nodes::Quoted.new(arel_table.name).as('regclass')])
          )
        )
      end
    end

    def tableoid
      connection.execute("SELECT oid FROM pg_class WHERE relname = '#{table_name}'")[0]['oid']
    end
  end
end
