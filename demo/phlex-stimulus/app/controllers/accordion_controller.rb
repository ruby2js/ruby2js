# Accordion controller - manages collapsible sections
class AccordionController < Stimulus::Controller
  def toggle(event)
    trigger = event.currentTarget
    index = triggerTargets.indexOf(trigger)
    panel = panelTargets[index]
    icon = iconTargets[index]

    isOpen = !panel.classList.contains("hidden")

    if isOpen
      # Close this panel
      panel.classList.add("hidden")
      icon.textContent = "+"
      trigger.classList.remove("active")
    else
      # Close all other panels first (exclusive mode)
      panelTargets.each_with_index do |p, i|
        p.classList.add("hidden")
        iconTargets[i].textContent = "+"
        triggerTargets[i].classList.remove("active")
      end

      # Open clicked panel
      panel.classList.remove("hidden")
      icon.textContent = "−"
      trigger.classList.add("active")
    end
  end
end
