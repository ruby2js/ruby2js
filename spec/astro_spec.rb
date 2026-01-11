require 'minitest/autorun'
require 'ruby2js/filter/phlex'
require 'ruby2js/filter/astro'

describe Ruby2JS::Filter::Astro do

  def to_astro(string)
    Ruby2JS.convert(string,
      filters: [:phlex, :astro],
      eslevel: 2022
    ).to_s
  end

  describe "basic components" do
    it "should convert a simple Phlex component to Astro format" do
      result = to_astro <<~RUBY
        class Card < Phlex::HTML
          def initialize(title:)
            @title = title
          end

          def view_template
            div(class: "card") { h1 { @title } }
          end
        end
      RUBY

      _(result).must_include '---'
      _(result).must_include 'const { title } = Astro.props;'
      _(result).must_include '<div class="card">'
      _(result).must_include '<h1>{title}</h1>'
    end

    it "should handle multiple props" do
      result = to_astro <<~RUBY
        class Article < Phlex::HTML
          def initialize(title:, content:, author:)
            @title = title
            @content = content
            @author = author
          end

          def view_template
            article do
              h1 { @title }
              p { @content }
              span { @author }
            end
          end
        end
      RUBY

      # Props may be in any order
      _(result).must_match(/const \{ .*(title|content|author).* \} = Astro\.props;/)
      _(result).must_include 'title'
      _(result).must_include 'content'
      _(result).must_include 'author'
      _(result).must_include '<article>'
      _(result).must_include '<h1>{title}</h1>'
      _(result).must_include '<p>{content}</p>'
      _(result).must_include '<span>{author}</span>'
    end

    it "should handle components without props" do
      result = to_astro <<~RUBY
        class Static < Phlex::HTML
          def view_template
            div { "Hello, World!" }
          end
        end
      RUBY

      # No frontmatter needed for static content
      _(result).wont_include 'const {'
      _(result).must_include '<div>Hello, World!</div>'
    end
  end

  describe "HTML elements" do
    it "should handle void elements" do
      result = to_astro <<~RUBY
        class Form < Phlex::HTML
          def view_template
            input(type: "text", name: "email")
            br
          end
        end
      RUBY

      _(result).must_include '<input type="text" name="email" />'
      _(result).must_include '<br />'
    end

    it "should handle nested elements" do
      result = to_astro <<~RUBY
        class Nav < Phlex::HTML
          def view_template
            nav(class: "main") do
              ul do
                li { "Home" }
                li { "About" }
              end
            end
          end
        end
      RUBY

      _(result).must_include '<nav class="main">'
      _(result).must_include '<ul>'
      _(result).must_include '<li>Home</li>'
      _(result).must_include '<li>About</li>'
    end

    it "should handle boolean attributes" do
      result = to_astro <<~RUBY
        class Button < Phlex::HTML
          def view_template
            button(disabled: true) { "Click" }
          end
        end
      RUBY

      _(result).must_include '<button disabled>Click</button>'
    end
  end

  describe "dynamic content" do
    it "should handle dynamic attributes" do
      result = to_astro <<~RUBY
        class Link < Phlex::HTML
          def initialize(url:, label:)
            @url = url
            @label = label
          end

          def view_template
            a(href: @url) { @label }
          end
        end
      RUBY

      _(result).must_include 'href={url}'
      _(result).must_include '{label}'
    end

    it "should handle method calls in expressions" do
      result = to_astro <<~RUBY
        class Display < Phlex::HTML
          def initialize(name:)
            @name = name
          end

          def view_template
            div { @name.upcase }
          end
        end
      RUBY

      _(result).must_include '{name.upcase}'
    end
  end

  describe "fragments" do
    it "should handle fragment content" do
      result = to_astro <<~RUBY
        class Multi < Phlex::HTML
          def view_template
            h1 { "Title" }
            p { "Content" }
          end
        end
      RUBY

      _(result).must_include '<h1>Title</h1>'
      _(result).must_include '<p>Content</p>'
    end
  end
end
