# frozen_string_literal: true

module Hoardable
  # This concern provides support for PostgreSQL’s tableoid system column to {SourceModel}.
  module Tableoid
    extend ActiveSupport::Concern

    # @!visibility private
    TABLEOID_AREL_CONDITIONS = lambda do |arel_table, condition|
      arel_table[:tableoid].send(
        condition,
        Arel::Nodes::NamedFunction.new('CAST', [Arel::Nodes::Quoted.new(arel_table.name).as('regclass')])
      )
    end.freeze

    included do
      # @!visibility private
      attr_writer :tableoid

      # By default, {Hoardable} only returns instances of the parent table, and not the +versions+
      # in the inherited table.
      default_scope { where(TABLEOID_AREL_CONDITIONS.call(arel_table, :eq)) }

      # @!scope class
      # @!method include_versions
      # @return [ActiveRecord<Object>]
      #
      # Returns +versions+ along with instances of the source models, all cast as instances of the
      # source model’s class.
      scope :include_versions, -> { unscope(where: [:tableoid]) }

      # @!scope class
      # @!method versions
      # @return [ActiveRecord<Object>]
      #
      # Returns only +versions+ of the parent +ActiveRecord+ class, cast as instances of the source
      # model’s class.
      scope :versions, -> { include_versions.where(TABLEOID_AREL_CONDITIONS.call(arel_table, :not_eq)) }
    end

    private

    def tableoid
      connection.execute("SELECT oid FROM pg_class WHERE relname = '#{table_name}'")[0]['oid']
    end
  end
end
