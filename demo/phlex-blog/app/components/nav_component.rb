# Navigation component - site header with navigation links
class NavComponent < Phlex::HTML
  def view_template
    nav(class: "site-nav") do
      div(class: "nav-brand") do
        a(href: "/", onclick: "return navigate(event, '/')", class: "brand-link") { "Phlex Blog" }
      end
      div(class: "nav-links") do
        a(href: "/posts", onclick: "return navigate(event, '/posts')", class: "nav-link") { "Posts" }
        a(href: "/posts/new", onclick: "return navigate(event, '/posts/new')", class: "nav-link") { "New Post" }
      end
    end
  end
end
