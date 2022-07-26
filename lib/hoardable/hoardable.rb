# frozen_string_literal: true

# An ActiveRecord extension for keeping versions of records in temporal inherited tables
module Hoardable
  VERSION = '0.1.0'
  DATA_KEYS = %i[changes meta whodunit note operation].freeze
  CONFIG_KEYS = %i[enabled save_trash].freeze

  @context = {}
  @config = CONFIG_KEYS.to_h do |key|
    [key, true]
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
