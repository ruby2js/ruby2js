gem 'minitest'
require 'minitest/autorun'

describe "namespace support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2017, filters: []).to_s)
  end

  describe "open modules" do
    it "should extend modules" do
      to_js( 'module M; def f(); end; end;' +
             'module M; def g(); end; end').
      must_equal('const M = {f() {}}; ' +
        'M.g = function() {}');
    end

    it "should extend nested modules" do
      to_js( 'module M; module N; def f(); end; end; end;' +
             'module M::N; def g(); end; end').
      must_equal('const M = {N: {f() {}}}; ' +
        'M.N.g = function() {}');
    end

    it "should extend nested modules with getter" do
      to_js( 'module M; module N; def f(); end; end; end;' +
             'module M::N; def g; end; end').
      must_equal('const M = {N: {f() {}}}; ' +
        'Object.defineProperties(M.N, ' +
        'Object.getOwnPropertyDescriptors({get g() {}}))');
    end
  end

  describe "open classes" do
    it "should extend classes" do
      to_js( 'class M; def f(); end; end;' +
             'class M; def g(); end; end').
      must_equal('class M {f() {}}; ' +
        'M.prototype.g = function() {}');
    end

    it "should extend nested modules with getter" do
      to_js( 'module M; class N; def f(); end; end; end;' +
             'class M::N; def g; end; end').
      must_equal('const M = {N: class {f() {}}}; ' +
        'Object.defineProperty(M.N.prototype, "g", ' +
        '{enumerable: true, configurable: true, get() {}})');
    end

    it "should bind references to methods defined in original class" do
      to_js( 'class C; def f(); end; end' +
             'class C; def g; f; end; end').
      must_include 'return this.f.bind(this)'
    end

    it "should bind references to methods defined in parent class" do
      to_js( 'class C; def f(); end; end' +
             'class D < C; def g; f; end; end').
      must_include 'return this.f.bind(this)'
    end
  end
end
