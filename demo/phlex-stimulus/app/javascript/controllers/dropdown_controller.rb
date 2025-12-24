# Dropdown Stimulus controller
class DropdownController < Stimulus::Controller
  def connect()
    @open = false
  end

  def toggle()
    @open ? close() : open()
  end

  def open()
    @open = true
    menuTarget.classList.remove("hidden")
    buttonTarget.setAttribute("aria-expanded", "true")
  end

  def close()
    @open = false
    menuTarget.classList.add("hidden")
    buttonTarget.setAttribute("aria-expanded", "false")
  end

  def select(event)
    value = event.currentTarget.dataset.value
    label = event.currentTarget.textContent
    buttonTarget.querySelector("span").textContent = label
    close()
    # Dispatch custom event for parent components
    element.dispatchEvent(CustomEvent.new("dropdown:select", detail: { value: value }))
  end

  def clickOutside(event)
    close() unless element.contains(event.target)
  end
end
