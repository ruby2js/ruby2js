# Posts index view - displays list of blog posts
class PostsIndexView < ApplicationView
  def initialize(posts:)
    @posts = posts
  end

  def title
    "Blog Posts"
  end

  def view_template
    div(class: "container") do
      render NavComponent.new

      header(class: "page-header") do
        h1 { "Blog Posts" }
        a(href: "/posts/new", onclick: "return navigate(event, '/posts/new')", class: "btn btn-primary") { "New Post" }
      end

      if @posts.length == 0
        div(class: "empty-state") do
          p { "No posts yet. Be the first to write one!" }
        end
      else
        div(class: "posts-grid") do
          @posts.each do |post|
            render PostCardComponent.new(post: post)
          end
        end
      end
    end
  end
end
