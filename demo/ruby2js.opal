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

# Make convert, parse, and AST.Node, nil available to JavaScript
`var Ruby2JS = {
  convert(string, options) {
    return Opal.Ruby2JS.$convert(string, Opal.Ruby2JS.$options(options))
  },

  parse(string, options) {
    return Opal.Ruby2JS.$parse(string, Opal.Ruby2JS.$options(options))
  },

  AST: {Node: Opal.Parser.AST.Node},

  nil: Opal.nil
}`

# Define a getter for sourcemap
`Object.defineProperty(Opal.Ruby2JS.Serializer.$$prototype, "sourcemap",
  {get() { return this.$sourcemap().$$smap }})`

# advertise that the function is available
if `typeof module !== 'undefined' && module.parent`
  `module.exports = Ruby2JS`
else
  $$.Ruby2JS = `Ruby2JS`
  if $$.document and $$.document[:body]
    $$.document[:body].dispatchEvent(`new CustomEvent('Ruby2JS-ready')`)
  end
end
