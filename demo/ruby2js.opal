require 'native'
require 'ruby2js/demo'
require 'patch.opal'
require 'filters.opal'

# fixup options:
#   * map filter names to filter modules
#   * parse autoimports, defs
def Ruby2JS.options(hash)
  hash = `Opal.hash(hash || {})`

  hash[:filters] ||= []
  hash[:filters] = hash[:filters].split(/,\s*/) if hash[:filters].is_a? String
  hash[:filters] = hash[:filters].map {|name| Filters[name]}
  hash[:filters].compact!

  if hash[:autoimports].is_a? String
    hash[:autoimports] = Ruby2JS::Demo.parse_autoimports(hash[:autoimports])
  end

  if hash[:defs].is_a? String
    hash[:defs] = Ruby2JS::Demo.parse_defs(hash[:defs])
  end

  hash
end

# Make Ruby2JS::SyntaxError a JavaScript SyntaxError
class Ruby2JS::SyntaxError
  def self.new(message, diagnostic=nil)
    error = `new SyntaxError(message)`
    if diagnostic
      lines = diagnostic.render.map {|line| line.sub(/^\(string\):/, '')}
      lines[-1] += '^' if diagnostic.location.size == 0
      `error.diagnostic = lines.join("\n")`
    end
    return error
  end
end

# export convert function
$$.Ruby2JS = Ruby2JS
`Ruby2JS.convert = (string, options) => Ruby2JS.$convert(string, Ruby2JS.$options(options ))`
`Ruby2JS.parse = (string, options) => Ruby2JS.$parse(string, Ruby2JS.$options(options))`
node = Parser::AST::Node; `Ruby2JS.AST = {Node: node}`
`Ruby2JS.nil = nil`

# advertise that the function is available
$$.document[:body].dispatchEvent(`new CustomEvent('Ruby2JS-ready')`)
