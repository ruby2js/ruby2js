gem 'minitest'
require 'minitest/autorun'

describe "namespace support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, filters: []).to_s)
  end

  describe "open modules" do
    it "should extend modules" do
      to_js( 'module M; def f(); end; end;' +
             'module M; def g(); end; end').
      must_equal('const M = {f: function() {}}; ' +
        'M.g = function() {}');
    end

    it "should extend nested modules" do
      to_js( 'module M; module N; def f(); end; end; end;' +
             'module M::N; def g(); end; end').
      must_equal('const M = {N: {f: function() {}}}; ' +
        'M.N.g = function() {}');
    end
  end
end
