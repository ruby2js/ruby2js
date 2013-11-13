require 'minitest/autorun'
require 'ruby2js'

describe 'not implemented' do
  # see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md
  
  def todo(string)
    proc { Ruby2JS.convert(string, filters: []) }.must_raise NotImplementedError
  end

  it "execute-string" do
    todo( '`echo hi`' )
  end

  it "range inclusive" do
    todo( '1..2' )
  end

  it "range exclusive" do
    todo( '1...2' )
  end

  it "Top-level constant" do
    todo( '::Foo' )
  end

  it "module" do
    todo( 'module Foo; end' )
  end

  it "alias" do
    todo( 'alias foo bar' )
  end

  it "optional arguments" do
    # TODO: if (typeof arg === "undefined") arg = value;
    todo( 'def f(x=1); return x; end' )
  end

  it "shadow arguments" do
    todo(' proc {|;a|} ')
  end

  it "decomposition" do
    todo( 'def f(a, (foo, *bar)); end' )
  end

  it "super" do
    todo( 'super()' )
    todo( 'super' )
  end

  it "yield" do
    todo( 'yield' )
  end

  it "case" do
    # TODO: switch
    todo("case a; when 1; nil; else nil; end")
  end

  it "until" do
    # TODO: while !
    todo("1 until false")
  end

  it "while with post condition" do
    # TODO: do while
    todo("begin; foo; end while condition")
  end

  it "until with post condition" do
    # TODO: do while !
    todo("begin; foo; end until condition")
  end

  it "catching exceptions" do
    # TODO: try catch
    todo("begin; rescue Exception; end")
  end

  it "redo" do
    todo("redo")
  end

  it "ensure" do
    todo("begin; ensure; end")
  end

  it "retry" do
    todo("retry")
  end

  it "flip-flops" do
    todo("if a..b; end")
  end

  it "implicit matches" do
    todo("if /a/; end")
  end

  unless RUBY_VERSION =~ /^1/
    it "keyword splat" do
      todo( 'foo **bar' )
    end

    it "keyword splat interpolation" do
      todo( '{ foo: 2, **bar }' )
    end

    it "keyword argument" do
      todo( 'def f(a:nil); end' )
    end
  end
end
