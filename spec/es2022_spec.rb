require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "ES2022 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2022, filters: []).to_s)
  end

  def to_js_underscored( string)
    _(Ruby2JS.convert(string, eslevel: 2022, underscored_private: true, filters: []).to_s)
  end

  def to_js_logical( string)
    _(Ruby2JS.convert(string, eslevel: 2022, or: :logical, filters: []).to_s)
  end
  
  def to_js_fn(string)
    _(Ruby2JS.convert(string,
      filters: [Ruby2JS::Filter::CJS, Ruby2JS::Filter::Functions],
      eslevel: 2022).to_s)
  end

# describe :ClassFields do
#   it "should convert class fields to static vars" do
#     to_js( 'class C; self.var = []; end' ).
#       must_equal 'class C {#a = 1; get a() {return this.#a}}'
#   end
# end

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
        must_equal 'class C {#a; #b; constructor() {[this.#a, this.#b] = [1, 2]}}'
    end

    it "should do short circuit assign - nullish (default)" do
      to_js( '@a ||= 1').must_equal 'this.#a ??= 1'
      to_js( '@@a ||= 1').must_equal 'this.constructor.#$a ??= 1'
    end

    it "should do short circuit assign - logical" do
      to_js_logical( '@a ||= 1').must_equal 'this.#a ||= 1'
      to_js_logical( '@@a ||= 1').must_equal 'this.constructor.#$a ||= 1'
    end
  end

  describe :ClassFields do
    it "should convert private class fields to static #vars" do
      to_js( 'class C; @@a=1; def self.a; @@a; end; end' ).
        must_equal 'class C {static #$a = 1; static get a() {return C.#$a}}'
    end
  end

  describe :InstanceFieldsUnderscored do
    it "should convert private fields to instance #vars" do
      to_js_underscored( 'class C; def initialize; @a=1; end; def a; @a; end; end' ).
        must_equal 'class C {constructor() {this._a = 1}; get a() {return this._a}}'
    end

    it "should handle instance variable assignments and implicit decls" do
      to_js_underscored( 'class C; def a; @a; end; def a=(a); @a=a; end; end' ).
        must_equal 'class C {get a() {return this._a}; ' +
          'set a(a) {this._a = a}}'
    end

    it "should handle multiple assignments" do
      to_js_underscored( 'class C; def initialize; @a, @b = 1, 2; end; end' ).
        must_equal 'class C {constructor() {[this._a, this._b] = [1, 2]}}'
    end
  end

  describe :ClassFieldsUnderscored do
    it "should convert private class fields to static #vars" do
      to_js_underscored( 'class C; @@a=1; def self.a; @@a; end; end' ).
        must_equal 'class C {static get a() {return C._a}}; C._a = 1'
    end
  end

  describe :ClassConstants do
    it "should convert public class constants to static vars" do
      to_js( 'class C; D=1; end' ).
        must_equal 'class C {static D = 1}'
    end
  end

  describe :attr do
    it 'should handle attr declarations' do
      to_js( 'class C; attr_accessor :a; end' ).
        must_equal 'class C {#a; get a() {return this.#a}; ' + 
          'set a(a) {this.#a = a}}'
      to_js( 'class C; attr_reader :a; end' ).
        must_equal 'class C {#a; get a() {return this.#a}}'
      to_js( 'class C; attr_writer :a; end' ).
        must_equal 'class C {#a; set a(a) {this.#a = a}}'
    end
  end

  describe :at do
    it 'should handle negative indexes' do
      to_js_fn('x[-2]').must_equal('x.at(-2)')
    end

    it 'should handle calls to last' do
      to_js_fn('x.last').must_equal('x.at(-1)')
    end
  end
end
