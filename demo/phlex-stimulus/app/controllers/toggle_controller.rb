# Toggle controller - toggles CSS classes on target elements
class ToggleController < Stimulus::Controller
  def toggle()
    contentTarget.classList.toggle("dark")
  end
end
