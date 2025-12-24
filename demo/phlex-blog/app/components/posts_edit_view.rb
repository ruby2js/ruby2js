# Posts edit view - form to edit an existing post
class PostsEditView < ApplicationView
  def initialize(post:)
    @post = post
  end

  def title
    "Edit Post"
  end

  def view_template
    div(class: "container") do
      render NavComponent.new

      div(class: "form-container") do
        h1 { "Edit Post" }

        render PostFormComponent.new(
          post: @post,
          action: "post.patch",
          method: :patch
        )

        div(class: "form-footer") do
          a(href: "/posts/#{@post.id}", onclick: "return navigate(event, '/posts/#{@post.id}')", class: "back-link") { "Cancel" }
          whitespace
          span { "|" }
          whitespace
          a(href: "/posts", onclick: "return navigate(event, '/posts')", class: "back-link") { "Back to Posts" }
        end
      end
    end
  end
end
