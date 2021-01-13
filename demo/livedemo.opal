require 'native'
require 'ruby2js'
require 'patch.opal'

document = $$.document
console = $$.console

document.addEventListener 'DOMContentLoaded' do
  document.querySelector('input.btn').addEventListener 'click' do |event|
    `event.preventDefault()`

    ruby = document.querySelector('textarea')[:value]
    begin
      js = Ruby2JS.convert(ruby)
    rescue Ruby2JS::SyntaxError => e
      js = e.inspect
    end

    document.querySelector('#js pre').textContent = js
    document.querySelector('div#js').style.display = 'block'
  end
end
