# frozen_string_literal: true

require_relative 'lib/hoardable/hoardable'

Gem::Specification.new do |spec|
  spec.name = 'Hoardable'
  spec.version = Hoardable::VERSION
  spec.authors = ['justin talbott']
  spec.email = ['justin@waymondo.com']

  spec.summary = 'An ActiveRecord extension for the archiving versions of records'
  spec.description = 'Archive versions of your Rails models with the power of temporal tables and table inheritance'
  spec.homepage = 'https://github.com/waymondo/hoardable'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 7.0', '< 8'
  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'pg', '>= 1.0', '< 2'
  spec.add_dependency 'railties', '>= 7.0', '< 8'
  spec.metadata['rubygems_mfa_required'] = 'true'
end