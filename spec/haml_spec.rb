require 'minitest/autorun'
require 'ruby2js/filter/functions'

require 'haml'
require 'ruby2js/haml'

describe 'HAML filter' do
  it 'should convert ruby to javascript' do
    haml = %{
       :ruby2js
         alert 'Hello'
    }

    # unindent template so that the first line starts in column 1
    # As in, it is valid haml
    haml.gsub!(/^#{haml[/\A\s+/]}/, '')

    #copied from from haml tests, module RenderHelper

    output = Haml::Template.new({}) { haml }.render(Object.new, {})

    _(output).must_include "<script type='text/javascript'>"
    _(output).must_include 'alert("Hello")'
    _(output).must_include '</script>'
  end

  it 'should convert ruby with interpolation to javascript' do
    haml = %{
       :ruby2js
         alert HASH{2 + 2}
    }

    # unindent template so that the first line starts in column 1
    # As in, it is valid haml
    haml.gsub!(/^#{haml[/\A\s+/]}/, '')
    haml.gsub!("HASH", "#") #stop ruby interpreteting the 2 + 2

    #copied from from haml tests, module RenderHelper
    output = Haml::Template.new({}) { haml }.render(Object.new, {})

    _(output).must_include 'alert(4)'
  end

end
