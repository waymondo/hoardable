# frozen_string_literal: true

module Hoardable
  # This concern includes the Hoardable API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    HOARDABLE_ENABLED = -> { Hoardable[:enabled] }.freeze

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }
      before_update :initialize_hoardable_version, if: HOARDABLE_ENABLED
      before_destroy :initialize_hoardable_version, if: HOARDABLE_ENABLED
      after_update :save_hoardable_version, if: HOARDABLE_ENABLED
      after_destroy :save_hoardable_version, if: HOARDABLE_ENABLED
      attr_reader :hoardable_version

      TracePoint.new(:end) do |trace|
        next unless self == trace.self

        version_class_name = "#{name}Version"
        next if Object.const_defined?(version_class_name)

        Object.const_set(version_class_name, Class.new(self) { include VersionModel })
        class_eval do
          has_many(
            :versions, -> { order(:_during) },
            dependent: :destroy, class_name: version_class_name, inverse_of: model_name.i18n_key
          )
        end
        trace.disable
      end.enable
    end

    def at(datetime)
      versions.find_by('_during @> ?::timestamp', datetime) || self
    end

    private

    def initialize_hoardable_version
      Hoardable.with(changes: changes) do
        @hoardable_version = versions.new(
          attributes_before_type_cast
            .without('id')
            .merge(changes.transform_values { |h| h[0] })
            .merge(_data: initialize_hoardable_data)
        )
      end
    end

    def initialize_hoardable_data
      Hoardable::VersionModel::DATA_KEYS.to_h do |key|
        [key, assign_hoardable_context(key)]
      end
    end

    def assign_hoardable_context(key)
      return nil if (value = Hoardable[key]).nil?

      value.is_a?(Proc) ? value.call : value
    end

    def save_hoardable_version
      hoardable_version.save!(validate: false, touch: false)
      @hoardable_version = nil
    end
  end
end
