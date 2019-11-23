require 'haml'
require 'ruby2js/haml'

describe 'HAML filter' do
  it 'should convert ruby to javascript' do
    template = %{
       :ruby2js
         alert 'Hello'
    }

    # unindent template so that the first line starts in column 1
    template.gsub!(/^#{template[/\A\s+/]}/, '')

    haml_engine = Haml::Engine.new(template)
    output = _(haml_engine.render)

    output.must_include "<script type='text/javascript'>"
    output.must_include 'alert("Hello")'
    output.must_include '</script>'
  end
end
