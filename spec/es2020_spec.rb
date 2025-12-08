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

  def to_js_logical( string)
    _(Ruby2JS.convert(string, eslevel: 2020, or: :logical, filters: []).to_s)
  end

  def to_js_nullish( string)
    _(Ruby2JS.convert(string, eslevel: 2020, or: :nullish, filters: []).to_s)
  end

  def to_js_nullish_to_s( string)
    _(Ruby2JS.convert(string, eslevel: 2020, nullish_to_s: true, filters: []).to_s)
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

  describe "or option" do
    describe "or: :auto (default)" do
      it "should use || in boolean contexts (if/while/until)" do
        to_js( 'if a || b; x; end' ).must_include 'if (a || b)'
        to_js( 'while a || b; x; end' ).must_include 'while (a || b)'
        to_js( 'a = 1 if b || c' ).must_include 'if (b || c)'
        to_js( 'begin; x; end while a || b' ).must_include 'while (a || b)'
      end

      it "should use ?? in value contexts (assignments)" do
        to_js( 'x = a || b' ).must_equal 'let x = a ?? b'
        to_js( 'a || b' ).must_equal 'a ?? b'
      end

      it "should use || when operands are boolean expressions" do
        to_js( '(a == 1) || (b == 2)' ).must_equal '(a == 1) || (b == 2)'
        to_js( 'a > 5 || b < 3' ).must_equal 'a > 5 || b < 3'
        to_js( 'a.empty? || b.nil?' ).must_equal 'a.empty || b.nil'
        to_js( 'a || true' ).must_equal 'a || true'
        to_js( 'false || b' ).must_equal 'false || b'
        to_js( '!a || !b' ).must_equal '!a || !b'
      end
    end

    describe "or: :nullish" do
      it "should use ?? in boolean contexts" do
        to_js_nullish( 'if a || b; x; end' ).must_include 'if (a ?? b)'
        to_js_nullish( 'while a || b; x; end' ).must_include 'while (a ?? b)'
      end

      it "should use ?? in value contexts" do
        to_js_nullish( 'x = a || b' ).must_equal 'let x = a ?? b'
      end

      it "should still use || for boolean expressions" do
        to_js_nullish( 'a > 5 || b < 3' ).must_equal 'a > 5 || b < 3'
        to_js_nullish( 'a.empty? || b.nil?' ).must_equal 'a.empty || b.nil'
      end
    end

    describe "or: :logical" do
      it "should use || in boolean contexts" do
        to_js_logical( 'if a || b; x; end' ).must_include 'if (a || b)'
      end

      it "should use || in value contexts" do
        to_js_logical( 'x = a || b' ).must_equal 'let x = a || b'
        to_js_logical( 'a || b' ).must_equal 'a || b'
      end
    end
  end

  describe "nullish coalescing operator" do

    it "should convert 'a.nil? ? b : a' to nullish coalescing" do
      to_js( 'a.nil? ? b : a' ).must_equal 'a ?? b'
      to_js( '@a.nil? ? b : @a' ).must_equal 'this._a ?? b'
      to_js( 'foo.bar.nil? ? default_val : foo.bar' ).must_equal 'foo.bar ?? default_val'
    end
  end

  describe "nullish_to_s option" do
    it "should wrap interpolated values with ?? ''" do
      to_js_nullish_to_s( '"hello #{x}"' ).must_equal '`hello ${x ?? ""}`'
    end

    it "should wrap multiple interpolated values" do
      to_js_nullish_to_s( '"#{a} and #{b}"' ).must_equal '`${a ?? ""} and ${b ?? ""}`'
    end

    it "should not wrap string literals in interpolation" do
      to_js_nullish_to_s( '"prefix #{x} suffix"' ).must_equal '`prefix ${x ?? ""} suffix`'
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
