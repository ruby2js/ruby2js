# Modal Stimulus controller
class ModalController < Stimulus::Controller
  def open()
    backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  end

  def close()
    backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  end

  def stopPropagation(event)
    event.stopPropagation()
  end

  def backdropClick(event)
    close() if event.target == backdropTarget
  end
end
