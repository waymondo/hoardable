# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'bundler/setup'
require 'debug'
require 'active_support/concern'
require 'active_record'
require 'minitest/autorun'
require 'minitest/spec'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hoardable'

def tmp_dir
  File.expand_path('../tmp', __dir__)
end

FileUtils.rm_f Dir.glob("#{tmp_dir}/**/*")

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_text/engine'

class Dummy < Rails::Application
  config.load_defaults(::Rails.gem_version.segments.take(2).join('.'))
  config.eager_load = false
  config.active_storage.service_configurations = {
    service: 'Disk',
    root: Rails.root.join('tmp/storage')
  }
  config.paths['config/database'] = ['test/config/database.yml']
end

Rails.initialize!

require_relative 'support/models'
require_relative 'support/database'
