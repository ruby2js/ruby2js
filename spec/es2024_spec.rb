gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "ES2024 support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2024, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_2023(string)
    _(Ruby2JS.convert(string, eslevel: 2023, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe :eslevel do
    it "should report es2024" do
      Ruby2JS.convert('', eslevel: 2024).eslevel.must_equal 2024
    end
  end

  describe :group_by do
    it "should convert group_by with block to Object.groupBy" do
      to_js('a.group_by { |x| x.category }').
        must_equal 'Object.groupBy(a, x => x.category)'
    end

    it "should handle complex block bodies" do
      to_js('people.group_by { |p| p.age > 30 ? "senior" : "junior" }').
        must_equal 'Object.groupBy(people, p => p.age > 30 ? "senior" : "junior")'
    end

    it "should use reduce fallback without ES2024" do
      # Without ES2024, group_by uses reduce
      to_js_2023('a.group_by { |x| x.category }').
        must_equal 'a.reduce(($acc, x) => {let $key = x.category; ($acc[$key] = $acc[$key] ?? []).push(x); return $acc}, {})'
    end
  end
end
