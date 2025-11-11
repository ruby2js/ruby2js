# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'ruby2js/version'

Gem::Specification.new do |s|
  s.name = "ruby2js".freeze
  s.version = Ruby2JS::VERSION::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sam Ruby".freeze, "Jared White".freeze]
  s.description = "    The base package maps Ruby syntax to JavaScript semantics.\n    Filters may be provided to add Ruby-specific or framework specific\n    behavior.\n".freeze
  s.email = "rubys@intertwingly.net".freeze
  s.files = %w(ruby2js.gemspec README.md bin/ruby2js demo/ruby2js.rb) + Dir.glob("{lib}/**/*")
  s.homepage = "http://github.com/rubys/ruby2js".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7".freeze)
  s.summary = "Minimal yet extensible Ruby to JavaScript conversion.".freeze

  s.executables << 'ruby2js'

  s.add_dependency('parser')
  s.add_dependency('regexp_parser', '~> 2.9')
end
