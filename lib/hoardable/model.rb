# frozen_string_literal: true

module Hoardable
  # This concern is the main entrypoint for using {Hoardable}. When included into an +ActiveRecord+
  # class, it dynamically generates the +Version+ variant of that class (with {VersionModel}) and
  # includes the {Hoardable} API methods and relationships on the source model class (through
  # {SourceModel}).
  module Model
    extend ActiveSupport::Concern

    class_methods do
      # Allows setting a custom table name for the +version+ model.
      attr_accessor :version_table_name

      # If called with a hash, this will set the model-level +Hoardable+ configuration variables. If
      # called without an argument it will return the computed +Hoardable+ configuration considering
      # both model-level and global values.
      #
      # @param hash [Hash] The +Hoardable+ configuration for the model. Keys must be present in
      #   {CONFIG_KEYS}
      # @return [Hash]
      def hoardable_config(hash = nil)
        if hash
          @_hoardable_config = hash.slice(*CONFIG_KEYS)
        else
          CONFIG_KEYS.to_h { |key| [key, _hoardable_config.fetch(key) { Hoardable.send(key) }] }
        end
      end

      # Set the model-level +Hoardable+ configuration variables around a block. The configuration
      # will be reset to it’s previous value afterwards.
      #
      # @param hash [Hash] The +Hoardable+ configuration for the model. Keys must be present in
      #   {CONFIG_KEYS}
      def with_hoardable_config(hash)
        thread = Thread.current
        current_thread_config = thread[hoardable_current_config_key]
        thread[hoardable_current_config_key] = _hoardable_config.merge(hash.slice(*CONFIG_KEYS))
        yield
      ensure
        thread[hoardable_current_config_key] = current_thread_config
      end

      private def _hoardable_config
        (@_hoardable_config ||= {}).merge(Thread.current[hoardable_current_config_key] ||= {})
      end

      private def hoardable_current_config_key
        :"hoardable_#{name}_config"
      end
    end

    included do
      include Associations
      attr_readonly :hoardable_id
      define_model_callbacks :versioned, only: :after
      define_model_callbacks :reverted, only: :after
      define_model_callbacks :untrashed, only: :after
    end

    def self.included(base)
      TracePoint
        .new(:end) do |trace|
          next unless base == trace.self

          full_version_class_name = "#{base.name}#{VERSION_CLASS_SUFFIX}"
          if (namespace_match = full_version_class_name.match(/(.*)::(.*)/))
            object_namespace = namespace_match[1].constantize
            version_class_name = namespace_match[2]
          else
            object_namespace = Object
            version_class_name = full_version_class_name
          end
          unless Object.const_defined?(full_version_class_name)
            object_namespace.const_set(version_class_name, Class.new(base) { include VersionModel })
          end
          base.class_eval { include SourceModel }
          REGISTRY.add(base)

          trace.disable
        end
        .enable
    end
  end
end
