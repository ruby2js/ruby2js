# Query input component with history support
class QueryInput < Ink::Component
  keys return: :submit,
       up: :history_back,
       down: :history_forward

  def view_template
    Box(borderStyle: "round", paddingX: 1) do
      Text(color: "green") { "> " }
      TextInput(
        value: @value,
        onChange: @on_change,
        placeholder: "Enter a Ruby query (e.g., Post.all)"
      )
    end
  end

  def submit
    @on_submit.call if @on_submit
  end

  def history_back
    @on_history_back.call if @on_history_back
  end

  def history_forward
    @on_history_forward.call if @on_history_forward
  end
end
