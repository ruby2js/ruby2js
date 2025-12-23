# Dropdown controller - manages dropdown menu with keyboard support
class DropdownController < Stimulus::Controller
  def connect()
    @open = false
    @focusIndex = -1
  end

  def toggle()
    @open = !@open
    if @open
      menuTarget.classList.remove("hidden")
      @focusIndex = 0
      focusCurrentItem()
    else
      menuTarget.classList.add("hidden")
      @focusIndex = -1
    end
  end

  def close()
    @open = false
    menuTarget.classList.add("hidden")
    @focusIndex = -1
  end

  def select(event)
    event.preventDefault()
    text = event.target.textContent
    triggerTarget.querySelector("span").textContent = text
    close()
  end

  def handleKeydown(event)
    return unless @open

    items = menuTarget.querySelectorAll("a")

    case event.key
    when "ArrowDown"
      event.preventDefault()
      @focusIndex = (@focusIndex + 1) % items.length
      focusCurrentItem()
    when "ArrowUp"
      event.preventDefault()
      @focusIndex = (@focusIndex - 1 + items.length) % items.length
      focusCurrentItem()
    when "Enter"
      event.preventDefault()
      items[@focusIndex].click() if @focusIndex >= 0
    when "Escape"
      close()
      triggerTarget.focus()
    end
  end

  def focusCurrentItem()
    items = menuTarget.querySelectorAll("a")
    items[@focusIndex].focus() if @focusIndex >= 0 && @focusIndex < items.length
  end
end
