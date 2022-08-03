# frozen_string_literal: true

module Hoardable
  # This concern is the main entrypoint for using {Hoardable}. When included into an +ActiveRecord+
  # class, it dynamically generates the +Version+ variant of that class (with {VersionModel}) and
  # includes the {Hoardable} API methods and relationships on the source model class (through
  # {SourceModel}).
  module Model
    extend ActiveSupport::Concern

    class_methods do
      # @!visibility private
      attr_reader :_hoardable_options

      # If called with a hash, this will set the model-level +Hoardable+ configuration variables. If
      # called without an argument it will return the computed +Hoardable+ configuration considering
      # both model-level and global values.
      #
      # @param hash [Hash] The +Hoardable+ configuration for the model. Keys must be present in
      #   {CONFIG_KEYS}
      # @return [Hash]
      def hoardable_options(hash = nil)
        if hash
          @_hoardable_options = hash.slice(*Hoardable::CONFIG_KEYS)
        else
          @_hoardable_options ||= {}
          Hoardable::CONFIG_KEYS.to_h do |key|
            [key, Hoardable.send(key) != false && @_hoardable_options[key] != false]
          end
        end
      end
    end

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
