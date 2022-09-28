# frozen_string_literal: true

module Hoardable
  # This is a private service class that manages the insertion of {VersionModel}s for a
  # {SourceModel} into the PostgreSQL database.
  class DatabaseClient
    attr_reader :source_model, :hoardable_version

    def initialize(source_model)
      @source_model = source_model
    end

    def insert_hoardable_version(operation)
      @hoardable_version = initialize_hoardable_version(operation)
      source_model.run_callbacks(:versioned) do
        yield
        hoardable_version.save(validate: false, touch: false)
      end
    end

    def insert_hoardable_version_on_untrashed
      initialize_hoardable_version('insert').save(validate: false, touch: false)
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
      @hoardable_version = nil
      return if ActiveRecord::Base.connection.transaction_open?

      Thread.current[:hoardable_event_uuid] = nil
    end
  end
  private_constant :DatabaseClient
end
