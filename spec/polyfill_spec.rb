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

  describe 'Array#uniq' do
    it 'should add polyfill and use property access' do
      js = to_js('arr.uniq')
      _(js).must_include 'Object.defineProperty(Array.prototype, "uniq"'
      _(js).must_include 'arr.uniq'
      _(js).wont_include 'arr.uniq()'
    end

    it 'should use Set spread in polyfill' do
      js = to_js('arr.uniq')
      _(js).must_include '[...new Set(this)]'
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

    it 'should use String(this) to return unchanged string' do
      js = to_js('str.chomp')
      _(js).must_include 'return String(this)'
      _(js).wont_include 'String.call'
    end
  end

  describe 'String#delete_prefix' do
    it 'should add polyfill for delete_prefix' do
      js = to_js('str.delete_prefix("foo")')
      _(js).must_include 'String.prototype.delete_prefix'
      _(js).must_include 'str.delete_prefix("foo")'
    end

    it 'should use startsWith in polyfill' do
      js = to_js('str.delete_prefix("x")')
      _(js).must_include 'this.startsWith(prefix)'
    end

    it 'should return unchanged string when prefix not found' do
      js = to_js('str.delete_prefix("x")')
      _(js).must_include 'return String(this)'
    end
  end

  describe 'String#delete_suffix' do
    it 'should add polyfill for delete_suffix' do
      js = to_js('str.delete_suffix("bar")')
      _(js).must_include 'String.prototype.delete_suffix'
      _(js).must_include 'str.delete_suffix("bar")'
    end

    it 'should use endsWith in polyfill' do
      js = to_js('str.delete_suffix("x")')
      _(js).must_include 'this.endsWith(suffix)'
    end

    it 'should return unchanged string when suffix not found' do
      js = to_js('str.delete_suffix("x")')
      _(js).must_include 'return String(this)'
    end
  end

  describe 'String#count' do
    it 'should add polyfill for count with chars' do
      js = to_js('str.count("aeiou")')
      _(js).must_include 'String.prototype.count'
      _(js).must_include 'str.count("aeiou")'
    end

    it 'should use for...of loop in polyfill' do
      js = to_js('str.count("x")')
      _(js).must_include 'for (let c of this)'
    end
  end

  describe 'Object#to_a' do
    it 'should add polyfill for to_a' do
      js = to_js('hash.to_a')
      _(js).must_include 'Object.defineProperty(Object.prototype, "to_a"'
      _(js).must_include 'hash.to_a'
      _(js).wont_include 'hash.to_a()'
    end

    it 'should use Object.entries in polyfill' do
      js = to_js('obj.to_a')
      _(js).must_include 'Object.entries(this)'
    end
  end

  describe 'Regexp.escape' do
    it 'should add polyfill for pre-ES2025' do
      js = to_js('Regexp.escape(str)', eslevel: 2024)
      # Always define polyfill (no guard) to ensure Ruby-compatible behavior
      # Native ES2025 RegExp.escape escapes more characters than Ruby's Regexp.escape
      _(js).must_include 'RegExp.escape = function'
      _(js).must_include 'RegExp.escape(str)'
    end

    it 'should not add polyfill for ES2025' do
      js = to_js('Regexp.escape(str)', eslevel: 2025)
      # For ES2025+, use native RegExp.escape without polyfill
      _(js).wont_include 'RegExp.escape = function'
      _(js).must_include 'RegExp.escape(str)'
    end

    it 'should convert Regexp to RegExp' do
      js = to_js('Regexp.escape("hello")', eslevel: 2024)
      _(js).must_include 'RegExp.escape("hello")'
      _(js).wont_include 'Regexp.escape'
    end
  end

  describe 'Hash.new with default value' do
    it 'should add $Hash polyfill for Hash.new(default)' do
      js = to_js('h = Hash.new(0)')
      _(js).must_include 'class $Hash extends Map'
      _(js).must_include 'new $Hash(0)'
    end

    it 'should add $Hash polyfill for Hash.new with block' do
      js = to_js('h = Hash.new { |hash, key| hash[key] = [] }')
      _(js).must_include 'class $Hash extends Map'
      _(js).must_include 'new $Hash('
    end

    it 'should support get with default value' do
      js = to_js('h = Hash.new(0)')
      _(js).must_include 'get(k)'
      _(js).must_include '__d'  # default value stored as __d
    end
  end

  describe 'Array#bsearch_index' do
    it 'should add polyfill for bsearch_index' do
      js = to_js('arr.bsearch_index { |x| x >= 5 }')
      _(js).must_include 'Array.prototype.bsearch_index'
      _(js).must_include 'arr.bsearch_index'
    end

    it 'should implement binary search correctly' do
      js = to_js('arr.bsearch_index { |x| x >= 5 }')
      # Binary search should have lo, hi, mid
      _(js).must_include 'let lo = 0'
      _(js).must_include 'let hi = this.length'
      _(js).must_include 'Math.floor((lo + hi) / 2)'
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
