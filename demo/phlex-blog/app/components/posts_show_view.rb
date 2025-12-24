# Posts show view - displays a single blog post
class PostsShowView < ApplicationView
  def initialize(post:)
    @post = post
  end

  def title
    @post.title
  end

  def view_template
    div(class: "container") do
      render NavComponent.new

      article(class: "post-detail") do
        header(class: "post-header") do
          h1 { @post.title }
          div(class: "post-meta") do
            span(class: "post-author") { "By #{@post.author}" }
            span(class: "post-date") { self.format_date(@post.created_at) }
          end
        end

        div(class: "post-body") do
          p { @post.body }
        end

        footer(class: "post-footer") do
          div(class: "post-actions") do
            a(href: "/posts/#{@post.id}/edit", onclick: "return navigate(event, '/posts/#{@post.id}/edit')", class: "btn btn-secondary") { "Edit" }
            a(href: "#", onclick: "if(confirm('Delete this post?')) { routes.post.delete(#{@post.id}) } return false;", class: "btn btn-destructive") { "Delete" }
          end
          a(href: "/posts", onclick: "return navigate(event, '/posts')", class: "back-link") { "Back to Posts" }
        end
      end
    end
  end
end
