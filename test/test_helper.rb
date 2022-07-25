# frozen_string_literal: true

require 'debug'
require 'active_support/concern'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hoardable'

require 'minitest/autorun'
require 'minitest/spec'
Dir[File.join(__dir__, 'support/**/*.rb')].sort.each { |file| require file }

FileUtils.rm_f Dir.glob('../tmp/*')
