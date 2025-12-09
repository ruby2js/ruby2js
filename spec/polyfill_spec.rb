gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/polyfill'

describe Ruby2JS::Filter::Polyfill do
  def to_js(string, options = {})
    Ruby2JS.convert(string, options.merge(filters: [Ruby2JS::Filter::Polyfill])).to_s
  end

  def to_js_with_functions(string, options = {})
    require 'ruby2js/filter/functions'
    Ruby2JS.convert(string, options.merge(filters: [Ruby2JS::Filter::Polyfill, Ruby2JS::Filter::Functions])).to_s
  end

  describe 'Array#first' do
    it 'should add polyfill and use property access' do
      js = to_js('arr.first')
      _(js).must_include 'Object.defineProperty(Array.prototype, "first"'
      _(js).must_include 'arr.first'
      _(js).wont_include 'arr.first()'
      _(js).wont_include 'arr[0]'
    end

    it 'should not be transformed by functions filter' do
      js = to_js_with_functions('arr.first')
      _(js).must_include 'Object.defineProperty(Array.prototype, "first"'
      _(js).must_include 'arr.first'
      _(js).wont_include 'arr[0]'
    end

    it 'should only add polyfill once for multiple uses' do
      js = to_js('arr.first; other.first')
      # Count occurrences of the polyfill
      count = js.scan('Object.defineProperty(Array.prototype, "first"').length
      _(count).must_equal 1
    end
  end

  describe 'Array#last' do
    it 'should add polyfill and use property access' do
      js = to_js('arr.last')
      _(js).must_include 'Object.defineProperty(Array.prototype, "last"'
      _(js).must_include 'arr.last'
      _(js).wont_include 'arr.last()'
    end
  end

  describe 'Array#compact' do
    it 'should add polyfill and use property access' do
      js = to_js('arr.compact')
      _(js).must_include 'Object.defineProperty(Array.prototype, "compact"'
      _(js).must_include 'arr.compact'
      _(js).wont_include 'arr.compact()'
    end
  end

  describe 'Array#rindex' do
    it 'should add polyfill for rindex with block' do
      js = to_js('arr.rindex { |x| x > 0 }')
      _(js).must_include 'Array.prototype.rindex'
      _(js).must_include 'arr.rindex('
    end
  end

  describe 'Array#insert' do
    it 'should add polyfill' do
      js = to_js('arr.insert(0, "x")')
      _(js).must_include 'Array.prototype.insert'
      _(js).must_include 'arr.insert(0, "x")'
    end
  end

  describe 'Array#delete_at' do
    it 'should add polyfill' do
      js = to_js('arr.delete_at(0)')
      _(js).must_include 'Array.prototype.delete_at'
      _(js).must_include 'arr.delete_at(0)'
    end
  end

  describe 'String#chomp' do
    it 'should add polyfill for no-arg chomp' do
      js = to_js('str.chomp')
      _(js).must_include 'String.prototype.chomp'
      _(js).must_include 'str.chomp()'
    end

    it 'should add polyfill for chomp with suffix' do
      js = to_js('str.chomp("\\n")')
      _(js).must_include 'String.prototype.chomp'
      _(js).must_include 'str.chomp("\\n")'
    end
  end

  describe 'multiple polyfills' do
    it 'should add multiple polyfills when needed' do
      js = to_js('arr.first; arr.last; str.chomp')
      _(js).must_include 'Array.prototype, "first"'
      _(js).must_include 'Array.prototype, "last"'
      _(js).must_include 'String.prototype.chomp'
    end
  end

  describe 'no polyfill when not needed' do
    it 'should not add polyfills for unrelated code' do
      js = to_js('x = 1 + 2')
      _(js).wont_include 'Array.prototype'
      _(js).wont_include 'String.prototype'
    end
  end
end
