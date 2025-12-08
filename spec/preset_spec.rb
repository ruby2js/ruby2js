require 'minitest/autorun'
require 'ruby2js'

describe "preset option" do

  def to_js(string)
    _(Ruby2JS.convert(string, preset: true).to_s)
  end

  def to_js_basic(string)
    _(Ruby2JS.convert(string).to_s)
  end

  # random tests just to santity check…see return_spec.rb for the full suite
  describe :return do
    it "should handle arrays" do
      to_js( 'lambda {|x| [x]}' ).must_equal 'x => [x]'
    end

    it "should handle case statements" do
      to_js( 'lambda {|x| case false; when true; a; when false; b; else c; end}' ).
        must_equal '(x) => {switch (false) {case true: return a; case false: return b; default: return c}}'
    end

    it "should handle single line definitions" do
      to_js( 'class C; def self.f(x) x(11); end; end' ).
        must_equal 'class C {static f(x) {return x(11)}}'
    end
  end

  describe :functions do
    it 'should handle well known methods' do
      to_js( 'a.map(&:to_i)' ).
        must_equal 'a.map(item => parseInt(item))'
    end
  end

  describe :options do
    it 'should handle equality comparisons' do
      to_js( 'x = str == "abc" ? str : nil' ).
        must_equal 'let x = str === "abc" ? str : null'
    end

    it 'should underscore instance variables' do
      to_js( 'class A; def b(); @c = 1; end; end;' ).
        must_equal 'class A {b() {this._c = 1; return this._c}}'
    end
  end

  describe :magic_comments do
    it 'should allow preset option' do
      to_js_basic( %(# ruby2js: preset\nclass A; def b(); @c = 1; end; end;) ).
        must_equal %(// ruby2js: preset\nclass A {\n  b() {\n    this._c = 1;\n    return this._c\n  }\n})
    end

    it 'should allow filters' do
      to_js_basic( %(# ruby2js: preset, filters: camelCase\nclass A; def b_x(); @c_z = 1; end; end;) ).
        must_equal %(// ruby2js: preset, filters: camelCase\nclass A {\n  bX() {\n    this._cZ = 1;\n    return this._cZ\n  }\n})
    end

    it 'should allow eslevel' do
      to_js_basic( %(# ruby2js: preset, eslevel: 2022\nx.last) ).
        must_equal %(// ruby2js: preset, eslevel: 2022\nx.at(-1))
    end

    it 'should allow for disabling filters' do
      to_js_basic( %(# ruby2js: preset, disable_filters: return\nclass A; def b(); @c = 1; end; end;) ).
        must_equal %(// ruby2js: preset, disable_filters: return\nclass A {\n  b() {\n    this._c = 1\n  }\n})
    end
  end
end
