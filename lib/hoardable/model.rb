# frozen_string_literal: true

module Hoardable
  # This concern includes the Hoardable API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }
      define_model_callbacks :versioned
      attr_reader :_version

      TracePoint.new(:end) do |trace|
        next unless self == trace.self

        version_class_name = "#{name}Version"
        next if Object.const_defined?(version_class_name)

        Object.const_set(version_class_name, Class.new(self) { include VersionModel })
        class_eval do
          has_many(:versions, dependent: :destroy, class_name: version_class_name, inverse_of: model_name.i18n_key)
        end
        trace.disable
      end.enable
    end

    def at(datetime)
      versions.find_by('hoardable_during @> ?::timestamp', datetime) || self
    end

    def versioned_update!(attributes)
      ActiveRecord::Base.transaction do
        @_version = versions.new(attributes_before_type_cast.without('id'))
        run_callbacks :versioned do
          assign_attributes(attributes)
          _version.hoardable_data = { attributes: attributes }
          _version.send(:assign_temporal_tsrange)
          _version.save!(validate: false, touch: false)
          save!
        end
      end
    end
  end
end
