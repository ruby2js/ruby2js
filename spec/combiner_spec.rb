require 'minitest/autorun'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/require'

describe Ruby2JS::Filter::Combiner do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022, filters: [Ruby2JS::Filter::Combiner]).to_s)
  end

  def to_js_with_functions(string)
    _(Ruby2JS.convert(string, eslevel: 2022, filters: [Ruby2JS::Filter::Combiner, Ruby2JS::Filter::Functions]).to_s)
  end

  describe 'module merging' do
    it "should merge reopened modules" do
      to_js(<<~RUBY).must_equal 'const Foo = {get bar() {}, get baz() {}}'
        module Foo
          def bar; end
        end
        module Foo
          def baz; end
        end
      RUBY
    end

    it "should handle single module" do
      to_js('module Foo; def bar; end; end').must_equal 'const Foo = {get bar() {}}'
    end
  end

  describe 'class merging' do
    it "should merge reopened classes" do
      result = to_js(<<~RUBY)
        class Foo
          def bar; end
        end
        class Foo
          def baz; end
        end
      RUBY
      result.must_include 'class Foo'
      result.must_include 'bar()'
      result.must_include 'baz()'
    end

    it "should preserve superclass from first definition" do
      result = to_js(<<~RUBY)
        class Foo < Bar
          def baz; end
        end
        class Foo
          def qux; end
        end
      RUBY
      result.must_include 'class Foo extends Bar'
      result.must_include 'baz()'
      result.must_include 'qux()'
    end

    it "should use superclass from reopening if original has none" do
      result = to_js(<<~RUBY)
        class Foo
          def baz; end
        end
        class Foo < Bar
          def qux; end
        end
      RUBY
      result.must_include 'class Foo extends Bar'
      result.must_include 'baz()'
      result.must_include 'qux()'
    end
  end

  describe 'nested definitions' do
    it "should merge nested modules" do
      result = to_js(<<~RUBY)
        module Outer
          module Inner
            def foo; end
          end
        end
        module Outer
          module Inner
            def bar; end
          end
        end
      RUBY
      result.must_include 'Outer'
      result.must_include 'Inner'
      result.must_include 'foo()'
      result.must_include 'bar()'
    end

    it "should merge nested classes" do
      result = to_js(<<~RUBY)
        module Outer
          class Inner
            def foo; end
          end
        end
        module Outer
          class Inner
            def bar; end
          end
        end
      RUBY
      result.must_include 'Outer'
      result.must_include 'Inner'
      result.must_include 'foo()'
      result.must_include 'bar()'
    end
  end

  describe 'multiple reopenings' do
    it "should handle three or more reopenings" do
      result = Ruby2JS.convert(<<~RUBY, eslevel: 2022, filters: [Ruby2JS::Filter::Combiner]).to_s
        module Foo
          def a; end
        end
        module Foo
          def b; end
        end
        module Foo
          def c; end
        end
      RUBY
      _(result).must_include 'const Foo'
      _(result).must_include 'a()'
      _(result).must_include 'b()'
      _(result).must_include 'c()'
      # Should only have one Foo definition
      _(result.scan('const Foo').length).must_equal 1
    end
  end

  describe 'mixed content' do
    it "should preserve non-module/class statements" do
      result = to_js_with_functions(<<~RUBY)
        module Foo
          def bar; end
        end
        module Foo
          def baz; end
        end
        puts "done"
      RUBY
      result.must_include 'Foo'
      result.must_include 'bar()'
      result.must_include 'baz()'
      result.must_include 'console.log("done")'
    end
  end

  describe 'expression grouping' do
    it "should preserve single-child begin nodes used for grouping" do
      # The !! pattern uses begin nodes for grouping: !!(a && b)
      # Combiner should not unwrap these, otherwise De Morgan's law gets applied
      to_js('x = !!(a && b)').must_equal 'let x = !!(a && b)'
    end

    it "should preserve negation of grouped and expressions" do
      to_js('x = !(a && b)').must_equal 'let x = !(a && b)'
    end

    it "should preserve negation of grouped or expressions" do
      # Note: || becomes ?? (nullish coalescing) in ES2022 for non-boolean contexts
      to_js('x = !(a || b)').must_equal 'let x = !(a ?? b)'
    end
  end

  describe 'nested begin nodes' do
    it "should flatten nested begin nodes from require filter" do
      # When the require filter inlines files, it wraps content in :begin nodes.
      # The combiner needs to flatten these to properly merge modules.
      # This test uses the require filter with combiner to verify the integration.
      code = <<~RUBY
        module Foo
          def bar; end
        end
        require_relative 'combiner/reopen_foo'
      RUBY
      result = Ruby2JS.convert(code,
        eslevel: 2022,
        file: __FILE__,
        filters: [Ruby2JS::Filter::Require, Ruby2JS::Filter::Combiner]).to_s
      _(result).must_include 'const Foo'
      _(result).must_include 'bar()'
      _(result).must_include 'baz()'
      # Should only have one Foo definition (modules were merged)
      _(result.scan('const Foo').length).must_equal 1
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should NOT include Combiner (it's for self-hosting only)" do
      _(Ruby2JS::Filter::DEFAULTS).wont_include Ruby2JS::Filter::Combiner
    end
  end
end
