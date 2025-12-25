require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "ES2023 support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2023, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe :eslevel do
    it "should report es2023" do
      _(Ruby2JS.convert('', eslevel: 2023).eslevel).must_equal 2023
    end
  end

  describe :sort_by do
    it "should convert sort_by to toSorted" do
      to_js('a.sort_by { |x| x.name }').
        must_equal 'a.toSorted((x_a, x_b) => {if (x_a.name < x_b.name) {return -1} else if (x_a.name > x_b.name) {return 1} else {return 0}})'
    end

    it "should handle complex block bodies" do
      to_js('people.sort_by { |p| p.age * 2 }').
        must_equal 'people.toSorted((p_a, p_b) => {if (p_a.age * 2 < p_b.age * 2) {return -1} else if (p_a.age * 2 > p_b.age * 2) {return 1} else {return 0}})'
    end
  end
end
