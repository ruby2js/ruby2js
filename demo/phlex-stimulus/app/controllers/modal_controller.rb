# Modal controller - manages modal open/close with backdrop click handling
class ModalController < Stimulus::Controller
  def open()
    backdropTarget.classList.remove("hidden")
    document.body.classList.add("modal-open")
  end

  def close()
    backdropTarget.classList.add("hidden")
    document.body.classList.remove("modal-open")
  end

  def closeOnBackdrop(event)
    # Only close if clicking directly on backdrop, not dialog
    close() if event.target == backdropTarget
  end

  def confirm()
    console.log("Modal confirmed!")
    close()
  end
end
