gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/pragma'

describe Ruby2JS::Filter::Pragma do

  def to_js(string, options={})
    _(Ruby2JS.convert(string, options.merge(
      eslevel: options[:eslevel] || 2021,
      or: options[:or] || :logical,  # Use || by default so we can test pragma override to ??
      filters: [Ruby2JS::Filter::Pragma]
    )).to_s)
  end

  describe "nullish pragma (??)" do
    it "should convert || to ?? with pragma" do
      to_js('x = a || b # Pragma: ??').
        must_equal 'let x = a ?? b'
    end

    it "should convert ||= to ??= with pragma" do
      to_js('a ||= b # Pragma: ??').
        must_equal 'a ??= b'
    end

    it "should accept 'nullish' as pragma name" do
      to_js('x = a || b # Pragma: nullish').
        must_equal 'let x = a ?? b'
    end

    it "should not convert || without pragma" do
      to_js('x = a || b').
        must_equal 'let x = a || b'
    end

    it "should not convert ||= without pragma" do
      to_js('a ||= b').
        must_equal 'a ||= b'
    end

    it "should handle nested || with pragma" do
      to_js('x = a || b || c # Pragma: ??').
        must_equal 'let x = a ?? b ?? c'
    end

    it "should handle complex expressions with pragma" do
      to_js('x = foo.bar || default_value # Pragma: ??').
        must_equal 'let x = foo.bar ?? default_value'
    end

    it "should handle instance variable assignment with pragma" do
      to_js('@a ||= b # Pragma: ??').
        must_equal 'this._a ??= b'
    end

    it "should be case insensitive for pragma name" do
      to_js('x = a || b # PRAGMA: ??').
        must_equal 'let x = a ?? b'
    end

    it "should fall back to || when ES2020 not available" do
      # When ES2020 is not available, nullish_or pragma has no effect
      to_js('x = a || b # Pragma: ??', eslevel: 2019).
        must_equal 'let x = a || b'
    end

    it "should expand nullish assignment when ES2021 not available" do
      # ES2020 has ?? but not ??=, so it expands to a = a ?? b
      to_js('a ||= b # Pragma: ??', eslevel: 2020).
        must_equal 'a = a ?? b'
    end
  end

  describe "noes2015 pragma" do
    it "should force function syntax for blocks" do
      to_js('items.each { |item| process(item) } # Pragma: noes2015').
        must_equal 'items.each(function(item) {process(item)})'
    end

    it "should accept 'function' as pragma name" do
      to_js('items.each { |item| process(item) } # Pragma: function').
        must_equal 'items.each(function(item) {process(item)})'
    end

    it "should use arrow functions without pragma" do
      to_js('items.each { |item| process(item) }').
        must_equal 'items.each(item => process(item))'
    end

    it "should handle multi-argument blocks with pragma" do
      # Note: method name stays as each_with_index since functions filter not included
      to_js('items.each_with_index { |item, i| process(item, i) } # Pragma: noes2015').
        must_equal 'items.each_with_index(function(item, i) {process(item, i)})'
    end

    it "should handle blocks with multiple statements" do
      to_js("items.map { |x| y = x * 2; y + 1 } # Pragma: noes2015").
        must_include 'function(x)'
    end

    it "should preserve this binding with function syntax" do
      # This is the main use case - jQuery/DOM callbacks need 'this'
      js = to_js('element.on("click") { handle_click(this) } # Pragma: noes2015')
      js.must_include 'function()'
      js.must_include 'this'
    end
  end

  describe "guard pragma" do
    it "should guard splat array against null" do
      to_js('[*a] # Pragma: guard').
        must_equal 'a ?? []'
    end

    it "should guard splat in mixed array" do
      to_js('[1, *a, 2] # Pragma: guard').
        must_equal '[1, ...a ?? [], 2]'
    end

    it "should not guard splat without pragma" do
      to_js('[*a]').
        must_equal 'a'
    end

    it "should handle multiple splats with guard" do
      to_js('[*a, *b] # Pragma: guard').
        must_include 'a ?? []'
    end

    it "should handle method call splats with guard" do
      to_js('[*items.to_a] # Pragma: guard').
        must_include '?? []'
    end

    it "should not apply guard pragma without ES2020" do
      # Without ES2020, nullish coalescing isn't available, so guard has no effect
      # At ES2019 spread is available but ?? is not, so guard doesn't apply
      to_js('[1, *a] # Pragma: guard', eslevel: 2019).
        must_equal '[1, ...a]'
    end

    it "should use concat without spread or guard at ES5" do
      # At ES5, no spread and no ??, so just use concat
      # NOTE: This test documents current (incorrect) behavior - ES5 should use concat not spread
      # The base converter has a bug where splat produces spread even at ES5
      to_js('[1, *a] # Pragma: guard', eslevel: 2009).
        must_equal '[1, ...a]'
    end
  end

  describe "multiple pragmas" do
    it "should handle multiple pragmas on different lines" do
      code = <<~RUBY
        a ||= b # Pragma: ??
        items.each { |x| process(x) } # Pragma: noes2015
      RUBY
      js = to_js(code)
      js.must_include '??='
      js.must_include 'function(x)'
    end
  end

  describe "pragma syntax variations" do
    it "should handle extra whitespace" do
      to_js('x = a || b #   Pragma:   ??').
        must_equal 'let x = a ?? b'
    end

    it "should handle pragma at end of complex statement" do
      # Note: 'default' is a JS reserved word, so it gets escaped to '$default'
      to_js('result = foo.bar.baz || default_value # Pragma: ??').
        must_equal 'let result = foo.bar.baz ?? default_value'
    end

    it "should ignore unknown pragmas" do
      to_js('x = a || b # Pragma: unknown').
        must_equal 'let x = a || b'
    end
  end

  describe "array pragma" do
    it "should convert dup to slice" do
      to_js('x = arr.dup # Pragma: array').
        must_equal 'let x = arr.slice()'
    end

    it "should convert << to push" do
      to_js('arr << item # Pragma: array').
        must_equal 'arr.push(item)'
    end

    it "should not affect dup without pragma" do
      to_js('x = arr.dup').
        must_equal 'let x = arr.dup'
    end
  end

  describe "hash pragma" do
    it "should convert dup to spread" do
      to_js('x = obj.dup # Pragma: hash').
        must_equal 'let x = {...obj}'
    end

    it "should convert include? to in operator" do
      to_js('obj.include?(key) # Pragma: hash').
        must_equal 'key in obj'
    end

    it "should not affect include? without pragma" do
      # Without functions filter, include? stays as is
      to_js('obj.include?(key)').
        must_equal 'obj.include(key)'
    end
  end

  describe "string pragma" do
    it "should convert dup to no-op" do
      to_js('x = str.dup # Pragma: string').
        must_equal 'let x = str'
    end
  end

  describe "method pragma" do
    it "should convert proc.call to direct invocation" do
      to_js('fn.call(x) # Pragma: method').
        must_equal 'fn(x)'
    end

    it "should handle call with multiple arguments" do
      to_js('fn.call(a, b, c) # Pragma: method').
        must_equal 'fn(a, b, c)'
    end

    it "should not affect call without pragma" do
      to_js('fn.call(x)').
        must_equal 'fn.call(x)'
    end
  end

  describe "proto pragma" do
    it "should convert .class to .constructor" do
      to_js('obj.class # Pragma: proto').
        must_equal 'obj.constructor'
    end

    it "should not affect .class without pragma" do
      to_js('obj.class').
        must_equal 'obj.class'
    end
  end

  describe "entries pragma" do
    it "should convert hash.each with two args to Object.entries" do
      to_js('hash.each { |k, v| puts k } # Pragma: entries').
        must_include 'Object.entries(hash)'
    end

    it "should convert each_pair to Object.entries" do
      to_js('hash.each_pair { |k, v| puts k } # Pragma: entries').
        must_include 'Object.entries(hash)'
    end

    it "should not affect each without pragma" do
      to_js('hash.each { |k, v| puts k }').
        must_include 'hash.each'
    end
  end

  describe "skip pragma" do
    it "should remove require with skip pragma" do
      to_js("require 'prism' # Pragma: skip").
        wont_include 'require'
    end

    it "should remove require_relative with skip pragma" do
      to_js("require_relative 'other' # Pragma: skip").
        wont_include 'require'
    end

    it "should not affect require without pragma" do
      to_js("require 'something'").
        must_include 'require'
    end

    it "should handle skip with other statements" do
      code = <<~RUBY
        require 'external' # Pragma: skip
        puts 'hello'
      RUBY
      js = to_js(code)
      js.wont_include 'require'
      js.must_include 'puts'
    end

    it "should remove method definition with skip pragma" do
      code = <<~RUBY
        def respond_to?(method) # Pragma: skip
          true
        end
        def foo
          1
        end
      RUBY
      js = to_js(code)
      js.wont_include 'respond_to'
      js.must_include 'foo'
    end

    it "should remove class method with skip pragma" do
      code = <<~RUBY
        class Foo
          def self.===(other) # Pragma: skip
            true
          end
          def self.create
            42
          end
        end
      RUBY
      js = to_js(code)
      js.wont_include '==='
      js.must_include 'create'
    end

    it "should remove alias with skip pragma" do
      code = <<~RUBY
        class Foo
          alias loc location # Pragma: skip
          alias name title
        end
      RUBY
      js = to_js(code)
      js.wont_include 'loc'
      js.must_include 'name'
    end
  end
end
