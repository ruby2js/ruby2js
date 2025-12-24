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

      # Input section
      section(class: "component-section") do
        h2(class: "section-title") { "Input" }
        div(class: "form-row") do
          render Input.new(placeholder: "Enter text...")
          render Input.new(type: "email", placeholder: "Email address")
          render Input.new(disabled: true, placeholder: "Disabled input")
        end
      end

      # Badge section
      section(class: "component-section") do
        h2(class: "section-title") { "Badges" }
        div(class: "button-row") do
          render Badge.new { "Default" }
          render Badge.new(variant: :secondary) { "Secondary" }
          render Badge.new(variant: :destructive) { "Destructive" }
          render Badge.new(variant: :outline) { "Outline" }
        end
      end

      # Alert section
      section(class: "component-section") do
        h2(class: "section-title") { "Alerts" }
        div(class: "alert-stack") do
          render Alert.new(title: "Heads up!") { "This is a default alert message." }
          render Alert.new(variant: :success, title: "Success") { "Your changes have been saved." }
          render Alert.new(variant: :warning, title: "Warning") { "Please review before continuing." }
          render Alert.new(variant: :destructive, title: "Error") { "Something went wrong." }
        end
      end

      # Card section
      section(class: "component-section") do
        h2(class: "section-title") { "Cards" }

        div(class: "card-grid") do
          render Card.new do
            render CardHeader.new do
              render CardTitle.new { "Card Title" }
              render CardDescription.new { "Card description goes here." }
            end
            render CardContent.new do
              p { "This is the main content area of the card." }
            end
            render CardFooter.new do
              render Button.new { "Action" }
            end
          end

          render Card.new do
            render CardHeader.new do
              render CardTitle.new(as: :h4) { "Secondary Card" }
              render CardDescription.new { "Using h4 for the title." }
            end
            render CardContent.new do
              p { "Cards can contain any nested content." }
            end
            render CardFooter.new do
              render Button.new(variant: :outline) { "Cancel" }
              render Button.new { "Confirm" }
            end
          end
        end
      end

      # Dialog section
      section(class: "component-section") do
        h2(class: "section-title") { "Dialog" }
        render Dialog.new(
          title: "Are you sure?",
          description: "This action cannot be undone."
        ) do
          p { "This will permanently delete your account and all associated data." }
          div(class: "dialog-actions") do
            render Button.new(variant: :outline, data_action: "click->dialog#close") { "Cancel" }
            render Button.new(variant: :destructive) { "Delete Account" }
          end
        end
      end

      # Tabs section
      section(class: "component-section") do
        h2(class: "section-title") { "Tabs" }
        render Tabs.new(
          tabs: [
            { label: "Account", content: "Make changes to your account here." },
            { label: "Password", content: "Change your password here." },
            { label: "Settings", content: "Manage your settings here." }
          ]
        )
      end
    end
  end
end
