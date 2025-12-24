# Tabs component with Stimulus controller (shadcn-inspired)
class Tabs < Phlex::HTML
  def initialize(tabs:, default_index: 0, **attrs)
    @tabs = tabs  # [{label: "Tab 1", content: "Content 1"}, ...]
    @default_index = default_index
    @attrs = attrs
  end

  def view_template
    div(
      data_controller: "tabs",
      data_tabs_index_value: @default_index,
      class: "tabs",
      **@attrs
    ) do
      # Tab list
      div(class: "tabs-list", role: "tablist") do
        @tabs.each_with_index do |tab, i|
          button(
            data_tabs_target: "tab",
            data_action: "click->tabs#select",
            data_index: i,
            role: "tab",
            class: "tabs-trigger",
            aria_selected: (i == @default_index).to_s
          ) { tab[:label] }
        end
      end

      # Tab panels
      @tabs.each_with_index do |tab, i|
        div(
          data_tabs_target: "panel",
          role: "tabpanel",
          class: "tabs-content#{i == @default_index ? '' : ' hidden'}"
        ) { tab[:content] }
      end
    end
  end
end
