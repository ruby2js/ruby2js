# Accordion component - demonstrates multiple expandable sections
class AccordionView < Phlex::HTML
  def view_template
    div(data_controller: "accordion", class: "component accordion") do
      h3 { "Accordion" }
      p(class: "description") { "Collapsible sections with exclusive or multi-open modes" }

      div(class: "accordion-item") do
        button(data_accordion_target: "trigger", data_action: "click->accordion#toggle", class: "accordion-trigger") do
          span { "Section 1: Getting Started" }
          span(data_accordion_target: "icon", class: "accordion-icon") { "+" }
        end
        div(data_accordion_target: "panel", class: "accordion-panel hidden") do
          p { "Welcome to the accordion component. Each section can be expanded or collapsed." }
          p { "By default, opening one section closes others. This can be configured." }
        end
      end

      div(class: "accordion-item") do
        button(data_accordion_target: "trigger", data_action: "click->accordion#toggle", class: "accordion-trigger") do
          span { "Section 2: Features" }
          span(data_accordion_target: "icon", class: "accordion-icon") { "+" }
        end
        div(data_accordion_target: "panel", class: "accordion-panel hidden") do
          ul do
            li { "Smooth animations" }
            li { "Keyboard accessible" }
            li { "ARIA attributes" }
            li { "Customizable behavior" }
          end
        end
      end

      div(class: "accordion-item") do
        button(data_accordion_target: "trigger", data_action: "click->accordion#toggle", class: "accordion-trigger") do
          span { "Section 3: Usage" }
          span(data_accordion_target: "icon", class: "accordion-icon") { "+" }
        end
        div(data_accordion_target: "panel", class: "accordion-panel hidden") do
          p { "Simply click on any section header to expand or collapse it." }
          p { "The accordion maintains state and provides visual feedback." }
        end
      end
    end
  end
end
