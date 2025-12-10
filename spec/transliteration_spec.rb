require 'minitest/autorun'
require 'ruby2js'

describe Ruby2JS do
  
  def to_js( string, opts={} )
    _(Ruby2JS.convert(string, opts.merge(filters: [])).to_s)
  end
  
  describe 'literals' do
    it "should parse literals and strings" do
      to_js( "1" ).must_equal '1'
      to_js( "'string'" ).must_equal '"string"'
      to_js( ":symbol" ).must_equal '"symbol"'
      to_js( "nil" ).must_equal 'null'
      to_js( "Constant" ).must_equal 'Constant'

      unicode = to_js( '"\u2620"' )
      unicode.must_equal "\"\u2620\""
    end

    it "should parse simple hash" do
      to_js( "{}" ).must_equal '{}'
      to_js( "{ a: :b }" ).must_equal '{a: "b"}'
      to_js( "{ :a => :b, 'c' => :d }" ).must_equal '{a: "b", c: "d"}'
    end

    it "should handle hashes with keys that aren't identifiers" do
      to_js( "{ 1 => 2 }" ).must_equal '{[1]: 2}'
      to_js( "{ 'data-foo' => 2 }" ).must_equal '{"data-foo": 2}'
    end
    
    it "should parse array" do
      to_js( "[]" ).must_equal '[]'
      to_js( "[1, 2, 3]" ).must_equal '[1, 2, 3]'
    end
    
    it "should parse nested hash" do
      to_js( "{ :a => {:b => :c} }" ).must_equal '{a: {b: "c"}}'
    end
    
    it "should parse array" do
      to_js( "[1, [2, 3]]" ).must_equal '[1, [2, 3]]'
    end
    
    it "should parse global variables" do
      to_js( "$a = 1" ).must_equal 'let $a = 1'
    end

    it "should parse regular expression capture groups" do
      to_js( "$1 == 'a'" ).must_equal 'RegExp.$1 == "a"'
    end
  end
  
  describe 'assign' do
    it "should parse left assign" do
      to_js( "a = 1" ).must_equal 'let a = 1'
      to_js( "a = 'string'" ).must_equal 'let a = "string"'
      to_js( "a = :symbol" ).must_equal 'let a = "symbol"'
    end

    it "should parse constant assign" do
      to_js( "PI = 3.14159" ).must_equal 'const PI = 3.14159'
    end

    it "should not output var if variable is allready declared within a context" do
      to_js( "a = 1; a = 2" ).must_equal 'let a = 1; a = 2'
    end

    it "should parse mass assign" do
      to_js( "a, b = 1, 2" ).must_equal 'let [a, b] = [1, 2]'
      to_js( "a = 1, 2" ).must_equal 'let a = [1, 2]'
      to_js( "a, b = c" ).must_equal 'let [a, b] = c'
    end

    it "should parse chained assignment statements" do
      to_js( "a = b = 1" ).must_equal 'let a, b; a = b = 1'
      to_js( "x.a = b = 1" ).must_equal 'let b; x.a = b = 1'
      to_js( "@a = b = 1" ).must_equal 'let b; this._a = b = 1'
      to_js( "@@a = b = 1" ).must_equal 'let b; this.constructor._a = b = 1'
      to_js( "A = b = 1" ).must_equal 'let b; const A = b = 1'
    end

    it "should parse op assignments" do
      to_js( 'a += 1' ).must_equal 'a++'
      to_js( '@a += 1' ).must_equal 'this._a++'
      to_js( '@@a += 1' ).must_equal 'this.constructor._a++'
    end

    it "should parse unary operators" do
      to_js( '+a' ).must_equal '+a'
      to_js( '-a' ).must_equal '-a'
    end

    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end

    it "should do short circuit assign" do
      to_js( 'a = nil; a ||= 1').must_equal 'let a = null; a = a ?? 1'
      to_js( '@a ||= 1').must_equal 'this._a = this._a ?? 1'
      to_js( '@@a ||= 1').
        must_equal 'this.constructor._a = this.constructor._a ?? 1'
      to_js( 'self.p ||= 1').must_equal 'this.p = this.p ?? 1'
      to_js( 'a[i] ||= 1').must_equal 'a[i] = a[i] ?? 1'
    end
    
    it "should parse ternary operator" do
      to_js( 'x = true ? true : false').
        must_equal "let x = true ? true : false"
      to_js( 'x = (true if y)').
        must_equal "let x = y ? true : null"
      to_js( 'x = (true unless y)').
        must_equal "let x = !y ? true : null"
      to_js( 'x = a + (b ? 1 : 0)').
        must_equal "let x = a + (b ? 1 : 0)"
    end
  end
  
  describe 'method call' do
    it "should parse function call with no args" do
      to_js( "a()" ).must_equal 'a()'
    end
    
    it "should parse method call with no args" do
      to_js( "a.b()" ).must_equal 'a.b()'
    end
    
    it "should parse method call with args" do
      to_js( "a 1, 2, 3" ).must_equal 'a(1, 2, 3)'
    end
    
    it "should parse lvar as variable call" do
      to_js( "a = 1; a" ).must_equal 'let a = 1; a'
    end
    
    it "should parse square bracket call" do
      to_js( "a = [1]; a[0]" ).must_equal 'let a = [1]; a[0]'
      to_js( "a['x']" ).must_equal 'a.x'
      to_js( "a[:x]" ).must_equal 'a.x'
    end

    it "should parse square bracket assignment" do
      to_js( "a = [1]; a[0]=2" ).must_equal 'let a = [1]; a[0] = 2'
      to_js( "a['x']=1" ).must_equal 'a.x = 1'
      to_js( "a[:x]=1" ).must_equal 'a.x = 1'
    end

    it "should parse nested square bracket call" do
      to_js( "a = [[1]]; a[0][0]" ).must_equal 'let a = [[1]]; a[0][0]'
    end
    
    it "should parse binary operation" do
      to_js( "1 + 1" ).must_equal '1 + 1'
    end
    
    it "should call method on literal" do
      to_js( "[0][0]" ).must_equal '[0][0]'
    end
    
    it "should nest arguments as needed" do
      exp = 'a((1 + 2) * 2)'
      to_js( exp ).must_equal exp
    end
    
    it "should chain method calls" do
      exp = 'a().one().two().three()'
      to_js( exp ).must_equal exp
    end

    it "should drop ! and ? from method calls and property accesses" do
      to_js( "a!()" ).must_equal 'a()'
      to_js( "a?()" ).must_equal 'a()'
      to_js( "a!" ).must_equal 'let a'
      to_js( "a?" ).must_equal 'let a'
    end

    it "should wrap numeric literals in parenthesis" do
      to_js( "1000.toLocaleString()" ).
        must_equal "(1000).toLocaleString()"
    end
  end

  describe "splat" do
    it "should pass splat" do
      to_js( "console.log 'a', 'b', *%w(c d e)" ).
        must_equal 'console.log("a", "b", ...["c", "d", "e"])'
    end

    it "should optimize splat as only arg" do
      to_js( "console.log *%w(a b c d e)" ).
        must_equal 'console.log(...["a", "b", "c", "d", "e"])'
    end

    it "should receive splat" do
      to_js( "def f(a,*b); return b; end" ).
        must_equal "function f(a, ...b) {return b}"
    end

    it "should receive unnamed splat" do
      to_js( "def f(a,*); return a; end" ).
        must_equal "function f(a, ...) {return a}"
    end

    it "should receive splat and block" do
      # Block is popped from args at runtime since JS requires rest param to be last
      to_js( "def f(a,*args, &block); end" ).
        must_equal "function f(a, ...args) {let block = args.pop()}"
    end

    it "should handle splats in array literals" do
      to_js( "[*a,1,2,*b,3,4,*c]" ).
        must_equal "[...a, 1, 2, ...b, 3, 4, ...c]"
    end
  end
  
  describe 'boolean' do
    it "should parse boolean" do
      to_js( "true; false" ).must_equal 'true; false'
    end

    it "should parse relation operators" do
      to_js( "a < b" ).must_equal 'a < b'
      to_js( "a <= b" ).must_equal 'a <= b'
      to_js( "a == b" ).must_equal 'a == b'
      to_js( "a === b" ).must_equal 'a === b'
      to_js( "a >= b" ).must_equal 'a >= b'
      to_js( "a > b" ).must_equal 'a > b'
      to_js( "a <=> b" ).must_equal 'a < b ? -1 : a > b ? 1 : 0'
    end

    it "should parse logic operators" do
      to_js( "true && false" ).must_equal 'true && false'
      to_js( "true and false" ).must_equal 'true && false'
      to_js( "true || false" ).must_equal 'true || false'
      to_js( "true or false" ).must_equal 'true || false'
    end
    
    it "should respect parens" do
      to_js( "true && (true || false)" ).must_equal 'true && (true || false)'
    end
    
    it "should parse not" do
      to_js( "not true" ).must_equal '!true'
    end
    
    it "should parse nested logic" do
      to_js( 'not (true or false)' ).must_equal '!(true || false)'
    end
    
    it "should parse more complex nested logic" do
      logic = '!((true && false) || (false || false))'
      to_js( logic ).must_equal logic
    end
    
    it "should parse another nested login example" do
      logic = '!true && true' 
      to_js( logic ).must_equal logic
    end
    
  end
  
  describe 'expressions' do
    it "should handle simple chaining" do
      exp = '1 + 1 + 1'
      to_js( exp ).must_equal exp
    end
    
    it "should respect parens" do
      exp = '1 + (1 - 1)'
      to_js( exp ).must_equal exp
    end
    
    it "should not nest" do
      exp = '1 + 1 * 1'
      to_js( exp ).must_equal exp
    end
    
    it "should parse nested expressions" do
      exp = '(1 + 1) * 1'
      to_js( exp ).must_equal exp
    end
    
    it "should parse complex nested expressions" do
      exp = '1 + (1 + (1 + 1 * (2 - 1)))'
      to_js( exp ).must_equal exp
    end
    
    it "should parse complex nested expressions with method calls" do
      exp = '1 + (a() + (1 + 1 * (b() - d())))'
      to_js( exp ).must_equal exp
    end
    
    it "should parse complex nested expressions with method calls and variables" do
      exp = 'a = 5; 1 + (a + (1 + a * (b() - d())))'
      to_js( exp ).must_equal "let " + exp
    end
    
    it "should parse nested sender" do
      exp = '((1 / 2) * 4 - (1 + 1)) - 1'
      to_js( exp ).must_equal exp
    end
    
    it "nest expressions when needed in string interpolation" do
      to_js( '"#{a}#{b}".length' ).must_equal '`${a}${b}`.length'
      to_js( '"#{a}#{b}".split(" ")' ).must_equal '`${a}${b}`.split(" ")'
      to_js( '"a#{b+c}"' ).must_equal '`a${b + c}`'
    end

    it "should concatenate strings" do
      to_js( '"a"+"b"' ).must_equal '"ab"'
    end
    
    it "should nest methods called on expressions" do
      exp = '(a + b).length'
      to_js( exp ).must_equal exp
      exp = '(a + b).split(" ")'
      to_js( exp ).must_equal exp
    end
    
    it "should nest arguments as needed" do
      exp = 'a((1 + 2) * 2 - 1)'
      to_js( exp ).must_equal exp
    end

    it "should handle function calls" do
      to_js( 'a = lambda {|x| return x+1}; a.(nil, 1)').
        must_equal 'let a = x => x + 1; a.call(null, 1)'
    end
  end
  
  describe 'string concat' do
    # it "should eval" do
    #   to_js('eval( "hi" )').must_equal 'eval(\"hi\")'
    # end
    
    it "should parse string " do
      to_js( '"time is #{ Time.now() }, say #{ hello }"' ).must_equal '`time is ${Time.now()}, say ${hello}`'
    end
    
    it "should parse string" do
      to_js( '"time is #{ Time.now() }"' ).must_equal '`time is ${Time.now()}`'
    end
    
    it "should parse interpolated symbols" do
      to_js( ':"a#{b}c"' ).must_equal '`a${b}c`'
    end
  end

  describe 'wow, such empty' do
    it "should handle totally empty interpolation" do
      to_js('"#{}"').must_equal '``'
    end

    it "should handle mixed empty interpolation" do
      to_js('"x#{}y"').must_equal '`xy`'
    end

    it "should handle empty here docs" do
      to_js("x = <<HERE\nHERE").must_equal "let x = \"\"\n"
    end

    it "should handle mixed empty parens" do
      to_js('x = ()').must_equal 'let x = null'
    end
  end

  describe 'array push' do
    it "should convert << statements to .push calls" do
      to_js( 'a << b' ).must_equal 'a.push(b)'
    end

    it "should convert multiple << statements to a single .push call" do
      to_js( 'a << b << c << d << e' ).must_equal 'a.push(b, c, d, e)'
    end

    it "should leave << expressions alone" do
      to_js( 'y = a << b' ).must_equal 'let y = a << b'
    end
  end

  describe 'control' do
    it "should parse single line if" do
      to_js( '1 if true' ).must_equal 'if (true) 1'
    end
    
    it "should parse single line unless" do
      to_js( '1 unless false' ).must_equal 'if (!false) 1'
      to_js( '1 unless a' ).must_equal 'if (!a) 1'
      to_js( '1 unless a == b' ).must_equal 'if (a != b) 1'
      to_js( '1 unless a === b' ).must_equal 'if (a !== b) 1'
      to_js( '1 unless a or b' ).must_equal 'if (!a && !b) 1'
      to_js( '1 unless a and b' ).must_equal 'if (!a || !b) 1'
    end
    
    it "should parse if else" do
      to_js( 'if true; 1; else; 2; end' ).must_equal 'if (true) {1} else {2}'
    end
    
    it "should parse if else unless" do
      to_js( 'if true; 1; else; 2 unless false; end' ).
        must_equal 'if (true) {1} else if (!false) {2}'
    end
    
    it "should parse if elsif" do
      to_js( 'if true; 1; elsif false; 2; else; 3; end' ).
        must_equal 'if (true) {1} else if (false) {2} else {3}'
    end
    
    it "should parse if elsif elsif" do
      to_js( 'if true; 1; elsif false; 2; elsif (true or false); 3; else; nassif(); end' ).
        must_equal 'if (true) {1} else if (false) {2} else if (true || false) {3} else {nassif()}' 
    end

    it "should parse if as an expression" do
      to_js( 'x = if a; b = 1; b; elsif c; x=1; x; end' ).
        must_equal 'let x = a ? (() => {let b = 1; return b})() : c ? ' +
          '(() => {let x = 1; return x})() : null'
    end
    
    it "should handle basic variable scope" do
      to_js( 'z = 1; if a; b; elsif c; d = proc do e = 1; end; end; z = d' ).
        must_equal 'let d; let z = 1; if (a) {let b} else if (c) {d = () => {let e = 1}}; z = d'

      to_js( 'if a == 1; b = 0; c.forEach {|d| if d; b += d; end} end' ).
        must_equal 'if (a == 1) {let b = 0; c.forEach((d) => {if (d) b += d})}'
    end
    
    it "should handle while loop" do
      to_js( 'a = 0; while true; a += 1; end' ).
        must_equal 'let a = 0; while (true) {a++}'
    end
    
    it "should handle while loop that assigns a variable" do
      to_js( 'while match=f(); end' ).
        must_equal 'let match; while (match = f()) {}'
    end
    
    it "should handle another while loop syntax" do
      to_js( 'a = 0; while true || false; a += 1; end' ).
        must_equal 'let a = 0; while (true || false) {a++}'
    end

    it "should handle a redo within a loop" do
      to_js( 'while true do redo; end' ).
        must_equal 'while (true) {let redo$; do {redo$ = false; ' +
          'redo$ = true; continue} while(redo$)}'
    end

    it "should handle simple case statement" do
      to_js( 'case a; when 1,2; puts :a; end' ).
        must_equal 'switch (a) {case 1: case 2: puts("a")}'
    end

    it "should handle case statement with irange" do
      to_js( 'case a; when 1..2; puts :a; end' ).
        must_equal 'switch (true) {case a >= 1 && a <= 2: puts("a")}'
    end

    it "should handle case statement with erange" do
      to_js( 'case a; when 1...2; puts :a; end' ).
        must_equal 'switch (true) {case a >= 1 && a < 2: puts("a")}'
    end

    it "should handle case statement with mixed values and ranges" do
      to_js( 'case a; when 1...2, 3; puts :a; end' ).
        must_equal 'switch (true) {case a >= 1 && a < 2: case a == 3: ' +
          'puts("a")}'
    end

    it "should parse when and else clauses as statements" do
      to_js( 'case 1; when 1; if true; end; else if false; end; end' ).
        must_equal 'switch (1) {case 1: if (true) null; break; default: if (false) null}'
    end

    it "should parse case expressions" do
      to_js( 'x = case a; when true; b; else; c; end' ).
        must_equal 'let x = (() => {switch (a) {case true: return b; default: return c}})()'
    end

    it "should handle empty when blocks" do
      to_js( 'case a; when 1; when 2; b; end' ).
        must_equal 'switch (a) {case 1: ; break; case 2: let b}'
    end

    it "should handle a for loop" do
      to_js( 'a = {}; b = {}; for i in a; b[i] = a[i]; end' ).
        must_equal 'let a = {}; let b = {}; for (let i in a) {b[i] = a[i]}'
    end

    it "should handle a for loop with an inclusive range" do
      to_js( 'a = 0; for i in 1..3; a += i; end' ).
        must_equal 'let a = 0; for (let i = 1; i <= 3; i++) {a += i}'
    end

    it "should handle a for loop with an exclusive range" do
      to_js( 'a = 0; for i in 1...4; a += i; end' ).
        must_equal 'let a = 0; for (let i = 1; i < 4; i++) {a += i}'
    end

    it "should handle a stepped range with an inclusive range" do
      to_js( 'a = 0; (1..3).step(2) {|i| a += i}' ).
        must_equal 'let a = 0; for (let i = 1; i <= 3; i += 2) {a += i}'
    end

    it "should handle a stepped range with an exclusive range" do
      to_js( 'a = 0; (1...4).step(2) {|i| a += i}' ).
        must_equal 'let a = 0; for (let i = 1; i < 4; i += 2) {a += i}'
    end

    it "should handle break" do
      to_js( 'while true; break; end' ).must_equal 'while (true) {break}'
    end

    it "should handle next as return" do
      to_js( 'x.forEach { next }' ).must_equal 'x.forEach(() => {return})'
      to_js( 'x.map {|i| next i}' ).must_equal 'x.map((i) => {return i})'
    end

    it "should handle next as continue" do
      to_js( 'while false; next; end' ).must_equal 'while (false) {continue}'
    end

    it "should handle next as continue for step" do
      to_js( '(1..3).step(1) {|i| next if i%2 == 0}' ).
        must_include '{if (i % 2 == 0) continue}'
    end


    it "should handle until" do
      to_js( '1 until false' ).must_equal 'while (!false) {1}'
    end

    it "should handle while with post condition" do
      to_js( 'begin; foo(); end while condition' ).
        must_equal 'do {foo()} while (condition)'
    end

    it "should handle until with post condition" do
      to_js( 'begin; foo(); end until condition' ).
        must_equal 'do {foo()} while (!condition)'
    end
  end
  
  describe 'blocks' do
    it "should parse return" do
      exp = 'return 1'
      to_js( exp ).must_equal exp
    end
    
    it "should parse proc" do
      to_js('Proc.new {}').must_equal '() => {}'
    end
    
    it "should parse lambda" do
      to_js( 'lambda {}').must_equal '() => {}'
      to_js( 'y = lambda {|x| x + 1}').must_equal 'let y = x => x + 1'
    end

    it "should parse proc" do
      to_js( 'proc {}').must_equal '() => {}'
    end

    it "should support calls to anonymous functions" do
      to_js( 'proc {}[]').must_equal '(() => {})()'
    end

    it "should handle basic variable scope" do
      to_js( 'a = 1; lambda { a = 2; b = 1}').must_equal 'let a = 1; () => {a = 2; let b = 1}'
    end

    it "should handle shadow args" do
      to_js( 'a = 1; lambda {|;a| a = 2}').must_equal 'let a = 1; () => {let a = 2}'
    end

    it "named functions aren't closures" do
      to_js( 'a = 1; def f; a = 2; b = 1; end').
        must_equal 'let a = 1; function f() {let a = 2; let b = 1}'
    end

    it "should handle one argument" do
      to_js( 'lambda { |a| return a + 1 }').
        must_equal 'a => a + 1'
    end
    
    it "should handle arguments" do
      to_js( 'lambda { |a,b| return a + b }').
        must_equal '(a, b) => a + b'
    end
    
    it "should pass functions" do
      to_js( 'run("task"){ |task| do_run task}').must_equal 'run("task", task => do_run(task))'
    end
    
    it "should handle variable scope" do
      to_js('a = 1; lambda {|b| c = 0; a = b - c }; lambda { |b| c = 1; a = b + c }').
        must_equal 'let a = 1; (b) => {let c = 0; a = b - c}; (b) => {let c = 1; a = b + c}'
    end
    
    it "should really handle variable scope" do
      to_js('a, d = 1, 2; lambda {|b| c = 0; a = b - c * d}; lambda { |b| c = 1; a = b + c * d}').
        must_equal 'let [a, d] = [1, 2]; (b) => {let c = 0; a = b - c * d}; (b) => {let c = 1; a = b + c * d}'
    end
    
    it "should parse with explicit return" do
      to_js('Proc.new {return nil}').must_equal '() => null'
    end

    it "should passthrough function definitions" do
      to_js('a=1; b=function(a,c) {return a + c}').
        must_equal 'let a = 1; let b = (a, c) => a + c'
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 7, 0]) == -1
      it "should handle numbered parameters" do
        to_js( 'lambda { _1 + _2 }').
          must_equal '(_1, _2) => _1 + _2'
      end
    end
  end

  describe 'object definition' do
    it "should parse class" do
      to_js('class Person; end').must_equal 'class Person {}'
    end

    it "should parse include" do
      to_js('class Employee; include Person; end').
        must_equal 'class Employee {}; (() => {let $0 = Employee.prototype; return Object.defineProperties($0, Object.getOwnPropertyDescriptors(Person))})()'
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

    it "should strip ? from predicate method names in prototype" do
      to_js('class Person; def valid?; @name != nil; end; end').
        must_equal 'class Person {valid() {this._name != null}}'
    end

    it "should parse class with constructor and methods with multiple arguments" do
      to_js('class Person; def initialize(name, surname); @name, @surname = name, surname; end; def full_name; @name  + @surname; end; end').
        must_equal 'class Person {constructor(name, surname) {[this._name, this._surname] = [name, surname]}; get full_name() {return this._name + this._surname}}'
    end

    it "should collapse multiple methods in a class" do
      to_js('class C; def a; end; def b; end; end').
        must_equal 'class C {get a() {}; get b() {}}'
    end

    it "should collapse getters and setters in a class" do
      to_js('class C; def a; end; def a=(a); end; end').
        must_equal 'class C {get a() {}; set a(a) {}}'
    end

    it "should collapse properties" do
      to_js('class C; def self.a; end; def self.b; end; end').
        must_equal 'class C {static get a() {}; static get b() {}}'
    end

    it "should parse class with inheritance" do
      to_js('class Employee < Person; end').
        must_equal 'class Employee extends Person {}'
    end

    it "should handle super" do
      to_js('class A; def initialize(x); end; end; class B < A; end').
        must_equal 'class A {constructor(x) {}}; class B extends A {}'
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
        must_equal 'class Person {}; Person.ID = 7'
    end

    it "should parse class with class methods" do
      to_js('class Person; def self.search(name); end; end').
        must_equal 'class Person {static search(name) {}}'
    end

    it "should parse class with alias" do
      to_js('class Person; def f(name); end; alias :g :f; end').
        must_equal 'class Person {f(name) {}; }; Person.prototype.g = Person.prototype.f'
    end

    it "should parse method def" do
      to_js('def method; end').must_equal 'function method() {}'
      to_js("def question?; end").must_equal 'function question() {}'
      to_js("def bang!; end").must_equal 'function bang() {}'
    end

    it "should parse endless method definitions (Ruby 3.0+)" do
      to_js('def square(x) = x * x').
        must_equal 'function square(x) {return x * x}'
      to_js('def add(a, b) = a + b').
        must_equal 'function add(a, b) {return a + b}'
    end

    it "should parse endless singleton method definitions" do
      to_js('def self.double(x) = x * 2').
        must_equal 'this.double = function(x) {return x * 2}'
    end

    it "should parse argument forwarding (Ruby 2.7+)" do
      to_js('def wrapper(...); wrapped(...); end').
        must_equal 'function wrapper(...args) {wrapped(...args)}'
      to_js('def forward(...); a(...); b(...); end').
        must_equal 'function forward(...args) {a(...args); b(...args)}'
    end

    it "should parse singleton method and property definitions" do
      to_js('def self.method(); end').must_equal 'this.method = function() {}'
      to_js('def self.prop; @prop; end').
        must_equal 'Object.defineProperty(this, "prop", {enumerable: true, configurable: true, get() {return this._prop}})'
      to_js('def self.prop=(prop); @prop=prop; end').
        must_equal 'Object.defineProperty(this, "prop", {enumerable: true, configurable: true, set(prop) {this._prop = prop}})'
      # JS selfhost: combine_properties doesn't merge getter/setter into single defineProperty
      unless defined? Function
        to_js('def self.prop; @prop; end; def self.prop=(prop); @prop=prop; end').
          must_equal 'Object.defineProperty(this, "prop", {enumerable: true, configurable: true, get() {return this._prop}, set(prop) {this._prop = prop}})'
      end
    end

    it "should parse nested classes" do
      to_js('class A; class B; class C; end; end; end').
        must_equal 'class A {}; A.B = class {}; A.B.C = class {}'
    end
    
    it "should convert self to this" do
      to_js('def method; return self.foo; end').
        must_equal 'function method() {return this.foo}'
    end

    it "should prefix intra-method calls with 'this.'" do
      to_js('class C; def m1; end; def m2; m1; end; end').
        must_equal 'class C {get m1() {}; get m2() {return this.m1}}'
    end

    it "should prefix property assignments with this." do
      to_js('class C; def a=(x); @a=x; end; def b(); a+=1; end; end').
        must_equal 'class C {set a(x) {this._a = x}; b() {this.a++}}'
    end

    it "should prefix bind references to methods as properties" do
      to_js('class C; def m1(); end; def m2; m1; end; end').
        must_equal 'class C {m1() {}; get m2() {return this.m1.bind(this)}}'
    end

    it "should prefix class constants referenced in methods by class name" do
      to_js('class C; X = 1; def m; X; end; end').
        must_equal 'class C {get m() {return C.X}}; C.X = 1'
    end

    it "should insert var self = this when needed" do
      to_js('class C; def m; list.each do; @ivar; end; end; end').
        must_equal 'class C {get m() {return list.each(() => this._ivar)}}'

      to_js('class C; def m(); list.each do; @ivar; @ivar; end; end; end').
        must_equal 'class C {m() {list.each(() => {this._ivar; this._ivar})}}'

      to_js('class C < S; def m; list.each do; @ivar; end; end; end').
        must_equal 'class C extends S {get m() {return list.each(() => this._ivar)}}'

      to_js('class C < S; def m(); list.each do; @ivar; @ivar; end; end; end').
        must_equal 'class C extends S {m() {list.each(() => {this._ivar; this._ivar})}}'

      to_js('class C < S; def m(); list.each do; {n: @ivar}; end; end; end').
        must_equal 'class C extends S {m() {list.each(() => ({n: this._ivar}))}}'

      to_js('class C; def self.a(); window.addEventListener :unload do; self.b(); end; end; end').
        must_equal 'class C {static a() {window.addEventListener("unload", () => this.b())}}'
    end
    
    it "should handle methods with multiple statements" do
      to_js('def method; self.foo(); self.bar; end').
        must_equal 'function method() {this.foo(); this.bar}'
    end

    it "should handle methods with optional arguments" do
      to_js( 'def method(opt=1); return opt; end' ).
        must_equal "function method(opt=1) {return opt}"
    end

    it "should handle methods with block arguments" do
      to_js( 'def method(&b); return b; end' ).
        must_equal 'function method(b) {return b}'
    end

    it "should handle calls with block arguments" do
      to_js( 'method(&b)' ).must_equal 'method(b)'
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
      skip() if defined? Function  # JS selfhost: Hash#map incompatibility in converter
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

  describe 'module definition' do
    it "should handle empty modules" do
      to_js( 'module A; end' ).
        must_equal 'A = {}'
    end

    it "should handle module definitions" do
      to_js( 'module A; B=1; end' ).
        must_equal 'A = (() => {const B = 1; return {B}})()'
      to_js( 'module A; def b; return 1; end; end' ).
        must_equal 'const A = {get b() {return 1}}'
      to_js( 'module A; def b(); return 1; end; end' ).
        must_equal 'const A = {b() {return 1}}'
      to_js( 'module A; class B; def initialize; @c=1; end; end; end' ).
        must_equal 'const A = {B: class {constructor() {this._c = 1}}}'
    end

    it "should handle private sections" do
      to_js( 'module A; B=1; private; C=1; end' ).
        must_equal 'A = (() => {const B = 1; const C = 1; return {B}})()'
    end

    it "should handle nested modules" do
      to_js( 'module M; module N; def f(); end; end; end' ).
        must_equal('const M = {N: {f() {}}}')
      to_js( 'module M; module N; end; module N::O; end; end' ).
        must_equal('const M = {N: {}}; M.N.O = {}')
    end
  end

  describe 'allocation' do
    it "should handle class new" do
      to_js( 'Date.new' ).must_equal 'new Date'
      to_js( 'Date.new.toString()' ).must_equal '(new Date).toString()'
      to_js( 'Date.new()' ).must_equal 'new Date()'
      to_js( 'Date.new().toString()' ).must_equal 'new Date().toString()'

      # support a JavaScript-like syntax too.
      to_js( 'new Date()' ).must_equal 'new Date()'
      to_js( 'new Date' ).must_equal 'new Date'
      to_js( 'new Promise do; y(); end' ).
        must_equal 'new Promise(() => y())'
      to_js( 'new Promise() do; y(); end' ).
        must_equal 'new Promise(() => y())'
      to_js( 'new xeogl.Model()' ).
        must_equal 'new xeogl.Model()'
    end
  end

  describe 'typeof, defined, instance_of' do
    it "should handle typeof" do
      to_js( 'typeof x' ).must_equal "typeof x"
    end

    it "should handle negation of typeof comparisons" do
      to_js( 'return unless typeof x == "number"' ).
        must_equal 'if (typeof x != "number") return'
      to_js( 'return if typeof x != "number"' ).
        must_equal 'if (typeof x != "number") return'
    end

    it "should handle defined?" do
      to_js( 'defined? x' ).must_equal "typeof x !== 'undefined'"
      to_js( '!defined? x' ).must_equal "typeof x === 'undefined'"
    end

    it "should handle undef" do
      to_js( 'undef x' ).must_equal "delete x"
    end

    it "should handle is_a?, kind_of?, instance_of?" do
      to_js( 'a.is_a? b' ).must_equal "(a instanceof b)"
      to_js( 'a.kind_of? b' ).must_equal "(a instanceof b)"
      to_js( 'a.instance_of? b' ).must_equal "(a.constructor == b)"

      to_js( 'x unless a.is_a? b' ).must_equal "if (!(a instanceof b)) let x"
      to_js( 'x unless a.kind_of? b' ).must_equal "if (!(a instanceof b)) let x"
      to_js( 'x unless a.instance_of? b' ).must_equal "if (!(a.constructor == b)) let x"
    end

    it "should handle is_a?, kind_of?, instance_of? with safe navigation" do
      to_js( 'a&.is_a? b' ).must_equal "a && (a instanceof b)"
      to_js( 'a&.kind_of? b' ).must_equal "a && (a instanceof b)"
      to_js( 'a&.instance_of? b' ).must_equal "a && (a.constructor == b)"
    end
  end

  describe 'attribute access' do
    it "should support attribute reference" do
      to_js('x=a.b').must_equal 'let x = a.b'
    end

    it "should support attribute assignments" do
      to_js('x={}; x.a="y"').must_equal 'let x = {}; x.a = "y"'
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 3, 0]) == -1
      it "should support conditional attribute references" do
        to_js('x=a&.b').must_equal 'let x = a?.b'
      end

      it "should chain conditional attribute references" do
        to_js('x=a&.b&.c').must_equal 'let x = a?.b?.c'
      end

      it "should handle method args with conditional chaining" do
        to_js('x=a&.b(c, d)').must_equal 'let x = a?.b(c, d)'
      end
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 0, 0]) == -1
      it "should support => operator with simple left hand sides" do
        to_js('0 => x').must_equal 'let x = 0'
      end

      it "should support => operator with simple destructuring" do
        skip() if defined? Function  # JS selfhost: missing visit_hash_pattern_node in walker
        to_js('hash => {a:, b:}').must_equal 'let { a, b } = hash'
      end
    end
  end
  
  describe 'whitespace' do
    it "should handle newlines" do
      to_js( "a = 1\na = 2" ).must_equal "let a = 1;\na = 2"
    end

    it "should handle if statements" do
      to_js( "a() if true" ).must_equal "if (true) a()"
    end

    it "should handle while statements" do
      to_js( "a() while false\n" ).must_equal "while (false) {\n  a()\n}"
    end

    it "should parse when and else clauses as statements" do
      skip() if defined? Function  # JS selfhost: missing blank line before default:
      to_js( "case 1\nwhen 1\na()\nelse\nb()\nend" ).
        must_equal "switch (1) {\ncase 1:\n  a();\n  break;\n\ndefault:\n  b()\n}"
    end

    it "should handle function declarations" do
      to_js("Proc.new {return null}\n").
        must_equal "() => null"
    end

    it "should add a blank line before blocks" do
      to_js( "x()\nif true; a(); b(); end" ).
        must_equal "x();\n\nif (true) {\n  a();\n  b()\n}"
    end

    it "should add a blank line after blocks" do
      to_js( "if true; a(); b(); end\nx()" ).
        must_equal "if (true) {\n  a();\n  b()\n};\n\nx()"
    end

    it "should add a single blank line between blocks" do
      to_js( "if true; a(); b(); end\nif false; c(); d(); end" ).
        must_equal "if (true) {\n  a();\n  b()\n};\n\n" +
          "if (false) {\n  c();\n  d()\n}"
    end
  end

  describe 'procs' do
    it "should handle procs" do
      # JS doesn't have Proc objects or source_location
      skip "JS doesn't support Proc source location" if defined? Function
      source = Proc.new { c + 1 }
      to_js( source ).must_equal "c + 1"
    end

    it "should handle lambdas" do
      # JS doesn't have Proc objects or source_location
      skip "JS doesn't support Proc source location" if defined? Function
      source = lambda { c + 1 }
      to_js( source ).must_equal "c + 1"
    end
  end

  describe 'regular expressions' do
    it "should handle regular expressions with options" do
      to_js( '/a.*b/im' ).must_equal "/a.*b/im"
    end

    it "should handle %regular expressions" do
      to_js( '%r{/\w+}' ).must_equal "/\\/\\w+/"
      to_js( '%r{/a/b/c/d}' ).must_equal %{new RegExp("/a/b/c/d")}
    end

    it "should handle extended regular expressions" do
      to_js( "/a\nb/x" ).must_equal "/ab/"
    end

    it "should handle regular expressions with interpolation" do
      to_js( '/a#{b}c/i' ).must_equal 'new RegExp(`a${b}c`, "i")'
    end

    it "should map Ruby's Regexp to JavaScript's RegExp" do
      to_js( 'Regexp.new(a)' ).must_equal 'new RegExp(a)'
    end

    it "should map static RegExps to regular expression literals" do
      to_js( 'RegExp.new("a", "g")' ).must_equal '/a/g'
    end

    it "should allow Regexps to be passed on the Regexp constructor" do
      # not allowed by Ruby or JS, but useful for adding JS specific flags
      to_js( "Regexp.new(/a\nb/ix, 'g')" ).must_equal '/ab/ig'
    end

    it "should handle regular expressions tests" do
      to_js( "'abc' =~ /abc/" ).must_equal '/abc/.test("abc")'
    end

    it "should handle regular expressions not tests" do
      to_js( "'abc' !~ /abc/" ).must_equal '!/abc/.test("abc")'
    end

    it "should treat ^ and $ as multiline" do
      to_js( "/^x/" ).must_equal '/^x/m'
      to_js( "/x$/" ).must_equal '/x$/m'
      to_js( "Regexp.new('^$')" ).must_equal '/^$/m'

      to_js( "/^./m" ).must_equal '/^./ms'
      to_js( "/.$/m" ).must_equal '/.$/ms'
      to_js( "Regexp.new('^$', 'm')" ).must_equal '/^$/m'
    end

    it "should treat \A and \z as singleline" do
      to_js( '/\A./' ).must_equal '/^./'
      to_js( '/.\z/' ).must_equal '/.$/'
      to_js( "Regexp.new(#{'\A\z'.inspect})" ).must_equal '/^$/'
    end
  end

  describe "exceptions" do
    it "should handle raise with a string" do
      to_js( 'raise "heck"' ).must_equal 'throw "heck"'
    end

    it "should handle raise with a class and string" do
      to_js( 'raise Exception, "heck"' ).
        must_equal 'throw new Exception("heck")'
    end

    it "should handle raise in expression context" do
      to_js( 'x = a ? b : raise("error")' ).
        must_include '(() => { throw "error" })()'
    end

    it "should handle catching any exception" do
      to_js( 'begin a; rescue => e; b; end' ).
        must_equal 'try {let a} catch (e) {let b}'
    end

    it "catching exceptions without a variable" do
      to_js("begin a; rescue; p $!; end").
        must_equal 'try {let a} catch ($EXCEPTION) {p($EXCEPTION)}'
    end

    it "should handle catching a specific exception" do
      to_js( 'begin a; rescue StandardError => e; b; end' ).
        must_equal 'try {let a} catch (e) {if (e instanceof StandardError) {let b} else {throw e}}'
    end

    it "should handle catching a String" do
      to_js( 'begin a; rescue String => e; b; end' ).
        must_equal 'try {let a} catch (e) {if (typeof e == "string") {let b} else {throw e}}'
    end

    it "catching exceptions with a type but without a variable" do
      to_js("begin a; rescue Foo; end").
        must_equal 'try {let a} catch ($EXCEPTION) {if ($EXCEPTION instanceof Foo) {} else {throw $EXCEPTION}}'
    end

    it "should handle an ensure clause" do
      to_js( 'begin a; ensure b; end' ).
        must_equal 'try {let a} finally {let b}'
    end

    it "should handle catching an exception and an ensure clause" do
      to_js( 'begin a; rescue => e; b; ensure; c; end' ).
        must_equal 'try {let a} catch (e) {let b} finally {let c}'
    end

    it "should handle multiple rescue clauses with different variables" do
      to_js( 'begin; a; rescue FooError => foo; b(foo); rescue BarError => bar; c(bar); end' ).
        must_equal 'try {let a} catch (foo) {if (foo instanceof FooError) {b(foo)} else if (foo instanceof BarError) {var bar = foo; c(bar)} else {throw foo}}'
    end

    it "should handle multiple rescue clauses with mixed variable usage" do
      to_js( 'begin; a; rescue FooError => e; b(e); rescue BarError; c; end' ).
        must_equal 'try {let a} catch (e) {if (e instanceof FooError) {b(e)} else if (e instanceof BarError) {let c} else {throw e}}'
    end

    it "should handle implicit begin in methods" do
      to_js( 'def foo; x(); rescue => e; y(e); end' ).
        must_equal 'function foo() {try {x()} catch (e) {y(e)}}'
    end

    it "should handle implicit ensure in methods" do
      to_js( 'def foo; x(); ensure; y(); end' ).
        must_equal 'function foo() {try {x()} finally {y()}}'
    end

    it "should handle implicit rescue and ensure in methods" do
      to_js( 'def foo; x(); rescue => e; y(e); ensure; z(); end' ).
        must_equal 'function foo() {try {x()} catch (e) {y(e)} finally {z()}}'
    end

    it "should handle retry in rescue block" do
      to_js( 'begin; a; rescue; retry; end' ).
        must_equal 'while (true) {try {let a; break} catch {continue}}'
    end

    it "should handle retry with exception type" do
      to_js( 'begin; a; rescue StandardError; retry; end' ).
        must_equal 'while (true) {try {let a; break} catch ($EXCEPTION) {if ($EXCEPTION instanceof StandardError) {continue} else {throw $EXCEPTION}}}'
    end

    it "should handle neither a rescue nor an ensure being present" do
      to_js( 'begin a; b; end' ).must_equal '{let a; let b}'
    end

    it "should handle else clause in begin/rescue" do
      to_js( 'begin; a; rescue => e; b; else; c; end' ).
        must_equal 'let $no_exception = false; try {let a; $no_exception = true} catch (e) {let b}; if ($no_exception) {let c}'
    end

    it "should handle else clause with ensure" do
      to_js( 'begin; a; rescue; b; else; c; ensure; d; end' ).
        must_equal 'let $no_exception = false; try {let a; $no_exception = true} catch {let b} finally {let d}; if ($no_exception) {let c}'
    end

    it "should hoist variables declared in try that are used in finally" do
      to_js( 'begin; x = 1; rescue; y; ensure; z(x); end', eslevel: 2020 ).
        must_equal '{let x; try {x = 1} catch {let y} finally {z(x)}}'
    end

    it "should not hoist variables already declared" do
      to_js( 'x = 0; begin; x = 1; ensure; z(x); end', eslevel: 2020 ).
        must_equal 'let x = 0; try {x = 1} finally {z(x)}'
    end

    it "should not hoist variables not used in finally" do
      to_js( 'begin; x = 1; ensure; z(); end', eslevel: 2020 ).
        must_equal 'try {let x = 1} finally {z()}'
    end

    it "should handle begin as an expression" do
      to_js( 'z = begin; x = 1; x; end' ).
        must_equal 'let z = (() => {let x = 1; return x})()'
    end
  end

  describe 'execution' do
    it "should handle tic marks" do
      # In JS context, pass an empty object; in Ruby, use binding
      b = defined?(Function) ? {} : binding
      to_js( '`1+2`', binding: b ).must_equal '3'
    end

    it "should handle execute strings" do
      # In JS context, pass an empty object; in Ruby, use binding
      b = defined?(Function) ? {} : binding
      to_js( '%x(3*4)', binding: b ).must_equal '12'
    end

    it "should evaluate variables using the binding" do
      foo = "console.log('hi there')"
      # In JS context, pass object with variable; in Ruby, use binding
      b = defined?(Function) ? {foo: foo} : binding
      to_js( '%x(foo)', binding: b ).must_equal foo
    end
  end

  describe 'ivars' do
    it "should handle ivars" do
      to_js( '@x', ivars: {:@x => {a:1}} ).must_equal '{a: 1}'
      to_js( '@x', ivars: {:@x => %w{a b c}} ).must_equal '["a", "b", "c"]'
      to_js( '@x', ivars: {:@x => 5.1} ).must_equal '5.1'
      to_js( '@x', ivars: {:@x => [true, false, nil]} ).
        must_equal '[true, false, null]'
      # Rational is Ruby-only, skip in JS context
      unless defined? Function
        to_js( '@x', ivars: {:@x => Rational(5,4)} ).must_equal '1'
      end
    end

    it "should not replace ivars in class definitions" do
      to_js( 'class F; def f; @x; end; end', ivars: {:@y => 1} ).
        must_equal 'class F {get f() {return this._x}}'
    end
  end

  describe 'global scope' do
    it "should handle top level constants" do
      to_js("::A").must_equal 'Function("return this")().A'
    end
  end

  describe 'method_missing' do
    it 'should handle method_missing with args' do
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

    it 'should handle method_missing with no args' do
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

  describe 'async/await' do
    it "should handle async named functions" do
      to_js( 'async def f(x); end' ).must_equal 'async function f(x) {}'
    end

    it "should handle async named methods in classes" do
      to_js( 'class F; async def m(x); end; end' ).
        must_include 'class F {async m(x) {}}'
    end

    it "should handle async class methods" do
      to_js( 'class F; async def self.m(x); end; end' ).
        must_equal 'class F {static async m(x) {}}'
    end

    it "should handle async instance methods" do
      to_js( 'async def o.m(x); end' ).
        must_include 'o.m = async function(x) {}'
    end

    it "should handle async lambda functions" do
      to_js( 'async lambda {|x| x}' ).
        must_equal 'async x => x'
      to_js( 'async lambda {|x| x}[]' ).
        must_equal '(async x => x)()'
    end

    it "should handle async procs" do
      to_js( 'async proc {|x| x}' ).
        must_equal 'async x => x'
      to_js( 'async proc {|x| x}[]' ).
        must_equal '(async x => x)()'
    end

    it "should handle async blocks" do
      to_js( 'it "works", async do end' ).
        must_equal 'it("works", async () => {})'
      to_js( 'async {x=1}[]' ).
        must_equal '(async () => {let x = 1})()'
    end

    it "should handle async arrow functions" do
      to_js( 'async -> (x) {x}' ).
        must_equal 'async x => x'
      to_js( 'async -> () {x}[]' ).
        must_equal '(async () => x)()'
    end

    it "should auto bind async methods referenced as properties" do
      to_js('class C; async def m1(x); end; def m2; m1; end; end').
        must_equal 'class C {async m1(x) {}; get m2() {return this.m1.bind(this)}}'
    end

    it "should handle await with simple method calls" do
      to_js( 'await f(x)' ).must_equal 'await f(x)'
    end

    it "should handle await with nested method calls" do
      to_js( 'await o.f(x)' ).must_equal 'await o.f(x)'
    end

    it "should handle await with blocks" do
      to_js( 'await f(x) {|y| y}' ).must_equal 'await f(x, y => y)'
      to_js( 'await f(x) do |y| y; end' ).must_equal 'await f(x, y => y)'
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

    it 'should handle keyword arguments defaulting to undefined in methods' do
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

    it 'should handle rest arguments with keyword arguments in methods' do
      to_js('def a(q, a:, b: 2, **r); end').
        must_equal('function a(q, { a, b=2, ...r }) {}')
    end

    it 'should handle rest arguments with keyword arguments in blocks' do
      to_js('proc {|q, a:, b: 2, **r|}').
        must_equal('(q, { a, b=2, ...r }) => {}')
    end
  end

  describe 'module extensions' do
    it 'should handle methods' do
      to_js('++module M; def m(); end; end').
        must_equal 'Object.assign(M, {m() {}})'
    end
  end
end
