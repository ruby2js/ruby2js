# Control the Ruby editor using selfhost Ruby2JS
# This controller uses the selfhost bundle instead of Opal
class SelfhostRubyController < DemoController
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
    @selfhost_ready = false
    @filters_loaded = {}
    @erb_mode = element.dataset.erb == 'true'
    @erb_compiler = nil

    # parse options provided (if any)
    if element.dataset.options
      begin
        @options = JSON.parse(element.dataset.options)
      rescue => e
        console.error('[SelfhostRubyController] options parse error:', e.message)
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

    # load selfhost bundle
    await load_selfhost()

    convert()
  end

  # Load the selfhost Ruby2JS bundle
  async def load_selfhost()
    return if @selfhost_ready

    begin
      # Import the selfhost bundle - use absolute URL to prevent rollup from modifying path
      bundle_url = "#{window.location.origin}/demo/selfhost/ruby2js.js"
      selfhost = await import(bundle_url)
      @selfhost_convert = selfhost.convert
      @selfhost_parse = selfhost.parse
      @selfhost_Ruby2JS = selfhost.Ruby2JS
      @selfhost_ready = true

      # Load ERB compiler if in ERB mode
      if @erb_mode
        erb_url = "#{window.location.origin}/demo/selfhost/lib/erb_compiler.js"
        erb_module = await import(erb_url)
        @erb_compiler = erb_module.ErbCompiler
      end
    rescue => e
      console.error('[SelfhostRubyController] Failed to load selfhost bundle:', e.message)
    end
  end

  # Load a filter by name
  async def load_filter(name)
    return @filters_loaded[name] if @filters_loaded[name]

    # Map filter names to paths - use absolute URL to prevent rollup from modifying path
    rails_filters = %w[model controller routes schema seeds logger]
    if rails_filters.include?(name.downcase)
      path = "#{window.location.origin}/demo/selfhost/filters/rails/#{name.downcase}.js"
    elsif name.downcase == 'camelcase'
      path = "#{window.location.origin}/demo/selfhost/filters/camelCase.js"
    else
      path = "#{window.location.origin}/demo/selfhost/filters/#{name.downcase}.js"
    end

    begin
      await import(path)

      # Find the filter in Ruby2JS.Filter - use simple string comparison
      target = name.downcase.gsub(/[_\/]/, '')
      filter_obj = nil

      # Check main Filter namespace
      Object.keys(@selfhost_Ruby2JS.Filter || {}).forEach do |key|
        if key.downcase.gsub(/[_\/]/, '') == target
          filter_obj = @selfhost_Ruby2JS.Filter[key]
        end
      end

      # Check Rails namespace if not found
      if !filter_obj and @selfhost_Ruby2JS.Filter.Rails
        Object.keys(@selfhost_Ruby2JS.Filter.Rails).forEach do |key|
          if key.downcase.gsub(/[_\/]/, '') == target
            filter_obj = @selfhost_Ruby2JS.Filter.Rails[key]
          end
        end
      end

      if filter_obj
        @filters_loaded[name] = filter_obj
        return filter_obj
      end

      console.warn("Filter #{name} not found after loading")
      return nil
    rescue => e
      console.error("Failed to load filter #{name}:", e.message)
      return nil
    end
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

  # convert ruby to JS using selfhost, sending results to target Controller
  async def convert()
    return unless targets.size > 0 and @rubyEditor and @selfhost_ready
    parsed = document.getElementById('parsed')
    filtered = document.getElementById('filtered')

    parsed.style.display = 'none' if parsed
    filtered.style.display = 'none' if filtered

    ruby = @rubyEditor.state.doc.to_s

    begin
      # If in ERB mode, preprocess the template to Ruby code
      if @erb_mode and @erb_compiler
        compiler = @erb_compiler.new(ruby)
        ruby = compiler.src
      end

      # Check for __END__ marker indicating SFC format
      is_sfc = ruby.include?("__END__")

      # Load required filters
      filter_names = @options[:filters] || []

      # Handle preset option - load preset filters
      if @options[:preset] or @options['preset']
        preset_filters = %w[esm functions pragma return]
        preset_filters.each do |name|
          unless filter_names.include?(name)
            filter_names = preset_filters.concat(filter_names)
            break
          end
        end
      end

      loaded_filters = []

      # Add ERB filter if in ERB mode
      if @erb_mode
        erb_filter = await load_filter('erb')
        loaded_filters.push(erb_filter) if erb_filter
      end

      # Use index-based iteration to get actual values, not indices
      i = 0
      while i < filter_names.length
        name = filter_names[i]
        filter = await load_filter(name)
        loaded_filters.push(filter) if filter
        i += 1
      end

      # Build options for selfhost convert
      convert_options = {
        eslevel: @options[:eslevel] || 2022,
        filters: loaded_filters
      }

      # Add other options
      convert_options[:comparison] = @options[:comparison] if @options[:comparison]

      if is_sfc
        # Split into Ruby code and template
        parts = ruby.split(/^__END__\r?\n?/, 2)
        ruby_code = parts[0]
        template = parts[1] || ''

        # Get framework from template option (vue, svelte, astro)
        # Note: use string key since @options is a JS object from JSON.parse
        framework = (@options['template'] || 'vue').to_s.to_sym

        # Convert the Ruby code
        result = @selfhost_convert.call(ruby_code, convert_options)

        # Build the SFC output
        sfc_output = build_sfc(result.to_s.strip, template.strip, framework)
        targets.each {|target| target.contents = sfc_output}
      else
        # Convert using selfhost
        result = @selfhost_convert.call(ruby, convert_options)
        js = result.to_s

        targets.each {|target| target.contents = js}
      end

      # AST display (only for non-SFC mode)
      if !is_sfc and ruby != '' and @ast and parsed and filtered
        raw, comments = @selfhost_parse.call(ruby)
        trees = [walk(raw).join(''), walk(result.ast).join('')]

        parsed.querySelector('pre').innerHTML = trees[0]
        parsed.style.display = 'block'
        if trees[0] != trees[1]
          filtered.querySelector('pre').innerHTML = trees[1]
          filtered.style.display = 'block'
        end
      end
    rescue => e
      console.error("[SelfhostRubyController] conversion error:", e)
      targets.each {|target| target.exception = e.to_s}
    end
  end

  # convert AST into displayable form
  def walk(ast, indent='', tail='', last=true)
    return [] unless ast
    output = ["<div class=#{nil == ast.location ? 'unloc' : 'loc'}>"]
    output << "#{indent}<span class=hidden>s(:</span>#{ast.type}"
    output << '<span class=hidden>,</span>' unless ast.children.empty?

    if ast.children.any? {|child| child.is_a?(Object) && child.respond_to?(:children)}
      ast.children.each_with_index do |child, index|
        ctail = index == ast.children.length - 1 ? ')' + tail : ''
        lastc = last && !ctail.empty?

        if child.is_a?(Object) && child.respond_to?(:children)
          output.push *walk(child, "  #{indent}", ctail, lastc)
        else
          output << "<div>#{indent}  "

          if child.is_a? String and child =~ /\A[!-~]+\z/
            output << ":#{child}"
          else
            output << child == nil ? 'nil' : child.inspect
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
          output << " #{nil == child ? 'nil' : child.inspect}"
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
