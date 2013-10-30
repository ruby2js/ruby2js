require  File.dirname( __FILE__ ) + '/spec_helper'
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
      to_js( "1" ).should        == '1'
      to_js( "'string'" ).should == '"string"'
      to_js( ":symbol" ).should  == '"symbol"'
      to_js( "nil" ).should      == 'null'
      to_js( "Constant" ).should == 'Constant'
    end
    
    it "should parse simple hash" do
      to_js( "{}" ).should            == '{}'
      to_js( "{ :a => :b }" ).should  == '{"a" : "b"}'
    end
    
    it "should parse array" do
      to_js( "[]" ).should         == '[]'
      to_js( "[1, 2, 3]" ).should  == '[1, 2, 3]'
    end
    
    it "should parse nested hash" do
      to_js( "{ :a => {:b => :c} }" ).should  == '{"a" : {"b" : "c"}}'
    end
    
    it "should parse array" do
      to_js( "[1, [2, 3]]" ).should  == '[1, [2, 3]]'
    end
    
    it "should parse global variables" do
      to_js( "$a = 1" ).should == 'a = 1'
    end
  end
  
  describe 'assign' do
    it "should parse left assign" do
      to_js( "a = 1" ).should        == 'var a = 1'
      to_js( "a = 'string'" ).should == 'var a = "string"'
      to_js( "a = :symbol" ).should  == 'var a = "symbol"'
    end
    
    it "should not output var if variable is allready declared within a context" do
      to_js( "a = 1; a = 2" ).should == 'var a = 1; a = 2'
    end
    
    it "should parse mass assign" do
      to_js( "a , b = 1, 2" ).should == 'var a = 1; var b = 2'
    end
    
    it "should parse" do
      to_js( 'a += 1').should == 'var a = a + 1'
    end
    
    it "should do short circuit assign" do
      to_js( 'a = nil; a ||= 1').should == 'var a = null; a = a || 1'
    end
    
    it "should parse tertiary operator" do
      to_js( 'true ? true : false').should == "if (true) {true} else {false}"
    end
  end
  
  describe 'method call' do
    it "should parse method call with no args" do
      to_js( "a" ).should == 'a()'
    end
    
    it "should parse method call with args" do
      to_js( "a 1, 2, 3" ).should == 'a(1, 2, 3)'
    end
    
    it "should parse lvar as variable call" do
      to_js( "a = 1; a" ).should == 'var a = 1; a'
    end
    
    it "should parse square bracket call" do
      to_js( "a = [1]; a[0]" ).should == 'var a = [1]; a[0]'
    end
    
    it "should parse nested square bracket call" do
      to_js( "a = [[1]]; a[0][0]" ).should == 'var a = [[1]]; a[0][0]'
    end
    
    it "should parse binary operation" do
      to_js( "1 + 1" ).should == '1 + 1'
    end
    
    it "should call method on literal" do
      to_js( "[0][0]" ).should == '[0][0]'
    end
    
    it "should nest arguments as needed" do
      exp = 'a((1 + 2) * 2)'
      to_js( exp ).should == exp
    end
    
    it "should chain method calls" do
      exp = 'a().one().two().three()'
      to_js( exp ).should == exp
    end
  end
  
  describe 'boolean' do
    it "should parse boolean" do
      to_js( "true; false" ).should    == 'true; false'
    end
    
    it "should parse logic operators" do
      to_js( "true && false" ).should  == 'true && false'
      to_js( "true and false" ).should == 'true && false'
      to_js( "true || false" ).should  == 'true || false'
      to_js( "true or false" ).should  == 'true || false'
    end
    
    it "should parse not" do
      to_js( "not true" ).should    == '!true'
    end
    
    it "should parse nested logic" do
      to_js( 'not (true or false)' ).should    == '!(true || false)'
    end
    
    it "should parse more complex nested logic" do
      logic = '!((true && false) || (false || false))'
      to_js( logic ).should == "!(true && false || (false || false))"
    end
    
    it "should parse another nested login example" do
      logic = '!true && true' 
      to_js( logic ).should == logic
    end
    
  end
  
  describe 'expressions' do
    it "should not nest" do
      exp = '1 + 1 * 1'
      to_js( exp ).should == exp
    end
    
    it "should parse nested expressions" do
      exp = '(1 + 1) * 1'
      to_js( exp ).should == exp
    end
    
    it "should parse complex nested expressions" do
      exp = '1 + (1 + (1 + 1 * (2 - 1)))'
      to_js( exp ).should == exp
    end
    
    it "should parse complex nested expressions with method calls" do
      exp = '1 + (a() + (1 + 1 * (b() - d())))'
      to_js( exp ).should == exp
    end
    
    it "should parse complex nested expressions with method calls and variables" do
      exp = 'a = 5; 1 + (a + (1 + a * (b() - d())))'
      to_js( exp ).should == "var " << exp
    end
    
    it "should parse nested sender" do
      exp = '((1 / 2) * 4 - (1 + 1)) - 1'
      to_js( exp ).should == exp
    end
    
    it "should nest arguments as needed" do
      exp = 'a((1 + 2) * 2 - 1)'
      to_js( exp ).should == exp
    end
  end
  
  describe 'string concat' do
    # it "should eval" do
    #   to_js('eval( "hi" )').should == 'eval("hi")'
    # end
    
    it "should parse string " do
      to_js( '"time is #{ Time.now }, say #{ hello }"' ).should == '"time is " + Time.now() + ", say " + hello()'
    end
    
    it "should parse string " do
      to_js( '"time is #{ Time.now }"' ).should == '"time is " + Time.now()'
    end
    
  end
  
  describe 'control' do
    it "should parse single line if" do
      to_js( '1 if true' ).should == 'if (true) {1}'
    end
    
    it "should parse if else" do
      to_js( 'if true; 1; else; 2; end' ).should == 'if (true) {1} else {2}'
    end
    
    it "should parse if elsif" do
      to_js( 'if true; 1; elsif false; 2; else; 3; end' ).should == 'if (true) {1} else if (false) {2} else {3}'
    end
    
    it "should parse if elsif elsif" do
      to_js( 'if true; 1; elsif false; 2; elsif (true or false); 3; else; nassif; end' ).should == 'if (true) {1} else if (false) {2} else if (true || false) {3} else {nassif()}' 
    end
    
    it "should handle basic variable scope" do
      to_js( 'a = 1; if true; a = 2; b = 1; elsif false; a = 3; b = 2; else; a = 4; b =3; end' ).should == 'var a = 1; if (true) {a = 2; var b = 1} else if (false) {a = 3; var b = 2} else {a = 4; var b = 3}'
    end
    
    it "should handle while loop" do
      to_js( 'a = 0; while true; a += 1; end').should == 'var a = 0; while (true) {a = a + 1}'
    end
    
    it "should handle another while loop" do
      to_js( 'a = 0; while true || false; a += 1; end').should == 'var a = 0; while (true || false) {a = a + 1}'
    end
  end
  
  describe 'blocks' do
    it "should parse return" do
      exp = 'return 1'
      to_js( exp ).should == exp
    end
    
    it "should parse proc" do
      to_js('Proc.new {}').should == 'function() {return null}'
    end
    
    it "should parse lambda" do
      to_js( 'lambda {}').should == 'function() {return null}'
    end
    
    it "should handle basic variable scope" do
      to_js( 'a = 1; lambda { a = 2; b = 1}').should == 'var a = 1; function() {a = 2; var b = 1; return b}'
    end
    
    it "should handle one argument" do
      to_js( 'lambda { |a| a + 1 }').should == 'function(a) {return a + 1}'
    end
    
    it "should handle arguments" do
      to_js( 'lambda { |a,b| a + b }').should == 'function(a, b) {return a + b}'
    end
    
    it "should pass functions" do
      to_js( 'run("task"){ |task| do_run task}').should == 'run("task", function(task) {return do_run(task)})'
    end
    
    it "should handle variable scope" do
      to_js('a = 1; lambda {|b| c = 0; a = b - c }; lambda { |b| c = 1; a = b + c }').
        should == 'var a = 1; function(b) {var c = 0; return a = b - c}; function(b) {var c = 1; return a = b + c}'
    end
    
    it "should really handle variable scope" do
      to_js('a, d = 1, 2; lambda {|b| c = 0; a = b - c * d}; lambda { |b| c = 1; a = b + c * d}').
        should == 'var a = 1; var d = 2; function(b) {var c = 0; return a = b - c * d}; function(b) {var c = 1; return a = b + c * d}'
    end
    
    it "should parse with explicit return" do
      to_js('Proc.new {return nil}').should == 'function() {return null}'
    end
  end

  describe 'object definition' do
    it "should parse class" do
      to_js('class Person; end').should == 'function Person() {}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name); @name = name; end; end').should == 'function Person(name) {this._name = name}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name); @name = name; end; def name; @name; end; end').
        should == 'function Person(name) {this._name = name}; Person.prototype.name = function() {return this._name}'
    end
    
    it "should parse class" do
      to_js('class Person; def initialize(name, surname); @name, @surname = name, surname; end; def full_name; @name  + @surname; end; end').
        should == 'function Person(name, surname) {this._name = name; this._surname = surname}; Person.prototype.full_name = function() {return this._name + this._surname}'
    end
    
    it "should parse class" do
      to_js('class Person; attr_accessor :name; def initialize(name); @name = name; end; end').
        should == 'function Person(name) {this._name = name}; Person.prototype.name = function(name) {if (name) {self._name = name} else {self._name}}'
    end
    
    it "should parse metod def" do
      to_js('def method; end').should == 'function method() {return null}'
    end
  end
  
  describe 'method substitutions' do
    # it "should not convert name" do
    #       to_js('a.size').should == 'a().size()'
    #     end
    
    it "should convert size to length" do
      to_js('[].size').should == '[].length()'
    end
    
    it "should convert size to length after assign" do
      to_js('a = []; a.size').should == 'var a = []; a.length()'
    end
    
    it "should convert size to length after several assigns" do
      to_js('a = []; b = a; c = b; d = c; d.size').should == 'var a = []; var b = a; var c = b; var d = c; d.length()'
    end
    
    it "should subtitute << for + for array" do
      to_js('a = []; a << []').should == 'var a = []; a + []'
    end
  end
end