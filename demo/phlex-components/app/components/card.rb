# Card compound components (shadcn-inspired)
# Usage:
#   render Card.new do
#     render CardHeader.new do
#       render CardTitle.new { "Title" }
#       render CardDescription.new { "Description" }
#     end
#     render CardContent.new { "Content" }
#     render CardFooter.new { render Button.new { "Action" } }
#   end

class Card < Phlex::HTML
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&block)
    div(class: "card", **@attrs, &block)
  end
end

class CardHeader < Phlex::HTML
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&block)
    div(class: "card-header", **@attrs, &block)
  end
end

class CardTitle < Phlex::HTML
  def initialize(as: :h3, **attrs)
    @tag = as
    @attrs = attrs
  end

  def view_template(&block)
    send(@tag, class: "card-title", **@attrs, &block)
  end
end

class CardDescription < Phlex::HTML
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&block)
    p(class: "card-description", **@attrs, &block)
  end
end

class CardContent < Phlex::HTML
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&block)
    div(class: "card-content", **@attrs, &block)
  end
end

class CardFooter < Phlex::HTML
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&block)
    div(class: "card-footer", **@attrs, &block)
  end
end
