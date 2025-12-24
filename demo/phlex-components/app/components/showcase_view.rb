# Showcase view demonstrating all components
class ShowcaseView < Phlex::HTML
  def view_template
    div(class: "container") do
      h1(class: "page-title") { "Component Library" }

      # Button variants section
      section(class: "component-section") do
        h2(class: "section-title") { "Button Variants" }
        div(class: "button-row") do
          render Button.new(variant: :primary) { "Primary" }
          render Button.new(variant: :secondary) { "Secondary" }
          render Button.new(variant: :destructive) { "Destructive" }
          render Button.new(variant: :outline) { "Outline" }
          render Button.new(variant: :ghost) { "Ghost" }
        end
      end

      # Button sizes section
      section(class: "component-section") do
        h2(class: "section-title") { "Button Sizes" }
        div(class: "button-row") do
          render Button.new(size: :sm) { "Small" }
          render Button.new(size: :md) { "Medium" }
          render Button.new(size: :lg) { "Large" }
        end
      end

      # Disabled button
      section(class: "component-section") do
        h2(class: "section-title") { "Disabled State" }
        div(class: "button-row") do
          render Button.new(disabled: true) { "Disabled" }
          render Button.new(variant: :outline, disabled: true) { "Disabled Outline" }
        end
      end

      # Card section
      section(class: "component-section") do
        h2(class: "section-title") { "Cards" }

        div(class: "card-grid") do
          # Basic card
          render Card.new do
            render CardHeader.new do
              render CardTitle.new { "Card Title" }
              render CardDescription.new { "Card description goes here." }
            end
            render CardContent.new do
              p { "This is the main content area of the card. You can put any content here." }
            end
            render CardFooter.new do
              render Button.new { "Action" }
            end
          end

          # Card with different title level
          render Card.new do
            render CardHeader.new do
              render CardTitle.new(as: :h4) { "Secondary Card" }
              render CardDescription.new { "Using h4 for the title." }
            end
            render CardContent.new do
              p { "Cards can contain any nested content." }
              ul do
                li { "Item one" }
                li { "Item two" }
                li { "Item three" }
              end
            end
            render CardFooter.new do
              render Button.new(variant: :outline) { "Cancel" }
              render Button.new { "Confirm" }
            end
          end
        end
      end
    end
  end
end
