require 'native'
require 'ruby2js'
require 'patch.opal'

document = $$.document
console = $$.console

document.addEventListener 'DOMContentLoaded' do
  document.querySelector('input.btn').addEventListener 'click' do |event|
    `event.preventDefault()`

    jsdiv = document.querySelector('div#js')
    jspre = jsdiv.querySelector('pre')

    ruby = document.querySelector('textarea')[:value]
    begin
      js = Ruby2JS.convert(ruby)
      jspre[:classList].remove 'exception'
    rescue Ruby2JS::SyntaxError => e
      js = e.to_s
      jspre[:classList].add 'exception'
    end

    jspre.textContent = js
    jsdiv[:style].display = 'block'
  end
end
