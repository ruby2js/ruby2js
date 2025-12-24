# Accordion component - demonstrates multiple expandable sections
class AccordionView < Phlex::HTML
  def initialize(items:, allow_multiple: false)
    @items = items  # [{title: "Section 1", content: "Content 1"}, ...]
    @allow_multiple = allow_multiple
  end

  def view_template
    div(
      data_controller: "accordion",
      data_accordion_allow_multiple_value: @allow_multiple.to_s,
      class: "accordion"
    ) do
      @items.each_with_index do |item, i|
        div(class: "accordion-item", data_accordion_target: "item") do
          button(
            data_action: "click->accordion#toggle",
            data_index: i,
            class: "accordion-header",
            aria_expanded: "false"
          ) do
            span { item[:title] }
            span(class: "accordion-icon") { "+" }
          end
          div(data_accordion_target: "content", class: "accordion-content hidden") do
            div(class: "accordion-body") { item[:content] }
          end
        end
      end
    end
  end
end
