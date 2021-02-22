class EvalController < DemoController
  SCRIPTS = {
    React: "https://unpkg.com/react@17/umd/react.production.min.js",
    ReactDOM: "https://unpkg.com/react-dom@17/umd/react-dom.production.min.js",
    Remarkable: "https://cdn.jsdelivr.net/remarkable/2.0.1/remarkable.min.js"
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
  end

  async def load(content)
    # remove previous script (if any)
    @script.remove() if @script

    # load all dependencies
		SCRIPTS.each_pair do |name, src|
			await Promise.new do |resolve, reject|
				if not content =~ /\b#{name}\./
					resolve()
				elsif window.respond_to? name
					resolve()
				else
				  script = document.createElement('script')
					script.src = src
					script.async = true
					script.crossorigin = true

					script.addEventListener(:error, reject)
					script.addEventListener(:load, resolve)
					document.head.appendChild(script)
				end
			end
		end

    # wrap script in a IIFE (Immediately Invoked Function Expression) in order
    # to avoid polluting the window environment.
    @script = document.createElement('script')
    if @div.shadowRoot
      @script.textContent = "(document => {
        if (document.lastElementChild?.classList?.contains('exception')) document.lastElementChild.remove();
        try { #{content} } catch (error) {
          let div = window.document.createElement('div');
          div.textContent = error.toString();
          div.classList.add('exception');
          div.style = 'background-color:#ff0;margin: 1em 0;padding: 1em;border: 4px solid red;border-radius: 1em'
          document.appendChild(div);
        }
      })(document.getElementById('#{@div.id}').shadowRoot)"
    else
      @script.textContent = "(() => {#{content}})()"
    end

    # append script to the div
    @div.appendChild(@script)
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
  end
end

