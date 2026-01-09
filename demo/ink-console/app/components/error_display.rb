# Error display component
class ErrorDisplay < Ink::Component
  def view_template
    return unless @message

    Box(borderStyle: "round", borderColor: "red", paddingX: 1, marginTop: 1) do
      Text(color: "red") { "Error: #{@message}" }
    end
  end
end
