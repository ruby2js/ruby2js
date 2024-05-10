gem 'minitest'
require 'minitest/autorun'

describe "ES2015 support" do

  def to_js( string, opts={} )
    _(Ruby2JS.convert(string, opts.merge(eslevel: 2015, filters: [])).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::Functions]).to_s)
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
  end

  describe :irange do
    it "(0..5).to_a" do
      to_js( '(0..5).to_a' ).must_equal('[...Array(6).keys()]')
    end

    it "(0..a).to_a" do
      to_js( '(0..a).to_a' ).must_equal('[...Array(a+1).keys()]')
    end

    it "(b..a).to_a" do
      to_js( '(b..a).to_a' ).must_equal('Array.from({length: (a-b+1)}, (_, idx) => idx+b)')
    end

    it "idx variable is used in range" do
      to_js( '(idx..i).to_a' ).must_equal('Array.from({length: (i-idx+1)}, (_, i$) => i$+idx)')
    end

    it "idx variable is reserved elsewhere" do
      to_js( 'idx=1;(b..a).to_a' ).must_equal('let idx = 1; Array.from({length: (a-b+1)}, (_, i$) => i$+b)')
    end

    it "_ variable is used in range start" do
      to_js( '(_..a).to_a' ).must_equal('Array.from({length: (a-_+1)}, (_$, idx) => idx+_)')
    end
  end

  describe :erange do
    it "(0...5).to_a" do
      to_js( '(0...5).to_a' ).must_equal('[...Array(5).keys()]')
    end

    it "(0...a).to_a" do
      to_js( '(0...a).to_a' ).must_equal('[...Array(a).keys()]')
    end

    it "(b...a).to_a" do
      to_js( '(b...a).to_a' ).must_equal('Array.from({length: (a-b)}, (_, idx) => idx+b)')
    end
  end

  describe :for do
    it "should handle for loops" do
      to_js( 'for i in 1..2; end' ).must_equal 'for (let i = 1; i <= 2; i++) {}'
    end

    it "should convert array.each to a for...of" do
      to_js_fn( 'a.each {|v| x+=v}' ).
        must_equal 'for (let v of a) {x += v}'
    end

    it "should convert array.each multiple to a for...of" do
      to_js_fn( 'a.each {|(v,w)| x+=v}' ).
        must_equal 'for (let [v, w] of a) {x += v}'
    end

    it "should handle conditional returns in an each block" do
      to_js_fn( 'a.each {|i| return i if true}' ).
        must_equal 'for (let i of a) {if (true) return i}'
    end

    it "should convert hash.each_value to a for...of" do
      to_js_fn( 'h.each_value {|v| x+=v}' ).
        must_equal 'for (let v of h) {x += v}'
    end
  end

  describe :destructuring do
    it "should destructure assignment statements" do
      to_js( 'a, (foo, *bar) = x' ).
        must_equal('let [a, [foo, ...bar]] = x')
    end

    it "should destructure parameters" do
      to_js( 'def f(a, (foo, *bar)); end' ).
        must_equal('function f(a, [foo, ...bar]) {}')
    end

    it "should handle parallel assignment" do
      to_js( 'a,b=b,a' ).must_equal('let [a, b] = [b, a]')
    end

    it "should handle spread operators" do
      to_js( 'a(*b)' ).must_equal('a(...b)')
    end

    it "should implement max with spread operators" do
      to_js_fn( 'a.max()' ).must_equal('Math.max(...a)')
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 0, 0]) == -1
      it "should support => operator with simple destructuring" do
        to_js('hash => {a:, b:}').must_equal 'let { a, b } = hash'
      end
    end
  end

  describe :arguments do
    it "should handle optional parameters" do
      to_js( 'def a(b=1); end' ).must_equal('function a(b=1) {}')
    end

    it "should handle rest parameters" do
      to_js( 'def a(*b); end' ).must_equal('function a(...b) {}')
    end

    it "should handle rest parameters as only argument to a proc" do
      to_js( 'proc {|*a| a}' ).must_equal('(...a) => a')
    end

    it "should handle splat arguments" do
      to_js( 'a(*b)' ).must_equal('a(...b)')
    end
  end

  describe :objectLiteral do
    it "should handle computed property names" do
      to_js( '{a => 1}' ).must_equal('{[a]: 1}')
    end

    it "should handle ivars" do
      to_js( '@x', ivars: {:@x => {a:1}} ).must_equal '{a: 1}'
      to_js( '@x', ivars: {:@x => {"a"=>1}} ).must_equal '{a: 1}'
    end
  end

  describe :templateLiteral do
    it "should convert interpolated strings into ES templates" do
      to_js( '"#{a}"' ).must_equal('`${a}`')
      to_js( '"#{a}" + "#{b}"' ).must_equal('`${a}${b}`')
    end

    it "should escape backticks in templates" do
      to_js( '"#{a} tick`mark"' ).must_equal('`${a} tick\`mark`')
    end

    it "should escape stray ${} characters" do
      to_js( '"#{a}${a}"' ).must_equal("`${a}$\\{a}`")
    end

    it "should escape newlines in short strings" do
      to_js( "\"\#{a}\n\"" ).must_equal("`${a}\\n`")
    end

    it "should not escape newlines in long strings" do
      to_js( "\"\n1234567890\n1234567890\n1234567890\n1234567890\n1\"" ).
       must_equal("`\n1234567890\n1234567890\n1234567890\n1234567890\n1`")
      to_js( "\"\#{a}\n1234567890\n1234567890\n1234567890\n1234567890\n1\"" ).
       must_equal("`${a}\n1234567890\n1234567890\n1234567890\n1234567890\n1`")
    end

    it "should convert interpolated regular expressions into templates" do
      to_js( '/a#{b}c/' ).must_equal("new RegExp(`a${b}c`)")
    end

    it "should handle totally empty interpolation" do
      to_js('"#{}"').must_equal '``'
    end

    it "should handle mixed empty interpolation" do
      to_js('"x#{}y"').must_equal '`xy`'
    end
  end

  describe :fat_arrow do
    it "should handle simple lambda expressions" do
      to_js( 'foo = lambda {|x| x*x}' ).must_equal 'let foo = x => x * x'
    end

    it "should handle block parameters" do
      to_js( 'a {|b| c}' ).must_equal 'a(b => c)'
    end

    it "should handle multi-statement blocks" do
      to_js( 'foo = proc {a() ;b()}' ).must_equal 'let foo = () => {a(); b()}'
    end

    it "should handle hashes with procs" do
      to_js( 'foo = {x: proc {}}' ).must_equal 'let foo = {x() {}}'
      to_js( 'class T; def d; {x: proc {self}}; end; end' ).
        must_include '{x: () => this}'
      to_js( 'class T; def d; {x: proc {this}}; end; end' ).
        must_include '{x: () => this}'
      to_js( 'class T; def d; {x: proc {@c}}; end; end' ).
        must_include '{x: () => this._c}'
      to_js( 'class T; def d; 1; end; def c; {a: -> {d}}; end; end' ).
        must_include 'get c() {return {a: () => this.d}}'
    end

    it "should treat arguments to anonymous functions as declared" do
      to_js( 'proc {|x| x=1}' ).must_equal '(x) => {x = 1}'
    end

    it "should treat new variables as local to the function" do
      to_js( 'proc {|x| y=1}' ).must_equal '(x) => {let y = 1}'
    end

    it "should not redeclare visible variables" do
      to_js( 'y=1; proc {|x| y=2}' ).must_equal 'let y = 1; (x) => {y = 2}'
    end

    it "should treat raise as a statement" do
      to_js( 'proc {|x| raise x}' ).must_equal '(x) => {throw x}'
    end

    it "should parenthesize hash results" do
      to_js( 'lambda {{x: 1}}' ).must_equal '() => ({x: 1})'
    end

    it "should parenthesize anonymous functions that are immediately called" do
      to_js( 'lambda {1}[]' ).must_equal '(() => 1)()'
    end

    it "should handle to_proc on a symbol" do
      to_js_fn( 'a.map(&:to_i)' ).must_equal 'a.map(item => parseInt(item))'
    end
  end

  describe :string do
    it "should handle start_with?" do
      to_js_fn('a.start_with? "b"').must_equal 'a.startsWith("b")'
    end

    it "should handle end_with?" do
      to_js_fn('a.end_with? "b"').must_equal 'a.endsWith("b")'
    end
  end

  describe :hash do
    it "should handle object literals shorthands" do
      to_js( 'a=1; {a:a}' ).must_equal 'let a = 1; {a}'
      to_js( '{a:a}' ).must_equal '{a}'
    end

    it "should handle merge" do
      to_js_fn( 'a.merge(b)' ).must_equal 'Object.assign({}, a, b)'
    end

    it "should handle merge!" do
      to_js_fn( 'a.merge!(b)' ).must_equal 'Object.assign(a, b)'
    end
  end

  describe :array do
    it "should handle array conversions" do
      to_js_fn('Array(a)').must_equal 'Array.from(a)'
    end

    it "should handle reduce" do
      to_js_fn('x.inject(0) {|sum, n| sum+n}').
        must_equal 'x.reduce((sum, n) => sum + n, 0)'
    end
  end

  describe 'object definition' do
    it "should parse class" do
      to_js('class Person; end').must_equal 'class Person {}'
    end

    it "should parse include" do
      to_js('class Employee; include Person; end').
        must_equal 'class Employee {}; ' +
        'Object.defineProperties(Employee.prototype, ' +
        'Object.getOwnPropertyNames(Person).reduce(($2, $3) => {$2[$3] = ' +
        'Object.getOwnPropertyDescriptor(Person, $3); return $2}, {}))'
    end

    it "should parse class with attr_accessor" do
      to_js('class Person; attr_accessor :a; end').
        must_equal 'class Person {get a() {return this._a}; set a(a) {this._a = a}}'
    end

    it "should parse class with attr_reader" do
      to_js('class Person; attr_reader :a; end').
        must_equal 'class Person {get a() {return this._a}}'
    end

    it "should parse class with attr_writer" do
      to_js('class Person; attr_writer :a; end').
        must_equal 'class Person {set a(a) {this._a = a}}'
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
      to_js('class C; def self.a; end; def self.b=(b); end; end').
        must_equal 'class C {static get a() {}; static set b(b) {}}'
    end

    it "should parse class with inheritance" do
      to_js('class Employee < Person; end').
        must_equal 'class Employee extends Person {}'
    end

    it "should handles static method calls within class" do
      to_js('class Model < Abstract; a :b; end').
        must_equal 'class Model extends Abstract {}; Model.a("b")'
    end

    it "should handles static method calls including blocks within class" do
      to_js('class Model < Abstract; a(:b) { :c }; end').
        must_equal 'class Model extends Abstract {}; Model.a("b", () => "c")'
    end

    it "should handles static property assignments within class" do
      to_js('class Model < Abstract; self.a = :b; end').
        must_equal 'class Model extends Abstract {}; Model.a = "b"'
    end

    it "should parse nested classes" do
      to_js('class A; class B; class C; end; end; end').
        must_equal 'class A {}; A.B = class {}; A.B.C = class {}'
    end

    it "should handle super" do
      class_definition = 'class A; end; class B < A;'
      to_js(class_definition + ' def initialize(x); super; end; end').
        must_equal 'class A {}; class B extends A {constructor(x) {super(x)}}'
      to_js(class_definition + ' def initialize(x); super(3); end; end').
        must_equal 'class A {}; class B extends A {constructor(x) {super(3)}}'
      to_js(class_definition + ' def foo(x); super; end; end').
        must_equal 'class A {}; class B extends A {foo(x) {super.foo(x)}}'
      to_js(class_definition + ' def foo(x); super(3); end; end').
        must_equal 'class A {}; class B extends A {foo(x) {super.foo(3)}}'
      to_js(class_definition + ' def _render(force = false, options = {}); super; end; end').
        must_equal 'class A {}; class B extends A {_render(force=false, options={}) {super._render(force, options)}}'
    end

    it "should handle class super" do
      to_js('class A; end; class B < A; def self.foo(x); super; end; end').
        must_equal 'class A {}; class B extends A {static foo(x) {A.foo(x)}}'
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
        must_equal 'class Person {}; Person.ID = 7'
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

    it "should prefix intra-method calls with 'this.' - reversed" do
      to_js('class C; def m2; m1; end; def m1; end; end').
        must_equal 'class C {get m2() {return this.m1}; get m1() {}}'
    end

    it "should auto bind methods referenced as properties" do
      to_js('class C; def m1(x); end; def m2; m1; end; end').
        must_equal 'class C {m1(x) {}; get m2() {return this.m1.bind(this)}}'
    end

    it "should leave alone methods that are already bound" do
      to_js('class C; def m1(x); end; def m2; m1.bind(this); end; end').
        must_equal 'class C {m1(x) {}; get m2() {return this.m1.bind(this)}}'
    end

    it "should leave alone methods that specify a target" do
      to_js('class C; def m1(x); end; def m2; self.m1; end; end').
        must_equal 'class C {m1(x) {}; get m2() {return this.m1}}'
    end

    it "should not bind methods called as methods" do
      to_js('class C; def m1(x); end; def m2; m1(); end; end').
        must_equal 'class C {m1(x) {}; get m2() {return this.m1()}}'
    end

    it "should prefix class constants referenced in methods by class name" do
      to_js('class C; X = 1; def m; X; end; end').
        must_equal 'class C {get m() {return C.X}}; C.X = 1'
    end
  end

  describe 'class extensions' do
    it 'should handle constructors' do
      to_js('++class F; def initialize() {}; end; end').
        must_equal '[(F = function F() {{}}).prototype] = [F.prototype]'
    end

    it 'should handle methods' do
      to_js('++class F; def m(); end; end').
        must_equal 'F.prototype.m = function() {}'
    end

    it 'should handle properties' do
      to_js('++class F; def p; 1; end; end').
        must_equal 'Object.defineProperty(F.prototype, "p", ' +
          '{enumerable: true, configurable: true, get() {return 1}})'
    end
  end

  describe 'anonymous classes' do
    it 'should handle anonymous classes without inheritance' do
      to_js('x = Class.new do def f(); return 1; end; end').
        must_equal 'let x = class {f() {return 1}}'
    end

    it 'should handle anonymous classes with inheritance' do
      to_js('x = Class.new(D) do def f(); return 1; end; end').
        must_equal 'let x = class extends D {f() {return 1}}'
    end
  end

  describe 'module extensions' do
    it 'should handle methods' do
      to_js('++module M; def m(); end; end').
        must_equal 'Object.assign(M, {m() {}})'
    end
  end

  describe 'keyword arguments' do
    it 'should handle keyword arguments in methods' do
      to_js('def a(q, a:, b: 2); end').
        must_equal('function a(q, { a, b=2 }) {}')
    end

    it 'should handle all optional keyword arguments in methods' do
      to_js('def a(q, a: 1, b: 2); end').
        must_equal('function a(q, { a=1, b=2 } = {}) {}')
    end

    it 'should keyword arguments defaulting to undefined in methods' do
      to_js('def a(q, a: undefined, b: 2); end').
        must_equal('function a(q, { a, b=2 } = {}) {}')
    end

    it 'should handle keyword arguments in blocks' do
      to_js('proc {|q, a:, b: 2|}').
        must_equal('(q, { a, b=2 }) => {}')
    end

    it 'should handle all optional keyword arguments in blocks' do
      to_js('proc {|q, a: 1, b: 2|}').
        must_equal('(q, { a=1, b=2 } = {}) => {}')
    end
  end

  describe :module do
    it "should handle classes nested in modules" do
      to_js( 'module M; class C; def f(); end; end; end' ).
        must_equal('const M = {C: class {f() {}}}')
    end
  end

  describe 'method_missing' do
    it 'should handle args' do
      to_js('class A; def method_missing(method, *args); end; end').
        must_equal(
          'class A$ {method_missing(method, ...args) {}}; ' +
          'function A(...args) {' +
            'return new Proxy(new A$(...args), {get(obj, prop) {' +
              'if (prop in obj) {'+
                'return obj[prop]'+
              '} else {'+
                'return (...args) => (obj.method_missing(prop, ...args))'+
              '}'+
            '}})' +
          '}'
        )
    end

    it 'should handle no args' do # see README for rationale
      to_js('class A; def method_missing(method); end; end').
        must_equal(
          'class A$ {method_missing(method) {}}; ' +
          'function A(...args) {' +
            'return new Proxy(new A$(...args), {get(obj, prop) {' +
              'if (prop in obj) {'+
                'return obj[prop]'+
              '} else {'+
                'return obj.method_missing(prop)'+
              '}'+
            '}})' +
          '}'
        )
    end
  end

end
