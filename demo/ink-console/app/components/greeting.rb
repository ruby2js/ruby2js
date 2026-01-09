# Simple greeting component to test Ink filter
class Greeting < Ink::Component
  def view_template
    Box(flexDirection: "column", padding: 1) do
      Text(bold: true, color: "green") { "Welcome to Ink Console!" }
      Text { "Hello, #{@name}!" }

      if @loading
        Box do
          Spinner(type: "dots")
          Text(color: "yellow") { " Loading..." }
        end
      else
        Text(dimColor: true) { "Ready for queries" }
      end
    end
  end
end
