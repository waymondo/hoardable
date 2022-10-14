# frozen_string_literal: true

# An +ActiveRecord+ extension for keeping versions of records in uni-temporal inherited tables.
module Hoardable
  # Symbols for use with setting contextual data, when creating versions. See
  # {file:README.md#tracking-contextual-data README} for more.
  DATA_KEYS = %i[meta whodunit note event_uuid].freeze

  # Symbols for use with setting {Hoardable} configuration. See {file:README.md#configuration
  # README} for more.
  CONFIG_KEYS = %i[enabled version_updates save_trash].freeze

  VERSION_CLASS_SUFFIX = 'Version'
  private_constant :VERSION_CLASS_SUFFIX

  VERSION_TABLE_SUFFIX = "_#{VERSION_CLASS_SUFFIX.tableize}"
  private_constant :VERSION_TABLE_SUFFIX

  DURING_QUERY = '_during @> ?::timestamp'
  private_constant :DURING_QUERY

  HOARDABLE_CALLBACKS_ENABLED = proc do |source_model|
    source_model.class.hoardable_config[:enabled] && !source_model.class.name.end_with?(VERSION_CLASS_SUFFIX)
  end.freeze
  private_constant :HOARDABLE_CALLBACKS_ENABLED

  HOARDABLE_SAVE_TRASH = proc do |source_model|
    source_model.class.hoardable_config[:save_trash]
  end.freeze
  private_constant :HOARDABLE_SAVE_TRASH

  HOARDABLE_VERSION_UPDATES = proc do |source_model|
    source_model.class.hoardable_config[:version_updates]
  end.freeze
  private_constant :HOARDABLE_VERSION_UPDATES

  SUPPORTS_ENCRYPTED_ACTION_TEXT = ActiveRecord.version >= ::Gem::Version.new('7.0.4')
  private_constant :SUPPORTS_ENCRYPTED_ACTION_TEXT

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

    # This is a general use method for setting {file:README.md#tracking-contextual-data Contextual
    # Data} or {file:README.md#configuration Configuration} around a block.
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

    # Allows performing a query for record states at a certain time. Returned {SourceModel}
    # instances within the block may be {SourceModel} or {VersionModel} records.
    #
    # @param datetime [DateTime, Time] the datetime or time to temporally query records at
    def at(datetime)
      @at = datetime
      yield
    ensure
      @at = nil
    end

    # @!visibility private
    def logger
      @logger ||= ActiveSupport::TaggedLogging.new(Logger.new($stdout))
    end
  end

  # A +Rails+ engine for providing support for +ActionText+
  class Engine < ::Rails::Engine
    isolate_namespace Hoardable

    initializer 'hoardable.action_text' do
      ActiveSupport.on_load(:action_text_rich_text) do
        require_relative 'rich_text'
        require_relative 'encrypted_rich_text' if SUPPORTS_ENCRYPTED_ACTION_TEXT
      end
    end
  end
end
