gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/jquery'

describe Ruby2JS::Filter::JQuery do
  
  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::JQuery]).to_s)
  end
  
  describe :gvars do
    it "should handle jquery calls" do
      to_js( '$$.("span")' ).must_equal '$("span")'
      to_js( '$$["span"]' ).must_equal '$("span")'
    end
  end

  describe 'tilde' do
    it "should handle simple jquery calls" do
      to_js( '~"span"' ).must_equal '$("span")'
    end

    it "should handle jquery calls with multiple parameters" do
      to_js( '~["span", self]' ).must_equal '$("span", this)'
    end

    it "should handle chained jquery calls" do
      to_js( '~this.show.fadeOut' ).must_equal '$(this).show().fadeOut()'
    end

    it "should not chain DOM elements" do
      to_js( '~this[0].selectionStart' ).must_equal '$(this)[0].selectionStart'
      to_js( '~this[0].selectionStart = start' ).
        must_equal '$(this)[0].selectionStart = start'
    end

    it "should handle consecutive tildes" do
      to_js( '~~value' ).must_equal '~~value'
      to_js( '~~~value' ).must_equal '~value'
    end

    it "should handle operator assignments" do
      to_js( '~"textarea".text += "TODO: empty trash\n"' ).
        must_equal '$("textarea").text($("textarea").text() + "TODO: empty trash\n")'
    end

    it "should handle setters" do
      to_js( '~this.text = "*"' ).must_equal '$(this).text("*")'
    end

    it "should handle DOM properties" do
      to_js( '~"button".readonly = false' ).
        must_equal '$("button").prop("readOnly", false)'
    end
  end

  describe 'toArray' do
    it "should handle to_a" do
      to_js( 'a.to_a' ).must_equal 'a.toArray()'
    end
  end

  describe 'post defaults' do
    it 'should default post parameters' do
      to_js( '$$.post { x() }' ).
        must_equal '$.post("", {}, () => {x()}, "json")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include JQuery" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::JQuery
    end
  end
end
