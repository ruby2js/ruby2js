# Dialog Stimulus controller
class DialogController < Stimulus::Controller
  def connect
    # Add escape key listener
    document.addEventListener("keydown", ->(e) { handleKeydown(e) })
  end

  def disconnect
    document.removeEventListener("keydown", ->(e) { handleKeydown(e) })
  end

  def open
    overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  end

  def close
    overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  end

  def backdropClick(event)
    close if event.target == overlayTarget
  end

  def stopPropagation(event)
    event.stopPropagation
  end

  def handleKeydown(event)
    close if event.key == "Escape" && !overlayTarget.classList.contains("hidden")
  end
end
