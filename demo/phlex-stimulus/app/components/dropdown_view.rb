# Dropdown component - demonstrates focus management and keyboard navigation
class DropdownView < Phlex::HTML
  def view_template
    div(data_controller: "dropdown", data_action: "keydown->dropdown#handleKeydown", class: "component dropdown-demo") do
      h3 { "Dropdown" }
      p(class: "description") { "Menu with keyboard navigation and click-outside close" }

      div(class: "dropdown") do
        button(data_dropdown_target: "trigger", data_action: "click->dropdown#toggle", class: "btn btn-primary dropdown-trigger") do
          span { "Select Option" }
          span(class: "dropdown-arrow") { "▼" }
        end

        ul(data_dropdown_target: "menu", class: "dropdown-menu hidden") do
          li { a(data_action: "click->dropdown#select", href: "#") { "Option 1" } }
          li { a(data_action: "click->dropdown#select", href: "#") { "Option 2" } }
          li { a(data_action: "click->dropdown#select", href: "#") { "Option 3" } }
          li(class: "divider")
          li { a(data_action: "click->dropdown#select", href: "#") { "Other..." } }
        end
      end
    end
  end
end
