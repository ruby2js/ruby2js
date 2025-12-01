gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/active_support'

describe Ruby2JS::Filter::ActiveSupport do

  def to_js(string, eslevel: 2020)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ActiveSupport], eslevel: eslevel).to_s)
  end

  describe 'blank?' do
    it "should convert blank? to null/empty check" do
      result = to_js('x.blank?')
      result.must_include '== null'
      result.must_include '.length === 0'
      result.must_include '=== ""'
    end

    it "should handle blank? on method calls" do
      result = to_js('user.name.blank?')
      result.must_include 'user.name'
      result.must_include '== null'
    end
  end

  describe 'present?' do
    it "should convert present? to negated blank check" do
      result = to_js('x.present?')
      result.must_include '!= null'
      result.must_include '.length != 0'
      result.must_include '!= ""'
    end

    it "should handle present? on method calls" do
      result = to_js('user.email.present?')
      result.must_include 'user.email'
      result.must_include '!= null'
    end
  end

  describe 'presence' do
    it "should convert presence to conditional" do
      result = to_js('x.presence')
      # Should return x if present, null otherwise
      result.must_include '!= null'
      result.must_include 'else {null}'
    end
  end

  describe 'try' do
    it "should convert try to optional chaining" do
      result = to_js('user.try(:name)')
      # csend generates method call syntax
      result.must_equal 'user?.name()'
    end

    it "should handle try with arguments" do
      result = to_js('obj.try(:fetch, :key)')
      result.must_equal 'obj?.fetch("key")'
    end

    it "should handle try with multiple arguments" do
      result = to_js('obj.try(:method, 1, 2)')
      result.must_equal 'obj?.method(1, 2)'
    end
  end

  describe 'in?' do
    it "should convert in? to includes" do
      result = to_js('x.in?(arr)')
      result.must_equal 'arr.includes(x)'
    end

    it "should handle in? with array literal" do
      result = to_js('x.in?([1, 2, 3])')
      result.must_equal '[1, 2, 3].includes(x)'
    end
  end

  describe 'squish' do
    it "should convert squish to trim and replace" do
      result = to_js('str.squish')
      result.must_include '.trim()'
      result.must_include '.replace('
      result.must_include '/\\s+/g'
      result.must_include '" "' # double quotes in JS output
    end
  end

  describe 'truncate' do
    it "should convert truncate with length" do
      result = to_js('str.truncate(50)')
      result.must_include '.length > 50'
      result.must_include '.slice(0'
      result.must_include '"..."'
    end

    it "should handle truncate with custom omission" do
      result = to_js('str.truncate(50, omission: "...")')
      result.must_include '.length > 50'
      result.must_include '.slice(0'
    end
  end

  describe 'to_sentence' do
    it "should convert to_sentence for arrays" do
      result = to_js('arr.to_sentence')
      result.must_include '.length === 0'
      result.must_include '.length === 1'
      result.must_include '.join(", ")'
      result.must_include '" and "'
    end
  end

  describe 'non-ActiveSupport methods' do
    it "should not affect regular method calls" do
      result = to_js('x.foo')
      result.must_equal 'x.foo'
    end

    it "should not affect methods with same name but wrong arity" do
      result = to_js('x.blank?(arg)')
      result.must_equal 'x.blank(arg)'
    end
  end
end
