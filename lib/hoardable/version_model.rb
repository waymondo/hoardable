# frozen_string_literal: true

module Hoardable
  # This concern is included into the dynamically generated +Version+ kind of the parent
  # +ActiveRecord+ class.
  module VersionModel
    extend ActiveSupport::Concern

    class_methods do
      # Returns the foreign column that holds the reference to the source model of the version.
      def hoardable_source_foreign_key
        @hoardable_source_foreign_key ||= "#{superclass.model_name.i18n_key}_id"
      end
    end

    included do
      hoardable_source_key = superclass.model_name.i18n_key

      # A +version+ belongs to it’s parent +ActiveRecord+ source.
      belongs_to hoardable_source_key, inverse_of: :versions
      alias_method :hoardable_source, hoardable_source_key

      self.table_name = "#{table_name.singularize}#{VERSION_TABLE_SUFFIX}"

      alias_method :readonly?, :persisted?
      alias_attribute :hoardable_operation, :_operation
      alias_attribute :hoardable_event_uuid, :_event_uuid
      alias_attribute :hoardable_during, :_during

      before_create :assign_temporal_tsrange

      # @!scope class
      # @!method trashed
      # @return [ActiveRecord<Object>]
      #
      # Returns only trashed +versions+ that are currently orphans.
      scope :trashed, lambda {
        left_outer_joins(hoardable_source_key)
          .where(superclass.table_name => { id: nil })
          .where(_operation: 'delete')
      }

      # @!scope class
      # @!method at
      # @return [ActiveRecord<Object>]
      #
      # Returns +versions+ that were valid at the supplied +datetime+ or +time+.
      scope :at, ->(datetime) { where(_operation: %w[delete update]).where(DURING_QUERY, datetime) }

      # @!scope class
      # @!method trashed_at
      # @return [ActiveRecord<Object>]
      #
      # Returns +versions+ that were trashed at the supplied +datetime+ or +time+.
      scope :trashed_at, ->(datetime) { where(_operation: 'insert').where(DURING_QUERY, datetime) }

      # @!scope class
      # @!method with_hoardable_event_uuid
      # @return [ActiveRecord<Object>]
      #
      # Returns all +versions+ that were created as part of the same +ActiveRecord+ database
      # transaction of the supplied +event_uuid+. Useful in +reverted+ and +untrashed+ callbacks.
      scope :with_hoardable_event_uuid, ->(event_uuid) { where(_event_uuid: event_uuid) }

      # @!scope class
      # @!method only_most_recent
      # @return [ActiveRecord<Object>]
      #
      # Returns a limited +ActiveRecord+ scope of only the most recent version.
      scope :only_most_recent, -> { limit(1).reorder('UPPER(_during) DESC') }
    end

    # Reverts the parent +ActiveRecord+ instance to the saved attributes of this +version+. Raises
    # an error if the version is trashed.
    def revert!
      raise(Error, 'Version is trashed, cannot revert') unless hoardable_operation == 'update'

      transaction do
        hoardable_source.tap do |reverted|
          reverted.update!(hoardable_source_attributes.without('id'))
          reverted.instance_variable_set(:@hoardable_version, self)
          reverted.run_callbacks(:reverted)
        end
      end
    end

    # Inserts a trashed +version+ back into its parent +ActiveRecord+ table with its original
    # primary key. Raises an error if the version is not trashed.
    def untrash!
      raise(Error, 'Version is not trashed, cannot untrash') unless hoardable_operation == 'delete'

      transaction do
        superscope = self.class.superclass.unscoped
        superscope.insert(hoardable_source_attributes.merge('id' => hoardable_source_foreign_id))
        superscope.find(hoardable_source_foreign_id).tap do |untrashed|
          untrashed.send('initialize_hoardable_version', 'insert').save(validate: false, touch: false)
          untrashed.instance_variable_set(:@hoardable_version, self)
          untrashed.run_callbacks(:untrashed)
        end
      end
    end

    DATA_KEYS.each do |key|
      define_method("hoardable_#{key}") do
        _data&.dig(key.to_s)
      end
    end

    # Returns the +ActiveRecord+
    # {https://api.rubyonrails.org/classes/ActiveModel/Dirty.html#method-i-changes changes} that
    # were present during version creation.
    def changes
      _data&.dig('changes')
    end

    # Returns the foreign reference that represents the source model of the version.
    def hoardable_source_foreign_id
      @hoardable_source_foreign_id ||= public_send(hoardable_source_foreign_key)
    end

    private

    delegate :hoardable_source_foreign_key, to: :class

    def hoardable_source_attributes
      @hoardable_source_attributes ||=
        attributes_before_type_cast
        .without(hoardable_source_foreign_key)
        .reject { |k, _v| k.start_with?('_') }
    end

    def previous_temporal_tsrange_end
      hoardable_source.versions.only_most_recent.pluck('_during').first&.end
    end

    def assign_temporal_tsrange
      range_start = (
        previous_temporal_tsrange_end ||
        if hoardable_source.class.column_names.include?('created_at')
          hoardable_source.created_at
        else
          Time.at(0).utc
        end
      )
      self._during = (range_start..Time.now.utc)
    end
  end
end
