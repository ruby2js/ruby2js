# Counter Stimulus controller
class CounterController < Stimulus::Controller
  def connect()
    @count = 0
  end

  def increment()
    @count += 1
    displayTarget.textContent = @count.to_s
  end

  def decrement()
    @count -= 1
    displayTarget.textContent = @count.to_s
  end
end
