require 'minitest/autorun'
require 'ruby2js/filter/phlex'
require 'ruby2js/filter/vue'

describe Ruby2JS::Filter::Vue do

  def to_vue(string)
    Ruby2JS.convert(string,
      filters: [:phlex, :vue],
      eslevel: 2022
    ).to_s
  end

  describe "basic components" do
    it "should convert a simple Phlex component to Vue SFC format" do
      result = to_vue <<~RUBY
        class Card < Phlex::HTML
          def initialize(title:)
            @title = title
          end

          def view_template
            div(class: "card") { h1 { @title } }
          end
        end
      RUBY

      _(result).must_include '<template>'
      _(result).must_include '</template>'
      _(result).must_include '<script setup>'
      _(result).must_include "defineProps(['title'])"
      _(result).must_include '<div class="card">'
      _(result).must_include '{{ title }}'
    end

    it "should handle multiple props" do
      result = to_vue <<~RUBY
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

      _(result).must_include "defineProps(["
      _(result).must_include '<article>'
      _(result).must_include '{{ title }}'
      _(result).must_include '{{ content }}'
      _(result).must_include '{{ author }}'
    end

    it "should handle components without props" do
      result = to_vue <<~RUBY
        class Static < Phlex::HTML
          def view_template
            div { "Hello, World!" }
          end
        end
      RUBY

      # No script section needed for static content
      _(result).wont_include '<script setup>'
      _(result).must_include '<div>Hello, World!</div>'
    end
  end

  describe "Vue template syntax" do
    it "should use {{ }} for interpolation" do
      result = to_vue <<~RUBY
        class Display < Phlex::HTML
          def initialize(name:)
            @name = name
          end

          def view_template
            span { @name }
          end
        end
      RUBY

      _(result).must_include '{{ name }}'
      _(result).wont_include '{name}'  # Not JSX style
    end

    it "should use :attr for dynamic attributes" do
      result = to_vue <<~RUBY
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

      _(result).must_include ':href="url"'
      _(result).must_include '{{ label }}'
    end
  end

  describe "HTML elements" do
    it "should handle void elements" do
      result = to_vue <<~RUBY
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
      result = to_vue <<~RUBY
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
      result = to_vue <<~RUBY
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
    it "should handle method calls in expressions" do
      result = to_vue <<~RUBY
        class Display < Phlex::HTML
          def initialize(name:)
            @name = name
          end

          def view_template
            div { @name.upcase }
          end
        end
      RUBY

      _(result).must_include '{{ name.upcase }}'
    end
  end

  describe "fragments" do
    it "should handle fragment content" do
      result = to_vue <<~RUBY
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
