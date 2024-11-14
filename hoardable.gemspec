# frozen_string_literal: true

require_relative "lib/hoardable/version"

Gem::Specification.new do |spec|
  spec.name = "hoardable"
  spec.version = Hoardable::VERSION
  spec.authors = ["justin talbott"]
  spec.email = ["justin@waymondo.com"]

  spec.summary = "An ActiveRecord extension for versioning and soft-deletion of records in Postgres"
  spec.description = "Rails model versioning with the power of uni-temporal inherited tables"
  spec.homepage = "https://github.com/waymondo/hoardable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files =
    Dir.chdir(File.expand_path(__dir__)) do
      `git ls-files -z`.split("\x0")
        .reject do |f|
          (f == __FILE__) ||
            f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
        end
    end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7"
  spec.add_dependency "activesupport", ">= 7"
  spec.add_dependency "railties", ">= 7"

  spec.add_dependency "fx", ">= 0.9", "< 1"
  spec.add_dependency "pg", ">= 1", "< 2"
end
