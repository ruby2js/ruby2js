class EvalController < DemoController
  SCRIPTS = {
    React: "https://unpkg.com/react@17/umd/react.production.min.js",
    ReactDOM: "https://unpkg.com/react-dom@17/umd/react-dom.production.min.js",
    Remarkable: "https://cdnjs.cloudflare.com/ajax/libs/remarkable/2.0.1/remarkable.min.js"
  }

  def source
    @source ||= findController type: RubyController,
      element: document.querySelector(element.dataset.source)
  end

  def setup()
    @div = document.createElement('div')
    @div.id = 'd' + Date.now() + Math.random().toString().slice(2)
    shadow = @div.attachShadow(mode: :open)
    @script = nil

    html = document.querySelector(element.dataset.html)
    if html
      @div.classList.add 'demo-results'
      div = document.createElement('div')
      html.content.childNodes.each do |node|
        div.appendChild node.cloneNode(true)
      end
      shadow.appendChild(div)
    end

    # add div to document
    element.appendChild(@div)

    # set up listener for script failures
    @pending = nil
    window.addEventListener :error do |event|
      @pending.reject(event.error) if @pending
      @pending = nil
    end
  end

  async def load(content)
    # remove previous script (if any)
    @script.remove() if @script

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

    # Stimulus support: remove imports, start application, register controllers
    content.gsub! /^import .*;\n\s*/, ''

    controllers = []
    content.gsub! /^export (default )?(class (\w+) extends Stimulus.Controller)/ do
      controllers << $3
      next $2
    end

    unless controllers.empty?
      content += ";\n\nwindow.application = Stimulus.Application.start(document.firstElementChild)"
    end

    controllers.each do |controller|
      name = controller.sub(/Controller$/, '').
        gsub(/[a-z][A-Z]/) {|match| "#{match[1]}-#{match[1]}"}.downcase()
      content += ";\nwindow.application.register(#{name.inspect}, #{controller})"
    end

    # wrap script in a IIFE (Immediately Invoked Function Expression) in order
    # to avoid polluting the window environment.
    @script = document.createElement('script')
    if @div.shadowRoot
      @script.textContent = 
        "(document => {#{content}})(document.getElementById('#{@div.id}').shadowRoot)"
    else
      @script.textContent = "(() => {#{content}})()"
    end

    # append script to the div
    begin
      # remove previous exceptions
      if element.lastElementChild&.classList&.contains('exception')
        element.lastElementChild.remove()
      end

      # run the script; throwing an error if either @script.onerror or
      # an error event is sent to the window (see above).  The latter
      # handles syntax errors in the script itself.
      await Promise.new do |resolve, reject|
        @pending = { resolve: resolve, reject: reject }
        @script.onerror = -> (event) {@pending.resolve(event.error) if @pending; @pending = nil}
        @script.onload = -> (event) {@pending.resolve() if @pending; @pending = nil}
        @div.appendChild(@script)
      end
    rescue => error
      # display exceptions
      div = document.createElement('div')
      div.textContent = error
      div.classList.add('exception')
      element.appendChild(div)
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
    # remove div from document
    @div.remove()

    # stop and remove stimulus application
    if windows.application
      windows.application.stop()
      delete windows.application
    end
  end
end

