# coding: utf-8
$:.push File.expand_path("../lib", __FILE__)
require "ruby2js/version"

Gem::Specification.new do |s|

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
    Filters may be provided to add Ruby-specific or framework specific
    behavior.
  EOD

  # Add any extra files to include in the gem
  s.files             = %w(ruby2js.gemspec README.md) + Dir.glob("{lib}/**/*")
  s.require_paths     = ["lib"]

  # If you want to depend on other gems, add them here, along with any
  # relevant versions
  s.add_dependency("parser")

  # Require Ruby 1.9.3 or greater
  s.required_ruby_version = '>= 1.9.3'
end
