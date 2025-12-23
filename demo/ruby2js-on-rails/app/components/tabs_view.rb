# Tabs component - demonstrates multiple targets and data values
class TabsView < Phlex::HTML
  def initialize(tabs:)
    @tabs = tabs  # [{label: "Tab 1", content: "Content 1"}, ...]
  end

  def view_template
    div(data_controller: "tabs", data_tabs_index_value: "0", class: "tabs") do
      div(class: "tab-list", role: "tablist") do
        @tabs.each_with_index do |tab, i|
          button(
            data_tabs_target: "tab",
            data_action: "click->tabs#select",
            data_index: i,
            role: "tab",
            class: "tab-button"
          ) { tab[:label] }
        end
      end

      div(class: "tab-panels") do
        @tabs.each_with_index do |tab, i|
          div(
            data_tabs_target: "panel",
            role: "tabpanel",
            class: "tab-panel"
          ) { tab[:content] }
        end
      end
    end
  end
end
