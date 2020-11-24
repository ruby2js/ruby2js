gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/node'
require 'ruby2js/filter/require'

describe "sourcemap" do

  def to_sm(string, *filters)
    _(Ruby2JS.convert(string, filters: filters, file: __FILE__).sourcemap)
  end

  it "should handle null input" do
    to_sm("").
      must_equal(version: 3, file: __FILE__, sources: [], mappings: "")
  end

  describe "simple filters" do
    it "should work without filters" do
      to_sm("x = 123; puts x").
        must_equal(version: 3, file: __FILE__, sources: [__FILE__], mappings: "QAAI,GAAJ,EAAS,KAAK,CAAL")
    end

    it "should produce different results with a filter" do
      to_sm("x = 123; puts x", Ruby2JS::Filter::Functions).
        must_equal(version: 3, file: __FILE__, sources: [__FILE__], mappings: "QAAI,GAAJ,SAAS,KAAK,CAAL")
    end
  end

  describe "prepended imports" do
    it "should work without filters" do
      to_sm("system 'echo hi'").
        must_equal(version: 3, file: __FILE__, sources: [__FILE__], mappings: "OAAO,SAAP")
    end
  
    it "should work with a filter that inserts import statements" do
      to_sm("system 'echo hi'", Ruby2JS::Filter::Node).
        must_equal(version: 3, file: __FILE__, sources: [__FILE__], mappings: ";AAAO,SAAP;AAAA")
    end
  end

  it "should handle requires" do
    dir = File.join(__dir__, 'require')
    sources = [File.join(dir, "test2.rb"), File.join(dir, "test1.rb"), File.join(dir, "test3.js.rb")]
    to_sm('require "require/test1.rb"', Ruby2JS::Filter::Require).
      must_equal(version: 3, file: __FILE__, sources: sources, mappings: "YAAY,OAAZ,CCAA,ECAA,YAAY,OAAZ")
  end
end
