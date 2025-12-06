gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/tagged_templates'

describe Ruby2JS::Filter::TaggedTemplates do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::TaggedTemplates], scope: self).to_s)
  end

  def to_js_with_new_tags(string)
    _(Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::TaggedTemplates], template_literal_tags: %i(tags work), scope: self).to_s)
  end

  describe "tagged heredoc" do
    it "should return tagged template literal" do
      js = to_js( "class Element\ndef render\nhtml <<~HTML\n<div>\#{1 + 3}</div>\nHTML\nend\nend" )
      js.must_include 'render() {'
      js.must_include 'return html`<div>${1 + 3}</div>`'
    end
  end

  describe "tagged short string" do
    it "should return tagged template literal" do
      js = to_js( "class Element\ndef self.styles\ncss 'display: block'\nend\nend" )
      js.must_include 'static get styles() {'
      js.must_include 'return css`display: block`'
    end

    it "should allow assignment" do
      to_js('styles = css("color: green")').
        must_include('let styles = css`color: green`')
    end
  end

  describe "available tags" do
    it "should be customizable" do
      to_js_with_new_tags('value = work("some value")').
        must_include('let value = work`some value`')
    end
  end

  describe "autobind" do
    it "should not autobind methods" do
      to_js('class C; def click(event); end; def render; html "<div @click=\"#{click}\"></div>"; end; end').
        must_include('{return html`<div @click="${this.click}"></div>`')
    end
  end

  describe "targets" do
    it "should not process unless target is nil" do
      to_js('styles = self.css("color: green")').
        must_include('let styles = this.css("color: green")')
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include TaggedTemplates" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::TaggedTemplates
    end
  end
end
