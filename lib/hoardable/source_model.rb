# frozen_string_literal: true

module Hoardable
  # This concern contains the {Hoardable} relationships, callbacks, and API methods for an
  # +ActiveRecord+. It is included by {Hoardable::Model} after the dynamic generation of the
  # +Version+ class variant.
  module SourceModel
    extend ActiveSupport::Concern

    class_methods do
      # The dynamically generated +Version+ class for this model.
      def version_class
        "#{name}#{VERSION_CLASS_SUFFIX}".constantize
      end
    end

    included do
      include Tableoid

      around_update :insert_hoardable_version_on_update, if: %i[hoardable_callbacks_enabled hoardable_version_updates]
      around_destroy :insert_hoardable_version_on_destroy, if: %i[hoardable_callbacks_enabled hoardable_save_trash]
      before_destroy :delete_hoardable_versions, if: :hoardable_callbacks_enabled, unless: :hoardable_save_trash
      after_commit :unset_hoardable_version_and_event_uuid

      # This will contain the +Version+ class instance for use within +versioned+, +reverted+, and
      # +untrashed+ callbacks.
      attr_reader :hoardable_version

      # @!attribute [r] hoardable_event_uuid
      #   @return [String] A postgres UUID that represents the +version+’s +ActiveRecord+ database transaction
      # @!attribute [r] hoardable_operation
      #   @return [String] The database operation that created the +version+ - either +update+ or +delete+.
      delegate :hoardable_event_uuid, :hoardable_operation, to: :hoardable_version, allow_nil: true

      # Returns all +versions+ in ascending order of their temporal timeframes.
      has_many(
        :versions, -> { order('UPPER(_during) ASC') },
        dependent: nil,
        class_name: version_class.to_s,
        inverse_of: model_name.i18n_key
      )

      # @!scope class
      # @!method at
      # @return [ActiveRecord<Object>]
      #
      # Returns instances of the source model and versions that were valid at the supplied
      # +datetime+ or +time+, all cast as instances of the source model.
      scope :at, lambda { |datetime|
        include_versions.where(id: version_class.at(datetime).select('id')).or(
          where.not(
            id: version_class.select(version_class.hoardable_source_foreign_key).where(DURING_QUERY, datetime)
          )
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

    def hoardable_callbacks_enabled
      self.class.hoardable_config[:enabled] && !self.class.name.end_with?(VERSION_CLASS_SUFFIX)
    end

    def hoardable_save_trash
      self.class.hoardable_config[:save_trash]
    end

    def hoardable_version_updates
      self.class.hoardable_config[:version_updates]
    end

    def insert_hoardable_version_on_update(&block)
      insert_hoardable_version('update', &block)
    end

    def insert_hoardable_version_on_destroy(&block)
      insert_hoardable_version('delete', &block)
    end

    def insert_hoardable_version_on_untrashed
      initialize_hoardable_version('insert').save(validate: false, touch: false)
    end

    def insert_hoardable_version(operation)
      @hoardable_version = initialize_hoardable_version(operation)
      run_callbacks(:versioned) do
        yield
        hoardable_version.save(validate: false, touch: false)
      end
    end

    def find_or_initialize_hoardable_event_uuid
      Thread.current[:hoardable_event_uuid] ||= ActiveRecord::Base.connection.query('SELECT gen_random_uuid();')[0][0]
    end

    def initialize_hoardable_version(operation)
      versions.new(
        attributes_before_type_cast.without('id').merge(
          changes.transform_values { |h| h[0] },
          {
            _event_uuid: find_or_initialize_hoardable_event_uuid,
            _operation: operation,
            _data: initialize_hoardable_data.merge(changes: changes)
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

    def delete_hoardable_versions
      versions.delete_all(:delete_all)
    end

    def unset_hoardable_version_and_event_uuid
      @hoardable_version = nil
      return if ActiveRecord::Base.connection.transaction_open?

      Thread.current[:hoardable_event_uuid] = nil
    end
  end
end
