gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/wunderbar'

describe Ruby2JS::Filter::Wunderbar do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Wunderbar]).to_s)
  end
  
  describe :wunderbar do
    it "should handle self enclosed values" do
      to_js( '_br' ).must_equal '<br/>'
    end

    it "should handle attributes and text" do
      to_js( '_a "text", href: "."' ).must_equal '<a href=".">text</a>'
    end

    it "should handle nested valuess" do
      to_js( '_div do _br; end' ).must_equal '<div><br/></div>'
    end

    it "should handle markaby style classes and id" do
      to_js( '_a.b.c.d!' ).must_equal '<a id="d" class="b c"/>'
    end

    it "should handle enclosing markaby style classes and id" do
      to_js( '_a.b.c.d! do _e; end' ).must_equal '<a id="d" class="b c"><e/></a>'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Wunderbar" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Wunderbar
    end
  end
end
