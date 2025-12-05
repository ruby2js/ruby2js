gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

describe "truthy option" do

  def to_js_ruby(string, eslevel: 2021)
    _(Ruby2JS.convert(string, eslevel: eslevel, truthy: :ruby).to_s)
  end

  def to_js_js(string, eslevel: 2021)
    _(Ruby2JS.convert(string, eslevel: eslevel, truthy: :js).to_s)
  end

  def to_js_default(string, eslevel: 2021)
    _(Ruby2JS.convert(string, eslevel: eslevel).to_s)
  end

  describe 'truthy: :ruby helper injection' do
    it "should inject $T and $ror helpers for ||" do
      to_js_ruby('a || b').must_include 'let $T = (v) => v !== false && v != null'
      to_js_ruby('a || b').must_include 'let $ror = (a, b) => $T(a) ? a : b()'
    end

    it "should inject $T and $rand helpers for &&" do
      to_js_ruby('a && b').must_include 'let $T = (v) => v !== false && v != null'
      to_js_ruby('a && b').must_include 'let $rand = (a, b) => $T(a) ? b() : a'
    end

    it "should not inject helpers when truthy option is disabled" do
      to_js_default('a || b').wont_include '$T'
      to_js_default('a || b').wont_include '$ror'
      to_js_default('a || b').wont_include '$rand'
    end
  end

  describe 'truthy: :ruby || operator' do
    it "should convert || to $ror call" do
      to_js_ruby('a || b').must_include '$ror(a, () => b)'
    end

    it "should handle chained || operators" do
      to_js_ruby('a || b || c').must_include '$ror($ror(a, () => b), () => c)'
    end

    it "should handle method calls" do
      to_js_ruby('foo.bar || baz').must_include '$ror(foo.bar, () => baz)'
    end
  end

  describe 'truthy: :ruby && operator' do
    it "should convert && to $rand call" do
      to_js_ruby('a && b').must_include '$rand(a, () => b)'
    end

    it "should handle chained && operators" do
      to_js_ruby('a && b && c').must_include '$rand($rand(a, () => b), () => c)'
    end
  end

  describe 'truthy: :ruby mixed operators' do
    it "should handle && and || together" do
      to_js_ruby('a && b || c').must_include '$ror($rand(a, () => b), () => c)'
    end

    it "should include all helpers when both operators used" do
      to_js_ruby('a && b || c').must_include '$T'
      to_js_ruby('a && b || c').must_include '$ror'
      to_js_ruby('a && b || c').must_include '$rand'
    end
  end

  describe 'truthy: :ruby ||= operator' do
    it "should convert ||= to assignment with $ror" do
      to_js_ruby('a ||= b').must_include 'a = $ror(a, () => b)'
    end

    it "should inject $ror helper for ||=" do
      to_js_ruby('a ||= b').must_include 'let $ror'
    end
  end

  describe 'truthy: :ruby &&= operator' do
    it "should convert &&= to assignment with $rand" do
      to_js_ruby('a &&= b').must_include 'a = $rand(a, () => b)'
    end

    it "should inject $rand helper for &&=" do
      to_js_ruby('a &&= b').must_include 'let $rand'
    end
  end

  describe 'truthy: :js (standard JS semantics)' do
    it "should use standard || with truthy: :js" do
      to_js_js('a || b').must_equal 'a || b'
    end

    it "should use standard && with truthy: :js" do
      to_js_js('a && b').must_equal 'a && b'
    end

    it "should use ||= operator with truthy: :js" do
      to_js_js('a ||= b').must_equal 'a ||= b'
    end

    it "should use &&= operator with truthy: :js" do
      to_js_js('a &&= b').must_equal 'a &&= b'
    end
  end

  describe 'no truthy option (default)' do
    it "should use standard || without truthy option" do
      to_js_default('a || b').must_equal 'a || b'
    end

    it "should use standard && without truthy option" do
      to_js_default('a && b').must_equal 'a && b'
    end

    it "should use ||= operator without truthy option" do
      to_js_default('a ||= b').must_equal 'a ||= b'
    end

    it "should use &&= operator without truthy option" do
      to_js_default('a &&= b').must_equal 'a &&= b'
    end
  end
end
