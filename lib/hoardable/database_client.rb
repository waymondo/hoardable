# frozen_string_literal: true

module Hoardable
  # This is a private service class that manages the insertion of {VersionModel}s into the
  # PostgreSQL database.
  class DatabaseClient
    attr_reader :source_record

    def initialize(source_record)
      @source_record = source_record
    end

    delegate :version_class, to: :source_record

    def insert_hoardable_version(operation, &block)
      version = version_class.insert(initialize_version_attributes(operation), returning: :id)
      version_id = version[0]['id']
      source_record.instance_variable_set('@hoardable_version', version_class.find(version_id))
      source_record.run_callbacks(:versioned, &block)
    end

    def find_or_initialize_hoardable_event_uuid
      Thread.current[:hoardable_event_uuid] ||= ActiveRecord::Base.connection.query('SELECT gen_random_uuid();')[0][0]
    end

    def initialize_version_attributes(operation)
      source_record.attributes_before_type_cast.without('id').merge(
        source_record.changes.transform_values { |h| h[0] },
        {
          'hoardable_id' => source_record.id,
          '_event_uuid' => find_or_initialize_hoardable_event_uuid,
          '_operation' => operation,
          '_data' => initialize_hoardable_data.merge(changes: source_record.changes),
          '_during' => initialize_temporal_range
        }
      )
    end

    def initialize_temporal_range
      ((previous_temporal_tsrange_end || hoardable_source_epoch)..Time.now.utc)
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
      source_record.instance_variable_set('@hoardable_version', nil)
      return if source_record.class.connection.transaction_open?

      Thread.current[:hoardable_event_uuid] = nil
    end

    def previous_temporal_tsrange_end
      source_record.versions.only_most_recent.pluck('_during').first&.end
    end

    def hoardable_source_epoch
      return source_record.created_at if source_record.class.column_names.include?('created_at')

      raise CreatedAtColumnMissingError, source_record.class.table_name
    end
  end
  private_constant :DatabaseClient
end
