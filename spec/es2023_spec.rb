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

    it "should handle sort_by with method call as key" do
      to_js('words.sort_by { |w| w.length }').
        must_equal 'words.toSorted((w_a, w_b) => {if (w_a.length < w_b.length) {return -1} else if (w_a.length > w_b.length) {return 1} else {return 0}})'
    end

    it "should handle sort_by with nested property access" do
      to_js('users.sort_by { |u| u.profile.name }').
        must_equal 'users.toSorted((u_a, u_b) => {if (u_a.profile.name < u_b.profile.name) {return -1} else if (u_a.profile.name > u_b.profile.name) {return 1} else {return 0}})'
    end

    it "should handle sort_by with method chain" do
      to_js('items.sort_by { |i| i.name.downcase }').
        must_equal 'items.toSorted((i_a, i_b) => {if (i_a.name.toLowerCase() < i_b.name.toLowerCase()) {return -1} else if (i_a.name.toLowerCase() > i_b.name.toLowerCase()) {return 1} else {return 0}})'
    end
  end
end
