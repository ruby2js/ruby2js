gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/wunderbar'

describe Ruby2JS::Filter::ESM do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::ESM, Ruby2JS::Filter::React,
      Ruby2JS::Filter::Functions, Ruby2JS::Filter::Wunderbar],
      scope: self).to_s)
  end
  
  describe "Wunderbar/JSX processing" do
    it "should create elements for HTML tags" do
      js = to_js( 'class Foo<React; def render; _X; end; end' )
      js.must_include 'import X from "./x.js"'
      js.must_include 'import React from "react"'
      js.must_include 'export default Foo'
    end
  end

  describe "const processing" do
    it "should create elements for HTML tags" do
      js = to_js( 'C=1; A=[B, C, D]; Object.is(1,1)' )
      js.wont_include 'import A'
      js.must_include 'import B from "./b.js"'
      js.wont_include 'import C'
      js.must_include 'import D from "./d.js"'
      js.wont_include 'import Object'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ESM" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::ESM
    end
  end
end
