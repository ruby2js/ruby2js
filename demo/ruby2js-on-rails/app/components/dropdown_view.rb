# Dropdown component - demonstrates focus management and click-outside
class DropdownView < Phlex::HTML
  def initialize(label:, items:)
    @label = label
    @items = items  # [{label: "Item 1", value: "1"}, ...]
  end

  def view_template
    div(
      data_controller: "dropdown",
      data_action: "click@window->dropdown#clickOutside keydown.escape->dropdown#close",
      class: "dropdown"
    ) do
      button(
        data_action: "click->dropdown#toggle",
        data_dropdown_target: "button",
        class: "dropdown-button",
        aria_haspopup: "true"
      ) do
        span { @label }
        span(class: "dropdown-arrow") { "\u25BC" }
      end

      div(data_dropdown_target: "menu", class: "dropdown-menu hidden", role: "menu") do
        @items.each do |item|
          button(
            data_action: "click->dropdown#select",
            data_value: item[:value],
            class: "dropdown-item",
            role: "menuitem"
          ) { item[:label] }
        end
      end
    end
  end
end
