# frozen_string_literal: true

module Hoardable
  # This concern provides support for PostgreSQL’s tableoid system column to {SourceModel} and
  # temporal +ActiveRecord+ scopes.
  module Scopes
    extend ActiveSupport::Concern

    included do
      # By default {Hoardable} only returns instances of the parent table, and not the +versions+ in
      # the inherited table. This can be bypassed by using the {.include_versions} scope or wrapping
      # the code in a `Hoardable.at(datetime)` block. When this is a version class that is an STI
      # model, also scope to them.
      default_scope do
        scope =
          (
            if (hoardable_at = Thread.current[:hoardable_at])
              at(hoardable_at)
            else
              exclude_versions
            end
          )
        next scope unless klass == version_class && "type".in?(column_names)

        scope.where(type: superclass.sti_name)
      end

      # @!scope class
      # @!method include_versions
      # @return [ActiveRecord<Object>]
      #
      # Returns +versions+ along with instances of the source models, all cast as instances of the
      # source model’s class.
      scope :include_versions, -> { unscope(:from) }

      # @!scope class
      # @!method versions
      # @return [ActiveRecord<Object>]
      #
      # Returns only +versions+ of the parent +ActiveRecord+ class, cast as instances of the source
      # model’s class.
      scope :versions, -> { from("ONLY #{version_class.table_name}") }

      # @!scope class
      # @!method exclude_versions
      # @return [ActiveRecord<Object>]
      #
      # Excludes +versions+ of the parent +ActiveRecord+ class. This is included by default in the
      # source model’s +default_scope+.
      scope :exclude_versions, -> { from("ONLY #{table_name}") }

      # @!scope class
      # @!method at
      # @return [ActiveRecord<Object>]
      #
      # Returns instances of the source model and versions that were valid at the supplied
      # +datetime+ or +time+, all cast as instances of the source model.
      scope(
        :at,
        lambda do |datetime|
          raise(CreatedAtColumnMissingError, table_name) unless column_names.include?("created_at")

          from(
            Arel::Nodes::As.new(
              Arel::Nodes::Union.new(
                include_versions.where(id: version_class.at(datetime).select(primary_key)).arel,
                exclude_versions
                  .where(created_at: ..datetime)
                  .where.not(id: version_class.select(:hoardable_id).where(DURING_QUERY, datetime))
                  .arel
              ),
              arel_table
            )
          ).hoardable
        end
      )
    end
  end
end
