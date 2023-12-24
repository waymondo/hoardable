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
      version =
        version_class.insert(
          initialize_version_attributes(operation),
          returning: source_primary_key.to_sym
        )
      version_id = version[0][source_primary_key]
      source_record.instance_variable_set("@hoardable_version", version_class.find(version_id))
      source_record.run_callbacks(:versioned, &block)
    end

    def source_primary_key
      source_record.class.primary_key
    end

    def find_or_initialize_hoardable_event_uuid
      Thread.current[:hoardable_event_uuid] ||= (
        ActiveRecord::Base.connection.query("SELECT gen_random_uuid();")[0][0]
      )
    end

    def initialize_version_attributes(operation)
      source_attributes_without_primary_key.merge(
        source_record.changes.transform_values { |h| h[0] },
        {
          "hoardable_id" => source_record.id,
          "_event_uuid" => find_or_initialize_hoardable_event_uuid,
          "_operation" => operation,
          "_data" => initialize_hoardable_data.merge(changes: source_record.changes),
          "_during" => initialize_temporal_range
        }
      )
    end

    def has_one_find_conditions(reflection)
      {
        reflection.type => source_record.class.name.sub(/Version$/, ""),
        reflection.foreign_key => source_record.hoardable_id,
        "name" =>
          (reflection.name.to_s.sub(/^rich_text_/, "") if reflection.class_name.match?(/RichText$/))
      }.reject { |k, v| k.nil? || v.nil? }
    end

    def has_one_at_timestamp
      Hoardable.instance_variable_get("@at") || source_record.updated_at
    rescue NameError
      raise(UpdatedAtColumnMissingError, source_record.class.table_name)
    end

    def source_attributes_without_primary_key
      source_record
        .attributes
        .without(source_primary_key, *generated_column_names)
        .merge(
          source_record
            .class
            .select(refreshable_column_names)
            .find(source_record.id)
            .slice(refreshable_column_names)
        )
    end

    def generated_column_names
      @generated_column_names ||= source_record.class.columns.select(&:virtual?).map(&:name)
    rescue NoMethodError
      []
    end

    def refreshable_column_names
      @refreshable_column_names ||=
        source_record
          .class
          .columns
          .select(&:default_function)
          .reject do |column|
            column.name == source_primary_key || column.name.in?(generated_column_names)
          end
          .map(&:name)
    end

    def initialize_temporal_range
      ((previous_temporal_tsrange_end || hoardable_source_epoch)..Time.now.utc)
    end

    def initialize_hoardable_data
      DATA_KEYS.to_h { |key| [key, assign_hoardable_context(key)] }
    end

    def assign_hoardable_context(key)
      return nil if (value = Hoardable.public_send(key)).nil?

      value.is_a?(Proc) ? value.call : value
    end

    def unset_hoardable_version_and_event_uuid
      source_record.instance_variable_set("@hoardable_version", nil)
      return if source_record.class.connection.transaction_open?

      Thread.current[:hoardable_event_uuid] = nil
    end

    def previous_temporal_tsrange_end
      source_record.versions.only_most_recent.pluck("_during").first&.end
    end

    def hoardable_source_epoch
      return source_record.created_at if source_record.class.column_names.include?("created_at")

      raise CreatedAtColumnMissingError, source_record.class.table_name
    end
  end
  private_constant :DatabaseClient
end
