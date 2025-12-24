# Posts new view - form to create a new post
class PostsNewView < ApplicationView
  def initialize(post:)
    @post = post
  end

  def title
    "New Post"
  end

  def view_template
    div(class: "container") do
      render NavComponent.new

      div(class: "form-container") do
        h1 { "New Post" }

        render PostFormComponent.new(
          post: @post,
          action: "posts.post",
          method: :post
        )

        div(class: "form-footer") do
          a(href: "/posts", onclick: "return navigate(event, '/posts')", class: "back-link") { "Back to Posts" }
        end
      end
    end
  end
end
