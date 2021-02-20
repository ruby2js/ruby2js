# control the Ruby editor.
class RubyController < DemoController
  def source
    @source ||= findController type: OptionsController,
      element: document.querySelector(element.dataset.target)
  end

  def ast=(value)
    @ast = value
    convert()
  end

  def options=(value)
    @options = value
    convert()
  end

  def pair(controller)
    super
    convert()
  end

  async def setup()
    @ast = false
    @options ||= {}

    # parse options provided (if any)
    if element.dataset.options
      begin
        options = JSON.parse(element.dataset.options)
      rescue => e
        puts e.message
      end
    end

    await codemirror_ready

    # create an editor
    editorDiv = document.createElement('div')
    editorDiv.classList.add('editor', 'ruby')
    @rubyEditor = CodeMirror.rubyEditor(editorDiv) do |value|
      convert()
    end
    element.appendChild(editorDiv)

    # set initial contents from text area, then hide the textarea
    textarea = element.querySelector('textarea')
    if textarea
      contents = textarea.value if textarea.value
      textarea.style.display = 'none'
    end

    # set initial contents from markdown code area, then hide the code
    nextSibling = element.nextElementSibling
    if nextSibling and nextSibling.classList.contains('language-ruby')
      contents = nextSibling.textContent.rstrip()
      nextSibling.style.display = 'none'
    end

    # focus on the editor
    @rubyEditor.focus()

    # do an initial conversion as soon as Ruby2JS comes online
    await ruby2js_ready

    convert()
  end

  # update editor contents from another source
  def contents=(script)
    if @rubyEditor
      @rubyEditor.dispatch(
         changes: {from: 0, to: @rubyEditor.state.doc.length, insert: script}
      )
    else
      textarea = element.querySelector('textarea.ruby')
      textarea.value = script if textarea
    end

    convert()
  end

  # convert ruby to JS, sending results to target Controller
  def convert()
    return unless targets.size > 0 and @rubyEditor and defined? Ruby2JS
    parsed = document.getElementById('parsed')
    filtered = document.getElementById('filtered')

    parsed.style.display = 'none' if parsed
    filtered.style.display = 'none' if filtered

    ruby = @rubyEditor.state.doc.to_s
    begin
      js = Ruby2JS.convert(ruby, @options)
      targets.each {|target| target.contents = js.to_s}

      if @ast and parsed and filtered
        raw, comments = Ruby2JS.parse(ruby)
        trees = [walk(raw).join(''), walk(js.ast).join('')]

        parsed.querySelector('pre').innerHTML = trees[0]
        parsed.style.display = 'block'
        if trees[0] != trees[1]
          filtered.querySelector('pre').innerHTML = trees[1]
          filtered.style.display = 'block'
        end
      end
    rescue SyntaxError => e
      target.exception = e.diagnostic || e
    rescue => e
      target.exception = e.to_s + e.stack
    end
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

  # remove editor on disconnect
  def teardown()
    element.querySelector('.editor.ruby').remove()
  end
end
