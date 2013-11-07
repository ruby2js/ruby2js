# Interactive demo of conversions from Ruby to JS.  Requires wunderbar.
#
# Installation
# ----
#
#   Web server set up to run CGI programs?
#     $ ruby ruby2js.rb --install=/web/docroot
#
#   Standalone server:
#     $ ruby ruby2js.rb --port=8080

require 'wunderbar'
require 'pp'

begin
  $:.unshift File.absolute_path('../../lib', __FILE__)
  require 'ruby2js'
rescue Exception => $load_error
end

_html do
  _h1 'Ruby2JS'
  _style %{
    textarea {display: block}
  }

  _form method: 'post' do
    _textarea @ruby, name: 'ruby', rows: 8, cols: 80
    _input type: 'submit', value: 'Convert'

    _input type: 'checkbox', name: 'ast', id: 'ast', checked: !!@ast
    _label 'Show AST', for: 'ast'
  end

  if @ruby
    _div_? do
      raise $load_error if $load_error

      if @ast
        _h2 'AST'
        _pre Parser::CurrentRuby.parse(@ruby).inspect
      end

      _h2 'JavaScript'
      _pre Ruby2JS.convert(@ruby)
    end
  end
end
