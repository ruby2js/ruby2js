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

    # customElements can't be undefined, so create an iframe to contain
    # the definition
    if content.include? 'customElements.define'
      # construct the iframe element
      iframe = document.createElement('iframe')
      iframe.id = @demo.id
      iframe.classList.add *@demo.classList
      iframe.height = @demo.height

      # extract HTML from previous element
      if @demo.shadowRoot
        html = @demo.shadowRoot.innerHTML
      elsif @demo.contentWindow
        html = @demo.contentWindow.document.body.innerHTML
      else
        html = ''
      end

      # insert into document
      @demo.parentNode.replaceChild(iframe, @demo)
      iwindow = iframe.contentWindow
      iwindow.document.body.innerHTML = html
      iwindow.document.body.id = iframe.id

      # firefox overwrites the body with the srcdoc after load so restore it.
      # setting srcdoc confuses Chrome, so we don't do that either.
      iwindow.addEventListener :DOMContentLoaded do
        iwindow.document.body.innerHTML = html
        iwindow.document.body.id = iframe.id
      end

      owner = iwindow.document.head
      @demo = iframe
    else
      iwindow = window
      owner = @demo
    end

    # wrap script in a IIFE (Immediately Invoked Function Expression) in order
    # to avoid polluting the window environment.
    @script = iwindow.document.createElement('script')
    if @demo.shadowRoot
      @script.textContent = 
        "(document => {#{content}})(document.getElementById('#{@demo.id}').shadowRoot)"
    else
      @script.textContent = "(() => {#{content}})()"
    end

    # load all dependencies
    SCRIPTS.each_pair do |name, src|
      if content =~ /\b#{name}\b/ and not iwindow.respond_to? name
        await Promise.new do |resolve, reject|
          script = document.createElement('script')
          script.src = src
          script.async = true
          script.crossorigin = true

          script.addEventListener(:error, reject)
          script.addEventListener(:load, resolve)
          iwindow.document.head.appendChild(script)
        end

        iwindow.Remarkable = remarkable.Remarkable if name == 'Remarkable'
      end
    end

    # append script to the div
    begin
      # remove previous exceptions
      Array(element.querySelectorAll('.exception')).each do |exception|
        exception.remove()
      end

      # run the script; throwing an error if either @script.onerror or
      # an error event is sent to the window (see above).  The latter
      # handles syntax errors in the script itself.
      await Promise.new do |resolve, reject|
        @pending = { resolve: resolve, reject: reject }
        @script.onerror = -> (event) {@pending.resolve(event.error) if @pending; @pending = nil}
        @script.onload = -> (event) {@pending.resolve() if @pending; @pending = nil}

        # safari doesn't run onload handlers for inline scripts
        setTimeout(2_000) {@pending.resolve() if @pending; @pending = nil}
        owner.appendChild(@script)
      end

      # resize iframe to accomodate content
      iframe.height = iwindow.document.body.scrollHeight + 20 if iframe

      # remove previous exceptions again to handle race conditions
      Array(element.querySelectorAll('.exception')).each do |exception|
        exception.remove()
      end
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

