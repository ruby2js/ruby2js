# TODOS:
#  * filter/functions.rb: require 'regexp_parser', needs YAML

require 'native'
require 'ruby2js'
require 'patch.opal'
require 'filters.opal'

$document = $$.document
jsdiv = $document.querySelector('div#js')
jspre = jsdiv.querySelector('pre')
convert = $document.querySelector('input.btn')
ast = $document.getElementById('ast')
parsed = $document.getElementById('parsed')
filtered = $document.getElementById('filtered')

# convert query into options
def parse_options
  options = {filters: []}
  search = $document[:location].search
  return options if search == ''

  search[1..-1].split('&').each do |parameter|
    name, value = parameter.split('=', 2)
    value = value ? $$.decodeURIComponent(value) : true

    case name
    when :filter
      name = :filters
      value = value.split(',').map {|name| Filters[name]}.compact
    when :identity
      value = name
      name = :comparison
    when :nullish
      value = name
      name = :or
    when /^es\d+$/
      value = name[2..-1].to_i
      name = :eslevel
    end

    options[name] = value
  end

  options
end

# convert AST into displayable form
def walk(ast, indent='')
  return [] unless ast
  output = ["<div class=#{ast.loc ? 'loc' : 'unloc'}>"]
  output << "#{indent}#{ast.type}"

  if ast.children.any? {|child| child.is_a? Parser::AST::Node}
    ast.children.each do |child|
      if Parser::AST::Node === child
        output += walk(child, "  #{indent}")
      else
        output << "<div>#{indent}  #{child.inspect}</div>"
      end
    end
  else
    ast.children.each do |child|
      output << " #{child.inspect}"
    end
  end

  output << '</div>'
end

# process convert button
convert.addEventListener 'click' do |event|
  `event.preventDefault()`

  ruby = $document.querySelector('textarea')[:value]
  begin
    js = Ruby2JS.convert(ruby, parse_options)
    jspre[:classList].remove 'exception'
    show_ast = ast.checked
  rescue Ruby2JS::SyntaxError => e
    js = e
    jspre[:classList].add 'exception'
  rescue => e
    js = e.inspect
    jspre[:classList].add 'exception'
  end

  if ast.checked and not jspre[:classList].contains('exception')
    raw, comments = Ruby2JS.parse(ruby)
    parsed.querySelector('pre').innerHTML = walk(raw).join
    parsed[:style].display = 'block'
    if raw == js.ast
      filtered[:style].display = 'none'
    else
      filtered.querySelector('pre').innerHTML = walk(js.ast).join
      filtered[:style].display = 'block'
    end
  else
    parsed[:style].display = 'none'
    filtered[:style].display = 'none'
  end

  jspre.textContent = js.to_s
  jsdiv[:style].display = 'block'
end

# enable the convert button
convert.disabled = false

# make inputs match query
parse_options.each do |name, value|
  case name
  when :ruby
    $document.querySelector('textarea').value = value
    event = `new MouseEvent('click', { bubbles: true, cancelable: true, view: window })`
    $document.querySelector('input[type=submit]').dispatchEvent(event)
  when :filters
    nodes = $document.getElementById(:filters)[:parentNode].querySelectorAll(:input)
    nodes.forEach do |node|
      `node.checked = true` if value.include? Filters[`node.name`]
    end
  when :eslevel
    $document.getElementById('eslevel').value = value.to_s
  when :comparison
    $document.querySelector("input[name=identity]").checked = true if value == :identity
  when :nullish
    $document.querySelector("input[name=or]").checked = true if value == :nullish
  else
    checkbox = $document.querySelector("input[name=#{name}]")
    checkbox.checked = true if checkbox
  end
end
