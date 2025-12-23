# Application entry point - initializes Stimulus and renders Phlex views

# ESM filter will convert these to JS imports
require "@hotwired/stimulus", :Application
require "./controllers/counter_controller.js", :CounterController
require "./controllers/toggle_controller.js", :ToggleController
require "./controllers/tabs_controller.js", :TabsController
require "./controllers/modal_controller.js", :ModalController
require "./controllers/dropdown_controller.js", :DropdownController
require "./controllers/accordion_controller.js", :AccordionController
require "./components/counter_view.js", :CounterView
require "./components/toggle_view.js", :ToggleView
require "./components/tabs_view.js", :TabsView
require "./components/modal_view.js", :ModalView
require "./components/dropdown_view.js", :DropdownView
require "./components/accordion_view.js", :AccordionView

# Start Stimulus application
window.Stimulus = Application.start()

# Register controllers
Stimulus.register("counter", CounterController)
Stimulus.register("toggle", ToggleController)
Stimulus.register("tabs", TabsController)
Stimulus.register("modal", ModalController)
Stimulus.register("dropdown", DropdownController)
Stimulus.register("accordion", AccordionController)

# Render views into their containers
document.getElementById("counter").innerHTML = CounterView.new().call()
document.getElementById("toggle").innerHTML = ToggleView.new().call()
document.getElementById("tabs").innerHTML = TabsView.new().call()
document.getElementById("modal").innerHTML = ModalView.new().call()
document.getElementById("dropdown").innerHTML = DropdownView.new().call()
document.getElementById("accordion").innerHTML = AccordionView.new().call()
