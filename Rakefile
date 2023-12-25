# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "syntax_tree/rake_tasks"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

SOURCE_FILES = %w[test/**/*.rb lib/**/*.rb Rakefile Gemfile bin/console hoardable.gemspec]

SyntaxTree::Rake::CheckTask.new(:check) do |t|
  t.source_files = SOURCE_FILES
  t.print_width = 100
end

SyntaxTree::Rake::WriteTask.new(:write) do |t|
  t.source_files = SOURCE_FILES
  t.print_width = 100
end

task :typeprof do
  `typeprof lib/hoardable.rb`
end

task default: %i[check test]
task pre_commit: %i[write typeprof]
