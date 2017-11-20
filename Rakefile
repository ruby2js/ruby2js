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

# This task actually builds the gem. We also regenerate a static
# .gemspec file, which is useful if something (i.e. GitHub) will
# be automatically building a gem for this project. If you're not
# using GitHub, edit as appropriate.
#
# To publish your gem online, install the 'gemcutter' gem; Read more
# about that here: http://gemcutter.org/pages/gem_docs
spec = eval File.read("ruby2js.gemspec")

Gem::PackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

# If you don't want to generate the .gemspec file, just remove this line. Reasons
# why you might want to generate a gemspec:
#  - using bundler with a git source
#  - building the gem without rake (i.e. gem build blah.gemspec)
#  - maybe others?
task :package => :gem

require 'rake/clean'
CLOBBER.include FileList.new('pkg')
Rake::Task[:clobber_package].clear
CLOBBER.existing!
