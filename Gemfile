# frozen_string_literal: true

source "https://rubygems.org"

gem "bigdecimal"
gem "debug"
gem "drb"
gem "logger"
gem "mutex_m"
gem "ostruct"
if (rails_version = ENV["RAILS_VERSION"])
  gem "rails", "~> #{rails_version}"
else
  gem "rails"
end
gem "syntax_tree"
gem "typeprof"

gemspec
