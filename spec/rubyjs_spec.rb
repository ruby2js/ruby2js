gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/rubyjs'

describe Ruby2JS::Filter::RubyJS do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::RubyJS])
  end
  
  describe 'String conversions' do
    it "should handle capitalize" do
      to_js( 'a.capitalize()' ).must_equal '_s.capitalize(a)'
    end

    it "should handle center" do
      to_js( 'a.center(80)' ).must_equal '_s.center(a, 80)'
    end

    it "should handle chomp" do
      to_js( 'a.chomp()' ).must_equal '_s.chomp(a)'
    end

    it "should handle ljust" do
      to_js( 'a.ljust(80)' ).must_equal '_s.ljust(a, 80)'
    end

    it "should handle lstrip" do
      to_js( 'a.ljust()' ).must_equal '_s.ljust(a)'
    end

    it "should handle rindex" do
      to_js( 'a.rindex("b")' ).must_equal '_s.rindex(a, "b")'
    end

    it "should handle rjust" do
      to_js( 'a.rjust(80)' ).must_equal '_s.rjust(a, 80)'
    end

    it "should handle rstrip" do
      to_js( 'a.rjust()' ).must_equal '_s.rjust(a)'
    end

    it "should handle scan" do
      to_js( 'a.scan(/f/)' ).must_equal '_s.scan(a, /f/)'
    end

    it "should handle swapcase" do
      to_js( 'a.swapcase()' ).must_equal '_s.swapcase(a)'
    end

    it "should handle tr" do
      to_js( 'a.tr("a", "A")' ).must_equal '_s.tr(a, "a", "A")'
    end
  end

  describe 'Time conversions' do
    it "should handle strftime" do
      to_js( 'Date.new().strftime("%Y")' ).
        must_equal '_t.strftime(new Date(), "%Y")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
    end
  end
end
