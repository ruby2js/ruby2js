# Modal component - demonstrates show/hide and click-outside handling
class ModalView < Phlex::HTML
  def view_template
    div(data_controller: "modal", class: "component modal-demo") do
      h3 { "Modal" }
      p(class: "description") { "Overlay dialog with backdrop click-to-close" }

      button(data_action: "click->modal#open", class: "btn btn-primary") { "Open Modal" }

      div(data_modal_target: "backdrop", data_action: "click->modal#closeOnBackdrop", class: "modal-backdrop hidden") do
        div(data_modal_target: "dialog", class: "modal-dialog") do
          div(class: "modal-header") do
            h4 { "Modal Title" }
            button(data_action: "click->modal#close", class: "modal-close") { "×" }
          end
          div(class: "modal-body") do
            p { "This is a modal dialog. Click outside or press the X to close." }
            p { "Modals are useful for confirmations, forms, and focused interactions." }
          end
          div(class: "modal-footer") do
            button(data_action: "click->modal#close", class: "btn btn-secondary") { "Cancel" }
            button(data_action: "click->modal#confirm", class: "btn btn-primary") { "Confirm" }
          end
        end
      end
    end
  end
end
