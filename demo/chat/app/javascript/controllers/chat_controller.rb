class ChatController < Stimulus::Controller
  self.targets = %w(body message)

  # Auto-scroll to show the new message
  def messageTargetConnected(element)
    element.scrollIntoView()
  end

  # Clear the message input after form submission
  def clearInput
    bodyTarget.value = ""
    bodyTarget.focus()
  end
end
