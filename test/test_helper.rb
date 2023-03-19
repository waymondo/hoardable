# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'bundler/setup'
require 'debug'
require 'rails'
require 'minitest/autorun'
require 'minitest/spec'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hoardable'
require 'fx'

def tmp_dir
  File.expand_path('../tmp', __dir__)
end

FileUtils.rm_f Dir.glob("#{tmp_dir}/**/*")

require 'active_model/railtie'
require 'active_record/railtie'
require 'action_text/engine'

class Dummy < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.active_storage.service_configurations = {}
  config.paths['config/database'] = ['test/config/database.yml']
  config.paths['db/migrate'] = ['tmp/db/migrate']
  config.active_record.encryption&.key_derivation_salt = SecureRandom.hex
  config.active_record.encryption&.primary_key = SecureRandom.hex
end

Rails.initialize!

SUPPORTS_ENCRYPTED_ACTION_TEXT = ActiveRecord.version >= Gem::Version.new('7.0.4')
SUPPORTS_VIRTUAL_COLUMNS = ActiveRecord.version >= Gem::Version.new('7.0.0')

require_relative 'support/models'
require_relative 'support/database'
