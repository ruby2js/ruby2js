# Tabs Stimulus controller
class TabsController < Stimulus::Controller
  def connect()
    showTab(indexValue || 0)
  end

  def select(event)
    index = event.currentTarget.dataset.index.to_i
    showTab(index)
  end

  def showTab(index)
    tabTargets.each_with_index do |tab, i|
      if i == index
        tab.classList.add("active")
        tab.setAttribute("aria-selected", "true")
      else
        tab.classList.remove("active")
        tab.setAttribute("aria-selected", "false")
      end
    end

    panelTargets.each_with_index do |panel, i|
      panel.classList.toggle("hidden", i != index)
    end
  end
end
