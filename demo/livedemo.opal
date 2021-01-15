# TODOS:
#  * filter/functions.rb: require 'regexp_parser', needs YAML

require 'native'
require 'ruby2js'
require 'patch.opal'
require 'filters.opal'

$document = $$.document
jsdiv = $document.querySelector('div#js')
jspre = jsdiv.querySelector('pre')

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

convert = $document.querySelector('input.btn')

convert.addEventListener 'click' do |event|
  `event.preventDefault()`

  ruby = $document.querySelector('textarea')[:value]
  begin
    js = Ruby2JS.convert(ruby, parse_options).to_s
    jspre[:classList].remove 'exception'
  rescue Ruby2JS::SyntaxError => e
    js = e.to_s
    jspre[:classList].add 'exception'
  rescue => e
    js = e.inspect
    jspre[:classList].add 'exception'
  end

  jspre.textContent = js
  jsdiv[:style].display = 'block'
end

convert.disabled = false

parse_options.each do |name, value|
  case name
  when :ruby
    $document.querySelector('textarea').value = value
    event = `new MouseEvent('click', { bubbles: true, cancelable: true, view: window })`;
    $document.querySelector('input[type=submit]').dispatchEvent(event);
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
