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

    def prevent_saving_if_actually_a_version
      raise Error, 'You cannot save a Hoardable Model that is actually already a version' if source_record.version?
    end

    def insert_hoardable_version(operation, &block)
      version = version_class.insert(initialize_version_attributes(operation), returning: :id)
      version_id = version[0]['id']
      source_record.instance_variable_set('@hoardable_version', version_class.find(version_id))
      source_record.run_callbacks(:versioned, &block)
    end

    def find_or_initialize_hoardable_event_uuid
      Thread.current[:hoardable_event_uuid] ||= ActiveRecord::Base.connection.query('SELECT gen_random_uuid();')[0][0]
    end

    def hoardable_version_source_id
      @hoardable_version_source_id ||= query_hoardable_version_source_id
    end

    def query_hoardable_version_source_id
      primary_key = source_record.class.primary_key
      version_class.where(primary_key => source_record.read_attribute(primary_key)).pluck('hoardable_source_id')[0]
    end

    def initialize_version_attributes(operation)
      source_record.attributes_before_type_cast.without('id').merge(
        source_record.changes.transform_values { |h| h[0] },
        {
          'hoardable_source_id' => source_record.id,
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
      if source_record.class.column_names.include?('created_at')
        source_record.created_at
      else
        maybe_warn_about_missing_created_at_column
        Time.at(0).utc
      end
    end

    def maybe_warn_about_missing_created_at_column
      return unless source_record.class.hoardable_config[:warn_on_missing_created_at_column]

      source_table_name = source_record.class.table_name
      Hoardable.logger.info(
        <<~LOG
          '#{source_table_name}' does not have a 'created_at' column, so the first version’s temporal period
          will begin at the unix epoch instead. Add a 'created_at' column to '#{source_table_name}'
          or set 'Hoardable.warn_on_missing_created_at_column = false' to disable this message.
        LOG
      )
    end
  end
  private_constant :DatabaseClient
end
