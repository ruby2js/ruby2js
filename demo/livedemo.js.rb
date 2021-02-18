async {

  # This superclass is intended for Stimulus controllers that not only
  # connect to Stimulus, but pair with each other.  Subclasses of
  # DemoController don't define connect methods, instead they define 
  # setup methods.  Subclasses that initiate pairing also define target and
  # pair methods.  A findController method is defined to help find targets.
  #
  # Examples: OptionsController sends options to RubyControllers.
  # RubyControllers send scripts to JSControllers.
  #
  # codemirror_ready and ruby2js_ready methods can be used to wait for these
  # scripts to load before proceeding.
  #
  class DemoController < Stimulus::Controller
    # subclasses are expected to override this method
    def setup()
    end

    # if subclasses override this, they need to call super
    async def connect()
      await setup()
      pair(target) if target

      application.controllers.select do |controller|
        controller.pair(self) if controller.target == self
      end
    end

    # override this method in classes that initiate pairing
    def target
      @target = nil
    end

    # logic to be executed when the second half of the pair connects to
    # Stimulus, independent of the order of the connection to Stimulus.
    def pair(target)
    end

    # logic to be executed when the second half of the pair disconnects.
    # Stimulus may reuse controller objects, so a controller needs to
    # return to a state where they seek out new targets
    def unpair()
      @target = nil
    end

    # if subclasses override this method, they need to call super
    def disconnect()
      application.controllers.select do |controller|
        controller.unpair() if controller.target == self
      end
    end

    # utility method, primarily to be used by target attribute accessors.
    # As the name indicates, it will find a controller that is either
    # connected to a given element or of a given type, or both.
    def findController(element: nil, type: nil)
      return application.controllers.find do |controller|
        (not element or controller.element == element) and
        (not type or controller.is_a? type)
      end
    end

    # wait for ruby2js.js to load and Ruby2JS to be defined.
    def ruby2js_ready
      Promise.new do |resolve, reject|
        if defined? Ruby2JS
          resolve()
        else
          document.body.addEventListener 'Ruby2JS-ready', resolve, once: true
        end
      end
    end

    # wait for codemirror.js to load and CodeMirror to be defined.
    def codemirror_ready
      Promise.new do |resolve, reject|
        if defined? CodeMirror
          resolve()
        else
          document.body.addEventListener 'CodeMirror-ready', resolve, once: true
        end
      end
    end
  end

  #############################################################################

  # control all of the drop-downs and checkboxes: ESLevel, AST?, Filters,
  # Options.

  class OptionsController < DemoController
    def target
      @target ||= findController type: RubyController,
        element: document.querySelector(element.dataset.target)
    end

    def pair(target)
      target.options = options = parse_options()
      target.contents = options.ruby if options.ruby
    end

    def setup()
      # determine base URL and what filters and options are selected
      @filters = new Set()
      @options = {}
      window.location.search.scan(/(\w+)(=([^&]*))?/).each do |match|
        @options[match[0]] = match[2] && decodeURIComponent(match[2])
      end
      if @options.filter
        @options.filter.split(',').each {|option| @filters.add(option)}
      end

      optionDialog = document.getElementById('option')
      optionInput = optionDialog.querySelector('sl-input')
      optionClose = optionDialog.querySelector('sl-button[slot="footer"]')

      optionDialog.addEventListener 'sl-initial-focus' do
        event.preventDefault()
        optionInput.setFocus(preventScroll: true)
      end

      optionClose.addEventListener 'click' do
        @options[optionDialog.label] = optionInput.value
        optionDialog.hide()
      end

      ast = document.getElementById('ast')
      ast.addEventListener 'sl-change' do
        target.ast = ast.checked if target
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

            if @options.respond_to? name
              @options.delete(name)
            elsif item.dataset.args
              event.target.parentNode.hide()
              dialog = document.getElementById('option')
              dialog.label = name
              dialog.querySelector('sl-input').value = @options[name] || ''
              dialog.show()
            else
              @options[name] = undefined
            end

          elsif dropdown.id == 'filters'

            item.checked = !item.checked
            name = item.textContent
            @filters.add(name) unless @filters.delete!(name)

          elsif dropdown.id == 'eslevel'

            button = event.target.parentNode.querySelector('sl-button')
            value = item.textContent
            @options['es' + value] = undefined if value != "default"
            event.target.querySelectorAll('sl-menu-item').each do |option|
              option.checked = (option == item)
              next if option.value == 'default' || option.value == value
              @options.delete('es' + option.value)
            end
            button.textContent = value

          end

          updateLocation()
        end
      end

      # make inputs match query
      parse_options().each_pair do |name, value|
        case name
        when :filters
          nodes = document.getElementById(:filters).parentNode.querySelectorAll('sl-menu-item')
          nodes.forEach do |node|
            node.checked = true if value.include? node.textContent
          end
        when :eslevel
          eslevel = document.getElementById('eslevel')
          eslevel.querySelector('sl-button').textContent = value.to_s
          eslevel.querySelectorAll("sl-menu-item").each {|item| item.checked = false}
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
    end

    def updateLocation()
      base = window.location.pathname
      location = URL.new(base, window.location)

      @options.filter = Array(@filters).join(',')
      @options.delete(:filter) if @filters.size == 0

      search = []
      @options.each_pair do |key, value|
        search << (value == undefined ? key : "#{key}=#{encodeURIComponent(value)}")
      end

      location.search = search.empty? ? "" : "#{search.join('&')}"
      return if window.location.to_s == location.to_s

      history.replaceState({}, null, location.to_s)

      return if document.getElementById('js').style.display == 'none'

      # update JavaScript
      target.options = parse_options() if target
    end

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

  end

  ###################################################################################

  # control the Ruby editor.
  class RubyController < DemoController
    def target
      @target ||= findController type: JSController,
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

    async def setup()
      @ast = false
      @options ||= {}

      await codemirror_ready

      # create an editor below the textarea, then hide the textarea
      textarea = element.querySelector('textarea.ruby')
      editorDiv = document.createElement('div')
      editorDiv.classList.add('editor', 'ruby')
      textarea.parentNode.insertBefore(editorDiv, textarea.nextSibling)
      textarea.style.display = 'none'

      # create an editor below the textarea, then hide the textarea
      @rubyEditor = CodeMirror.rubyEditor(editorDiv) do |value|
        textarea.value = value
        convert()
      end

      # focus on the editor
      @rubyEditor.focus()

      # set initial contents from text area 
      contents = textarea.value if textarea.value

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
      return unless target and @rubyEditor and defined? Ruby2JS
      parsed = document.getElementById('parsed')
      filtered = document.getElementById('filtered')

      parsed.style.display = 'none'
      filtered.style.display = 'none'

      ruby = @rubyEditor.state.doc.to_s
      begin
        js = Ruby2JS.convert(ruby, @options)
        target.content = js.to_s

        if @ast
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
  end

  #############################################################################

  # control the JS (read-only) editor.
  class JSController < DemoController
    async def setup()
      await codemirror_ready

      # create another editor below the output
      @jsout = element.querySelector('.js')
      @outputDiv = document.createElement('div')
      @outputDiv.classList.add('editor', 'js')
      @jsout.parentNode.insertBefore(@outputDiv, @jsout.nextSibling)

      @jsEditor = CodeMirror.jsEditor(@outputDiv)

      @jspre = element.querySelector('pre')

      element.style.display = 'block'
    end

    # update contents
    def content=(script)
      return unless @jsEditor

      @jsEditor.dispatch(
        changes: {from: 0, to: @jsEditor.state.doc.length, insert: script}
      )

      @jspre.classList.remove 'exception'
      @jsout.style.display = 'none'
      @outputDiv.style.display = 'block'
    end

    # display an error
    def exception=(message)
      return unless @jsEditor
      @jspre.textContent = message
      @jspre.classList.add 'exception'
      @jsout.style.display = 'block'
      @outputDiv.style.display = 'none'
    end
  end

  #############################################################################

  application = Stimulus::Application.start()
  application.register("options", OptionsController)
  application.register("ruby", RubyController)
  application.register("js", JSController)

}[]
