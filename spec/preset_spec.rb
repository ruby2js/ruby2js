gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

describe "preset option" do

  def to_js( string)
    _(Ruby2JS.convert(string, preset: true).to_s)
  end

  # random tests just to santity check…see return_spec.rb for the full suite
  describe :return do
    it "should handle arrays" do
      to_js( 'lambda {|x| [x]}' ).must_equal 'x => [x]'
    end

    it "should handle case statements" do
      to_js( 'lambda {|x| case false; when true; a; when false; b; else c; end}' ).
        must_equal '(x) => {switch (false) {case true: return a; case false: return b; default: return c}}'
    end

    it "should handle single line definitions" do
      to_js( 'class C; def self.f(x) x(11); end; end' ).
        must_equal 'class C {static f(x) {return x(11)}}'
    end
  end

  describe :functions do
    it 'should handle well known methods' do
      to_js( 'a.map(&:to_i)' ).
        must_equal 'a.map(item => parseInt(item))'
    end
  end
end
