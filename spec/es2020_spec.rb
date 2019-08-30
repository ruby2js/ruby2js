gem 'minitest'
require 'minitest/autorun'

describe "ES2020 support" do
  
  def to_js( string)
    Ruby2JS.convert(string, eslevel: 2020, filters: []).to_s
  end
  
  def to_js_fn(string)
    Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::Functions]).to_s
  end

  describe :InstanceFields do
    it "should convert private fields to instance #vars" do
      to_js( 'class C; def initialize; @a=1; end; def a; @a; end; end' ).
        must_equal 'class C {#a = 1; get a() {return this.#a}}'
    end

    it "should handle instance variable assignments and implicit decls" do
      to_js( 'class C; def a; @a; end; def a=(a); @a=a; end; end' ).
        must_equal 'class C {#a; get a() {return this.#a}; ' +
          'set a(a) {this.#a = a}}'
    end

    it "should handle multiple assignments" do
      to_js( 'class C; def initialize; @a, @b = 1, 2; end; end' ).
        must_equal 'class C {constructor() {[this.#a, this.#b] = [1, 2]}}'
    end
  end

  describe :ClassFields do
    it "should convert private class fields to static #vars" do
      to_js( 'class C; @@a=1; def self.a; @@a; end; end' ).
        must_equal 'class C {static #a = 1; static get a() {return C.#a}}'
    end
  end

  describe :ClassConstants do
    it "should convert public class constants to static vars" do
      to_js( 'class C; D=1; end' ).
        must_equal 'class C {static D = 1}'
    end
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

  unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 3, 0]) == -1
    describe :OptionalChaining do
      it "should support conditional attribute references" do
        to_js('x=a&.b').must_equal 'let x = a?.b'
      end

      it "should chain conditional attribute references" do
        to_js('x=a&.b&.c').must_equal 'let x = a?.b?.c'
      end
    end
  end
end
