# Counter component - demonstrates basic Stimulus state management
class CounterView < Phlex::HTML
  def view_template
    div(data_controller: "counter", class: "component counter") do
      h3 { "Counter" }
      p(class: "description") { "Basic increment/decrement with Stimulus targets and actions" }

      div(class: "counter-controls") do
        button(data_action: "click->counter#decrement", class: "btn btn-secondary") { "-" }
        span(data_counter_target: "display", class: "counter-value") { "0" }
        button(data_action: "click->counter#increment", class: "btn btn-primary") { "+" }
      end
    end
  end
end
