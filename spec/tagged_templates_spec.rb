gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/tagged_templates'

describe Ruby2JS::Filter::TaggedTemplates do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015,
      filters: [Ruby2JS::Filter::TaggedTemplates], scope: self).to_s)
  end

  describe "tagged heredoc" do
    it "should output tagged template literal" do
      js = to_js( "class Element\ndef render\nhtml <<~HTML\n<div>\#{1 + 3}</div>\nHTML\nend\nend" )
      js.must_include 'render() {'
      js.must_include 'return html`<div>${1 + 3}</div>`'
    end
  end

end