# Interactive demo of conversions from Ruby to JS.  Requires wunderbar.
#
# Installation
# ----
#
#   Web server set up to run CGI programs?
#     $ ruby ruby2js.rb --install=/web/docroot
#
#   Want to run a standalone server?
#     $ ruby ruby2js.rb --port=8080

require 'wunderbar'

begin
  # support running directly from a git clone
  $:.unshift File.absolute_path('../../lib', __FILE__)
  require 'ruby2js'

  filters = {
    'angularrb' => 'ruby2js/filter/angularrb',
    'angular-resource' => 'ruby2js/filter/angular-resource',
    'angular-route' => 'ruby2js/filter/angular-route',
    'functions' => 'ruby2js/filter/functions',
    'jquery'    => 'ruby2js/filter/jquery',
    'minitest-jasmine' => 'ruby2js/filter/minitest-jasmine',
    'return'    => 'ruby2js/filter/return',
    'react'     => 'ruby2js/filter/react',
    'strict'    => 'ruby2js/filter/strict',
    'underscore' => 'ruby2js/filter/underscore',
    'camelCase' => 'ruby2js/filter/camelCase' # should be last
  }

  # allow filters to be selected based on the path
  selected = env['PATH_INFO'].to_s.split('/')
  filters.each do |name, filter|
    require filter if selected.include?(name) or selected.include? 'all'
  end
rescue Exception => $load_error
end

_html do
  _title 'Ruby2JS'
  _style %{
    textarea {display: block}
  }

  _h1 { _a 'Ruby2JS', href: 'https://github.com/rubys/ruby2js#ruby2js' }
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
        _pre Ruby2JS.parse(@ruby).inspect
      end

      _h2 'JavaScript'
      _pre Ruby2JS.convert(@ruby)
    end
  end
end
