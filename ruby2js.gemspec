# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'ruby2js/version'

Gem::Specification.new do |s|
  s.name = "ruby2js".freeze
  s.version = Ruby2JS::VERSION::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sam Ruby".freeze]
  s.date = "2017-11-13"
  s.description = "    The base package maps Ruby syntax to JavaScript semantics.\n    Filters may be provided to add Ruby-specific or framework specific\n    behavior.\n".freeze
  s.email = "rubys@intertwingly.net".freeze
  s.files = ["README.md".freeze, "lib/ruby2js".freeze, "lib/ruby2js.rb".freeze, "lib/ruby2js/cgi.rb".freeze, "lib/ruby2js/converter".freeze, "lib/ruby2js/converter.rb".freeze, "lib/ruby2js/converter/arg.rb".freeze, "lib/ruby2js/converter/args.rb".freeze, "lib/ruby2js/converter/array.rb".freeze, "lib/ruby2js/converter/begin.rb".freeze, "lib/ruby2js/converter/block.rb".freeze, "lib/ruby2js/converter/blockpass.rb".freeze, "lib/ruby2js/converter/boolean.rb".freeze, "lib/ruby2js/converter/break.rb".freeze, "lib/ruby2js/converter/case.rb".freeze, "lib/ruby2js/converter/casgn.rb".freeze, "lib/ruby2js/converter/class.rb".freeze, "lib/ruby2js/converter/const.rb".freeze, "lib/ruby2js/converter/cvar.rb".freeze, "lib/ruby2js/converter/cvasgn.rb".freeze, "lib/ruby2js/converter/def.rb".freeze, "lib/ruby2js/converter/defined.rb".freeze, "lib/ruby2js/converter/defs.rb".freeze, "lib/ruby2js/converter/dstr.rb".freeze, "lib/ruby2js/converter/for.rb".freeze, "lib/ruby2js/converter/hash.rb".freeze, "lib/ruby2js/converter/if.rb".freeze, "lib/ruby2js/converter/in.rb".freeze, "lib/ruby2js/converter/ivar.rb".freeze, "lib/ruby2js/converter/ivasgn.rb".freeze, "lib/ruby2js/converter/kwbegin.rb".freeze, "lib/ruby2js/converter/literal.rb".freeze, "lib/ruby2js/converter/logical.rb".freeze, "lib/ruby2js/converter/masgn.rb".freeze, "lib/ruby2js/converter/module.rb".freeze, "lib/ruby2js/converter/next.rb".freeze, "lib/ruby2js/converter/nil.rb".freeze, "lib/ruby2js/converter/nthref.rb".freeze, "lib/ruby2js/converter/opasgn.rb".freeze, "lib/ruby2js/converter/prototype.rb".freeze, "lib/ruby2js/converter/regexp.rb".freeze, "lib/ruby2js/converter/return.rb".freeze, "lib/ruby2js/converter/self.rb".freeze, "lib/ruby2js/converter/send.rb".freeze, "lib/ruby2js/converter/super.rb".freeze, "lib/ruby2js/converter/sym.rb".freeze, "lib/ruby2js/converter/undef.rb".freeze, "lib/ruby2js/converter/until.rb".freeze, "lib/ruby2js/converter/untilpost.rb".freeze, "lib/ruby2js/converter/var.rb".freeze, "lib/ruby2js/converter/vasgn.rb".freeze, "lib/ruby2js/converter/while.rb".freeze, "lib/ruby2js/converter/whilepost.rb".freeze, "lib/ruby2js/converter/xstr.rb".freeze, "lib/ruby2js/execjs.rb".freeze, "lib/ruby2js/filter".freeze, "lib/ruby2js/filter/angular-resource.rb".freeze, "lib/ruby2js/filter/angular-route.rb".freeze, "lib/ruby2js/filter/angularrb.rb".freeze, "lib/ruby2js/filter/camelCase.rb".freeze, "lib/ruby2js/filter/functions.rb".freeze, "lib/ruby2js/filter/jquery.rb".freeze, "lib/ruby2js/filter/minitest-jasmine.rb".freeze, "lib/ruby2js/filter/react.rb".freeze, "lib/ruby2js/filter/require.rb".freeze, "lib/ruby2js/filter/return.rb".freeze, "lib/ruby2js/filter/rubyjs.rb".freeze, "lib/ruby2js/filter/strict.rb".freeze, "lib/ruby2js/filter/underscore.rb".freeze, "lib/ruby2js/filter/vue.rb".freeze, "lib/ruby2js/haml.rb".freeze, "lib/ruby2js/rails.rb".freeze, "lib/ruby2js/serializer.rb".freeze, "lib/ruby2js/sinatra.rb".freeze, "lib/ruby2js/version.rb".freeze, "ruby2js.gemspec".freeze]
  s.homepage = "http://github.com/rubys/ruby2js".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3".freeze)
  s.rubygems_version = "2.6.14".freeze
  s.summary = "Minimal yet extensible Ruby to JavaScript conversion.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<parser>.freeze, [">= 0"])
    else
      s.add_dependency(%q<parser>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<parser>.freeze, [">= 0"])
  end
end
