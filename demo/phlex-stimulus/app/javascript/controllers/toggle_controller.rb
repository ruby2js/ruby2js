# Toggle Stimulus controller
class ToggleController < Stimulus::Controller
  def connect()
    @open = false
  end

  def toggle()
    @open = !@open
    contentTarget.classList.toggle("hidden", !@open)
    buttonTarget.classList.toggle("active", @open)
  end
end
