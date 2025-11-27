gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/filter/functions'

describe "ES2020 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2020, filters: []).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_nullish( string)
    _(Ruby2JS.convert(string, eslevel: 2020, or: :nullish, filters: []).to_s)
  end

  describe :matchAll do
    it 'should handle scan' do
      to_js_fn( 'str.scan(/\d/)' ).must_equal 'str.match(/\d/g)'
      to_js_fn( 'str.scan(/(\d)(\d)/)' ).
        must_equal 'Array.from(str.matchAll(/(\\d)(\\d)/g), s => s.slice(1))'
      to_js_fn( 'str.scan(pattern)' ).
        must_equal 'Array.from(str.matchAll(new RegExp(pattern, "g")), ' +
          's => s.slice(1))'
    end
  end

  describe :regex do
    it "should handle regular expression indexes" do
      to_js_fn( 'a[/\d+/]' ).must_equal 'a.match(/\d+/)?.[0]'
      to_js_fn( 'a[/(\d+)/, 1]' ).must_equal 'a.match(/(\d+)/)?.[1]'
    end
  end

  describe "nullish coalescing operator" do
    it "should map || operator based on :or option" do
      to_js( 'a || b' ).must_equal 'a || b'
      to_js_nullish( 'a || b' ).must_equal 'a ?? b'
    end

    it "should use || instead of ?? in boolean contexts" do
      # Comparison operators should preserve ||
      to_js_nullish( '(a == 1) || (b == 2)' ).must_equal '(a == 1) || (b == 2)'
      to_js_nullish( 'a > 5 || b < 3' ).must_equal 'a > 5 || b < 3'

      # Predicate methods should preserve ||
      to_js_nullish( 'a.empty? || b.nil?' ).must_equal 'a.empty || b.nil'

      # Boolean literals should preserve ||
      to_js_nullish( 'a || true' ).must_equal 'a || true'
      to_js_nullish( 'false || b' ).must_equal 'false || b'

      # Mixed boolean context should preserve ||
      to_js_nullish( 'a > 5 || b' ).must_equal 'a > 5 || b'
      to_js_nullish( 'a || b < 3' ).must_equal 'a || b < 3'

      # Non-boolean contexts should use ??
      to_js_nullish( 'x = a || b' ).must_equal 'let x = a ?? b'
    end

    it "should convert 'a.nil? ? b : a' to nullish coalescing" do
      to_js( 'a.nil? ? b : a' ).must_equal 'a ?? b'
      to_js( '@a.nil? ? b : @a' ).must_equal 'this._a ?? b'
      to_js( 'foo.bar.nil? ? default_val : foo.bar' ).must_equal 'foo.bar ?? default_val'
    end
  end

  describe :OptionalChaining do
    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 3, 0]) == -1
      it "should support conditional attribute references" do
        to_js('x=a&.b').must_equal 'let x = a?.b'
      end

      it "should chain conditional attribute references" do
        to_js('x=a&.b&.c').must_equal 'let x = a?.b?.c'
      end

      it "should support conditional indexing" do
        to_js('x=a&.[](b)').must_equal 'let x = a?.[b]'
      end

      it "should handle method args with conditional chaining" do
        to_js('x=a&.b&.c(d, e)').must_equal 'let x = a?.b?.c(d, e)'
      end
    end

    it "should combine conditions when it can" do
      to_js('x=a && a.b').must_equal 'let x = a?.b'
      to_js('x=a && a.b(c)').must_equal 'let x = a?.b(c)'
      to_js('x && a && a.b(c)').must_equal 'x && a?.b(c)'
    end

    it "should ignore unrelated ands" do
      to_js('x=x && a && a.b && a.b.c && a.b.c.d && y').
        must_equal 'let x = x && a?.b?.c?.d && y'

      to_js('foo() if bar and bar != @bar').
        must_equal 'if (bar && bar != this._bar) foo()'
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 3, 0]) == -1
      it "should convert methods after optional chaining" do
        to_js_fn('filter.subTypes&.include?(item.subType)').
          must_equal 'filter.subTypes?.includes(item.subType)'
      end

      it "should convert proc symbols after optional chaining" do
        to_js_fn('a&.map(&:to_i)').
          must_equal 'a?.map(item => parseInt(item))'
      end
    end
  end
end
