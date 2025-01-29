# frozen_string_literal: true

# An +ActiveRecord+ extension for keeping versions of records in uni-temporal inherited tables.
module Hoardable
  REGISTRY = Set.new

  # Symbols for use with setting contextual data, when creating versions. See
  # {file:README.md#tracking-contextual-data README} for more.
  DATA_KEYS = %i[meta whodunit event_uuid].freeze

  # Symbols for use with setting {Hoardable} configuration. See {file:README.md#configuration
  # README} for more.
  CONFIG_KEYS = %i[enabled version_updates save_trash].freeze

  VERSION_CLASS_SUFFIX = "Version"
  private_constant :VERSION_CLASS_SUFFIX

  VERSION_TABLE_SUFFIX = "_#{VERSION_CLASS_SUFFIX.tableize}"
  private_constant :VERSION_TABLE_SUFFIX

  DURING_QUERY = "_during @> ?::timestamp"
  private_constant :DURING_QUERY

  HOARDABLE_CALLBACKS_ENABLED =
    proc do |source_model|
      source_model.class.hoardable_config[:enabled] &&
        !source_model.class.name.end_with?(VERSION_CLASS_SUFFIX)
    end.freeze
  private_constant :HOARDABLE_CALLBACKS_ENABLED

  HOARDABLE_SAVE_TRASH =
    proc { |source_model| source_model.class.hoardable_config[:save_trash] }.freeze
  private_constant :HOARDABLE_SAVE_TRASH

  HOARDABLE_VERSION_UPDATES =
    proc { |source_model| source_model.class.hoardable_config[:version_updates] }.freeze
  private_constant :HOARDABLE_VERSION_UPDATES

  SUPPORTS_ENCRYPTED_ACTION_TEXT = ActiveRecord.version >= ::Gem::Version.new("7.0.4")
  private_constant :SUPPORTS_ENCRYPTED_ACTION_TEXT

  @context = {}
  @config = CONFIG_KEYS.to_h { |key| [key, true] }

  class << self
    CONFIG_KEYS.each do |key|
      define_method(key) do
        local_config = Thread.current[:hoardable_config] || @config
        local_config[key]
      end

      define_method("#{key}=") { |value| @config[key] = value }
    end

    DATA_KEYS.each do |key|
      define_method(key) do
        local_context = Thread.current[:hoardable_context] || @context
        local_context[key]
      end

      define_method("#{key}=") { |value| @context[key] = value }
    end

    # This is a general use method for setting {file:README.md#tracking-contextual-data Contextual
    # Data} or {file:README.md#configuration Configuration} around a block.
    #
    # @param hash [Hash] config and contextual data to set within a block
    def with(hash)
      thread = Thread.current
      thread[:hoardable_config] = @config.merge(hash.slice(*CONFIG_KEYS))
      thread[:hoardable_context] = @context.merge(hash.slice(*DATA_KEYS))
      yield
    ensure
      thread[:hoardable_config] = nil
      thread[:hoardable_context] = nil
    end

    # Allows performing a query for record states at a certain time. Returned {SourceModel}
    # instances within the block may be {SourceModel} or {VersionModel} records.
    #
    # @param datetime [DateTime, Time] the datetime or time to temporally query records at
    def at(datetime)
      thread = Thread.current
      thread[:hoardable_at] = datetime
      yield
    ensure
      thread[:hoardable_at] = nil
    end

    # Allows calling code to set the upper bound for the temporal range for recorded audits.
    #
    # @param datetime [DateTime] the datetime to temporally record versions at
    def travel_to(datetime)
      thread = Thread.current
      thread[:hoardable_travel_to] = datetime
      yield
    ensure
      thread[:hoardable_travel_to] = nil
    end

    # @!visibility private
    def logger
      @logger ||= ActiveSupport::TaggedLogging.new(Logger.new($stdout))
    end
  end

  # A +Rails+ engine for providing support for +ActionText+
  class Engine < ::Rails::Engine
    isolate_namespace Hoardable

    initializer "hoardable.action_text" do
      ActiveSupport.on_load(:action_text_rich_text) do
        require_relative "rich_text"
        require_relative "encrypted_rich_text" if SUPPORTS_ENCRYPTED_ACTION_TEXT
      end
    end

    initializer "hoardable.schema_statements" do
      ActiveSupport.on_load(:active_record_postgresqladapter) do
        # We need to control the table dumping order of tables, so revert these to just +super+
        Fx::SchemaDumper.module_eval("def tables(streams); super; end")

        ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(SchemaDumper)
        ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaStatements.prepend(SchemaStatements)
      end
    end
  end
end
