# frozen_string_literal: true

module Archiversion
  # This concern includes the Archiversion API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }
      define_model_callbacks :versioned
      attr_reader :_version

      version_class_name = "#{name}Version"
      TracePoint.new(:end) do |trace|
        next unless self == trace.self
        next if Object.const_defined?(version_class_name)

        version_class = Class.new(self) do
          include VersionModel
        end
        Object.const_set(version_class_name, version_class)
        class_eval do
          has_many(:versions, dependent: :destroy, class_name: version_class_name, inverse_of: model_name.i18n_key)
        end
        trace.disable
      end.enable
    end

    def versioned_update!(attributes)
      ActiveRecord::Base.transaction do
        @_version = versions.new(dup.attributes)
        run_callbacks :versioned do
          assign_attributes(attributes)
          _version.av_data = { attributes: attributes }
          _version.av_during = (updated_at..Time.now)
          _version.save!
          save!
        end
      end
    end
  end
end
