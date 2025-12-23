# Counter controller - manages a simple counter with increment/decrement
class CounterController < Stimulus::Controller
  def connect()
    @count = 0
  end

  def increment()
    @count += 1
    render()
  end

  def decrement()
    @count -= 1
    render()
  end

  def render()
    displayTarget.textContent = @count.to_s
  end
end
