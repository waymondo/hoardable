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

    # A module for overriding +ActiveRecord#find_one+’ in the case you are doing a temporal query
    # and the current {SourceModel} record may in fact be a {VersionModel} record.
    module FinderMethods
      def find_one(id)
        conditions = { primary_key => [id, *version_class.where(hoardable_source_id: id).select(primary_key).ids] }
        find_by(conditions) || where(conditions).raise_record_not_found_exception!
      end
    end
    private_constant :FinderMethods

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

      before_destroy(if: HOARDABLE_CALLBACKS_ENABLED, unless: HOARDABLE_SAVE_TRASH) do
        versions.delete_all(:delete_all)
      end

      before_commit { hoardable_client.prevent_saving_if_actually_a_version }
      after_commit { hoardable_client.unset_hoardable_version_and_event_uuid }

      # Returns all +versions+ in ascending order of their temporal timeframes.
      has_many(
        :versions, -> { order('UPPER(_during) ASC') },
        dependent: nil,
        class_name: version_class.to_s,
        inverse_of: :hoardable_source,
        foreign_key: :hoardable_source_id
      )
    end

    # Returns a boolean of whether the record is actually a trashed +version+ cast as an instance of the
    # source model.
    #
    # @return [Boolean]
    def trashed?
      versions.trashed.only_most_recent.first&.hoardable_source_id == id
    end

    # Returns a boolean of whether the record is actually a +version+ cast as an instance of the
    # source model.
    #
    # @return [Boolean]
    def version?
      !!hoardable_client.hoardable_version_source_id
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

      version.is_a?(version_class) ? version.revert! : self
    end

    # Returns the +hoardable_source_id+ that represents the original {SourceModel} record’s ID. Will
    # return nil if the current {SourceModel} record is not an instance of a {VersionModel} cast as
    # {SourceModel}.
    #
    # @return [Integer, nil]
    def hoardable_source_id
      hoardable_client.hoardable_version_source_id || id
    end

    delegate :version_class, to: :class

    private

    def hoardable_client
      @hoardable_client ||= DatabaseClient.new(self)
    end
  end
end
