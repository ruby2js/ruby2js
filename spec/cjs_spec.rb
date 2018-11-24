gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/cjs'

describe Ruby2JS::Filter::CJS do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CJS],
      file: __FILE__, eslevel: 2017)
  end
  
  describe :exports do
    it "should export a simple function" do
      to_js( 'export def f(a); return a; end' ).to_s.
        must_equal 'exports.f = a => a'
    end

    it "should export an async function" do
      to_js( 'export async def f(a, b); return a; end' ).to_s.
        must_equal 'exports.f = async (a, b) => a'
    end

    it "should export a value" do
      to_js( 'export foo = 1' ).to_s.
        must_equal 'exports.foo = 1'
    end
  end

  describe :default do
    it "should export a simple function" do
      to_js( 'export default proc do |a|; return a; end' ).to_s.
        must_equal 'module.exports = a => a'
    end

    it "should export an async function" do
      to_js( 'export default async proc do |a, b| return a; end' ).to_s.
        must_equal 'module.exports = async (a, b) => a'
    end

    it "should export a value" do
      to_js( 'export default 1' ).to_s.
        must_equal 'module.exports = 1'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include CJS" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::CJS
    end
  end
end
