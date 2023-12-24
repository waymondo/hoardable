# frozen_string_literal: true

source 'https://rubygems.org'

puts "#############"
pp ENV["RAILS_VERSION"]
puts "#############"

gem 'debug'
if (rails_version = ENV['RAILS_VERSION'])
  gem 'rails', "~> #{rails_version}.0"
else
  gem 'rails'
end

gemspec
