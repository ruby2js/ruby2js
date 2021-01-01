gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/jsx'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/react'

# this spec handles two very different, JSX related transformations:
#
# * ruby/JSX to ruby/wunderbar, which is used by both filter/react and
#   filter/vue to produce an intermediate "pure ruby" version of
#   ruby intermixed with (X)HTML element syntax, which is subsequently
#   converted to JS.
#
# * ruby/wunderbar to JSX, which is implemented by filter/JSX to enable
#   a one way syntax conversion of wunderbar style calls to JSX syntax.


describe Ruby2JS::Filter::JSX do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, 
      filters: [Ruby2JS::Filter::JSX, Ruby2JS::Filter::Functions]).to_s)
  end

  def to_rb(string)
    _(Ruby2JS.jsx2_rb(string))
  end
  
  describe "ruby/JSX to ruby/wunderbar" do
    it "should handle self enclosed elements" do
      to_rb( '<br/>' ).must_equal '_br'
    end

    it "should handle attributes and text" do
      to_rb( '<a href=".">text</a>' ).must_equal(
        ['_a href: "." do', '_ "text"', 'end'].join("\n"))
    end

    it "should handle attributes expressions" do
      to_rb( '<img src={link}/>' ).must_equal('_img src: link')
    end

    it "should handle nested valuess" do
      to_rb( '<div><br/></div>' ).must_equal(
        ['_div do', '_br', 'end'].join("\n"))
    end

    it "should handle fragments" do
      to_rb( '<><h1/><h2/></>' ).must_equal(
        ['_ do', '_h1', '_h2', 'end'].join("\n"))
    end
  end

  describe "ruby/wunderbar to JSX" do
    it "should handle self enclosed values" do
      to_js( '_br' ).must_equal '<br/>'
    end

    it "should handle attributes and text" do
      to_js( '_a "text", href: "."' ).must_equal '<a href=".">text</a>'
    end

    it "should handle nested valuess" do
      to_js( '_div do _br; end' ).must_equal '<div><br/></div>'
    end

    it "should handle implicit iteration" do
      to_js( '_tr(rows) {|row| _td row}' ).
        must_equal '<tr>{rows.map(row => <td>{row}</td>)}</tr>'
    end

    it "should handle markaby style classes and id" do
      to_js( '_a.b.c.d!' ).must_equal '<a id="d" className="b c"/>'
    end

    it "should handle fragments" do
      to_js( '_ {_h1; _h2}' ).must_equal '<><h1/><h2/></>'
      to_js( '_(key: "x"){_h1; _h2}' ).
        must_equal '<React.Fragment key="x"><h1/><h2/></React.Fragment>'
    end

    it "should handle enclosing markaby style classes and id" do
      to_js( '_a.b.c.d! do _e; end' ).
       must_equal '<a id="d" className="b c"><e/></a>'
    end

    it "should class for to className" do
      to_js( '_div class: "foo"' ).
       must_equal '<div className="foo"/>'
    end

    it "should map for to htmlFor" do
      to_js( '_label "foo", for: "foo"' ).
       must_equal '<label htmlFor="foo">foo</label>'
    end
  end

  describe 'control structures' do
    it "should handle if" do
      to_js('_p {"hi" if a}').
        must_equal '<p>{a ? "hi" : null}</p>'
    end

    it "should handle each" do
      to_js('_ul { a.each {|b| _li b} }').
        must_equal '<ul>{a.map(b => <li>{b}</li>)}</ul>'
    end

    it "should handle blocks" do
      to_js('_div {if a; _br; _br; end}').
        must_equal '<div>{a ? <><br/><br/></> : null}</div>'
    end
  end

  describe :logging do
    it "should map wunderbar logging calls to console" do
      to_js( 'Wunderbar.debug "a"' ).must_equal 'console.debug("a")'
      to_js( 'Wunderbar.info "a"' ).must_equal 'console.info("a")'
      to_js( 'Wunderbar.warn "a"' ).must_equal 'console.warn("a")'
      to_js( 'Wunderbar.error "a"' ).must_equal 'console.error("a")'
      to_js( 'Wunderbar.fatal "a"' ).must_equal 'console.error("a")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include JSX" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::JSX
    end
  end
end
