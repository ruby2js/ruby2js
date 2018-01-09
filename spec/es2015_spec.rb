gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/es2015'

describe "ES2015 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ES2015]).to_s
  end
  
  describe :vars do
    it "should use let as the new var" do
      to_js( 'a = 1' ).must_equal('let a = 1')
    end

    it "should use const for constants" do
      to_js( 'A = 1' ).must_equal('const A = 1')
    end

    it "should handle scope" do
      to_js( 'b=0 if a==1' ).must_equal 'let b; if (a == 1) b = 0'
    end

    it "should handle for loops" do
      to_js( 'for i in 1..2; end' ).must_equal 'for (let i = 1; i <= 2; i++) {}'
    end
  end

  describe :for do
    it "should for loops" do
      to_js( 'for i in x; end' ).must_equal('for (let i of x) {}')
    end

    it "should destructure assignment statements" do
      to_js( 'a, (foo, *bar) = x' ).
        must_equal('let [a, [foo, ...bar]] = x')
    end

    it "should destructure parameters" do
      to_js( 'def f(a, (foo, *bar)); end' ).
        must_equal('function f(a, [foo, ...bar]) {}')
    end
  end

  describe :destructuring do
    it "should handle parallel assignment" do
      to_js( 'a,b=b,a' ).must_equal('let [a, b] = [b, a]')
    end
  end

  describe :arguments do
    it "should handle optional parameters" do
      to_js( 'def a(b=1); end' ).must_equal('function a(b=1) {}')
    end

    it "should handle rest parameters" do
      to_js( 'def a(*b); end' ).must_equal('function a(...b) {}')
    end

    it "should handle splat arguments" do
      to_js( 'a(*b)' ).must_equal('a(...b)')
    end
  end

  describe :objectLiteral do
    it "should handle computed property names" do
      to_js( '{a => 1}' ).must_equal('{[a]: 1}')
    end
  end

  describe :templateLiteral do
    it "should convert interpolated strings into ES templates" do
      to_js( '"#{a}"' ).must_equal('`${a}`')
    end

    it "should escape stray ${} characters" do
      to_js( '"#{a}${a}"' ).must_equal("`${a}$\\{a}`")
    end

    it "should escape newlines in short strings" do
      to_js( "\"\#{a}\n\"" ).must_equal("`${a}\\n`")
    end

    it "should not escape newlines in long strings" do
      to_js( "\"\#{a}\n12345678901234567890123456789012345678901\"" ).
       must_equal("`${a}\n12345678901234567890123456789012345678901`")
    end
  end

  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end
  end

  describe :fat_arrow do
    it "should handle simple lambda expressions" do
      to_js( 'foo = lambda {|x| x*x}' ).must_equal 'let foo = (x) => x * x'
    end

    it "should handle block parameters" do
      to_js( 'a {|b| c}' ).must_equal 'a((b) => c)'
    end

    it "should handle multi-statement blocks" do
      to_js( 'foo = proc {a;b}' ).must_equal 'let foo = () => {a; b}'
    end
  end

  describe :array do
    it "should handle array conversions" do
      Ruby2JS.convert(
        'Array(a)', 
        filters: [Ruby2JS::Filter::Functions], 
        eslevel: :es2015
      ).to_s.must_equal 'Array.from(a)'
    end
  end

  describe 'object definition' do
    it "should parse class" do
      to_js('class Person; end').must_equal 'class Person {}'
    end

    it "should parse class with attr_accessor" do
      to_js('class Person; attr_accessor :a; end').
        must_equal 'class Person {get a() {return this._a}; set a(a) {this._a = a}}'
    end

    it "should parse class with constructor" do
      to_js('class Person; def initialize(name); @name = name; end; end').
        must_equal 'class Person {constructor(name) {this._name = name}}'
    end

    it "should parse a nested class with constructor" do
      to_js('class A::Person; def initialize(name); @name = name; end; end').
        must_equal 'A.Person = class {constructor(name) {this._name = name}}'
    end

    it "should parse class with constructor and method" do
      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; end').
        must_equal 'class Person {constructor(name) {this._name = name}; get name() {return this._name}}'
    end

    it "should parse class with constructor and two methods" do
      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; def reset!; @name = nil; end; end').
        must_equal 'class Person {constructor(name) {this._name = name}; get name() {return this._name}; reset() {this._name = null}}'
    end

    it "should parse class with constructor and methods with multiple arguments" do
      to_js('class Person; def initialize(name, surname); @name, @surname = name, surname; end; def full_name; @name  + @surname; end; end').
        must_equal 'class Person {constructor(name, surname) {[this._name, this._surname] = [name, surname]}; get full_name() {return this._name + this._surname}}'
    end

    it "should handle multiple methods in a class" do
      to_js('class C; def a; end; def b; end; end').
        must_equal 'class C {get a() {}; get b() {}}'
    end

    it "should handle both getters and setters in a class" do
      to_js('class C; def a; end; def a=(a); end; end').
        must_equal 'class C {get a() {}; set a(a) {}}'
    end

    it "should handles class getters and setters" do
      to_js('class C; def self.a; end; def self.b; end; end').
        must_equal 'class C {static get a() {}; static get b() {}}'
    end

    it "should parse class with inheritance" do
      to_js('class Employee < Person; end').
        must_equal 'class Employee extends Person {}'
    end

    it "should handle super" do
      to_js('class A; end; class B < A; def initialize(x); super; end; end').
        must_equal 'class A {}; class B extends A {constructor(x) {super(x)}}'
      to_js('class A; end; class B < A; def initialize(x); super(3); end; end').
        must_equal 'class A {}; class B extends A {constructor(x) {super(3)}}'
      to_js('class A; end; class B < A; def foo(x); super; end; end').
        must_equal 'class A {}; class B extends A {foo(x) {super.foo(x)}}'
      to_js('class A; end; class B < A; def foo(x); super(3); end; end').
        must_equal 'class A {}; class B extends A {foo(x) {super.foo(3)}}'
    end

    it "should parse class with class variables" do
      to_js('class Person; @@count=0; end').
        must_equal 'class Person {}; Person._count = 0'
      to_js('class Person; @@count={}; @@count[1]=1; end').
        must_equal 'class Person {}; Person._count = {}; Person._count[1] = 1'
    end

    it "should parse class with instance variables, properties and methods" do
      to_js('class Person; @@count=0; def offset(x); return @@count+x; end; end').
        must_equal 'class Person {offset(x) {return Person._count + x}}; Person._count = 0'

      to_js('class Person; @@count=0; def count; @@count; end; end').
        must_equal 'class Person {get count() {return Person._count}}; Person._count = 0'

      to_js('class Person; @@count=0; def count(); return @@count; end; end').
        must_equal 'class Person {count() {return Person._count}}; Person._count = 0'

      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; @@count=0; def count; return @@count; end; end').
        must_equal 'class Person {constructor(name) {this._name = name}; get name() {return this._name}; get count() {return Person._count}}; Person._count = 0'

      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; @@count=0; def count(); return @@count; end; end').
        must_equal 'class Person {constructor(name) {this._name = name}; get name() {return this._name}; count() {return Person._count}}; Person._count = 0'
    end

    it "should parse instance methods with class variables" do
      to_js('class Person; def count; @@count; end; end').
        must_equal 'class Person {get count() {return Person._count}}'
    end

    it "should parse class methods with class variables" do
      to_js('class Person; def self.count(); return @@count; end; end').
        must_equal 'class Person {static count() {return Person._count}}'

      to_js('class Person; def self.count; @@count; end; end').
        must_equal 'class Person {static get count() {return Person._count}}'

      to_js('class Person; def self.count=(count); @@count=count; end; end').
        must_equal 'class Person {static set count(count) {Person._count = count}}'
    end

    it "should parse constructor methods with class variables" do
      to_js('class Person; def initialize; @@count+=1; end; end').
        must_equal 'class Person {constructor() {Person._count++}}'
    end

    it "should parse class with class constants" do
      to_js('class Person; ID=7; end').
        must_equal 'class Person {}; const Person.ID = 7'
    end

    it "should parse class with class methods" do
      to_js('class Person; def self.search(name); end; end').
        must_equal 'class Person {static search(name) {}}'
    end

    it "should parse class with alias" do
      to_js('class Person; def f(name); end; alias :g :f; end').
        must_include 'Person.prototype.g = Person.prototype.f'
    end

    it "should prefix intra-method calls with 'this.'" do
      to_js('class C; def m1; end; def m2; m1; end; end').
        must_equal 'class C {get m1() {}; get m2() {return this.m1}}'
    end

    it "should prefix class constants referenced in methods by class name" do
      to_js('class C; X = 1; def m; X; end; end').
        must_equal 'class C {get m() {return C.X}}; const C.X = 1'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ES2015" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::ES2015
    end
  end
end
