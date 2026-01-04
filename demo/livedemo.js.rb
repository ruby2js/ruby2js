import [Application], "@hotwired/stimulus"

# Create Stimulus namespace object for compatibility with Opal
# Controller is imported by the stimulus filter
Stimulus = { Controller: Controller, Application: Application }

async {

  # This superclass is intended for Stimulus controllers that not only
  # connect to Stimulus, but pair with each other.  Subclasses of
  # DemoController don't define connect methods, instead they define
  # setup methods.  Subclasses that initiate pairing define source methods.
  # Subclasses that expect to be targets define pair methods.  A
  # findController method is defined to help find sources.
  #
  # Examples: OptionsController sends options to RubyControllers.
  # RubyControllers send scripts to JSControllers.
  #
  # codemirror_ready and ruby2js_ready methods can be used to wait for these
  # scripts to load before proceeding.
  #
  class DemoController < Stimulus::Controller
    attr_reader :source, :targets

    # subclasses are expected to override this method
    def setup()
    end

    # if subclasses override this, they need to call super.  Most should
    # just override setup instead.
    async def connect()
      @targets = Set.new()
      await setup()
      source.pair(self) if source

      application.controllers.select do |controller|
        if controller.source == self
          controller.targets.add self
          controller.pair(self) 
        end
      end
    end

    # override this method in classes that initiate pairing
    def source
      @source = nil
    end

    # logic to be executed when the second half of the pair connects to
    # Stimulus, independent of the order of the connection to Stimulus.
    # if subclasses override this method, they need to call super.
    def pair(component)
      @targets.add component
    end

    # logic to be executed when the second half of the pair disconnects.
    # Stimulus may reuse controller objects, so a controller needs to
    # return to a state where they seek out new sources
    def unpair(component)
      @targets.delete component
      @source = nil if @source == component
    end

    # subclasses can override this method
    def teardown()
    end

    # unpair all partners (sources and targets)
    # if subclasses override this method, they need to call super.
    # Generally, it is best to override teardown instead.
    def disconnect()
      @source.unpair(self) if @source

      application.controllers.select do |controller|
        controller.unpair(self) if controller.targets.has(self)
      end

      teardown()
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

  require_relative './controllers/options_controller'
  require_relative './controllers/ruby_controller'
  require_relative './controllers/selfhost_ruby_controller'
  require_relative './controllers/js_controller'
  require_relative './controllers/combo_controller'
  require_relative './controllers/eval_controller'

  application = Application.start()
  application.register("options", OptionsController)
  application.register("ruby", RubyController)
  application.register("selfhost-ruby", SelfhostRubyController)
  application.register("js", JSController)
  application.register("combo", ComboController)
  application.register("eval", EvalController)

  globalThis.Stimulus = Stimulus

}[]
