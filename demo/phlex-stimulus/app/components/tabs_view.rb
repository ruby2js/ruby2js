# Tabs component - demonstrates multiple targets and data values
class TabsView < Phlex::HTML
  def view_template
    div(data_controller: "tabs", data_tabs_active_class: "active", class: "component tabs") do
      h3 { "Tabs" }
      p(class: "description") { "Multiple targets with active state management" }

      div(class: "tab-buttons") do
        button(data_tabs_target: "button", data_action: "click->tabs#select", data_tabs_index_param: "0", class: "tab-btn active") { "Tab 1" }
        button(data_tabs_target: "button", data_action: "click->tabs#select", data_tabs_index_param: "1", class: "tab-btn") { "Tab 2" }
        button(data_tabs_target: "button", data_action: "click->tabs#select", data_tabs_index_param: "2", class: "tab-btn") { "Tab 3" }
      end

      div(class: "tab-panels") do
        div(data_tabs_target: "panel", class: "tab-panel active") do
          h4 { "First Tab" }
          p { "Content for the first tab panel." }
        end
        div(data_tabs_target: "panel", class: "tab-panel") do
          h4 { "Second Tab" }
          p { "Content for the second tab panel." }
        end
        div(data_tabs_target: "panel", class: "tab-panel") do
          h4 { "Third Tab" }
          p { "Content for the third tab panel." }
        end
      end
    end
  end
end
