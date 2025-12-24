# Tabs Stimulus controller
class TabsController < Stimulus::Controller
  def connect
    showTab(indexValue || 0)
  end

  def select(event)
    index = parseInt(event.currentTarget.dataset.index, 10)
    showTab(index)
  end

  def showTab(index)
    tabTargets.forEach do |tab, i|
      if i == index
        tab.classList.add("active")
        tab.setAttribute("aria-selected", "true")
      else
        tab.classList.remove("active")
        tab.setAttribute("aria-selected", "false")
      end
    end

    panelTargets.forEach do |panel, i|
      if i == index
        panel.classList.remove("hidden")
      else
        panel.classList.add("hidden")
      end
    end
  end
end
