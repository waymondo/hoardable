# frozen_string_literal: true

source "https://rubygems.org"

ruby_version = ENV.fetch("RUBY_VERSION") do
  File.read(".tool-versions").match(/ruby\s(.*)$/)[1]
end
ruby "#{ruby_version}"

gem "debug"
if (rails_version = ENV["RAILS_VERSION"])
  gem "rails", "~> #{rails_version}.0"
else
  gem "rails"
end
gem "syntax_tree"
gem "typeprof"

gemspec
