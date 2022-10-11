# frozen_string_literal: true

module Hoardable
  # This concern provides support for PostgreSQL’s tableoid system column to {SourceModel} and
  # temporal +ActiveRecord+ scopes.
  module Scopes
    extend ActiveSupport::Concern

    TABLEOID_AREL_CONDITIONS = lambda do |arel_table, condition|
      arel_table[:tableoid].send(
        condition,
        Arel::Nodes::NamedFunction.new('CAST', [Arel::Nodes::Quoted.new(arel_table.name).as('regclass')])
      )
    end.freeze
    private_constant :TABLEOID_AREL_CONDITIONS

    included do
      # @!visibility private
      attr_writer :tableoid

      # By default {Hoardable} only returns instances of the parent table, and not the +versions+ in
      # the inherited table. This can be bypassed by using the {.include_versions} scope or wrapping
      # the code in a `Hoardable.at(datetime)` block.
      default_scope do
        if (hoardable_at = Hoardable.instance_variable_get('@at'))
          at(hoardable_at)
        else
          exclude_versions
        end
      end

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

      # @!scope class
      # @!method exclude_versions
      # @return [ActiveRecord<Object>]
      #
      # Excludes +versions+ of the parent +ActiveRecord+ class. This is included by default in the
      # source model’s +default_scope+.
      scope :exclude_versions, -> { where(TABLEOID_AREL_CONDITIONS.call(arel_table, :eq)) }

      # @!scope class
      # @!method at
      # @return [ActiveRecord<Object>]
      #
      # Returns instances of the source model and versions that were valid at the supplied
      # +datetime+ or +time+, all cast as instances of the source model.
      scope :at, lambda { |datetime|
        raise(CreatedAtColumnMissingError, @klass.table_name) unless @klass.column_names.include?('created_at')

        include_versions.where(id: version_class.at(datetime).select('id')).or(
          exclude_versions
            .where("#{table_name}.created_at < ?", datetime)
            .where.not(id: version_class.select(:hoardable_id).where(DURING_QUERY, datetime))
        ).hoardable
      }
    end

    private

    def tableoid
      connection.execute("SELECT oid FROM pg_class WHERE relname = '#{table_name}'")[0]['oid']
    end
  end
end
