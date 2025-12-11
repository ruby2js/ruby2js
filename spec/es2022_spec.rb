require 'minitest/autorun'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/cjs'

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

    it "should not hoist ivar assignments that reference constructor args" do
      to_js( 'class C; def initialize(name); @name=name; end; end' ).
        must_equal 'class C {#name; constructor(name) {this.#name = name}}'
    end

    it "should hoist literals but not arg references in mixed constructor" do
      to_js( 'class C; def initialize(x); @a=1; @b=[]; @x=x; end; end' ).
        must_equal 'class C {#a = 1; #b = []; #x; constructor(x) {this.#x = x}}'
    end

    it "should not hoist when arg is used in expression" do
      to_js( 'class C; def initialize(name); @name=name.upcase; end; end' ).
        must_equal 'class C {#name; constructor(name) {this.#name = name.upcase}}'
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

  describe :PrivateMethods do
    it "should convert private methods to #methods" do
      to_js( 'class C; def foo; helper; end; private; def helper; 1; end; end' ).
        must_equal 'class C {get foo() {return this.#helper}; get #helper() {return 1}}'
    end

    it "should handle private method calls with arguments" do
      to_js( 'class C; def foo; helper(1, 2); end; private; def helper(a, b); a + b; end; end' ).
        must_equal 'class C {get foo() {return this.#helper(1, 2)}; #helper(a, b) {a + b}}'
    end

    it "should handle explicit self receiver for private methods" do
      to_js( 'class C; def foo; self.helper; end; private; def helper; 1; end; end' ).
        must_equal 'class C {get foo() {return this.#helper}; get #helper() {return 1}}'
    end

    it "should handle private setters" do
      to_js( 'class C; def set(v); self.internal = v; end; private; def internal=(v); @v = v; end; end' ).
        must_equal 'class C {#v; set(v) {this.#internal = v}; set #internal(v) {this.#v = v}}'
    end

    it "should handle multiple private methods" do
      to_js( 'class C; private; def a; 1; end; def b; a; end; end' ).
        must_equal 'class C {get #a() {return 1}; get #b() {return this.#a}}'
    end

    it "should handle public after private" do
      to_js( 'class C; private; def priv; 1; end; public; def pub; priv; end; end' ).
        must_equal 'class C {get #priv() {return 1}; get pub() {return this.#priv}}'
    end
  end

  describe :PrivateMethodsUnderscored do
    it "should convert private methods to _methods with underscored_private" do
      to_js_underscored( 'class C; def foo; helper; end; private; def helper; 1; end; end' ).
        must_equal 'class C {get foo() {return this._helper}; get _helper() {return 1}}'
    end

    it "should handle explicit self receiver with underscored_private" do
      to_js_underscored( 'class C; def foo; self.helper; end; private; def helper; 1; end; end' ).
        must_equal 'class C {get foo() {return this._helper}; get _helper() {return 1}}'
    end
  end
end
