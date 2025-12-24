# Button component with variants and sizes (shadcn-inspired)
class Button < Phlex::HTML
  VARIANTS = {
    primary: "btn-primary",
    secondary: "btn-secondary",
    destructive: "btn-destructive",
    outline: "btn-outline",
    ghost: "btn-ghost"
  }

  SIZES = {
    sm: "btn-sm",
    md: "btn-md",
    lg: "btn-lg"
  }

  def initialize(variant: :primary, size: :md, disabled: false, type: "button", **attrs)
    @variant = variant
    @size = size
    @disabled = disabled
    @type = type
    @attrs = attrs
  end

  def view_template(&block)
    classes = ["btn", VARIANTS[@variant], SIZES[@size]]
    classes << "btn-disabled" if @disabled

    button(
      type: @type,
      class: classes.join(" "),
      disabled: @disabled,
      **@attrs,
      &block
    )
  end
end
