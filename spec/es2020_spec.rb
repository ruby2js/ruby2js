gem 'minitest'
require 'minitest/autorun'

describe "ES2020 support" do
  
  def to_js( string)
    Ruby2JS.convert(string, eslevel: 2020, filters: []).to_s
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
end
