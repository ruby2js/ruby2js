gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/esm'

describe 'Ruby2JS::Filter::Hooks' do
  
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
      to_js( 'class Foo<React; end' ).
        must_equal 'function Foo() {}'
    end

    it "should convert initialize methods to getInitialState" do
      to_js( 'class Foo<React; def initialize(); end; end' ).
        must_include 'function Foo() {}'
    end

    it "should call useState for instance variables" do
      to_js( 'class Foo<React; def foo(); @i=1; end; end' ).
        must_include 'let [i, setI] = React.useState(null)'
      to_js( 'class Foo<React; def initialize(); @i=1; end; end' ).
        must_include 'let [i, setI] = React.useState(1)'
      to_js( 'class Foo<React; def initialize(); @i=1 if @@i; end; end' ).
        must_include 'let [i, setI] = React.useState(null)'
    end

    it "should not autobind event handlers" do
      to_js( 'class Foo<React; def render; _a onClick: handleClick; end; ' + 
        'def handleClick(event); end; end' ).
        must_include '{onClick: handleClick}'
    end

    it "should handle parallel instance variable assignments" do
      to_js( 'class Foo<React; def initialize; @a=@b=1; end; end' ).
        must_include 'let [a, setA] = React.useState(1); ' +
          'let [b, setB] = React.useState(1)'
    end

    it "should handle operator assignments on state values" do
      to_js( 'class Foo<React; def foo(); @a+=1; end; end' ).
        must_include '{setA(a + 1)}'
    end

    it "should handle calls to methods" do
      to_js( 'class Foo<React; def a(); b(); end; def b(); end; end' ).
        must_include '{b()}'
    end

    it "should NOT handle local variables" do
      to_js( 'class Foo<React; def a(); b; end; end' ).
        wont_include 'this.b()'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map instance variables to state" do
      to_js( 'class Foo<React; def method(); @x; end; end' ).
        must_include '{x}'
    end

    it "should map setting instance variables to setState" do
      to_js( 'class Foo<React; def method(); @x=1; end; end' ).
        must_include '{setX(1)}'
    end

    it "should map parallel instance variables to setState" do
      to_js( 'class Foo<React; def method(); @x=@y=1; end; end' ).
        must_include 'setX(setY(1))'
    end

    it "should not create temporary variables for ivars" do
      to_js( 'class Foo<React; def f(); @a+=1; b=@a; end; end' ).
        must_include 'setA(a + 1); let b = a'
    end

    it "should treat singleton method definitions as a separate scope" do
      js = to_js( 'class F < React; def m(); def x.a; @i=1; end; return @i; end; end' )
      js.must_include 'setI(1)'
      js.must_include 'return i'
    end

    it "should generate code to handle instance vars within singleton method" do
      js = to_js('class F < React; def m(); def x.a; @i=1; @i+1; end; end; end')
      js.must_include 'setI(1)'
      js.must_include 'return i + 1'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<React; def method(); @@x; end; end' ).
        must_include 'prop$.x'
    end
  end

  describe "method calls" do
    it "should handle ivars" do
      to_js( 'class Foo<React; def method(); @x.(); end; end' ).
        must_include 'x()'
    end

    it "should handle cvars" do
      to_js( 'class Foo<React; def method(); @@x.(); end; end' ).
        must_include 'prop$.x()'
    end
  end

  describe "controlled components" do
    it "should should automatically create onInput value functions" do
      to_js( 'class Foo<React; def render; _input value: @x; end; end' ).
        must_include 'onChange(event) {setX(event.target.value)}'
    end

    it "should should automatically create onInput checked functions" do
      to_js( 'class Foo<React; def render; _input checked: @x; end; end' ).
        must_include 'onChange() {setX(!x)}'
    end

    it "should should retain onInput functions" do
      to_js( 'class Foo<React; def render; _input checked: @x, onInput: change; end; end' ).
        must_include 'onInput: change'
    end
  end

  describe "props" do
    it "should add props arg to function if needed" do
      to_js( 'class Foo<React; def initialize; @x=@@y; end; end' ).
        must_equal 'function Foo(prop$) {let [x, setX] = React.useState(prop$.y)}'
    end
  end

  describe :autoimports do
    it "should autoimport React" do
      to_esm( 'class Foo<React; end' ).
        must_include 'import React from "react";'
    end

    it "should autoimport Preact" do
      to_esm( 'class Foo<Preact; end' ).
        must_include 'import * as Preact from "preact";'
    end

    it "should autoimport Preact useState" do
      to_esm( 'class Foo<Preact; def initialize; @i=1; end; end' ).
        must_include 'import { useState } from "preact/hooks"'
      to_esm( 'class Foo<Preact; def initialize; @i=1; end; end' ).
        must_include 'let [i, setI] = useState(1)'
    end
  end
end
