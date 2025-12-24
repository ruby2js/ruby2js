# Showcase component - displays all Stimulus + Phlex components
class ShowcaseView < Phlex::HTML
  def view_template
    div(class: "showcase") do
      h1 { "Phlex + Stimulus Showcase" }
      p(class: "intro") { "Interactive UI components built with Ruby2JS, Phlex, and Stimulus." }

      # Counter
      section(class: "component-section") do
        h2 { "Counter" }
        p { "Basic state management with increment/decrement buttons." }
        render CounterView.new
      end

      # Toggle
      section(class: "component-section") do
        h2 { "Toggle" }
        p { "Show/hide content with classList manipulation." }
        render ToggleView.new(label: "Click to toggle")
      end

      # Tabs
      section(class: "component-section") do
        h2 { "Tabs" }
        p { "Multiple targets and data values for tab switching." }
        render TabsView.new(tabs: [
          { label: "Tab 1", content: "Content for the first tab. This demonstrates basic tab switching." },
          { label: "Tab 2", content: "Content for the second tab. Each tab can have different content." },
          { label: "Tab 3", content: "Content for the third tab. Click the tabs above to switch." }
        ])
      end

      # Modal
      section(class: "component-section") do
        h2 { "Modal" }
        p { "Dialog with backdrop, click-outside, and keyboard support." }
        render ModalView.new(title: "Example Modal", trigger_text: "Open Modal") do
          p { "This is the modal content. Click outside or press Escape to close." }
          p { "Modals are great for confirmations, forms, or detailed information." }
        end
      end

      # Dropdown
      section(class: "component-section") do
        h2 { "Dropdown" }
        p { "Menu with focus management and click-outside handling." }
        render DropdownView.new(
          label: "Select an option",
          items: [
            { label: "Option 1", value: "1" },
            { label: "Option 2", value: "2" },
            { label: "Option 3", value: "3" }
          ]
        )
      end

      # Accordion
      section(class: "component-section") do
        h2 { "Accordion" }
        p { "Expandable sections with single or multiple open items." }
        render AccordionView.new(items: [
          { title: "Section 1", content: "Content for section 1. Click the header to expand or collapse." },
          { title: "Section 2", content: "Content for section 2. By default, only one section can be open at a time." },
          { title: "Section 3", content: "Content for section 3. The allow_multiple option enables multiple open sections." }
        ])
      end
    end
  end
end
