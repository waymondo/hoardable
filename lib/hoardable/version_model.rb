# frozen_string_literal: true

module Hoardable
  # This concern is included into the dynamically generated +Version+ kind of the parent
  # +ActiveRecord+ class.
  module VersionModel
    extend ActiveSupport::Concern

    included do
      # A +version+ belongs to it’s parent +ActiveRecord+ source.
      belongs_to(
        :hoardable_source,
        inverse_of: :versions,
        class_name: superclass.model_name
      )

      self.table_name = "#{table_name.singularize}#{VERSION_TABLE_SUFFIX}"

      alias_method :readonly?, :persisted?
      alias_attribute :hoardable_operation, :_operation
      alias_attribute :hoardable_event_uuid, :_event_uuid
      alias_attribute :hoardable_during, :_during

      before_create { hoardable_version_service.assign_temporal_tsrange }

      # @!scope class
      # @!method trashed
      # @return [ActiveRecord<Object>]
      #
      # Returns only trashed +versions+ that are currently orphans.
      scope :trashed, lambda {
        left_outer_joins(:hoardable_source)
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
          reverted.update!(hoardable_version_service.hoardable_source_attributes.without('id'))
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
        hoardable_version_service.insert_untrashed_source.tap do |untrashed|
          untrashed.send('hoardable_source_service').insert_hoardable_version('insert')
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
      @hoardable_source_foreign_id ||= public_send(:hoardable_source_id)
    end

    def hoardable_version_service
      @hoardable_version_service ||= Service.new(self)
    end

    # This is a private service class that manages the construction of {VersionModel} attributes and
    # untrashing / re-insertion into the {SourceModel} table.
    class Service
      attr_reader :version_model

      def initialize(version_model)
        @version_model = version_model
      end

      delegate :hoardable_source_foreign_id, :hoardable_source, to: :version_model

      def insert_untrashed_source
        superscope = version_model.class.superclass.unscoped
        superscope.insert(hoardable_source_attributes.merge('id' => hoardable_source_foreign_id))
        superscope.find(hoardable_source_foreign_id)
      end

      def hoardable_source_attributes
        @hoardable_source_attributes ||=
          version_model
          .attributes_before_type_cast
          .without('hoardable_source_id')
          .reject { |k, _v| k.start_with?('_') }
      end

      def previous_temporal_tsrange_end
        hoardable_source.versions.only_most_recent.pluck('_during').first&.end
      end

      def hoardable_source_epoch
        if hoardable_source.class.column_names.include?('created_at')
          hoardable_source.created_at
        else
          maybe_warn_about_missing_created_at_column
          Time.at(0).utc
        end
      end

      def assign_temporal_tsrange
        version_model._during = ((previous_temporal_tsrange_end || hoardable_source_epoch)..Time.now.utc)
      end

      def maybe_warn_about_missing_created_at_column
        return unless hoardable_source.class.hoardable_config[:warn_on_missing_created_at_column]

        source_table_name = hoardable_source.class.table_name
        Hoardable.logger.info(
          <<~LOG
            '#{source_table_name}' does not have a 'created_at' column, so the first version’s temporal period
            will begin at the unix epoch instead. Add a 'created_at' column to '#{source_table_name}'
            or set 'Hoardable.warn_on_missing_created_at_column = false' to disable this message.
          LOG
        )
      end
    end
    private_constant :Service
  end
end
