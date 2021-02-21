class EvalController < DemoController
  def source
    @source ||= findController type: RubyController,
      element: document.querySelector(element.dataset.source)
  end

  def setup()
    @div = document.createElement('div')
    shadow = @div.attachShadow(mode: :open)
    @script = nil

    # add div to document
    element.appendChild(@div)
  end

  # update contents
  def contents=(script)
    # remove previous script (if any)
    @script.remove() if @script

    # wrap script in a IIFE (Immediately Invoked Function Expression) in order
    # to avoid polluting the window environment.
    @script = document.createElement('script')
    @script.textContent = "(() => {#{script}})()"

    # append script to the div
    @div.appendChild(@script)
  end

  # ignore errors
  def exception=(message)
  end

  def teardown()
    # remove div from document
    @div.remove()
  end
end

