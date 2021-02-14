require 'native'
require 'ruby2js/demo'
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
  $load_error = nil

  search[1..-1].split('&').each do |parameter|
    name, value = parameter.split('=', 2)
    value = value ? $$.decodeURIComponent(value.gsub('+', ' ')) : true

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
    when :autoimports
      value = Ruby2JS::Demo.parse_autoimports(value)
    when :defs
      value = Ruby2JS::Demo.parse_defs(value)
    when /^es\d+$/
      value = name[2..-1].to_i
      name = :eslevel
    end

    raise ArgumentError.new($load_error) if $load_error

    options[name] = value
  end

  options
end

# convert AST into displayable form
def walk(ast, indent='', tail='', last=true)
  return [] unless ast
  output = ["<div class=#{ast.loc ? 'loc' : 'unloc'}>"]
  output << "#{indent}<span class=hidden>s(:</span>#{ast.type}"
  output << '<span class=hidden>,</span>' unless ast.children.empty?

  if ast.children.any? {|child| child.is_a? Parser::AST::Node}
    ast.children.each_with_index do |child, index|
      ctail = index == ast.children.length - 1 ? ')' + tail : ''
      lastc = last && !ctail.empty?

      if Parser::AST::Node === child
        output += walk(child, "  #{indent}", ctail, lastc)
      else
        output << "<div>#{indent}  "

        if child.is_a? String and child =~ /\A[!-~]+\z/
          output << ":#{child}"
        else
          output << child.inspect
        end

        output << "<span class=hidden>#{ctail}#{',' unless lastc}</span>"
        output << ' ' if lastc
        output << '</div>'
      end
    end
  else
    ast.children.each_with_index do |child, index|
      if ast.type != :str and child.is_a? String and child =~ /\A[!-~]+\z/
        output << " :#{child}"
      else
        output << " #{child.inspect}"
      end
      output << '<span class=hidden>,</span>' unless index == ast.children.length - 1
    end
    output << "<span class=hidden>)#{tail}#{',' unless last}</span>"
    output << ' ' if last
  end

  output << '</div>'
end

# update output on every keystroke in textarea
$document.querySelector('textarea').addEventListener :input do
  event = `new MouseEvent('click', { bubbles: true, cancelable: true, view: window })`
  $document.querySelector('input[type=submit]').dispatchEvent(event)
end

# process convert button
convert.addEventListener :click do |event|
  `event.preventDefault()`

  ruby = $document.querySelector('textarea')[:value]
  begin
    js = Ruby2JS.convert(ruby, parse_options)
    jspre[:classList].remove 'exception'
    show_ast = ast.checked
  rescue Ruby2JS::SyntaxError => e
    if e.diagnostic
      diagnostic = e.diagnostic.render.map {|line| line.sub(/^\(string\):/, '')}
      diagnostic[-1] += '^' if e.diagnostic.location.size == 0
      js = diagnostic.join("\n")
    else
      js = e
    end
    jspre[:classList].add 'exception'
  rescue Exception => e
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
  jsdiv[:style].display = js.to_s.empty? ? 'none' : 'block'
end

# make inputs match query
parse_options.each do |name, value|
  case name
  when :ruby
    $document.querySelector('textarea').value = value
  when :filters
    nodes = $document.getElementById(:filters)[:parentNode].querySelectorAll('sl-menu-item')
    nodes.forEach do |node|
      `node.checked = true` if value.include? Filters[`node.textContent`]
    end
  when :eslevel
    eslevel = $document.getElementById('eslevel')
    eslevel.querySelector('sl-button').textContent = value.to_s
    eslevel.querySelector("sl-menu-item[value='']").checked = false
    eslevel.querySelector("sl-menu-item[value='#{value}']").checked = true
  when :comparison
    $document.querySelector("sl-menu-item[name=identity]").checked = true if value == :identity
  when :nullish
    $document.querySelector("sl-menu-item[name=or]").checked = true if value == :nullish
  else
    checkbox = $document.querySelector("sl-menu-item[name=#{name}]")
    checkbox.checked = true if checkbox
  end
end

# initial conversion if textarea is not empty
unless $document.querySelector('textarea').value.empty?
  event = `new MouseEvent('click', { bubbles: true, cancelable: true, view: window })`
  $document.querySelector('input[type=submit]').dispatchEvent(event)
end
