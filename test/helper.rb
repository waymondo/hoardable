# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "bundler/setup"
require "debug"
require "rails"
require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hoardable"

def tmp_dir
  File.expand_path("../tmp", __dir__)
end

FileUtils.rm_f Dir.glob("#{tmp_dir}/**/*")

require_relative "config/application"
Rails.initialize!

SUPPORTS_ENCRYPTED_ACTION_TEXT = ActiveRecord.version >= Gem::Version.new("7.0.4")

require_relative "support/models"
require_relative "support/database"
