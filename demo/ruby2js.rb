#!/usr/bin/env ruby
#
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
#
#   Want to run from the command line?
#     $ ruby ruby2js.rb [options] [file]
#
#       available options:
#
#         --es2015
#         --es2016
#         --es2017
#         --es2018
#         --es2019
#         --es2020
#         --strict
#         --equality
#         --identity
#         ---filter filter
#         -f filter

require 'wunderbar'

# extract options from the argument list
options = {}
options[:strict] = true if ARGV.delete('--strict')
options[:comparison] = :equality if ARGV.delete('--equality')
options[:comparison] = :identity if ARGV.delete('--identity')

begin
  # support running directly from a git clone
  $:.unshift File.absolute_path('../../lib', __FILE__)
  require 'ruby2js'

  filters = {}

  # autoregister eslevels
  Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
    eslevel = File.basename(file, '.rb')
    filters[eslevel] = "ruby2js/#{eslevel}"

    options[:eslevel] = eslevel[/\d+/].to_i if ARGV.delete("--#{eslevel}")
  end

  # autoregister filters
  Dir["#{$:.first}/ruby2js/filter/*.rb"].sort.each do |file|
    filter = File.basename(file, '.rb')
    filters[filter] = "ruby2js/filter/#{filter}"
  end

  # put camelCase last as it may interfere with other filters
  filters['camelCase'] = filters.delete('camelCase')

  # allow filters to be selected based on the path
  selected = env['PATH_INFO'].to_s.split('/')

  # add filters from the argument list
  while %w(-f --filter).include? ARGV[0]
    ARGV.shift
    selected << ARGV.shift
  end

  # require selected filters
  filters.each do |name, filter|
    require filter if selected.include?(name) or selected.include? 'all'
  end
rescue Exception => $load_error
end

# command line support
if not env['REQUEST_METHOD'] and not env['SERVER_PORT']
  if ARGV.length > 0
    options[:file] = ARGV.first
    puts Ruby2JS.convert(File.read(ARGV.first), options).to_s
  else
    puts Ruby2JS.convert(STDIN.read, options).to_s
  end  

  exit
end

_html do
  _title 'Ruby2JS'
  _style %{
    textarea {display: block}
    .unloc {background-color: yellow}
    .loc {background-color: white}
  }

  _h1 { _a 'Ruby2JS', href: 'https://github.com/rubys/ruby2js#ruby2js' }
  _form method: 'post' do
    _textarea @ruby, name: 'ruby', rows: 8, cols: 80
    _input type: 'submit', value: 'Convert'

    _label 'ES level', for: 'eslevel'
    _select name: 'eslevel', id: 'eslevel' do
      _option 'default', selected: !@eslevel || @eslevel == 'default'
      _option 2015, value: 2015, selected: @eslevel == '2015'
      _option 2016, value: 2016, selected: @eslevel == '2016'
      _option 2017, value: 2017, selected: @eslevel == '2017'
      _option 2018, value: 2018, selected: @eslevel == '2018'
      _option 2019, value: 2019, selected: @eslevel == '2019'
      _option 2020, value: 2020, selected: @eslevel == '2020'
    end

    _input type: 'checkbox', name: 'ast', id: 'ast', checked: !!@ast
    _label 'Show AST', for: 'ast'
  end

  if @ruby
    _div_? do
      raise $load_error if $load_error

      options[:eslevel] = @eslevel.to_i if @eslevel

      ruby = Ruby2JS.convert(@ruby, options)

      if @ast
        walk = proc do |ast, indent=''|
          _div class: (ast.loc ? 'loc' : 'unloc') do
            _ "#{indent}#{ast.type}"
            if ast.children.any? {|child| Parser::AST::Node === child}
              ast.children.each do |child|
                if Parser::AST::Node === child
                  walk[child, "  #{indent}"]
                else
                  _div "#{indent}  #{child.inspect}"
                end
              end
            else
              ast.children.each do |child|
                _ " #{child.inspect}"
              end
            end
          end
        end

        _h2 'AST'
        parsed = Ruby2JS.parse(@ruby).first
        _pre {walk[parsed]}

        if ruby.ast != parsed
          _h2 'filtered AST'
          _pre {walk[ruby.ast]}
        end
      end

      _h2 'JavaScript'
      _pre ruby.to_s
    end
  end
end
