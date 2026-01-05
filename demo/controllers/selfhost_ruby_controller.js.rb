# Control the Ruby editor using selfhost Ruby2JS
# This controller uses the selfhost bundle instead of Opal
class SelfhostRubyController < DemoController
  def source
    @source ||= findController type: OptionsController,
      element: document.querySelector(element.dataset.source)
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

  async def setup()
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

    ruby = @rubyEditor.state.doc.to_s

    begin
      # If in ERB mode, preprocess the template to Ruby code
      if @erb_mode and @erb_compiler
        compiler = @erb_compiler.new(ruby)
        ruby = compiler.src
      end

      # Load required filters
      filter_names = @options[:filters] || []
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

      # Convert using selfhost
      result = @selfhost_convert.call(ruby, convert_options)
      js = result.to_s

      targets.each {|target| target.contents = js}
    rescue => e
      console.error("[SelfhostRubyController] conversion error:", e)
      targets.each {|target| target.exception = e.to_s}
    end
  end

  # remove editor on disconnect
  def teardown()
    element.querySelector('.editor.ruby').remove()
  end
end
