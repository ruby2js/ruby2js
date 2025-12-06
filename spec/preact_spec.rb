gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/esm'

describe 'Ruby2JS::Filter::Preact' do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, scope: self,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::Functions]).to_s)
  end
  
  def to_jsx(string)
    _(Ruby2JS.convert(string, eslevel: 2015, scope: self,
      filters: [Ruby2JS::Filter::React, Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::JSX]).to_s)
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

    it "should autobind event handlers" do
      to_js( 'class Foo<Preact::Component; def render; _a onClick: handleClick; end; ' + 
        'def handleClick(event); end; end' ).
        must_include 'onClick: this.handleClick.bind(this)'
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

  describe "Wunderbar/JSX processing" do
    it "should create elements for HTML tags" do
      to_js( 'class Foo<Preact; def render; _a; end; end' ).
        must_include 'return Preact.h("a")'
    end

    it "should create elements for Preact Components" do
      to_js( 'class Foo<Preact; def render; _A; end; end' ).
        must_include 'return Preact.h(A)'
    end

    it "should create elements with attributes and text" do
      to_js( 'class Foo<Preact; def render; _a "name", href: "link"; end; end' ).
        must_include 'return Preact.h("a", {href: "link"}, "name")}'
    end

    it "should create simple nested elements" do
      to_js( 'class Foo<Preact; def render; _a {_b}; end; end' ).
        must_include ' Preact.h("a", null, Preact.h("b"))'
    end

    it "should handle options with blocks" do
      to_js( 'class Foo<Preact; def render; _a options do _b; end; end; end' ).
        must_include ' Preact.h("a", options, Preact.h("b"))'
    end

    unless RUBY_VERSION =~ /^1/
      it "should handle **options" do
        to_js( 'class Foo<Preact; def render; _a **options; end; end' ).
          must_include ' Preact.h("a", options)'
      end

      it "should handle **options with blocks" do
        to_js('class Foo<Preact; def render; _a **options do _b; end; end; end').
          must_include ' Preact.h("a", options, Preact.h("b"))'
      end
    end

    it "should create complex nested elements" do
      result = to_js('class Foo<Preact; def render; _a {c="c"; _b c}; end; end')

      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["a", null];'
      result.must_include '$_.push(Preact.h("b", null, c));'
      result.must_include 'return $_'
      result.must_include '})())'
    end

    it "should treat explicit calls to Preact.h as simple" do
      to_js( 'class Foo<Preact; def render; _a {h("b")}; end; end' ).
        must_include ' Preact.h("a", null, Preact.h("b"))'

      to_js( 'class Foo<Preact; def render; _a {Preact.h("b")}; end; end' ).
        must_include ' Preact.h("a", null, Preact.h("b"))'
    end

    it "should push results of explicit calls to h" do
      result = to_js('class Foo<Preact; def render; _a {c="c"; ' +
        'h("b", null, c)}; end; end')

      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["a", null];'
      result.must_include '$_.push(Preact.h("b", null, c));'
      result.must_include 'return $_'
      result.must_include '})())'
    end

    it "should push results of explicit calls to Preact.h" do
      result = to_js('class Foo<Preact; def render; _a {c="c"; ' +
        'Preact.h("b", null, c)}; end; end')

      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["a", null];'
      result.must_include '$_.push(Preact.h("b", null, c));'
      result.must_include 'return $_'
      result.must_include '})())'
    end

    it "should handle call with blocks to h" do
      result = to_js( 'class Foo<Preact; def render; h("a") {_b}; end; end' )
      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["a"];'
      result.must_include '$_.push(Preact.h("b")'
    end

    it "should handle call with blocks to Preact.h" do
      result = to_js( 'class Foo<Preact; def render; ' +
        'Preact.h("a") {_b}; end; end' )
      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["a"];'
      result.must_include '$_.push(Preact.h("b")'
    end

    it "should iterate" do
      # single element each iteration
      result = to_js('class Foo<Preact; def render; _ul list ' + 
        'do |i| _li i; end; end; end')

      result.must_include 'Preact.h("ul", null,'
      result.must_include 'list.map(i => ('
      result.must_include 'Preact.h("li", null, i)))'

      # multiple elements each iteration
      result = to_js('class Foo<Preact; def render; _dl list ' + 
        'do |i| _dt i.term; _dd i.defn; end; end; end')

      result.must_include 'Preact.h(...(() => {'
      result.must_include 'let $_ = ["dl", null];'
      result.must_include 'list.forEach((i) => {'
      result.must_include '$_.push(Preact.h("dt", null, i.term))'
      result.must_include '$_.push(Preact.h("dd", null, i.defn))'
      result.must_include 'return $_'
      result.must_include '})())'
    end

    it "should iterate with markaby style classes/ids" do
      # single element each iteration
      result = to_js('class Foo<Preact; def render; _ul.todos list ' + 
        'do |i| _li i; end; end; end')

      result.must_include 'Preact.h("ul", {class: "todos"},'
      result.must_include 'list.map(i => ('
      result.must_include 'Preact.h("li", null, i)'

      # multiple elements each iteration
      result = to_js('class Foo<Preact; def render; _dl.terms list ' + 
        'do |i| _dt i.term; _dd i.defn; end; end; end')

      result.must_include 'return Preact.h(...(() => {'
      result.must_include 'let $_ = ["dl", {class: "terms"}];'
      result.must_include 'list.forEach((i) =>'
      result.must_include '$_.push(Preact.h("dt", null, i.term))'
      result.must_include '$_.push(Preact.h("dd", null, i.defn))'
      result.must_include 'return $_'
      result.must_include '})())}'
    end

    it "should handle text nodes" do
      to_js( 'class Foo<Preact::Component; def render; _a {_ @text}; end; end' ).
        must_include 'return Preact.h("a", null, this.state.text)'
    end

    it "should apply text nodes" do
      to_js( 'class Foo<Preact; def render; _a {text="hi"; _ text}; end; end' ).
        must_include 'let text = "hi"; $_.push(text);'
    end

    it "should handle arbitrary nodes" do
      to_js( 'class Foo<Preact::Component; def render; _a {_[@text]}; end; end' ).
        must_include 'return Preact.h("a", null, this.state.text)'
    end

    it "should handle lists of arbitrary nodes" do
      to_js( 'class Foo<Preact::Component; def render; _a {_[@text, @text]}; end; end' ).
        must_include 'return Preact.h(' +
          '"a", null, ...[this.state.text, this.state.text])'
    end

    it "should apply arbitrary nodes" do
      to_js( 'class Foo<Preact; def render; _a {text="hi"; _[text]}; end; end' ).
        must_include 'let text = "hi"; $_.push(text);'
    end

    it "should apply list of arbitrary nodes" do
      to_js( 'class Foo<Preact; def render; _a {text="hi"; _[text, text]}; end; end' ).
        must_include 'let text = "hi"; $_.push(text, text);'
    end
  end

  describe "JSX" do
    it "should wrap list" do
      to_js( 'class Foo<Preact; def render; %x{<p/><p/>}; end; end' ).
        must_include 'Preact.h(Preact.Fragment, null, ' + 
          'Preact.h("p"), Preact.h("p"))'
    end
  end

  describe "render method" do
    it "should wrap multiple elements with a Fragment" do
      result = to_js( 'class Foo<Preact; def render; _h1 "a"; _p "b"; end; end' )
      result.must_include 'return Preact.h(Preact.Fragment, null, '
      result.must_include ', Preact.h("h1", null, "a"),'
      result.must_include ', Preact.h("p", null, "b"))}'
    end

    it "should wrap anything that is not a method or block call with a span" do
      result = to_js( 'class Foo<Preact; def render; if @a; _p "a"; else;_p "b"; end; end;end' )
      result.must_include 'return Preact.h(...(() => {'
      result.must_include 'push(Preact.h("p", null, "a"))} else {'
      result.must_include 'push(Preact.h("p", null, "b"))};'
    end
  end

  describe "class attributes" do
    it "should handle class attributes" do
      to_js( 'class Foo<Preact; def render; _a class: "b"; end; end' ).
        must_include 'Preact.h("a", {class: "b"})'
    end

    it "should handle className attributes" do
      to_js( 'class Foo<Preact; def render; _a className: "b"; end; end' ).
        must_include 'Preact.h("a", {class: "b"})'
    end

    it "should handle markaby syntax" do
      to_js( 'class Foo<Preact; def render; _a.b.c href: "d"; end; end' ).
        must_include 'Preact.h("a", {class: "b c", href: "d"})'
    end

    it "should handle mixed strings" do
      to_js( 'class Foo<Preact; def render; _a.b class: "c"; end; end' ).
        must_include 'Preact.h("a", {class: "b c"})'
    end

    it "should handle mixed strings and a value" do
      to_js( 'class Foo<Preact; def render; _a.b class: c; end; end' ).
        must_include 'Preact.h("a", {class: "b " + (c ?? "")})'
    end

    it "should handle mixed strings and a conditional value" do
      to_js( 'class Foo<Preact; def render; _a.b class: ("c" if d); end; end' ).
        must_include 'Preact.h("a", {class: "b " + (d ? "c" : "")})'
    end

    it "should handle only a value" do
      to_js( 'class Foo<Preact; def render; _a class: c; end; end' ).
        must_include 'Preact.h("a", {class: c})'
    end

    it "should handle a constant string" do
      to_js( 'class Foo<Preact; def render; _a class: "x"; end; end' ).
        must_include 'Preact.h("a", {class: "x"})'
    end
  end

  describe "other attributes" do
    it "should handle markaby syntax ids" do
      to_js( 'class Foo<Preact; def render; _a.b! href: "c"; end; end' ).
        must_include 'Preact.h("a", {id: "b", href: "c"})'
    end

    it "should map htmlFor attributes to for" do
      to_js( 'class Foo<Preact; def render; _a htmlFor: "b"; end; end' ).
        must_include 'Preact.h("a", {for: "b"})'
    end

    it "should map leave for attributes alone" do
      to_js( 'class Foo<Preact; def render; _a for: "b"; end; end' ).
        must_include 'Preact.h("a", {for: "b"})'
    end

    it "should NOT map case insensitive attributes to javascript properties" do
      to_js( 'class Foo<Preact; def render; _input tabindex: 1; end; end' ).
        must_include 'Preact.h("input", {tabindex: 1})'
    end

    it "should map tabIndex attributes to tabindex" do
      to_js( 'class Foo<Preact; def render; _svg tabIndex: 0; end; end' ).
        must_include 'Preact.h("svg", {tabindex: 0})'
    end

    it "should map input onChange attributes to onInput" do
      to_js( 'class Foo<Preact; def render; _input onChange: foo; end; end' ).
        must_include 'Preact.h("input", {onInput: foo})'
    end

    it "should map style string attributes to hashes" do
      to_js( 'class Foo<Preact; def render; _a ' +
        'style: "color: blue; margin-top: 0"; end; end' ).
        must_include '{style: {color: "blue", marginTop: 0}}'
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

    it "shouldn't produce temporary variables for inline event handlers" do
      js = to_js( 'class F < Preact::Component; def render; _input value: @draft; ' +
        '_button "Cancel", onClick:-> {@draft = @base}; ' +
        '_button "Save", disabled: @draft == @base; end; end' )
      js.must_include 'this.setState({draft: event.target.value})'
      js.must_include '{onClick: () => ' +
        'this.setState({draft: this.state.base})}'
      js.must_include '{disabled: this.state.draft == this.state.base}'
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

  describe 'preact calls' do
    it 'should create elements' do
      to_js( 'Preact.render _Element, document.getElementById("sidebar")' ).
        must_include 'Preact.h(Element)'
    end

    it 'should substitute scope instance variables / props' do
      @data = 5
      to_js( "Preact.render _Element(data: @data),
        document.getElementById('sidebar')" ).
        must_include 'Preact.h(Element, {data: 5})'
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

  describe "controlled components" do
    it "should should automatically create onInput value functions" do
      to_js( 'class Foo<Preact::Component; def render; _input value: @x; end; end' ).
        must_include 'onInput: event => this.setState({x: event.target.value})'
    end

    it "should should automatically create onInput checked functions" do
      to_js( 'class Foo<Preact::Component; def render; _input checked: @x; end; end' ).
        must_include 'onInput: () => this.setState({x: !this.state.x})'
    end

    it "should should retain onInput functions" do
      to_js( 'class Foo<Preact; def render; _input checked: @x, onInput: self.change; end; end' ).
        must_include 'onInput: this.change'
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

    it "should not treat lifecycle methods as getters" do
      result = to_js( 'class Foo<Preact::Component; def render; _br; end; end' )
      result.must_include 'render() {'
      result.wont_include 'get render() {'
    end
  end

  describe "wunderbar filter/JSX integration" do
    it "should handle simple calls" do
      to_jsx( 'class Foo<Preact::Component; def render; _br; end; end' ).
        must_include 'render() {return <br/>}'
    end

    it "should handle multiple calls" do
      to_jsx( 'class Foo<Preact::Component; def render; _br; _br; end; end' ).
        must_include 'render() {return <><br/><br/></>}'
    end

    it "should not wrap non wunderbar calls" do
      to_jsx( 'class Foo<Preact::Component; def render; x="a"; _p x; end; end' ).
        must_include 'render() {let x = "a"; return <><p>{x}</p></>}}'
    end

    it "should handle if statements" do
      to_jsx( 'class Foo<Preact::Component; def render; _br if @@x; end; end' ).
        must_include '{return <>{this.props.x ? <br/> : null}</>}'
    end

    it "should handle loops" do
      to_jsx( 'class Foo<Preact::Component; def render; _ul {@@x.each {|i| _li i; }}; end; end' ).
        must_include '<ul>{this.props.x.map(i => (<li>{i}</li>))}</ul>'
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

    it "should not autoimport Preact unless ESM is included" do
      to_js( 'Preact.render _h1("hello world"), document.getElementById("root")' ).
        wont_include 'import * as Preact from "preact";'
    end

    it "should autoimport Preact if ESM is included" do
      to_esm( 'Preact.render _h1("hello world"), document.getElementById("root")' ).
        must_include 'import * as Preact from "preact";'
    end
  end
end
