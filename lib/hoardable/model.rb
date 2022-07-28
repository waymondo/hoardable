# frozen_string_literal: true

module Hoardable
  # This concern dynamically generates the Version variant of the class module Model and includes
  # the API methods and relationships on the source model
  module Model
    extend ActiveSupport::Concern

    included do
      define_model_callbacks :versioned
      define_model_callbacks :reverted, only: :after
      define_model_callbacks :untrashed, only: :after

      TracePoint.new(:end) do |trace|
        next unless self == trace.self

        version_class_name = "#{name}#{VERSION_CLASS_SUFFIX}"
        unless Object.const_defined?(version_class_name)
          Object.const_set(version_class_name, Class.new(self) { include VersionModel })
        end

        include SourceModel

        trace.disable
      end.enable
    end
  end
end
