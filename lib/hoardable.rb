# frozen_string_literal: true

require_relative 'hoardable/version'
require_relative 'hoardable/errors'
require_relative 'hoardable/version_model'
require_relative 'hoardable/model'
require_relative 'generators/hoardable/migration_generator'

# An ActiveRecord extension for keeping versions of records in temporal inherited tables
module Hoardable
  @config = {
    enabled: true,
    note: nil,
    meta: nil,
    whodunit: nil
  }

  def self.[](key)
    @config[key]
  end

  def self.[]=(key, val)
    @config[key] = val
  end

  def self.with(config)
    current_config = @config
    @config = current_config.merge(config)
    yield
  ensure
    @config = current_config
  end
end
