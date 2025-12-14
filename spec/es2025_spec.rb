require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "ES2025 support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2025, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe :eslevel do
    it "should report es2025" do
      Ruby2JS.convert('', eslevel: 2025).eslevel.must_equal 2025
    end
  end

  describe :RegExp_escape do
    it "should convert Regexp.escape to RegExp.escape" do
      to_js('Regexp.escape(str)').must_equal 'RegExp.escape(str)'
    end

    it "should handle string literals" do
      to_js('Regexp.escape("hello.world")').must_equal 'RegExp.escape("hello.world")'
    end
  end
end
