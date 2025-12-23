# Accordion Stimulus controller
class AccordionController < Stimulus::Controller
  def toggle(event)
    index = event.currentTarget.dataset.index.to_i
    item = itemTargets[index]
    content = contentTargets[index]
    header = event.currentTarget
    isOpen = !content.classList.contains("hidden")

    if isOpen
      closeItem(item, content, header)
    else
      # Close others if not allowing multiple
      unless allowMultipleValue
        itemTargets.each_with_index do |otherItem, i|
          if i != index
            otherContent = contentTargets[i]
            otherHeader = otherItem.querySelector(".accordion-header")
            closeItem(otherItem, otherContent, otherHeader)
          end
        end
      end
      openItem(item, content, header)
    end
  end

  def openItem(item, content, header)
    content.classList.remove("hidden")
    header.setAttribute("aria-expanded", "true")
    header.querySelector(".accordion-icon").textContent = "-"
    item.classList.add("open")
  end

  def closeItem(item, content, header)
    content.classList.add("hidden")
    header.setAttribute("aria-expanded", "false")
    header.querySelector(".accordion-icon").textContent = "+"
    item.classList.remove("open")
  end
end
