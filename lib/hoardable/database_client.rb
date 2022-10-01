# frozen_string_literal: true

module Hoardable
  # This is a private service class that manages the insertion of {VersionModel}s into the
  # PostgreSQL database.
  class DatabaseClient
    attr_reader :source_model

    def initialize(source_model)
      @source_model = source_model
    end

    delegate :version_class, to: :source_model

    def insert_hoardable_version(operation, &block)
      version = version_class.insert(initialize_version_attributes(operation), returning: :id)
      version_id = version[0]['id']
      source_model.instance_variable_set('@hoardable_version', version_class.find(version_id))
      source_model.run_callbacks(:versioned, &block)
    end

    def find_or_initialize_hoardable_event_uuid
      Thread.current[:hoardable_event_uuid] ||= ActiveRecord::Base.connection.query('SELECT gen_random_uuid();')[0][0]
    end

    def initialize_version_attributes(operation)
      source_model.attributes_before_type_cast.without('id').merge(
        source_model.changes.transform_values { |h| h[0] },
        {
          'hoardable_source_id' => source_model.id,
          '_event_uuid' => find_or_initialize_hoardable_event_uuid,
          '_operation' => operation,
          '_data' => initialize_hoardable_data.merge(changes: source_model.changes),
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
      source_model.instance_variable_set('@hoardable_version', nil)
      return if source_model.class.connection.transaction_open?

      Thread.current[:hoardable_event_uuid] = nil
    end

    def previous_temporal_tsrange_end
      source_model.versions.only_most_recent.pluck('_during').first&.end
    end

    def hoardable_source_epoch
      if source_model.class.column_names.include?('created_at')
        source_model.created_at
      else
        maybe_warn_about_missing_created_at_column
        Time.at(0).utc
      end
    end

    def maybe_warn_about_missing_created_at_column
      return unless source_model.class.hoardable_config[:warn_on_missing_created_at_column]

      source_table_name = source_model.class.table_name
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
