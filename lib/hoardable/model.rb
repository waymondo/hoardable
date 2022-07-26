# frozen_string_literal: true

module Hoardable
  # This concern includes the Hoardable API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }

      before_update :initialize_hoardable_version, if: -> { Hoardable.enabled }
      before_destroy :initialize_hoardable_version, if: -> { Hoardable.enabled && Hoardable.save_trash }
      after_update :save_hoardable_version, if: -> { Hoardable.enabled }
      before_destroy :delete_hoardable_versions, if: -> { Hoardable.enabled && !Hoardable.save_trash }
      after_destroy :save_hoardable_version, if: -> { Hoardable.enabled && Hoardable.save_trash }

      attr_reader :hoardable_version

      define_model_callbacks :reverted, only: :after

      TracePoint.new(:end) do |trace|
        next unless self == trace.self

        version_class_name = "#{name}Version"
        next if Object.const_defined?(version_class_name)

        Object.const_set(version_class_name, Class.new(self) { include VersionModel })
        has_many(
          :versions, -> { order(:_during) },
          dependent: nil,
          class_name: version_class_name,
          inverse_of: model_name.i18n_key
        )
        trace.disable
      end.enable
    end

    def at(datetime)
      versions.find_by('_during @> ?::timestamp', datetime) || self
    end

    private

    def initialize_hoardable_version
      @hoardable_version = versions.new(
        attributes_before_type_cast
          .without('id')
          .merge(changes.transform_values { |h| h[0] })
          .merge(_data: initialize_hoardable_data.merge(changes: changes))
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

    def save_hoardable_version
      hoardable_version._operation = persisted? ? 'update' : 'delete'
      hoardable_version.save!(validate: false, touch: false)
      @hoardable_version = nil
    end

    def delete_hoardable_versions
      versions.delete_all(:delete_all)
    end
  end
end
