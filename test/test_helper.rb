# frozen_string_literal: true

require 'bundler/setup'
require 'debug'
require 'active_support/concern'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hoardable'

require 'minitest/autorun'
require 'minitest/spec'

def tmp_dir
  File.expand_path('../tmp', __dir__)
end

FileUtils.rm_f Dir.glob("#{tmp_dir}/**/*")

require_relative 'support/models'
require_relative 'support/database'
