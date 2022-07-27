# frozen_string_literal: true

module Hoardable
  # This concern contains the relationships, callbacks, and API methods for a Source model
  module SourceModel
    extend ActiveSupport::Concern

    included do
      around_update :insert_hoardable_version_on_update, if: :hoardable_callbacks_enabled
      around_destroy :insert_hoardable_version_on_destroy, if: [:hoardable_callbacks_enabled, SAVE_TRASH_ENABLED]
      before_destroy :delete_hoardable_versions, if: :hoardable_callbacks_enabled, unless: SAVE_TRASH_ENABLED
      after_commit :unset_hoardable_version_and_event_id

      attr_reader :hoardable_version

      include Tableoid

      has_many(
        :versions, -> { order(:_during) },
        dependent: nil,
        class_name: "#{name}#{VERSION_CLASS_SUFFIX}",
        inverse_of: model_name.i18n_key
      )
    end

    def trashed?
      versions.limit(1).order(_during: :desc).first&.send(:hoardable_source_attributes) == attributes
    end

    def at(datetime)
      versions.find_by('_during @> ?::timestamp', datetime) || self
    end

    private

    def hoardable_callbacks_enabled
      Hoardable.enabled && !self.class.name.end_with?(VERSION_CLASS_SUFFIX)
    end

    def insert_hoardable_version_on_update(&block)
      insert_hoardable_version('update', attributes_before_type_cast.without('id'), &block)
    end

    def insert_hoardable_version_on_destroy(&block)
      insert_hoardable_version('delete', attributes_before_type_cast, &block)
    end

    def insert_hoardable_version(operation, attrs)
      event_id = find_or_initialize_hoardable_event_id
      Hoardable.with(event_id: event_id) do
        @hoardable_version = initialize_hoardable_version(operation, attrs)
        run_callbacks(:versioned) do
          yield
          hoardable_version.save(validate: false, touch: false)
        end
      end
    end

    def find_or_initialize_hoardable_event_id
      Thread.current[:hoardable_event_id] ||= SecureRandom.hex
    end

    def initialize_hoardable_version(operation, attrs)
      versions.new(
        attrs.merge(
          changes.transform_values { |h| h[0] },
          {
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

    def unset_hoardable_version_and_event_id
      @hoardable_version = nil
      return if ActiveRecord::Base.connection.transaction_open?

      Thread.current[:hoardable_event_id] = nil
    end
  end
end
