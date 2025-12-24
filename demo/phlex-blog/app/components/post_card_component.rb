# Post card component - displays a post preview in the index
class PostCardComponent < ApplicationView
  def initialize(post:)
    @post = post
  end

  def view_template
    article(class: "post-card") do
      header(class: "post-card-header") do
        h2(class: "post-card-title") do
          a(href: "/posts/#{@post.id}", onclick: "return navigate(event, '/posts/#{@post.id}')") { @post.title }
        end
        div(class: "post-card-meta") do
          span(class: "post-author") { @post.author }
          span(class: "post-date") { self.time_ago(@post.created_at) }
        end
      end
      div(class: "post-card-body") do
        p { self.truncate(@post.body, length: 150) }
      end
      footer(class: "post-card-footer") do
        a(href: "/posts/#{@post.id}", onclick: "return navigate(event, '/posts/#{@post.id}')", class: "read-more") { "Read more" }
      end
    end
  end
end
