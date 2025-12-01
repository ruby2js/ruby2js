gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/filter/selfhost'

describe Ruby2JS::Filter::Selfhost do
  def to_js(string, opts = {})
    _(Ruby2JS.convert(string, opts.merge(filters: [:selfhost])).to_s)
  end

  describe 's() calls' do
    it 'should convert symbol to string in s() first argument' do
      to_js('s(:send, target, :method)').must_equal 'this.s("send", target, "method")'
    end

    it 'should handle nested s() calls' do
      to_js('s(:if, cond, s(:true), s(:false))').must_equal 'this.s("if", cond, this.s("true"), this.s("false"))'
    end

    it 'should preserve non-symbol arguments' do
      to_js('s(:send, nil, :foo, *args)', eslevel: 2015).must_equal 'this.s("send", null, "foo", ...args)'
    end
  end

  describe 'sl() calls' do
    it 'should convert symbol to string in sl() second argument' do
      to_js('sl(node, :int, value)').must_equal 'this.sl(node, "int", value)'
    end
  end

  describe 'type comparisons' do
    it 'should convert node.type == :sym to node.type === "string"' do
      to_js('node.type == :str').must_equal 'node.type === "str"'
    end

    it 'should handle various type symbols' do
      to_js('node.type == :send').must_equal 'node.type === "send"'
      to_js('node.type == :lvar').must_equal 'node.type === "lvar"'
    end
  end

  describe 'array include? with symbols' do
    it 'should convert %i().include? to array.includes()' do
      to_js('%i(send csend).include?(node.type)').must_equal '["send", "csend"].includes(node.type)'
    end

    it 'should handle single symbol arrays' do
      to_js('%i(str).include?(type)').must_equal '["str"].includes(type)'
    end
  end

  describe 'handle blocks' do
    it 'should convert single type handle block to method' do
      code = 'handle :str do |value|; put value; end'
      to_js(code).must_equal 'function on_str(value) {this.put(value)}'
    end

    it 'should convert multi-type handle block to multiple methods' do
      code = 'handle :int, :float do |value|; put value; end'
      result = to_js(code)
      result.must_include 'on_int(value)'
      result.must_include 'on_float(value)'
    end
  end

  describe 'case/when on node.type' do
    it 'should convert symbol conditions to strings' do
      code = <<~RUBY
        case node.type
        when :str
          handle_str
        when :int
          handle_int
        end
      RUBY
      result = to_js(code)
      result.must_include 'case "str"'
      result.must_include 'case "int"'
    end

    it 'should handle multiple symbols in when clause' do
      code = <<~RUBY
        case node.type
        when :int, :float
          handle_number
        end
      RUBY
      result = to_js(code)
      result.must_include 'case "int"'
      result.must_include 'case "float"'
    end
  end

  describe 'Prism::Visitor subclass' do
    it 'should remove Prism::Visitor inheritance' do
      code = <<~RUBY
        class MyWalker < Prism::Visitor
          def visit_integer_node(node)
            node.value
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015)
      result.wont_include '< Prism'
      result.wont_include 'extends'
    end

    it 'should generate self-dispatch visit method' do
      code = <<~RUBY
        class MyWalker < Prism::Visitor
          def visit_integer_node(node)
            node.value
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015)
      result.must_include 'visit(node)'
      result.must_include 'node.constructor.name'
      result.must_include 'method.call(this, node)'
    end

    it 'should convert visit_*_node methods to camelCase' do
      code = <<~RUBY
        class MyWalker < Prism::Visitor
          def visit_integer_node(node)
            s(:int, node.value)
          end

          def visit_string_node(node)
            s(:str, node.unescaped)
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015)
      result.must_include 'visitIntegerNode'
      result.must_include 'visitStringNode'
      result.wont_include 'visit_integer_node'
      result.wont_include 'visit_string_node'
    end

    it 'should not affect non-Prism::Visitor classes' do
      code = <<~RUBY
        class MyClass < BaseClass
          def visit_something_node(node)
            node
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015)
      result.must_include 'extends BaseClass'
      # Method name still converted (could be intentional visitor pattern)
      result.must_include 'visitSomethingNode'
    end

    it 'should remove super() calls inside Prism::Visitor' do
      code = <<~RUBY
        class MyWalker < Prism::Visitor
          def initialize(source)
            @source = source
            super()
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015)
      result.wont_include 'super'
      result.must_include 'this._source = source'
    end

    it 'should skip user-defined visit method' do
      code = <<~RUBY
        class MyWalker < Prism::Visitor
          def visit(node)
            return nil if node.nil?
            super
          end

          def visit_integer_node(node)
            node
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015).to_s
      # Should have exactly one visit method (the generated one)
      _(result.scan(/visit\(node\)/).length).must_equal 1
      _(result).must_include 'visitIntegerNode'
    end
  end

  describe 'multi-type handle blocks in class' do
    it 'should flatten methods from multi-type handle block into class body' do
      code = <<~RUBY
        class Converter
          handle :int, :float do |value|
            put value
          end
        end
      RUBY
      result = to_js(code, eslevel: 2015).to_s
      # Both methods should be direct class members, not nested in a block
      _(result).must_include 'on_int(value)'
      _(result).must_include 'on_float(value)'
      # Methods should be at class level, not nested
      _(result.scan(/on_int\(value\)/).length).must_equal 1
      _(result.scan(/on_float\(value\)/).length).must_equal 1
    end
  end
end
