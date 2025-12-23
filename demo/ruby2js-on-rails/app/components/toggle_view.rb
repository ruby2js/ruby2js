# Toggle component - demonstrates conditional classes with Stimulus
class ToggleView < Phlex::HTML
  def initialize(label: "Toggle me")
    @label = label
  end

  def view_template
    div(data_controller: "toggle", class: "toggle") do
      button(
        data_action: "click->toggle#toggle",
        data_toggle_target: "button",
        class: "btn"
      ) { @label }
      div(data_toggle_target: "content", class: "toggle-content hidden") do
        p { "This content can be toggled on and off." }
      end
    end
  end
end
