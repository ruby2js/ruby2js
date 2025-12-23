# Toggle component - demonstrates classList manipulation
class ToggleView < Phlex::HTML
  def view_template
    div(data_controller: "toggle", class: "component toggle") do
      h3 { "Toggle" }
      p(class: "description") { "CSS class toggling with Stimulus" }

      button(data_action: "click->toggle#toggle", class: "btn btn-primary") do
        "Toggle Dark Mode"
      end

      div(data_toggle_target: "content", class: "toggle-content") do
        p { "This panel changes appearance when toggled." }
        p { "Click the button to switch between light and dark modes." }
      end
    end
  end
end
