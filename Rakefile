require "bundler/gem_tasks"
require "rake/testtask"
require "bundler"

Bundler.setup

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList["spec/*_spec.rb"]
  t.verbose = true
end

task :default => :test

namespace :demo do
  task :build do
    Dir.chdir('demo') { sh 'rake' }
  end
end

# Run `rake release` to release a new version of the gem.
