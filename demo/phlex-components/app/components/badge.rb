# Badge component with variants (shadcn-inspired)
class Badge < Phlex::HTML
  VARIANTS = {
    default: "badge-default",
    secondary: "badge-secondary",
    destructive: "badge-destructive",
    outline: "badge-outline"
  }

  def initialize(variant: :default, **attrs)
    @variant = variant
    @attrs = attrs
  end

  def view_template(&block)
    span(
      class: "badge #{VARIANTS[@variant]}",
      **@attrs,
      &block
    )
  end
end
