require 'rubygems/package_task'
require File.expand_path(File.dirname(__FILE__) + "/lib/ruby2js/version")

require 'rake/testtask'
task :default => :test
Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList["spec/*_spec.rb"]
  t.verbose = true
end

# This builds the actual gem. For details of what all these options
# mean, and other ones you can add, check the documentation here:
#
#   http://rubygems.org/read/chapter/20
#
spec = Gem::Specification.new do |s|

  # Change these as appropriate
  s.name           = "ruby2js"
  s.license        = 'MIT'
  s.version        = Ruby2JS::VERSION::STRING
  s.summary        = "Minimal yet extensible Ruby to JavaScript conversion."
  s.author         = "Sam Ruby"
  s.email          = "rubys@intertwingly.net"
  s.homepage       = "http://github.com/rubys/ruby2js"
  s.description    = <<-EOD
    The base package maps Ruby syntax to JavaScript semantics.
    Filters may be provided to add Ruby-specific or Framework specific
    behavior.
  EOD

  # Add any extra files to include in the gem
  s.files             = %w(ruby2js.gemspec README.md) + Dir.glob("{lib}/**/*")
  s.require_paths     = ["lib"]

  # If you want to depend on other gems, add them here, along with any
  # relevant versions
  s.add_dependency("parser")

  # If your tests use any gems, include them here
  # s.add_development_dependency("mocha") # for example
end

# This task actually builds the gem. We also regenerate a static
# .gemspec file, which is useful if something (i.e. GitHub) will
# be automatically building a gem for this project. If you're not
# using GitHub, edit as appropriate.
#
# To publish your gem online, install the 'gemcutter' gem; Read more 
# about that here: http://gemcutter.org/pages/gem_docs
Gem::PackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

file "#{spec.name}.gemspec" => [:gemspec]

desc "Build the gemspec file #{spec.name}.gemspec"
task :gemspec do
  file = File.dirname(__FILE__) + "/#{spec.name}.gemspec"
  File.open(file, "w") {|f| f << spec.to_ruby }
end

# If you don't want to generate the .gemspec file, just remove this line. Reasons
# why you might want to generate a gemspec:
#  - using bundler with a git source
#  - building the gem without rake (i.e. gem build blah.gemspec)
#  - maybe others?
task :package => :gemspec

require 'rake/clean'
CLEAN.include('pkg')
