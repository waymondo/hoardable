# frozen_string_literal: true

source "https://rubygems.org"

gem "debug"
if (rails_version = ENV["RAILS_VERSION"])
  gem "rails", "~> #{rails_version}"
else
  gem "rails", "7.0.8.4"
end
gem "syntax_tree"
gem "typeprof"

gemspec
