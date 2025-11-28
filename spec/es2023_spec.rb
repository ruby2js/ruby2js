gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "ES2023 support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2023, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe :eslevel do
    it "should report es2023" do
      Ruby2JS.convert('', eslevel: 2023).eslevel.must_equal 2023
    end
  end
end
