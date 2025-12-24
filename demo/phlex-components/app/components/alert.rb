# Alert component with variants (shadcn-inspired)
class Alert < Phlex::HTML
  VARIANTS = {
    default: "alert-default",
    destructive: "alert-destructive",
    success: "alert-success",
    warning: "alert-warning"
  }

  def initialize(variant: :default, title: nil, dismissible: false, **attrs)
    @variant = variant
    @title = title
    @dismissible = dismissible
    @attrs = attrs
  end

  def view_template(&block)
    div(
      class: "alert #{VARIANTS[@variant]}",
      role: "alert",
      **@attrs
    ) do
      if @title
        div(class: "alert-title") { @title }
      end
      div(class: "alert-description", &block)
      if @dismissible
        button(
          class: "alert-dismiss",
          type: "button",
          aria_label: "Dismiss"
        ) { "\u00D7" }
      end
    end
  end
end
