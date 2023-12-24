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

      # Extends the current {SourceModel} scoping to include Hoardable’s {FinderMethods} overrides.
      def hoardable
        extending(FinderMethods)
      end
    end

    included do
      include Scopes

      around_update(if: [HOARDABLE_CALLBACKS_ENABLED, HOARDABLE_VERSION_UPDATES]) do |_, block|
        hoardable_client.insert_hoardable_version('update', &block)
      end

      around_destroy(if: [HOARDABLE_CALLBACKS_ENABLED, HOARDABLE_SAVE_TRASH]) do |_, block|
        hoardable_client.insert_hoardable_version('delete', &block)
      end

      before_destroy(if: HOARDABLE_CALLBACKS_ENABLED, unless: HOARDABLE_SAVE_TRASH) { versions.delete_all }

      after_commit { hoardable_client.unset_hoardable_version_and_event_uuid }

      # Returns all +versions+ in ascending order of their temporal timeframes.
      has_many(
        :versions,
        -> { order('UPPER(_during) ASC') },
        dependent: nil,
        class_name: version_class.to_s,
        inverse_of: :hoardable_source,
        foreign_key: :hoardable_id,
      )
    end

    # Returns a boolean of whether the record is actually a trashed +version+ cast as an instance of the
    # source model.
    #
    # @return [Boolean]
    def trashed?
      !self.class.exists?(self.class.primary_key => id)
    end

    # Returns a boolean of whether the record is actually a +version+ cast as an instance of the
    # source model.
    #
    # @return [Boolean]
    def version?
      hoardable_id != id
    end

    # Returns the +version+ at the supplied +datetime+ or +time+, or +self+ if there is none.
    #
    # @param datetime [DateTime, Time]
    def at(datetime)
      return self if datetime.nil? || !created_at

      version_at(datetime) || (self if created_at < datetime)
    end

    # Returns the +version+ at the supplied +datetime+ or +time+. This will raise an error if you
    # try to find a version in the future.
    #
    # @param datetime [DateTime, Time]
    def version_at(datetime)
      raise(Error, 'Future state cannot be known') if datetime.future?

      versions.at(datetime).limit(1).first
    end

    # If a version is found at the supplied datetime, it will +revert!+ to it and return it. This
    # will raise an error if you try to revert to a version in the future.
    #
    # @param datetime [DateTime, Time]
    def revert_to!(datetime)
      return unless (version = at(datetime))

      version.is_a?(version_class) ? version.revert! : self
    end

    def hoardable_id
      read_attribute('hoardable_id')
    end

    delegate :version_class, to: :class

    private

    def hoardable_client
      @hoardable_client ||= DatabaseClient.new(self)
    end
  end
end
