# Tabs controller - manages tab selection with multiple targets
class TabsController < Stimulus::Controller
  def select(event)
    index = event.params.index.to_i

    # Update button states
    buttonTargets.each_with_index do |button, i|
      if i == index
        button.classList.add("active")
      else
        button.classList.remove("active")
      end
    end

    # Update panel visibility
    panelTargets.each_with_index do |panel, i|
      if i == index
        panel.classList.add("active")
      else
        panel.classList.remove("active")
      end
    end
  end
end
