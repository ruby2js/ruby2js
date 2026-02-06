require 'minitest/autorun'
require 'ruby2js/filter/active_support'

describe Ruby2JS::Filter::ActiveSupport do

  def to_js(string, eslevel: 2020)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ActiveSupport], eslevel: eslevel).to_s
  end

  describe 'blank?' do
    it "should convert blank? using optional chaining" do
      _(to_js('x.blank?')).must_equal '!x?.length'
    end

    it "should handle blank? on method calls" do
      _(to_js('user.name.blank?')).must_equal '!user.name?.length'
    end
  end

  describe 'present?' do
    it "should convert present? using optional chaining" do
      _(to_js('x.present?')).must_equal 'x?.length > 0'
    end

    it "should handle present? on method calls" do
      _(to_js('user.email.present?')).must_equal 'user.email?.length > 0'
    end
  end

  describe 'presence' do
    it "should convert presence to conditional" do
      result = to_js('x.presence')
      # May be ternary or if/else depending on context
      _(result).must_include 'x?.length > 0'
      _(result).must_include 'null'
    end
  end

  describe 'try' do
    it "should convert try to optional chaining" do
      _(to_js('user.try(:name)')).must_equal 'user?.name()'
    end

    it "should handle try with arguments" do
      _(to_js('obj.try(:fetch, :key)')).must_equal 'obj?.fetch("key")'
    end

    it "should handle try with multiple arguments" do
      _(to_js('obj.try(:method, 1, 2)')).must_equal 'obj?.method(1, 2)'
    end
  end

  describe 'in?' do
    it "should convert in? to includes" do
      _(to_js('x.in?(arr)')).must_equal 'arr.includes(x)'
    end

    it "should handle in? with array literal" do
      _(to_js('x.in?([1, 2, 3])')).must_equal '[1, 2, 3].includes(x)'
    end
  end

  describe 'squish' do
    it "should convert squish to trim and replace" do
      result = to_js('str.squish')
      _(result).must_include '.trim()'
      _(result).must_include '.replace('
      _(result).must_include '/\\s+/g'
      _(result).must_include '" "'
    end
  end

  describe 'truncate' do
    it "should convert truncate with length" do
      result = to_js('str.truncate(50)')
      _(result).must_include '.length > 50'
      _(result).must_include '.slice(0'
      _(result).must_include '"..."'
    end

    it "should handle truncate with custom omission" do
      result = to_js('str.truncate(50, omission: "...")')
      _(result).must_include '.length > 50'
      _(result).must_include '.slice(0'
    end
  end

  describe 'to_sentence' do
    it "should convert to_sentence for arrays" do
      result = to_js('arr.to_sentence')
      _(result).must_include '.length === 0'
      _(result).must_include '.length === 1'
      _(result).must_include '.join(", ")'
      _(result).must_include '" and "'
    end
  end

  describe 'index_by' do
    it "should convert index_by with &:itself" do
      result = to_js('%w[drafted published].index_by(&:itself)')
      _(result).must_equal 'Object.fromEntries(["drafted", "published"].map(item => ([item, item])))'
    end

    it "should convert index_by with &:attribute" do
      result = to_js('users.index_by(&:id)')
      _(result).must_equal 'Object.fromEntries(users.map(item => ([item.id(), item])))'
    end

    it "should convert index_by with block" do
      result = to_js('records.index_by { |r| r.name }')
      _(result).must_equal 'Object.fromEntries(records.map(r => ([r.name, r])))'
    end

    it "should convert index_by with complex block body" do
      result = to_js('records.index_by { |r| [r.class.name, r.id] }')
      _(result).must_equal 'Object.fromEntries(records.map(r => ([[r.class.name, r.id], r])))'
    end
  end

  describe 'non-ActiveSupport methods' do
    it "should not affect regular method calls" do
      _(to_js('x.foo')).must_equal 'x.foo'
    end

    it "should not affect methods with same name but wrong arity" do
      _(to_js('x.blank?(arg)')).must_equal 'x.blank(arg)'
    end
  end
end
