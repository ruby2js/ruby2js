# Counter component - demonstrates basic Phlex + Stimulus integration
class CounterView < Phlex::HTML
  def view_template
    div(data_controller: "counter", class: "counter") do
      button(data_action: "click->counter#decrement", class: "btn btn-secondary") { "-" }
      span(data_counter_target: "display", class: "count") { "0" }
      button(data_action: "click->counter#increment", class: "btn btn-primary") { "+" }
    end
  end
end
