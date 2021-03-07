class EvalController < DemoController
  SCRIPTS = {
    LitElement: "/demo/litelement.js",
    React: "https://unpkg.com/react@17/umd/react.production.min.js",
    ReactDOM: "https://unpkg.com/react-dom@17/umd/react-dom.production.min.js",
    Remarkable: "https://cdnjs.cloudflare.com/ajax/libs/remarkable/2.0.1/remarkable.min.js"
  }

  def source
    @source ||= findController type: RubyController,
      element: document.querySelector(element.dataset.source)
  end

  def setup()
    @demo = document.createElement('div')
    @demo.id = 'd' + Date.now() + Math.random().toString().slice(2)
    shadow = @demo.attachShadow(mode: :open)
    @script = nil

    # copy missing document functions to shadow
    for prop in document
      next unless typeof document[prop] == 'function'
      next if shadow.respond_to? prop
      shadow[prop] = ->(*args) {document[prop].call(document, *args)}
    end

    # add css (if any) to shadow
    css = document.querySelector(element.dataset.css)
    if css
      style = document.createElement('style')
      style.textContent = css.textContent
      shadow.appendChild(style)
    end

    # add html (if any) to shadow; handling both templates and markdown code
    html = document.querySelector(element.dataset.html)
    if html
      @demo.classList.add 'demo-results'
      div = document.createElement('div')
      if html.content
        html.content.childNodes.each do |node|
          div.appendChild node.cloneNode(true)
        end
      else
        div.innerHTML = html.textContent
      end
      shadow.appendChild(div)
    end

    # add div to document
    element.appendChild(@demo)

    # set up listener for script failures.  Ensure every error is only
    # reported once (I'm looking at you, Safari)
    @pending = nil
    @timestamp = 0
    window.addEventListener :error do |event|
      @pending.reject(event.error) if @pending and event.timestamp != @timestamp
      @timestamp = event.timestamp
      @pending = nil
    end

    # listener for frame events
    window.addEventListener :message do |event|
      console.log(event.data)
      if event.data == 'load'
        @pending.resolve() if @pending
        @pending = nil
      elsif event.data.error
        @pending.reject(event.data.error) if @pending
        @pending = nil
      elsif event.data.resize
        @demo.height = event.data.resize
      end
    end
  end

  async def load(content)
    first_load = !@script

    # remove previous script (if any)
    if @script
      stop_application()
      @script.remove()
    end

    # Stimulus support: remove imports, start application, register controllers
    content.gsub! /^import .*;\n\s*/, ''

    controllers = []
    content.gsub! /^export (default )?(class (\w+) extends Stimulus.Controller)/ do
      controllers << $3
      $2
    end

    unless controllers.empty?
      content += ";\n\nwindow.application = Stimulus.Application.start(document.lastElementChild)"
    end

    controllers.each do |controller|
      name = controller.sub(/Controller$/, '').
        gsub(/[a-z][A-Z]/) {|match| "#{match[0]}-#{match[1]}"}.downcase()
      content += ";\nwindow.application.register(#{name.inspect}, #{controller})"
    end

    # if a script is currently loading, wait before proceeding
    if @pending
      await Promise.new do |resolve, reject|
        interval = setInterval(100) do
          unless @pending
            clearInterval interval
            resolve()
          end
        end
      end
    end

    # append script to the demo
    begin
      # remove previous exceptions
      Array(element.querySelectorAll('.exception')).each do |exception|
        exception.remove()
      end

      # run the script; throwing an error if either @script.onerror or
      # an error event is sent to the window (see above).  The latter
      # handles syntax errors in the script itself.
      await Promise.new async do |resolve, reject|
        @pending = { resolve: resolve, reject: reject }

        # safari doesn't run onload handlers for inline scripts
        setTimeout(2_000) {@pending.resolve() if @pending; @pending = nil}

        if content.include? 'customElements.define'
          await load_iframe(content)
        else
          await load_shadow(content)
        end
      end

      # remove previous exceptions again to handle race conditions
      # Array(element.querySelectorAll('.exception')).each do |exception|
      #   exception.remove()
      # end
    rescue => error
      # display exception
      div = element.querySelector('.exception') || document.createElement('div')
      div.textContent = error
      div.classList.add('exception')
      element.appendChild(div)

      # downgrade eslevel if the script doesn't load the first time
      if first_load and @source&.options&.eslevel == 2022
        @source.options = {**@source.options, eslevel: 2021}
      end
    end
  end

  # Add script to the shadow element.  A shadow element provides some
  # encapsulation, but will share scripts that were previously loaded.
  # Also means that there is no need to replace the HTML.
  async def load_shadow(content)
    # load all dependencies
    SCRIPTS.each_pair do |name, src|
      if content =~ /\b#{name}\b/ and not window.respond_to? name
        await Promise.new do |resolve, reject|
          script = document.createElement('script')
          script.src = src
          script.async = true
          script.crossorigin = true

          script.addEventListener(:error, reject)
          script.addEventListener(:load, resolve)
          document.head.appendChild(script)
        end

        window.Remarkable = remarkable.Remarkable if name == 'Remarkable'
      end
    end

    @script = window.document.createElement('script')
    @script.textContent = "(document => {
      #{content};
      window.postMessage('load', '*')
    })(document.getElementById('#{@demo.id}').shadowRoot)"
    @demo.appendChild(@script)
  end

  # Add script to an iframe.  All scripts and custom elements need to be
  # reloaded.  Also repaints the HTML.  This is needed as there is no way to
  # unregister a custom element.
  async def load_iframe(content)
    # extract HTML from previous element
    if @demo.shadowRoot
      html = @demo.shadowRoot.innerHTML
    elsif @demo.contentWindow and @demo.contentWindow.document.body
      html = @demo.contentWindow.document.body.innerHTML
    else
      html = ''
    end

    # create a new document
    idoc = document.implementation.createHTMLDocument()
    idoc.body.innerHTML = html
    idoc.body.id = @demo.id

    # add the error watcher
    script = idoc.createElement('script')
    script.textContent = <<~JAVASCRIPT
      window.addEventListener('error', event => {
        window.parent.postMessage({resize: 10}, '*');
        window.parent.postMessage({error: event.error.message}, '*');
      });
    JAVASCRIPT
    idoc.head.appendChild(script)

    # load all dependencies
    SCRIPTS.each_pair do |name, src|
      if content =~ /\b#{name}\b/
        script = idoc.createElement('script')
        script.src = src
        script.crossorigin = true
        idoc.head.appendChild(script)
      end
    end

    # add the script
    script = idoc.createElement('script')
    script.textContent = <<~JAVASCRIPT
      #{content};

      window.addEventListener('load', () => {
        let height = document.documentElement.scrollHeight + 20;
        window.parent.postMessage({resize: height});
        window.parent.postMessage('load', '*');
      })
    JAVASCRIPT
    idoc.head.appendChild(script)

    # construct the iframe element
    iframe = document.createElement('iframe')
    iframe.srcdoc = '<!DOCTYPE html>' + idoc.documentElement.outerHTML
    iframe.id = @demo.id
    iframe.classList.add *@demo.classList
    iframe.height = @demo.height

    # insert into document
    @demo.parentNode.replaceChild(iframe, @demo)
    @demo = iframe
  end

  # update contents
  def contents=(script)
    load(script)
  end

  # ignore errors
  def exception=(message)
  end

  def teardown()
    stop_application()
    @demo.remove()
  end

  # stop and remove stimulus application
  def stop_application()
    if window.application
      window.application.controllers.each do |controller|
        controller.disconnect()
      end

      window.application.stop()
      delete window.application
    end
  end
end

