# frozen_string_literal: true

# An +ActiveRecord+ extension for keeping versions of records in uni-temporal inherited tables.
module Hoardable
  # Symbols for use with setting contextual data, when creating versions. See
  # {file:README.md#tracking-contextual-data README} for more.
  DATA_KEYS = %i[meta whodunit note event_uuid].freeze
  # Symbols for use with setting {Hoardable} configuration. See {file:README.md#configuration
  # README} for more.
  CONFIG_KEYS = %i[enabled version_updates save_trash return_everything].freeze

  # @!visibility private
  VERSION_CLASS_SUFFIX = 'Version'

  # @!visibility private
  VERSION_TABLE_SUFFIX = "_#{VERSION_CLASS_SUFFIX.tableize}"

  # @!visibility private
  DURING_QUERY = '_during @> ?::timestamp'

  @context = {}
  @config = CONFIG_KEYS.to_h do |key|
    [key, key != :return_everything]
  end

  class << self
    CONFIG_KEYS.each do |key|
      define_method(key) do
        @config[key]
      end

      define_method("#{key}=") do |value|
        @config[key] = value
      end
    end

    DATA_KEYS.each do |key|
      define_method(key) do
        @context[key]
      end

      define_method("#{key}=") do |value|
        @context[key] = value
      end
    end

    # This is a general use method for setting {DATA_KEYS} or {CONFIG_KEYS} around a scoped block.
    #
    # @param hash [Hash] config and contextual data to set within a block
    def with(hash)
      current_config = @config
      current_context = @context
      @config = current_config.merge(hash.slice(*CONFIG_KEYS))
      @context = current_context.merge(hash.slice(*DATA_KEYS))
      yield
    ensure
      @config = current_config
      @context = current_context
    end
  end
end
