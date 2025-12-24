# Input component (shadcn-inspired)
class Input < Phlex::HTML
  def initialize(type: "text", placeholder: nil, disabled: false, required: false, **attrs)
    @type = type
    @placeholder = placeholder
    @disabled = disabled
    @required = required
    @attrs = attrs
  end

  def view_template
    classes = ["input"]
    classes << "input-disabled" if @disabled

    input(
      type: @type,
      class: classes.join(" "),
      placeholder: @placeholder,
      disabled: @disabled,
      required: @required,
      **@attrs
    )
  end
end
