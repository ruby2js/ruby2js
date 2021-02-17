async {
  # determine base URL and what filters and options are selected
  base = window.location.pathname
  filters = new Set()
  options = {}
  window.location.search.scan(/(\w+)(=([^&]*))?/).each do |match|
    options[match[0]] = match[2] && decodeURIComponent(match[2])
  end
  if options.filter
    options.filter.split(',').each {|option| filters.add(option)}
  end

  updateLocation = -> (force = false) do
    location = URL.new(base, window.location)

    options.filter = Array(filters).join(',')
    options.delete(:filter) if filters.size == 0

    search = []
    options.each_pair do |key, value|
      search << (value == undefined ? key : "#{key}=#{encodeURIComponent(value)}")
    end

    location.search = search.empty? ? "" : "#{search.join('&')}"
    return if !force && window.location.to_s == location.to_s

    history.replaceState({}, null, location.to_s)

    return if document.getElementById('js').style.display == 'none'

    # update JavaScript
    event = MouseEvent.new(:click, bubbles: true, cancelable: true, view: window)
    document.querySelector('input[type=submit]').dispatchEvent(event)
  end

  optionDialog = document.getElementById('option')
  optionInput = optionDialog.querySelector('sl-input')
  optionClose = optionDialog.querySelector('sl-button[slot="footer"]')

  optionDialog.addEventListener 'sl-initial-focus' do
    event.preventDefault()
    optionInput.setFocus(preventScroll: true)
  end

  optionClose.addEventListener 'click' do
    options[optionDialog.label] = optionInput.value
    optionDialog.hide()
  end

  document.getElementById('ast').addEventListener 'sl-change' do
    updateLocation(true)
  end

  document.querySelectorAll('sl-dropdown').each do |dropdown|
    menu = dropdown.querySelector('sl-menu')
    dropdown.addEventListener 'sl-show', -> {
      menu.style.display = 'block'
    }, once: true

    menu.addEventListener 'sl-select' do |event|
      item = event.detail.item

      if dropdown.id == 'options'
        item.checked = !item.checked
        name = item.textContent

        if options.respond_to? name
          options.delete(name)
        elsif item.dataset.args
          event.target.parentNode.hide()
          dialog = document.getElementById('option')
          dialog.label = name
          dialog.querySelector('sl-input').value = options[name] || ''
          dialog.show()
        else
          options[name] = undefined
        end

      elsif dropdown.id == 'filters'

        item.checked = !item.checked
        name = item.textContent
        filters.add(name) unless filters.delete!(name)

      elsif dropdown.id == 'eslevel'

        button = event.target.parentNode.querySelector('sl-button')
        value = item.textContent
        options['es' + value] = undefined if value != "default"
        event.target.querySelectorAll('sl-menu-item').each do |option|
          option.checked = (option == item)
          next if option.value == 'default' || option.value == value
          options.delete('es' + option.value)
        end
        button.textContent = value

      end

      updateLocation()
    end
  end

  ###################################################################################

  await Promise.new(->(resolve, reject) {
    if defined? CodeMirror
      resolve()
    else
      document.body.addEventListener 'CodeMirror-ready', resolve, once: true
    end
  })

  # create an editor below the textarea, then hide the textarea
  textarea = document.querySelector('textarea.ruby')
  editorDiv = document.createElement('div')
  editorDiv.classList.add('editor', 'ruby')
  textarea.parentNode.insertBefore(editorDiv, textarea.nextSibling)
  textarea.style.display = 'none'

  # create an editor below the textarea, then hide the textarea
  rubyEditor = CodeMirror.rubyEditor(editorDiv) do |value|
    textarea.value = value
    event = MouseEvent.new 'click', bubbles: true, cancelable: true, view: window
    document.querySelector('input[type=submit]').dispatchEvent(event)
  end

  # focus on the editor
  rubyEditor.focus()

  # first submit may come from the livedemo itself; if that occurs
  # copy the textarea value into the editor
  document.querySelector('input[type=submit]').addEventListener 'click', -> {
    return unless textarea.value
    return unless rubyEditor.state.doc.empty?

    rubyEditor.dispatch(
      changes: {from: 0, to: rubyEditor.state.doc.length, insert: textarea.value}
    )
  }, once: true

  # create another editor below the output
  jsout = document.querySelector('#js .js')
  outputDiv = document.createElement('div')
  outputDiv.classList.add('editor', 'js')
  jsout.parentNode.insertBefore(outputDiv, jsout.nextSibling)

  jsEditor = CodeMirror.jsEditor(outputDiv)

  observer = MutationObserver.new do |mutationsList, observer|
    mutationsList.each do |mutation|
      if mutation.type == 'childList'
        jsEditor.dispatch(
          changes: {from: 0, to: jsEditor.state.doc.length, insert: jsout.textContent}
        )
      elsif mutation.type == 'attributes'
        if jsout.classList.contains? "exception"
          jsout.style.display = 'block'
          outputDiv.style.display = 'none'
        else
          jsout.style.display = 'none'
          outputDiv.style.display = 'block'
        end
      end
    end
  end

  observer.observe(jsout, attributes: true, childList: true, subtree: true)

  ###################################################################################

  await Promise.new(->(resolve, reject) {
    if defined? Ruby2JS
      resolve()
    else
      document.body.addEventListener 'Ruby2JS-ready', resolve, once: true
    end
  })

  jsdiv = document.querySelector('div#js')
  jspre = jsdiv.querySelector('pre')
  convert = document.querySelector('input.btn')
  ast = document.getElementById('ast')
  parsed = document.getElementById('parsed')
  filtered = document.getElementById('filtered')

  # convert query into options
  def parse_options()
    options = {filters: []}
    search = document.location.search
    return options if search == ''

    search[1..-1].split('&').each do |parameter|
      name, value = parameter.split('=', 2)
      value = value ? decodeURIComponent(value.gsub('+', ' ')) : true

      if name == :filter
        name = :filters
        value = [] if value == true
      elsif name == :identity
        value = name
        name = :comparison
      elsif name == :nullish
        value = name
        name = :or
      elsif name =~ /^es\d+$/
        value = name[2..-1].to_i
        name = :eslevel
      end

      options[name] = value
    end

    return options
  end

  # convert AST into displayable form
  def walk(ast, indent='', tail='', last=true)
    return [] unless ast
    output = ["<div class=#{ast.location == Ruby2JS.nil ? 'unloc' : 'loc'}>"]
    output << "#{indent}<span class=hidden>s(:</span>#{ast.type}"
    output << '<span class=hidden>,</span>' unless ast.children.empty?

    if ast.children.any? {|child| child.is_a? Ruby2JS::AST::Node}
      ast.children.each_with_index do |child, index|
        ctail = index == ast.children.length - 1 ? ')' + tail : ''
        lastc = last && !ctail.empty?

        if child.is_a? Ruby2JS::AST::Node
          output.push *walk(child, "  #{indent}", ctail, lastc)
        else
          output << "<div>#{indent}  "

          if child.is_a? String and child =~ /\A[!-~]+\z/
            output << ":#{child}"
          else
            output << child == Ruby2JS.nil ? 'nil' : child.inspect
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
          output << " #{child == Ruby2JS.nil ? 'nil' : child.inspect}"
        end
        output << '<span class=hidden>,</span>' unless index == ast.children.length - 1
      end
      output << "<span class=hidden>)#{tail}#{',' unless last}</span>"
      output << ' ' if last
    end

    output << '</div>'

    return output
  end

  # update output on every keystroke in textarea
  document.querySelector('textarea').addEventListener :input do
    event = MouseEvent.new('click', bubbles: true, cancelable: true, view: window)
    document.querySelector('input[type=submit]').dispatchEvent(event)
  end

  # process convert button
  convert.addEventListener :click do |event|
    event.preventDefault()

    ruby = document.querySelector('textarea').value
    js = show_ast = nil
    begin
      js = Ruby2JS.convert(ruby, parse_options())
      jspre.classList.remove 'exception'
      show_ast = ast.checked
    rescue SyntaxError => e
      js = e.diagnostic || e
      jspre.classList.add 'exception'
    rescue => e
      js = e.inspect
      jspre.classList.add 'exception'
    end

    if ast.checked and not jspre.classList.contains('exception')
      raw, comments = Ruby2JS.parse(ruby)
      trees = [walk(raw).join(''), walk(js.ast).join('')]
      parsed.querySelector('pre').innerHTML = trees[0]
      parsed.style.display = 'block'
      if trees[0] == trees[1]
        filtered.style.display = 'none'
      else
        filtered.querySelector('pre').innerHTML = trees[1]
        filtered.style.display = 'block'
      end
    else
      parsed.style.display = 'none'
      filtered.style.display = 'none'
    end

    jspre.textContent = js.to_s
    jsdiv.style.display = js.to_s.empty? ? 'none' : 'block'
  end

  # make inputs match query
  parse_options().each_pair do |name, value|
    puts [name, value]
    case name
    when :ruby
      document.querySelector('textarea').value = value
    when :filters
      nodes = document.getElementById(:filters).parentNode.querySelectorAll('sl-menu-item')
      nodes.forEach do |node|
        node.checked = true if value.include? node.textContent
      end
    when :eslevel
      eslevel = document.getElementById('eslevel')
      eslevel.querySelector('sl-button').textContent = value.to_s
      eslevel.querySelector("sl-menu-item[value='']").checked = false
      eslevel.querySelector("sl-menu-item[value='#{value}']").checked = true
    when :comparison
      document.querySelector("sl-menu-item[name=identity]").checked = true if value == :identity
    when :nullish
      document.querySelector("sl-menu-item[name=or]").checked = true if value == :nullish
    else
      checkbox = document.querySelector("sl-menu-item[name=#{name}]")
      checkbox.checked = true if checkbox
    end
  end

  # initial conversion if textarea is not empty
  unless document.querySelector('textarea').value.empty?
    event = MouseEvent.new(:click, bubbles: true, cancelable: true, view: window)
    document.querySelector('input[type=submit]').dispatchEvent(event)
  end

}[]
