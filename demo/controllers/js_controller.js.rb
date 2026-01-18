# control the JS (read-only) editor.
class JSController < DemoController
  attr_reader :source

  def source
    return @source if @source

    # If data-source is specified, use that element
    source_selector = element.dataset.source
    if source_selector
      source_element = document.querySelector(source_selector)
      # Try RubyController first, then SelfhostRubyController
      @source = findController(type: RubyController, element: source_element) ||
                findController(type: SelfhostRubyController, element: source_element)
      return @source
    end

    # Otherwise, find the RubyController in the same parent (e.g., same combo tab group)
    parent = element.parentElement
    if parent
      # Try ruby controller first, then selfhost-ruby controller
      ruby_div = parent.parentElement&.querySelector('[data-controller="ruby"]') ||
                 parent.parentElement&.querySelector('[data-controller="selfhost-ruby"]')
      if ruby_div
        @source = findController(type: RubyController, element: ruby_div) ||
                  findController(type: SelfhostRubyController, element: ruby_div)
      end
    end

    @source
  end

  async def setup()
    await codemirror_ready()

    # create editor containers
    @jsOutputDiv = document.createElement('div')
    @jsOutputDiv.classList.add('editor', 'js')
    element.appendChild(@jsOutputDiv)

    @sfcOutputDiv = document.createElement('div')
    @sfcOutputDiv.classList.add('editor', 'sfc')
    @sfcOutputDiv.style.display = 'none'
    element.appendChild(@sfcOutputDiv)

    # create both editors
    @jsEditor = CodeMirror.jsEditor(@jsOutputDiv)
    @sfcEditor = CodeMirror.sfcEditor(@sfcOutputDiv)

    # track which editor is active
    @is_sfc = false

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

  # detect if content is an SFC (contains <script and <template or similar)
  def is_sfc?(content)
    return false unless content
    # Vue/Svelte SFC pattern
    return true if content.include?('<script') && content.include?('<template')
    # Svelte without explicit template (just <script> + HTML)
    return true if content.include?('<script>') && content =~ /<\/script>\s*\n\s*</
    # Astro pattern (--- frontmatter ---)
    return true if content.start_with?('---') && content.include?('---', 3)
    false
  end

  # update contents
  def contents=(script)
    return unless @jsEditor && @sfcEditor

    sfc_mode = is_sfc?(script)

    if sfc_mode
      @sfcEditor.dispatch(
        changes: {from: 0, to: @sfcEditor.state.doc.length, insert: script}
      )
      @jsOutputDiv.style.display = 'none'
      @sfcOutputDiv.style.display = 'block'
    else
      @jsEditor.dispatch(
        changes: {from: 0, to: @jsEditor.state.doc.length, insert: script}
      )
      @jsOutputDiv.style.display = 'block'
      @sfcOutputDiv.style.display = 'none'
    end

    @is_sfc = sfc_mode
    @jspre.classList.remove 'exception'
    @jspre.style.display = 'none'
  end

  # display an error
  def exception=(message)
    return unless @jsEditor
    @jspre.textContent = message
    @jspre.classList.add 'exception'
    @jspre.style.display = 'block'
    @jsOutputDiv.style.display = 'none'
    @sfcOutputDiv.style.display = 'none'
  end

  # remove editor on disconnect
  def teardown()
    element.querySelector('.editor.js')&.remove()
    element.querySelector('.editor.sfc')&.remove()
  end
end
