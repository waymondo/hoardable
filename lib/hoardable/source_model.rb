# frozen_string_literal: true

module Hoardable
  # This concern contains the {Hoardable} relationships, callbacks, and API methods for an
  # +ActiveRecord+. It is included by {Hoardable::Model} after the dynamic generation of the
  # +Version+ class variant.
  module SourceModel
    extend ActiveSupport::Concern

    # The +Version+ class instance for use within +versioned+, +reverted+, and +untrashed+ callbacks.
    attr_reader :hoardable_version

    # @!attribute [r] hoardable_event_uuid
    #   @return [String] A postgres UUID that represents the +version+’s +ActiveRecord+ database transaction
    # @!attribute [r] hoardable_operation
    #   @return [String] The database operation that created the +version+ - either +update+ or +delete+.
    delegate :hoardable_event_uuid, :hoardable_operation, to: :hoardable_version, allow_nil: true

    class_methods do
      # The dynamically generated +Version+ class for this model.
      def version_class
        "#{name}#{VERSION_CLASS_SUFFIX}".constantize
      end
    end

    included do
      include Tableoid

      around_update(if: [HOARDABLE_CALLBACKS_ENABLED, HOARDABLE_VERSION_UPDATES]) do |_, block|
        hoardable_source_service.insert_hoardable_version('update', &block)
      end

      around_destroy(if: [HOARDABLE_CALLBACKS_ENABLED, HOARDABLE_SAVE_TRASH]) do |_, block|
        hoardable_source_service.insert_hoardable_version('delete', &block)
      end

      before_destroy(if: HOARDABLE_CALLBACKS_ENABLED, unless: HOARDABLE_SAVE_TRASH) do
        versions.delete_all(:delete_all)
      end

      after_commit { hoardable_source_service.unset_hoardable_version_and_event_uuid }

      # Returns all +versions+ in ascending order of their temporal timeframes.
      has_many(
        :versions, -> { order('UPPER(_during) ASC') },
        dependent: nil,
        class_name: version_class.to_s,
        inverse_of: :hoardable_source,
        foreign_key: :hoardable_source_id
      )

      # @!scope class
      # @!method at
      # @return [ActiveRecord<Object>]
      #
      # Returns instances of the source model and versions that were valid at the supplied
      # +datetime+ or +time+, all cast as instances of the source model.
      scope :at, lambda { |datetime|
        include_versions.where(id: version_class.at(datetime).select('id')).or(
          where.not(id: version_class.select(:hoardable_source_id).where(DURING_QUERY, datetime))
        )
      }
    end

    # Returns a boolean of whether the record is actually a trashed +version+.
    #
    # @return [Boolean]
    def trashed?
      versions.trashed.only_most_recent.first&.hoardable_source_foreign_id == id
    end

    # Returns the +version+ at the supplied +datetime+ or +time+. It will return +self+ if there is
    # none. This will raise an error if you try to find a version in the future.
    #
    # @param datetime [DateTime, Time]
    def at(datetime)
      raise(Error, 'Future state cannot be known') if datetime.future?

      versions.at(datetime).first || self
    end

    # If a version is found at the supplied datetime, it will +revert!+ to it and return it. This
    # will raise an error if you try to revert to a version in the future.
    #
    # @param datetime [DateTime, Time]
    def revert_to!(datetime)
      return unless (version = at(datetime))

      version.is_a?(self.class.version_class) ? version.revert! : self
    end

    private

    def hoardable_source_service
      @hoardable_source_service ||= Service.new(self)
    end

    # This is a private service class that manages the insertion of {VersionModel}s for a
    # {SourceModel} into the PostgreSQL database.
    class Service
      attr_reader :source_model

      def initialize(source_model)
        @source_model = source_model
      end

      def insert_hoardable_version(operation)
        source_model.instance_variable_set('@hoardable_version', initialize_hoardable_version(operation))
        source_model.run_callbacks(:versioned) do
          yield if block_given?
          source_model.hoardable_version.save(validate: false, touch: false)
        end
      end

      def find_or_initialize_hoardable_event_uuid
        Thread.current[:hoardable_event_uuid] ||= ActiveRecord::Base.connection.query('SELECT gen_random_uuid();')[0][0]
      end

      def initialize_hoardable_version(operation)
        source_model.versions.new(
          source_model.attributes_before_type_cast.without('id').merge(
            source_model.changes.transform_values { |h| h[0] },
            {
              _event_uuid: find_or_initialize_hoardable_event_uuid,
              _operation: operation,
              _data: initialize_hoardable_data.merge(changes: source_model.changes)
            }
          )
        )
      end

      def initialize_hoardable_data
        DATA_KEYS.to_h do |key|
          [key, assign_hoardable_context(key)]
        end
      end

      def assign_hoardable_context(key)
        return nil if (value = Hoardable.public_send(key)).nil?

        value.is_a?(Proc) ? value.call : value
      end

      def unset_hoardable_version_and_event_uuid
        source_model.instance_variable_set('@hoardable_version', nil)
        return if source_model.class.connection.transaction_open?

        Thread.current[:hoardable_event_uuid] = nil
      end
    end
    private_constant :Service
  end
end
