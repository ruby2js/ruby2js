# control the Ruby editor.
class RubyController < DemoController
  attr_reader :source

  def source
    return @source ||= findController(type: OptionsController,
      element: document.querySelector(element.dataset.source))
  end

  def ast=(value)
    @ast = value
    convert()
  end

  attr_reader :options

  def options=(value)
    @options = value
    convert()
  end

  def pair(controller)
    super
    convert()
  end

  # Build SFC output from script and template
  def build_sfc(script, template, framework)
    # Note: use explicit return to ensure JS transpilation returns the value
    case framework
    when :vue
      return "<script setup>\n#{script}\n</script>\n\n<template>\n#{template}\n</template>"
    when :svelte
      return "<script>\n#{script}\n</script>\n\n#{template}"
    when :astro
      return "---\n#{script}\n---\n\n#{template}"
    else
      # Default Vue-style if no framework detected
      return "<script setup>\n#{script}\n</script>\n\n<template>\n#{template}\n</template>"
    end
  end

  async def setup()
    @ast = false
    @options ||= {}
    @opal_ready = false

    # parse options provided (if any)
    if element.dataset.options
      begin
        @options = JSON.parse(element.dataset.options)
      rescue => e
        puts e.message
      end
    end

    await codemirror_ready()

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

    # populate editor with initial contents
    self.contents = contents if contents

    # focus on the editor without scrolling page
    @rubyEditor.focus(preventScroll: true)

    # load Opal bundle if not already loaded
    await load_opal()

    convert()
  end

  # Load the Opal Ruby2JS bundle dynamically (singleton pattern to prevent double-loading)
  async def load_opal()
    # If already loaded, we're done
    if defined? Ruby2JS
      @opal_ready = true
      return
    end

    # If already loading, wait for the existing load to complete
    if @@opal_loading_promise
      await @@opal_loading_promise
      @opal_ready = true
      return
    end

    # Start loading - store promise so other instances can await it
    @@opal_loading_promise = Promise.new do |resolve, reject|
      script = document.createElement('script')
      script.src = "#{window.location.origin}/demo/ruby2js.js"
      script.async = true
      script.addEventListener(:load, resolve)
      script.addEventListener(:error, reject)
      document.head.appendChild(script)
    end

    await @@opal_loading_promise

    # Wait for Ruby2JS to be ready
    await ruby2js_ready()

    @opal_ready = true
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
    return unless targets.size > 0 and @rubyEditor and @opal_ready
    parsed = document.getElementById('parsed')
    filtered = document.getElementById('filtered')

    parsed.style.display = 'none' if parsed
    filtered.style.display = 'none' if filtered

    ruby = @rubyEditor.state.doc.to_s
    begin
      # Check for __END__ marker indicating SFC format
      is_sfc = ruby.include?("__END__")

      if is_sfc
        # Split into Ruby code and template
        parts = ruby.split(/^__END__\r?\n?/, 2)
        ruby_code = parts[0]
        template = parts[1] || ''

        # Get framework from template option (vue, svelte, astro)
        # Note: use string key since @options is a JS object from JSON.parse
        framework = (@options['template'] || 'vue').to_sym

        # Convert the Ruby code with template option
        js = Ruby2JS.convert(ruby_code, @options)

        # Build the SFC output
        sfc_output = build_sfc(js.to_s.strip, template.strip, framework)
        targets.each {|target| target.contents = sfc_output}
      else
        # Normal conversion (no __END__)
        js = Ruby2JS.convert(ruby, @options)
        targets.each {|target| target.contents = js.to_s}
      end

      # AST display (only for non-SFC mode as AST doesn't include template)
      if !is_sfc and ruby != '' and @ast and parsed and filtered
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
      targets.each {|target| target.exception = e.diagnostic || e}
    rescue => e
      targets.each {|target| target.exception = e.to_s + e.stack}
    end
  end

  # convert AST into displayable form
  def walk(ast, indent='', tail='', last=true)
    return [] unless ast
    output = ["<div class=#{Ruby2JS.nil == ast.location ? 'unloc' : 'loc'}>"]
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
          output << " #{Ruby2JS.nil == child ? 'nil' : child.inspect}"
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
