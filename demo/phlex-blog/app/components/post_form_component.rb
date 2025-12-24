# Post form component - reusable form for new/edit
class PostFormComponent < Phlex::HTML
  def initialize(post:, action:, method: :post)
    @post = post
    @action = action
    @method = method
  end

  def view_template
    if @post.errors && @post.errors.length > 0
      div(class: "form-errors") do
        ul do
          @post.errors.each do |error|
            li { error }
          end
        end
      end
    end

    form(class: "post-form", onsubmit: "return routes.#{@action}(event)") do
      div(class: "form-group") do
        label(for: "title") { "Title" }
        input(
          type: "text",
          id: "title",
          name: "title",
          value: @post.title || "",
          required: true,
          class: "input"
        )
      end

      div(class: "form-group") do
        label(for: "author") { "Author" }
        input(
          type: "text",
          id: "author",
          name: "author",
          value: @post.author || "",
          required: true,
          class: "input"
        )
      end

      div(class: "form-group") do
        label(for: "body") { "Content" }
        textarea(
          id: "body",
          name: "body",
          required: true,
          class: "input textarea",
          rows: 8
        ) { @post.body || "" }
      end

      div(class: "form-actions") do
        button(type: "submit", class: "btn btn-primary") do
          @method == :post ? "Create Post" : "Update Post"
        end
      end
    end
  end
end
