# frozen_string_literal: true

module Hoardable
  # This concern provides support for PostgreSQL's tableoid system column
  module Tableoid
    extend ActiveSupport::Concern

    TABLEOID_AREL_CONDITIONS = lambda do |arel_table, condition|
      arel_table[:tableoid].send(
        condition,
        Arel::Nodes::NamedFunction.new('CAST', [Arel::Nodes::Quoted.new(arel_table.name).as('regclass')])
      )
    end.freeze

    included do
      attr_writer :tableoid

      default_scope { where(TABLEOID_AREL_CONDITIONS.call(arel_table, :eq)) }
      scope :include_versions, -> { unscope(where: [:tableoid]) }
      scope :versions, -> { include_versions.where(TABLEOID_AREL_CONDITIONS.call(arel_table, :not_eq)) }
    end

    def tableoid
      connection.execute("SELECT oid FROM pg_class WHERE relname = '#{table_name}'")[0]['oid']
    end
  end
end
