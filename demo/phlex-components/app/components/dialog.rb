# Dialog component with Stimulus controller (shadcn-inspired)
class Dialog < Phlex::HTML
  def initialize(title: nil, description: nil, **attrs)
    @title = title
    @description = description
    @attrs = attrs
  end

  def view_template(&block)
    div(
      data_controller: "dialog",
      **@attrs
    ) do
      # Trigger button slot - passed as first part of block or default
      button(
        class: "btn btn-primary",
        data_action: "click->dialog#open"
      ) { "Open Dialog" }

      # Dialog overlay and content
      div(
        class: "dialog-overlay hidden",
        data_dialog_target: "overlay",
        data_action: "click->dialog#backdropClick"
      ) do
        div(
          class: "dialog-content",
          role: "dialog",
          aria_modal: "true",
          data_action: "click->dialog#stopPropagation"
        ) do
          # Header
          if @title || @description
            div(class: "dialog-header") do
              if @title
                h2(class: "dialog-title") { @title }
              end
              if @description
                p(class: "dialog-description") { @description }
              end
            end
          end

          # Body - yielded content
          div(class: "dialog-body", &block)

          # Close button
          button(
            class: "dialog-close",
            data_action: "click->dialog#close",
            aria_label: "Close"
          ) { "\u00D7" }
        end
      end
    end
  end
end
