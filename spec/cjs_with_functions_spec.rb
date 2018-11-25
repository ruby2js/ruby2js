gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/cjs'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::CJS do
  describe 'with Ruby2JS::Filter::Functions' do
    def to_js( string)
      Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CJS, Ruby2JS::Filter::Functions],
        file: __FILE__, eslevel: 2017)
    end

    describe :exports do
      it "should convert .inspect into JSON.stringify()" do
        to_js( 'export async def f(a, b); return {input: a}.inspect; end' ).to_s.
          must_equal 'exports.f = async (a, b) => JSON.stringify({input: a})'
      end
    end

    describe Ruby2JS::Filter::DEFAULTS do
      it "should include CJS and Functions" do
        Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::CJS
        Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
      end
    end
  end
end
