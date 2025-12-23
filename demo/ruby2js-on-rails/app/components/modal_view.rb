# Modal component - demonstrates show/hide and click-outside handling
class ModalView < Phlex::HTML
  def initialize(title:, trigger_text: "Open Modal")
    @title = title
    @trigger_text = trigger_text
  end

  def view_template(&content)
    div(data_controller: "modal", data_action: "keydown.escape->modal#close") do
      button(data_action: "click->modal#open", class: "btn btn-primary") { @trigger_text }

      div(
        data_modal_target: "backdrop",
        data_action: "click->modal#backdropClick",
        class: "modal-backdrop hidden"
      ) do
        div(class: "modal-content", data_action: "click->modal#stopPropagation") do
          div(class: "modal-header") do
            h2(class: "modal-title") { @title }
            button(data_action: "click->modal#close", class: "modal-close") { "\u00D7" }
          end
          div(class: "modal-body", &content)
        end
      end
    end
  end
end
