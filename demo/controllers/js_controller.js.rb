# control the JS (read-only) editor.
class JSController < DemoController
  def source
    return @source if @source

    # If data-source is specified, use that element
    source_selector = element.dataset.source
    if source_selector
      @source = findController type: RubyController,
        element: document.querySelector(source_selector)
      return @source
    end

    # Otherwise, find the RubyController in the same parent (e.g., same combo tab group)
    parent = element.parentElement
    if parent
      ruby_div = parent.parentElement&.querySelector('[data-controller="ruby"]')
      @source = findController type: RubyController, element: ruby_div if ruby_div
    end

    @source
  end

  async def setup()
    await codemirror_ready

    # create another editor below the output
    @outputDiv = document.createElement('div')
    @outputDiv.classList.add('editor', 'js')
    element.appendChild(@outputDiv)

    @jsEditor = CodeMirror.jsEditor(@outputDiv)

    @jspre = element.querySelector('pre.js')
    if @jspre
      contents = @jspre.value
    else
      @jspre = document.createElement('pre')
      @jspre.classList.add 'js'
      element.appendChild(@jspre)

      # set initial contents from markdown code area, then hide the code
      nextSibling = element.nextElementSibling
      if nextSibling and nextSibling.classList.contains('language-js')
        contents = nextSibling.textContent.rstrip()
        nextSibling.style.display = 'none'
      end
    end

    element.style.display = 'block'
  end

  # update contents
  def contents=(script)
    return unless @jsEditor

    @jsEditor.dispatch(
      changes: {from: 0, to: @jsEditor.state.doc.length, insert: script}
    )

    @jspre.classList.remove 'exception'
    @jspre.style.display = 'none'
    @outputDiv.style.display = 'block'
  end

  # display an error
  def exception=(message)
    return unless @jsEditor
    @jspre.textContent = message
    @jspre.classList.add 'exception'
    @jspre.style.display = 'block'
    @outputDiv.style.display = 'none'
  end

  # remove editor on disconnect
  def teardown()
    element.querySelector('.editor.js').remove()
  end
end
