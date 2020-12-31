gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/jsx'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/react'

describe Ruby2JS::Filter::JSX do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2015, 
      filters: [Ruby2JS::Filter::JSX, Ruby2JS::Filter::Functions]).to_s)
  end
  
  describe :jsx do
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
