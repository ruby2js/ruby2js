require 'minitest/autorun'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'

describe 'Ruby2JS::Filter::Preact' do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, scope: self,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::Functions]).to_s)
  end

  def to_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::ESM]).to_s)
  end
  
  describe :createClass do
    it "should create classes" do
      to_js( 'class Foo<Preact::Component; end' ).
        must_equal 'class Foo extends Preact.Component {}'
    end

    it "should create methods" do
      to_js( 'class Foo<Preact; def f(); end; end' ).
        must_include 'f() {}'
    end

    it "should convert initialize methods to getInitialState" do
      to_js( 'class Foo<Preact::Component; def initialize(); end; end' ).
        must_include 'constructor() {super(); this.state = {}}'
    end

    it "should create default getInitialState methods" do
      to_js( 'class Foo<Preact::Component; def foo(); @i=1; end; end' ).
        must_include 'constructor() {super(); this.state = {}}'
    end

    it "should initialize, accumulate, and return state" do
      to_js( 'class Foo<Preact::Component; def initialize; @a=1; b=2; @b = b; end; end' ).
        must_include 'constructor() {super(); this.state = {a: 1}; ' +
          'let b = 2; this.state.b = b}'
    end

    it "should collapse instance variable assignments into a return" do
      to_js( 'class Foo<Preact::Component; def initialize; @a=1; @b=2; end; end' ).
        must_include 'constructor() {super(); this.state = {a: 1, b: 2}}'
    end

    it "should handle parallel instance variable assignments" do
      to_js( 'class Foo<Preact::Component; def initialize; @a=@b=1; end; end' ).
        must_include 'constructor() {super(); this.state = {a: 1, b: 1}}'
    end

    it "should handle operator assignments on state values" do
      to_js( 'class Foo<Preact::Component; def initialize; @a+=1; end; end' ).
        must_include 'super(); this.state = {}; this.state.a++'
    end

    it "should handle calls to methods" do
      to_js( 'class Foo<Preact::Component; def a(); b(); end; def b(); end; end' ).
        must_include 'this.b()'
    end

    it "should NOT handle local variables" do
      to_js( 'class Foo<Preact; def a(); b; end; end' ).
        wont_include 'this.b()'
    end
  end

  describe "Preact create element calls" do
    it "should should be able to render using only h directly" do
      to_js( 'class Foo<Preact; def render; ' +
        'h("h1", nil, h("a", nil, href = ".")); end; end' ).
        must_include 'return Preact.h("h1", null, Preact.h("a", null, href = "."))'
    end

    it "should should be able to render using only Preact.h directly" do
      to_js( 'class Foo<Preact; def render; ' +
        'Preact.h("h1", nil, Preact.h("a", nil, href = ".")); end; end' ).
        must_include 'return Preact.h("h1", null, Preact.h("a", null, href = "."))'
    end
  end

  describe "JSX" do
    it "should wrap list" do
      to_js( 'class Foo<Preact; def render; %x{<p/><p/>}; end; end' ).
        must_include 'Preact.h(Preact.Fragment, null, ' + 
          'Preact.h("p"), Preact.h("p"))'
    end
  end

  describe "~refs" do
    it "should handle ~ symbols properties" do
      to_js( 'class Foo<Preact; def method; ~x.textContent; end; end' ).
        must_include 'this.refs.x.textContent'
    end

    it "should handle ~ lvar properties" do
      to_js( 'class Foo<Preact; def method; text = ~x.textContent; end; end' ).
        must_include 'text = this.refs.x.textContent'
    end

    it "should handle ~ methods" do
      to_js( 'class Foo<Preact; def method; ~x.remove(); end; end' ).
        must_include 'this.refs.x.remove()'
    end

    it "should convert ~(expression) to querySelector calls" do
      to_js( 'class Foo<Preact; def method; ~(x).remove(); end; end' ).
        must_include 'document.querySelector(x).remove()'
    end

    it "should convert ~'a b' to querySelector calls" do
      to_js( 'class Foo<Preact; def method; ~"a b".remove(); end; end' ).
        must_include 'document.querySelector("a b").remove()'
    end

    it "should convert ~'.a.b_c' to getElementsByClassName calls" do
      to_js( 'class Foo<Preact; def method; ~".a.b_c".remove(); end; end' ).
        must_include 'document.getElementsByClassName("a b-c")[0].remove()'
    end

    it "should convert ~'#a_b' to getElementById calls" do
      to_js( 'class Foo<Preact; def method; ~"#a_b".remove(); end; end' ).
        must_include 'document.getElementById("a-b").remove()'
    end

    it "should convert ~'a_b' to getElementsByTagName calls" do
      to_js( 'class Foo<Preact; def method; ~"a_b".remove(); end; end' ).
        must_include 'document.getElementsByTagName("a-b")[0].remove()'
    end

    it "should leave ~~a alone" do
      to_js( 'class Foo<Preact; def method; ~~a; end; end' ).
        must_include '~~a'
    end

    it "should convert ~~~a to ~a" do
      to_js( 'class Foo<Preact; def method; ~~~a; end; end' ).
        must_include '~a'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map global variables to refs" do
      to_js( 'class Foo<Preact; def method; $x; end; end' ).
        must_include 'this.refs.x'
    end

    it "should map instance variables to state" do
      to_js( 'class Foo<Preact::Component; def method; @x; end; end' ).
        must_include 'this.state.x'
    end

    it "should map setting instance variables to setState" do
      to_js( 'class Foo<Preact::Component; def method; @x=1; end; end' ).
        must_include 'this.setState({x: 1})'
    end

    it "should map parallel instance variables to setState" do
      to_js( 'class Foo<Preact::Component; def method(); @x=@y=1; end; end' ).
        must_include 'this.setState({x: 1, y: 1})'
    end

    it "should map consecutive instance variables to setState" do
      to_js( 'class Foo<Preact::Component; def method(); @x=1; @y=2; end; end' ).
        must_include 'this.setState({x: 1, y: 2})'
    end

    it "should create temporary variables when needed" do
      to_js( 'class Foo<Preact::Component; def f; @a+=1; b=@a; end; end' ).
        must_include 'let $a = this.state.a; $a++; let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should create temporary variables when conditionals are involved" do
      to_js( 'class Foo<Preact::Component; def f; @a+=1 if 1; b=@a; end; end' ).
        must_include 'let $a = this.state.a; if (1) {$a++}; let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should create temporary variables when blocks are involved" do
      to_js( 'class Foo<Preact::Component; def f; foo {@a=1}; b=@a; end; end' ).
        must_include 'foo(() => (this.setState({a: $a = 1}))); '
          'let b = $a; return this.setState({a: $a})'
    end

    it "should create temporary variables when blocks+opasgn are involved" do
      to_js( 'class Foo<Preact::Component; def f; foo {@a+=1}; b=@a; end; end' ).
        must_include 'let $a = this.state.a; ' +
          'foo(() => (this.setState({a: ++$a}))); let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should treat singleton method definitions as a separate scope" do
      js = to_js( 'class F < Preact::Component; def m(); def x.a; @i=1; end; @i; end; end' )
      js.must_include 'this.setState({i: 1})'
      js.must_include 'this.state.i'
    end

    it "should generate code to handle instance vars within singleton method" do
      js = to_js('class F < Preact::Component; def m(); def x.a; @i=1; @i+1; end; end; end')
      js.must_include '$i = 1'
      js.must_include '$i + 1'
      js.must_include 'this.setState({i: $i}'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<Preact; def method; @@x; end; end' ).
        must_include 'this.props.x'
    end

    it "should not support assigning to class variables" do
      _(proc { 
        to_js( 'class Foo<Preact; def method; @@x=1; end; end' )
      }).must_raise NotImplementedError
    end
  end

  describe "method calls" do
    it "should handle ivars" do
      to_js( 'class Foo<Preact::Component; def method; @x.(); end; end' ).
        must_include 'this.state.x()'
    end

    it "should handle cvars" do
      to_js( 'class Foo<Preact; def method; @@x.(); end; end' ).
        must_include 'this.props.x()'
    end

    it "should handle gvars" do
      to_js( 'class Foo<Preact; def method; $x.(); end; end' ).
        must_include 'this.refs.x()'
    end
  end

  describe "preact statics" do
    it "should handle static properties" do
      to_js( 'class Foo<Preact; def self.one; 1; end; end' ).
        must_include '{static get one() {return 1}}'
    end

    it "should handle computed static properties" do
      to_js( 'class Foo<Preact; def self.one; return 1; end; end' ).
        must_include '{static get one() {return 1}}'
    end

    it "should handle static methods" do
      to_js( 'class Foo<Preact; def self.one(); return 1; end; end' ).
        must_include '{static one() {return 1}}'
    end
  end

  describe "componentWillReceiveProps" do
    it "should should insert props on calls to componentWillReceiveProps" do
      to_js( 'class Foo<Preact; def componentWillMount();' +
        'self.componentWillReceiveProps(); end; end' ).
        must_include 'this.componentWillReceiveProps(this.props)'
    end

    it "should should insert props arg on componentWillReceiveProps" do
      to_js( 'class Foo<Preact; def componentWillReceiveProps();' +
        '@foo = @@foo; end; end' ).
        must_include 'componentWillReceiveProps($$props) {this.setState({foo: $$props.foo})}'
    end

    it "should should use props arg on componentWillReceiveProps" do
      to_js( 'class Foo<Preact; def componentWillReceiveProps(props);' +
        '@foo = @@foo; end; end' ).
        must_include 'componentWillReceiveProps(props) {this.setState({foo: props.foo})}'
    end
  end

  describe "es6 support" do
    it "should create classes" do
      to_js( 'class Foo<Preact::Component; end' ).
        must_equal 'class Foo extends Preact.Component {}'
    end

    it "should handle contructors" do
      to_js( 'class Foo<Preact::Component; def initialize; @x=1; end; end' ).
        must_include 'constructor() {super(); this.state = {x: 1}}'
    end

    it "should add props arg to contructors if needed" do
      to_js( 'class Foo<Preact::Component; def initialize; @x=@@y; end; end' ).
        must_include 'constructor(prop$) {super(prop$); this.state = {x: this.props.y}}'
    end

    it "should handle static properties" do
      to_js( 'class Foo<Preact; def self.one; 1; end; end' ).
        must_include 'static get one() {return 1}'
    end

    it "should handle calls to getters" do
      result = to_js( 'class Foo<Preact; def a(); console.log b; end; def b; end; end' )
      result.must_include 'get b() {'
      result.must_include 'console.log(this.b)'
    end

    it "should handle calls to setters" do
      result = to_js( 'class Foo<Preact; def a(); b=1; end; def b=(b); @b=b; end; end' )
      result.must_include 'set b(b) {'
      result.must_include 'this.b = 1'
    end

  end

  describe :autoimports do
    it "should not autoimport Preact unless ESM is included" do
      to_js( 'class Foo<Preact; end' ).
        wont_include 'import * as Preact from "preact";'
    end

    it "should autoimport Preact if ESM is included" do
      to_esm( 'class Foo<Preact; end' ).
        must_include 'import * as Preact from "preact";'
    end

  end
end
