require 'minitest/autorun'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::React do
  
  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::React],
      scope: self).to_s)
  end
  
  def to_js6(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::JSX]).to_s)
  end
  
  def to_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::ESM]).to_s)
  end
  
  describe :createClass do
    it "should create classes" do
      to_js( 'class Foo<React; end' ).
        must_equal 'function Foo() {}'
    end

    it "should create methods" do
      to_js( 'class Foo<React; def f(); end; end' ).
        must_include 'function f() {}'
    end

    it "should convert initialize methods to function body" do
      to_js( 'class Foo<React; def initialize(); end; end' ).
        must_equal 'function Foo() {}'
    end

    it "should create useState hooks for state" do
      to_js( 'class Foo<React; def foo(); @i=1; end; end' ).
        must_include 'React.useState'
    end

    it "should define event handlers as functions" do
      to_js( 'class Foo<React; def render; _a onClick: handleClick; end; ' +
        'def handleClick(event); end; end' ).
        must_include 'function handleClick(event) {}'
    end

    it "should initialize state with useState hooks" do
      to_js( 'class Foo<React; def initialize; @a=1; b=2; @b = b; end; end' ).
        must_include 'React.useState'
    end

    it "should collapse instance variable assignments into useState" do
      result = to_js( 'class Foo<React; def initialize; @a=1; @b=2; end; end' )
      result.must_include 'React.useState(1)'
      result.must_include 'React.useState(2)'
    end

    it "should handle parallel instance variable assignments with useState" do
      to_js( 'class Foo<React; def initialize; @a=@b=1; end; end' ).
        must_include 'React.useState(1)'
    end

    it "should handle operator assignments on state values" do
      to_js( 'class Foo<React; def initialize; @a+=1; end; end' ).
        must_include 'setA(a + 1)'
    end

    it "should not use this for method calls in function components" do
      result = to_js( 'class Foo<React; def a(); b(); end; def b(); end; end' )
      result.must_include 'b()'
      result.wont_include 'this.b()'
    end

    it "should NOT handle local variables" do
      to_js( 'class Foo<React; def a(); b; end; def b(); end; end' ).
        wont_include 'this.b()'
    end
  end

  describe "React create element calls" do
    it "should should be able to render using only React.createElement directly" do
      to_js( 'class Foo<React; def render; ' +
        'React.createElement("h1", nil, React.createElement("a", nil, href = ".")); end; end' ).
        must_include 'return React.createElement("h1", null, React.createElement("a", null, href = "."))'
    end
  end

  describe "JSX" do
    it "should wrap list" do
      to_js( 'class Foo<React; def render; %x{<p/><p/>}; end; end' ).
        must_include 'React.createElement(React.Fragment, null, ' + 
          'React.createElement("p"), React.createElement("p"))'
    end

    it "should handle stateless components" do
      to_js( 'Button = ->(x) { %x(<button>{x}</button>)}' ).
        must_equal 'const Button = x => (React.createElement("button", null, x))'
    end
  end

  describe "~refs" do
    it "should handle ~ symbols properties" do
      to_js( 'class Foo<React; def method; ~x.textContent; end; end' ).
        must_include 'this.refs.x.textContent'
    end

    it "should handle ~ lvar properties" do
      to_js( 'class Foo<React; def method; text = ~x.textContent; end; end' ).
        must_include 'text = this.refs.x.textContent'
    end

    it "should handle ~ methods" do
      to_js( 'class Foo<React; def method; ~x.remove(); end; end' ).
        must_include 'this.refs.x.remove()'
    end

    it "should convert ~(expression) to querySelector calls" do
      to_js( 'class Foo<React; def method; ~(x).remove(); end; end' ).
        must_include 'document.querySelector(x).remove()'
    end

    it "should convert ~'a b' to querySelector calls" do
      to_js( 'class Foo<React; def method; ~"a b".remove(); end; end' ).
        must_include 'document.querySelector("a b").remove()'
    end

    it "should convert ~'.a.b_c' to getElementsByClassName calls" do
      to_js( 'class Foo<React; def method; ~".a.b_c".remove(); end; end' ).
        must_include 'document.getElementsByClassName("a b-c")[0].remove()'
    end

    it "should convert ~'#a_b' to getElementById calls" do
      to_js( 'class Foo<React; def method; ~"#a_b".remove(); end; end' ).
        must_include 'document.getElementById("a-b").remove()'
    end

    it "should convert ~'a_b' to getElementsByTagName calls" do
      to_js( 'class Foo<React; def method; ~"a_b".remove(); end; end' ).
        must_include 'document.getElementsByTagName("a-b")[0].remove()'
    end

    it "should leave ~~a alone" do
      to_js( 'class Foo<React; def method; ~~a; end; end' ).
        must_include '~~a'
    end

    it "should convert ~~~a to ~a" do
      to_js( 'class Foo<React; def method; ~~~a; end; end' ).
        must_include '~a'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map global variables to refs" do
      to_js( 'class Foo<React; def method; $x; end; end' ).
        must_include 'refs.x'
    end

    it "should map instance variables to state" do
      to_js( 'class Foo<React; def method; @x; end; end' ).
        must_include 'this.state.x'
    end

    it "should map setting instance variables to setState" do
      to_js( 'class Foo<React; def method; @x=1; end; end' ).
        must_include 'this.setState({x: 1})'
    end

    it "should map parallel instance variables with hooks" do
      to_js( 'class Foo<React; def method(); @x=@y=1; end; end' ).
        must_include 'setX(setY(1))'
    end

    it "should map consecutive instance variables to setState" do
      result = to_js( 'class Foo<React; def method(); @x=1; @y=2; end; end' )
      result.must_include 'setX(1)'
      result.must_include 'setY(2)'
    end

    it "should create temporary variables when needed" do
      to_js6( 'class Foo<React::Component; def f; @a+=1; b=@a; end; end' ).
        must_include 'let $a = this.state.a; $a++; let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should create temporary variables when conditionals are involved" do
      to_js6( 'class Foo<React::Component; def f; @a+=1 if 1; b=@a; end; end' ).
        must_include 'let $a = this.state.a; if (1) {$a++}; let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should create temporary variables when blocks are involved" do
      to_js6( 'class Foo<React::Component; def f; foo {@a=1}; b=@a; end; end' ).
        must_include 'foo(() => (this.setState({a: $a = 1})))'
    end

    it "should create temporary variables when blocks+opasgn are involved" do
      to_js6( 'class Foo<React::Component; def f; foo {@a+=1}; b=@a; end; end' ).
        must_include 'let $a = this.state.a; ' +
          'foo(() => (this.setState({a: ++$a}))); let b = $a; ' +
          'return this.setState({a: $a})'
    end

    it "should treat singleton method definitions as a separate scope" do
      js = to_js( 'class F < React; def m(); def x.a; @i=1; end; @i; end; end' )
      js.must_include 'setI(1)'
      js.must_include '; i}'
    end

    it "should generate code to handle instance vars within singleton method" do
      js = to_js('class F < React; def m(); def x.a; @i=1; @i+1; end; end; end')
      js.must_include 'setI(1)'
      js.must_include 'i + 1'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<React; def method; @@x; end; end' ).
        must_include 'props.x'
    end

    it "should not support assigning to class variables" do
      _(proc {
        to_js( 'class Foo<React; def method; @@x=1; end; end' )
      }).must_raise NotImplementedError
    end
  end

  describe "method calls" do
    it "should handle ivars" do
      to_js( 'class Foo<React; def method; @x.(); end; end' ).
        must_include 'x()'
    end

    it "should handle cvars" do
      to_js( 'class Foo<React; def method; @@x.(); end; end' ).
        must_include 'props.x()'
    end

    it "should handle gvars" do
      to_js( 'class Foo<React; def method; $x.(); end; end' ).
        must_include 'refs.x()'
    end
  end

  describe "react statics" do
    it "should handle static properties" do
      to_js( 'class Foo<React; def self.one; 1; end; end' ).
        must_include 'static get one() {return 1}'
    end

    it "should handle computed static properties" do
      to_js( 'class Foo<React; def self.one; return 1; end; end' ).
        must_include 'static get one() {return 1}'
    end

    it "should handle static methods" do
      to_js( 'class Foo<React; def self.one(); return 1; end; end' ).
        must_include 'static one() {return 1}'
    end
  end

  describe "componentWillReceiveProps" do
    it "should should insert props on calls to componentWillReceiveProps" do
      to_js( 'class Foo<React; def componentWillMount();' +
        'self.componentWillReceiveProps(); end; end' ).
        must_include 'this.componentWillReceiveProps(this.props)'
    end

    it "should should insert props arg on componentWillReceiveProps" do
      to_js( 'class Foo<React; def componentWillReceiveProps();' +
        '@foo = @@foo; end; end' ).
        must_include 'componentWillReceiveProps($$props) {this.setState({foo: $$props.foo})}'
    end

    it "should should use props arg on componentWillReceiveProps" do
      to_js( 'class Foo<React; def componentWillReceiveProps(props);' +
        '@foo = @@foo; end; end' ).
        must_include 'componentWillReceiveProps(props) {this.setState({foo: props.foo})}'
    end
  end

  describe "es6 support" do
    it "should create classes" do
      to_js6( 'class Foo<React::Component; end' ).
        must_equal 'class Foo extends React.Component {}'
    end

    it "should handle contructors" do
      to_js6( 'class Foo<React::Component; def initialize; @x=1; end; end' ).
        must_include 'constructor() {super(); this.state = {x: 1}}'
    end

    it "should add props arg to contructors if needed" do
      to_js6( 'class Foo<React::Component; def initialize; @x=@@y; end; end' ).
        must_include 'constructor(prop$) {super(prop$); this.state = {x: this.props.y}}'
    end

    it "should handle static properties" do
      to_js6( 'class Foo<React; def self.one; 1; end; end' ).
        must_include 'static get one() {return 1}'
    end

    it "should handle calls to getters" do
      result = to_js6( 'class Foo<React; def a(); console.log b; end; def b; end; end' )
      result.must_include 'get b() {'
      result.must_include 'console.log(this.b)'
    end

    it "should handle calls to setters" do
      result = to_js6( 'class Foo<React; def a(); b=1; end; def b=(b); @b=b; end; end' )
      result.must_include 'set b(b) {'
      result.must_include 'this.b = 1'
    end

    it "should not treat lifecycle methods as getters" do
      result = to_js6( 'class Foo<React::Component; def render; _br; end; end' )
      result.must_include 'render() {'
      result.wont_include 'get render() {'
    end
  end

  describe "wunderbar filter/JSX integration" do
    it "should handle simple calls" do
      to_js6( 'class Foo<React::Component; def render; _br; end; end' ).
        must_include 'render() {return <br/>}'
    end

    it "should handle multiple calls" do
      to_js6( 'class Foo<React::Component; def render; _br; _br; end; end' ).
        must_include 'render() {return <><br/><br/></>}'
    end

    it "should not wrap non wunderbar calls" do
      to_js6( 'class Foo<React::Component; def render; x="a"; _p x; end; end' ).
        must_include 'render() {let x = "a"; return <><p>{x}</p></>}}'
    end

    it "should handle if statements" do
      to_js6( 'class Foo<React::Component; def render; _br if @@x; end; end' ).
        must_include '{return <>{this.props.x ? <br/> : null}</>}'
    end

    it "should handle loops" do
      to_js6( 'class Foo<React::Component; def render; _ul {@@x.each {|i| _li i; }}; end; end' ).
        must_include '<ul>{this.props.x.map(i => (<li>{i}</li>))}</ul>'
    end
  end

  describe :autoimports do
    it "should not autoimport React unless ESM is included" do
      to_js6( 'class Foo<React; end' ).
        wont_include 'import React from "react";'
    end

    it "should autoimport React if ESM is included" do
      to_esm( 'class Foo<React; end' ).
        must_include 'import React from "react";'
    end

    it "should not autoimport ReactDOM unless ESM is included" do
      to_js( 'ReactDOM.render _h1("hello world"), document.getElementById("root")' ).
        wont_include 'import ReactDOM from "react-dom";'
    end

    it "should autoimport ReactDOM if ESM is included" do
      to_esm( 'ReactDOM.render _h1("hello world"), document.getElementById("root")' ).
        must_include 'import ReactDOM from "react-dom";'
    end
  end

  describe "pnode conversion" do
    # Helper to convert an AST node directly with React filter active
    def convert_pnode(ast)
      # Use Pipeline which properly applies filters and sets options
      comments = {}
      options = {
        filters: [Ruby2JS::Filter::React],
        react: true
      }
      pipeline = Ruby2JS::Pipeline.new(ast, comments, filters: options[:filters], options: options)
      converter = pipeline.run
      converter.to_s
    end

    # Helper to create AST nodes - use appropriate class based on parser
    def s(type, *children)
      if RUBY2JS_PARSER == :prism
        Ruby2JS::Node.new(type, children)
      else
        Parser::AST::Node.new(type, children)
      end
    end

    it "should convert pnode HTML element to React.createElement" do
      ast = s(:pnode, :div, s(:hash))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("div")'
    end

    it "should convert pnode with class to className" do
      ast = s(:pnode, :div, s(:hash, s(:pair, s(:sym, :class), s(:str, "card"))))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("div"'
      _(result).must_include 'className'
      _(result).must_include '"card"'
    end

    it "should convert pnode with nested children" do
      ast = s(:pnode, :div, s(:hash),
        s(:pnode, :span, s(:hash)))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("div"'
      _(result).must_include 'React.createElement("span"'
    end

    it "should convert pnode component (uppercase) to React.createElement" do
      ast = s(:pnode, :Card, s(:hash))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement(Card)'
    end

    it "should convert pnode component with props" do
      ast = s(:pnode, :Button, s(:hash, s(:pair, s(:sym, :onClick), s(:lvar, :handler))))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement(Button'
      _(result).must_include 'onClick'
    end

    it "should convert pnode custom element (string tag)" do
      ast = s(:pnode, "my-widget", s(:hash))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("my-widget"'
    end

    it "should convert pnode fragment (nil tag)" do
      ast = s(:pnode, nil, s(:hash),
        s(:pnode, :h1, s(:hash)),
        s(:pnode, :p, s(:hash)))
      result = convert_pnode(ast)
      _(result).must_include 'React.Fragment'
      _(result).must_include '"h1"'
      _(result).must_include '"p"'
    end

    it "should convert pnode_text with static text" do
      ast = s(:pnode, :p, s(:hash),
        s(:pnode_text, s(:str, "Hello")))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("p"'
      _(result).must_include '"Hello"'
    end

    it "should convert pnode_text with dynamic content" do
      ast = s(:pnode, :span, s(:hash),
        s(:pnode_text, s(:lvar, :name)))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("span"'
      _(result).must_include 'name'
    end

    it "should convert for attribute to htmlFor" do
      ast = s(:pnode, :label, s(:hash, s(:pair, s(:sym, :for), s(:str, "email"))))
      result = convert_pnode(ast)
      _(result).must_include 'htmlFor'
      _(result).must_include '"email"'
    end

    it "should convert tabindex to tabIndex" do
      ast = s(:pnode, :input, s(:hash, s(:pair, s(:sym, :tabindex), s(:int, 1))))
      result = convert_pnode(ast)
      _(result).must_include 'tabIndex'
      _(result).must_include '1'
    end

    it "should convert data_foo attributes to data-foo" do
      ast = s(:pnode, :div, s(:hash, s(:pair, s(:sym, :data_id), s(:str, "123"))))
      result = convert_pnode(ast)
      _(result).must_include '"data-id"'
      _(result).must_include '"123"'
    end

    it "should handle deeply nested pnodes" do
      ast = s(:pnode, :div, s(:hash),
        s(:pnode, :ul, s(:hash),
          s(:pnode, :li, s(:hash),
            s(:pnode_text, s(:str, "Item 1"))),
          s(:pnode, :li, s(:hash),
            s(:pnode_text, s(:str, "Item 2")))))
      result = convert_pnode(ast)
      _(result).must_include 'React.createElement("div"'
      _(result).must_include 'React.createElement("ul"'
      _(result).must_include 'React.createElement("li"'
      _(result).must_include '"Item 1"'
      _(result).must_include '"Item 2"'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include React" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::React
    end
  end
end
