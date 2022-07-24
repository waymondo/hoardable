# frozen_string_literal: true

require 'debug'
require 'active_support/concern'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'archiversion'

require 'minitest/autorun'
Dir[File.join(__dir__, 'support/**/*.rb')].sort.each { |file| require file }
