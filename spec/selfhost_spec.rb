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
      to_js('s(:send, target, :method)').must_equal 's("send", target, "method")'
    end

    it 'should handle nested s() calls' do
      to_js('s(:if, cond, s(:true), s(:false))').must_equal 's("if", cond, s("true"), s("false"))'
    end

    it 'should preserve non-symbol arguments' do
      to_js('s(:send, nil, :foo, *args)', eslevel: 2015).must_equal 's("send", null, "foo", ...args)'
    end
  end

  describe 'sl() calls' do
    it 'should convert symbol to string in sl() second argument' do
      to_js('sl(node, :int, value)').must_equal 'sl(node, "int", value)'
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
    it 'should convert single type handle block' do
      code = 'handle :str do |value|; put value; end'
      to_js(code).must_equal 'this.handle("str", function(value) {put(value)})'
    end

    it 'should convert multi-type handle block' do
      code = 'handle :int, :float do |value|; put value; end'
      result = to_js(code)
      result.must_include 'this.handle("int"'
      result.must_include 'this.handle("float"'
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
end
