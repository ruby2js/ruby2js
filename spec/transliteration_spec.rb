require 'minitest/autorun'
require 'ruby2js'
require 'ruby_parser'

describe Ruby2JS do
  
  def rb_parse( string )
    RubyParser.new.parse string
  end
  
  def to_js( string)
    Ruby2JS.new( rb_parse( string ) ).to_js
  end
  
  describe 'literals' do
    it "should parse literals and strings" do
      to_js( "1" ).must_equal '1'
      to_js( "'string'" ).must_equal '"string"'
      to_js( ":symbol" ).must_equal '"symbol"'
      to_js( "nil" ).must_equal 'null'
      to_js( "Constant" ).must_equal 'Constant'
    end
    
    it "should parse simple hash" do
      to_js( "{}" ).must_equal '{}'
      to_js( "{ :a => :b }" ).must_equal '{"a" : "b"}'
    end
    
    it "should parse array" do
      to_js( "[]" ).must_equal '[]'
      to_js( "[1, 2, 3]" ).must_equal '[1, 2, 3]'
    end
    
    it "should parse nested hash" do
      to_js( "{ :a => {:b => :c} }" ).must_equal '{"a" : {"b" : "c"}}'
    end
    
    it "should parse array" do
      to_js( "[1, [2, 3]]" ).must_equal '[1, [2, 3]]'
    end
    
    it "should parse global variables" do
      to_js( "$a = 1" ).must_equal 'a = 1'
    end
  end
  
  describe 'assign' do
    it "should parse left assign" do
      to_js( "a = 1" ).must_equal 'var a = 1'
      to_js( "a = 'string'" ).must_equal 'var a = "string"'
      to_js( "a = :symbol" ).must_equal 'var a = "symbol"'
    end

    it "should parse constant assign" do
      to_js( "PI = 3.14159" ).must_equal 'const PI = 3.14159'
    end

    it "should not output var if variable is allready declared within a context" do
      to_js( "a = 1; a = 2" ).must_equal 'var a = 1; a = 2'
    end
    
    it "should parse mass assign" do
      to_js( "a , b = 1, 2" ).must_equal 'var a = 1; var b = 2'
      to_js( "a = 1, 2" ).must_equal 'var a = [1, 2]'
    end
    
    it "should parse" do
      to_js( 'a += 1').must_equal 'var a = a + 1'
    end
    
    it "should do short circuit assign" do
      to_js( 'a = nil; a ||= 1').must_equal 'var a = null; a = a || 1'
    end
    
    it "should parse tertiary operator" do
      to_js( 'true ? true : false').must_equal "if (true) {true} else {false}"
    end
  end
  
  describe 'method call' do
    it "should parse method call with no args" do
      to_js( "a" ).must_equal 'a()'
    end
    
    it "should parse method call with args" do
      to_js( "a 1, 2, 3" ).must_equal 'a(1, 2, 3)'
    end
    
    it "should parse lvar as variable call" do
      to_js( "a = 1; a" ).must_equal 'var a = 1; a'
    end
    
    it "should parse square bracket call" do
      to_js( "a = [1]; a[0]" ).must_equal 'var a = [1]; a[0]'
    end
    
    it "should parse nested square bracket call" do
      to_js( "a = [[1]]; a[0][0]" ).must_equal 'var a = [[1]]; a[0][0]'
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
  end
  
  describe 'boolean' do
    it "should parse boolean" do
      to_js( "true; false" ).must_equal 'true; false'
    end
    
    it "should parse logic operators" do
      to_js( "true && false" ).must_equal 'true && false'
      to_js( "true and false" ).must_equal 'true && false'
      to_js( "true || false" ).must_equal 'true || false'
      to_js( "true or false" ).must_equal 'true || false'
    end
    
    it "should parse not" do
      to_js( "not true" ).must_equal '!true'
    end
    
    it "should parse nested logic" do
      to_js( 'not (true or false)' ).must_equal '!(true || false)'
    end
    
    it "should parse more complex nested logic" do
      logic = '!((true && false) || (false || false))'
      to_js( logic ).must_equal "!(true && false || (false || false))"
    end
    
    it "should parse another nested login example" do
      logic = '!true && true' 
      to_js( logic ).must_equal logic
    end
    
  end
  
  describe 'expressions' do
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
      to_js( exp ).must_equal "var " << exp
    end
    
    it "should parse nested sender" do
      exp = '((1 / 2) * 4 - (1 + 1)) - 1'
      to_js( exp ).must_equal exp
    end
    
    it "should nest arguments as needed" do
      exp = 'a((1 + 2) * 2 - 1)'
      to_js( exp ).must_equal exp
    end
  end
  
  describe 'string concat' do
    # it "should eval" do
    #   to_js('eval( "hi" )').must_equal 'eval("hi")'
    # end
    
    it "should parse string " do
      to_js( '"time is #{ Time.now }, say #{ hello }"' ).must_equal '"time is " + Time.now() + ", say " + hello()'
    end
    
    it "should parse string " do
      to_js( '"time is #{ Time.now }"' ).must_equal '"time is " + Time.now()'
    end
    
  end
  
  describe 'control' do
    it "should parse single line if" do
      to_js( '1 if true' ).must_equal 'if (true) {1}'
    end
    
    it "should parse if else" do
      to_js( 'if true; 1; else; 2; end' ).must_equal 'if (true) {1} else {2}'
    end
    
    it "should parse if elsif" do
      to_js( 'if true; 1; elsif false; 2; else; 3; end' ).must_equal 'if (true) {1} else if (false) {2} else {3}'
    end
    
    it "should parse if elsif elsif" do
      to_js( 'if true; 1; elsif false; 2; elsif (true or false); 3; else; nassif; end' ).must_equal 'if (true) {1} else if (false) {2} else if (true || false) {3} else {nassif()}' 
    end
    
    it "should handle basic variable scope" do
      to_js( 'a = 1; if true; a = 2; b = 1; elsif false; a = 3; b = 2; else; a = 4; b =3; end' ).must_equal 'var a = 1; if (true) {a = 2; var b = 1} else if (false) {a = 3; var b = 2} else {a = 4; var b = 3}'
    end
    
    it "should handle while loop" do
      to_js( 'a = 0; while true; a += 1; end').must_equal 'var a = 0; while (true) {a = a + 1}'
    end
    
    it "should handle another while loop" do
      to_js( 'a = 0; while true || false; a += 1; end').must_equal 'var a = 0; while (true || false) {a = a + 1}'
    end
  end
  
  describe 'blocks' do
    it "should parse return" do
      exp = 'return 1'
      to_js( exp ).must_equal exp
    end
    
    it "should parse proc" do
      to_js('Proc.new {}').must_equal 'function() {return null}'
    end
    
    it "should parse lambda" do
      to_js( 'lambda {}').must_equal 'function() {return null}'
    end
    
    it "should handle basic variable scope" do
      to_js( 'a = 1; lambda { a = 2; b = 1}').must_equal 'var a = 1; function() {a = 2; var b = 1; return b}'
    end
    
    it "should handle one argument" do
      to_js( 'lambda { |a| a + 1 }').must_equal 'function(a) {return a + 1}'
    end
    
    it "should handle arguments" do
      to_js( 'lambda { |a,b| a + b }').must_equal 'function(a, b) {return a + b}'
    end
    
    it "should pass functions" do
      to_js( 'run("task"){ |task| do_run task}').must_equal 'run("task", function(task) {return do_run(task)})'
    end
    
    it "should handle variable scope" do
      to_js('a = 1; lambda {|b| c = 0; a = b - c }; lambda { |b| c = 1; a = b + c }').
        must_equal 'var a = 1; function(b) {var c = 0; return a = b - c}; function(b) {var c = 1; return a = b + c}'
    end
    
    it "should really handle variable scope" do
      to_js('a, d = 1, 2; lambda {|b| c = 0; a = b - c * d}; lambda { |b| c = 1; a = b + c * d}').
        must_equal 'var a = 1; var d = 2; function(b) {var c = 0; return a = b - c * d}; function(b) {var c = 1; return a = b + c * d}'
    end
    
    it "should parse with explicit return" do
      to_js('Proc.new {return nil}').must_equal 'function() {return null}'
    end
  end

  describe 'object definition' do
    it "should parse class" do
      to_js('class Person; end').must_equal 'function Person() {}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name); @name = name; end; end').must_equal 'function Person(name) {this._name = name}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; end').
        must_equal 'function Person(name) {this._name = name}; Person.prototype.name = function() {return this._name}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name, surname); @name, @surname = name, surname; end; def full_name; @name  + @surname; end; end').
        must_equal 'function Person(name, surname) {this._name = name; this._surname = surname}; Person.prototype.full_name = function() {return this._name + this._surname}'
    end
    
    it "should parse class" do
      to_js('class Person; attr_accessor :name; def initialize(name); @name = name; end; end').
        must_equal 'function Person(name) {this._name = name}; Person.prototype.name = function(name) {if (name) {self._name = name} else {self._name}}'
    end
    
    it "should parse method def" do
      to_js('def method; end').must_equal 'function method() {return null}'
    end
  end
  
  describe 'attribute access' do
    it "should support attribute assignments" do
      to_js('x={}; x.a="y"').must_equal 'var x = {}; x.a = "y"'
    end
  end
  
  describe 'method substitutions' do
    # it "should not convert name" do
    #       to_js('a.size').must_equal 'a().size()'
    #     end
    
    it "should convert size to length" do
      to_js('[].size').must_equal '[].length()'
    end
    
    it "should convert size to length after assign" do
      to_js('a = []; a.size').must_equal 'var a = []; a.length()'
    end
    
    it "should convert size to length after several assigns" do
      to_js('a = []; b = a; c = b; d = c; d.size').must_equal 'var a = []; var b = a; var c = b; var d = c; d.length()'
    end
    
    it "should subtitute << for + for array" do
      to_js('a = []; a << []').must_equal 'var a = []; a + []'
    end
  end
end
