require 'minitest/autorun'
require 'ruby2js/filter/phlex'

describe Ruby2JS::Filter::Phlex do

  def to_js(string, eslevel: 2020)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Phlex], eslevel: eslevel).to_s)
  end

  describe 'Phlex component detection' do
    it "should detect Phlex::HTML inheritance" do
      result = to_js(<<~RUBY)
        class MyComponent < Phlex::HTML
          def view_template
            div { "hello" }
          end
        end
      RUBY
      result.must_include 'class MyComponent'
      result.must_include 'render()'
    end

    it "should not transform non-Phlex classes" do
      result = to_js(<<~RUBY)
        class MyClass < BaseClass
          def view_template
            div { "hello" }
          end
        end
      RUBY
      result.must_include 'view_template()'
      result.wont_include 'render()'
    end
  end

  describe 'basic elements' do
    it "should convert simple div" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div { "content" }
          end
        end
      RUBY
      result.must_include '<div>'
      result.must_include '</div>'
      result.must_include 'content'
    end

    it "should convert void elements without closing tag" do
      result = to_js(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input
            br
          end
        end
      RUBY
      result.must_include '<input>'
      result.must_include '<br>'
      result.wont_include '</input>'
      result.wont_include '</br>'
    end

    it "should handle multiple elements" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            h1 { "Title" }
            p { "Paragraph" }
          end
        end
      RUBY
      result.must_include '<h1>'
      result.must_include '</h1>'
      result.must_include '<p>'
      result.must_include '</p>'
    end
  end

  describe 'attributes' do
    it "should convert class attribute" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: "card") { "content" }
          end
        end
      RUBY
      # Quotes are escaped in JS string output
      result.must_include 'class=\\"card\\"'
    end

    it "should convert multiple attributes" do
      result = to_js(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input(type: "text", name: "email", placeholder: "Enter email")
          end
        end
      RUBY
      # Quotes are escaped in JS string output
      result.must_include 'type=\\"text\\"'
      result.must_include 'name=\\"email\\"'
      result.must_include 'placeholder=\\"Enter email\\"'
    end

    it "should convert data attributes with underscores to dashes" do
      result = to_js(<<~RUBY)
        class Button < Phlex::HTML
          def view_template
            button(data_controller: "click", data_action: "click->do") { "Click" }
          end
        end
      RUBY
      # Quotes are escaped in JS string output
      result.must_include 'data-controller=\\"click\\"'
      result.must_include 'data-action=\\"click-'
    end

    it "should handle boolean true attributes" do
      result = to_js(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input(type: "checkbox", checked: true)
          end
        end
      RUBY
      result.must_include 'checked'
    end

    it "should skip boolean false attributes" do
      result = to_js(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input(type: "checkbox", disabled: false)
          end
        end
      RUBY
      result.wont_include 'disabled'
    end
  end

  describe 'nested elements' do
    it "should handle nested elements" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: "card") do
              h2 { "Title" }
              p { "Content" }
            end
          end
        end
      RUBY
      # Quotes are escaped in JS string output
      result.must_include '<div class=\\"card\\">'
      result.must_include '<h2>'
      result.must_include '</h2>'
      result.must_include '<p>'
      result.must_include '</p>'
      result.must_include '</div>'
    end

    it "should handle deeply nested elements" do
      result = to_js(<<~RUBY)
        class Nav < Phlex::HTML
          def view_template
            nav do
              ul do
                li { "Item 1" }
                li { "Item 2" }
              end
            end
          end
        end
      RUBY
      result.must_include '<nav>'
      result.must_include '<ul>'
      result.must_include '<li>'
      result.must_include '</li>'
      result.must_include '</ul>'
      result.must_include '</nav>'
    end
  end

  describe 'phlex special methods' do
    it "should handle plain text" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            plain "Hello World"
          end
        end
      RUBY
      result.must_include 'String("Hello World")'
    end

    it "should handle whitespace" do
      result = to_js(<<~RUBY)
        class Inline < Phlex::HTML
          def view_template
            span { "a" }
            whitespace
            span { "b" }
          end
        end
      RUBY
      result.must_include '" "'
    end

    it "should handle unsafe_raw" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            unsafe_raw "<script>alert(1)</script>"
          end
        end
      RUBY
      result.must_include '<script>alert(1)</script>'
      result.wont_include 'String('
    end

    it "should handle comment" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            comment "TODO: fix this"
          end
        end
      RUBY
      result.must_include '<!-- TODO: fix this -->'
    end

    it "should handle doctype" do
      result = to_js(<<~RUBY)
        class Layout < Phlex::HTML
          def view_template
            doctype
            html { body { "content" } }
          end
        end
      RUBY
      result.must_include '<!DOCTYPE html>'
    end
  end

  describe 'instance variables' do
    it "should convert instance variables to parameters" do
      result = to_js(<<~RUBY)
        class Greeting < Phlex::HTML
          def view_template
            h1 { @title }
          end
        end
      RUBY
      result.must_include 'String(title)'
    end

    it "should destructure multiple instance variables as parameters" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            h1 { @title }
            p { @description }
            span { @author }
          end
        end
      RUBY
      # Parameters should be alphabetically sorted and destructured
      result.must_include 'render({ author, description, title })'
    end

    it "should remove initialize method" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def initialize(title:, description:)
            @title = title
            @description = description
          end

          def view_template
            h1 { @title }
            p { @description }
          end
        end
      RUBY
      result.wont_include 'initialize'
      result.wont_include 'constructor'
      result.must_include 'render({ description, title })'
    end
  end

  describe 'dynamic attributes' do
    it "should handle dynamic class attribute" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: @theme) { "content" }
          end
        end
      RUBY
      # Dynamic attributes use template literals
      result.must_include '${theme}'
      result.must_include 'render({ theme })'
    end

    it "should handle mixed static and dynamic attributes" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: "card", id: @card_id, data_theme: @theme) { "content" }
          end
        end
      RUBY
      # Template literals don't escape inner quotes
      result.must_include 'class="card"'
      result.must_include '${card_id}'
      result.must_include '${theme}'
    end
  end

  describe 'conditionals' do
    it "should handle if conditions" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            h1 { @title } if @show_title
          end
        end
      RUBY
      result.must_include 'if (show_title)'
      result.must_include '<h1>'
    end

    it "should handle unless conditions" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            p { @content } unless @hide_content
          end
        end
      RUBY
      result.must_include 'if (!hide_content)'
      result.must_include '<p>'
    end

    it "should handle if/else conditions" do
      result = to_js(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            if @premium
              div(class: "premium") { @content }
            else
              div(class: "basic") { @content }
            end
          end
        end
      RUBY
      result.must_include 'if (premium)'
      result.must_include 'else'
      result.must_include 'premium'
      result.must_include 'basic'
    end
  end

  describe 'loops' do
    def to_js_with_functions(string, eslevel: 2020)
      require 'ruby2js/filter/functions'
      _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Phlex, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
    end

    it "should handle each loops with functions filter" do
      result = to_js_with_functions(<<~RUBY)
        class ItemList < Phlex::HTML
          def view_template
            ul do
              @items.each do |item|
                li { item.name }
              end
            end
          end
        end
      RUBY
      result.must_include 'for (let item of items)'
      result.must_include '<li>'
      result.must_include '</li>'
    end

    it "should handle nested loops" do
      result = to_js_with_functions(<<~RUBY)
        class Table < Phlex::HTML
          def view_template
            table do
              @rows.each do |row|
                tr do
                  row.cells.each do |cell|
                    td { cell }
                  end
                end
              end
            end
          end
        end
      RUBY
      result.must_include 'for (let row of rows)'
      result.must_include 'for (let cell of row.cells)'
      result.must_include '<tr>'
      result.must_include '<td>'
    end
  end

  describe 'indirect inheritance with pragma' do
    it "should detect phlex pragma" do
      result = to_js(<<~RUBY)
        # @ruby2js phlex
        class Card < ApplicationComponent
          def view_template
            div { @title }
          end
        end
      RUBY
      result.must_include 'render({ title })'
      result.must_include '<div>'
    end
  end

  describe 'render function output' do
    it "should generate render function with buffer" do
      result = to_js(<<~RUBY)
        class Simple < Phlex::HTML
          def view_template
            div { "test" }
          end
        end
      RUBY
      result.must_include 'render()'
      result.must_include 'let _phlex_out = ""'
      result.must_include 'return _phlex_out'
    end
  end

  describe 'component composition' do
    it "should handle render Component.new without children" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            render Header.new(title: "Welcome")
          end
        end
      RUBY
      result.must_include 'Header.render'
      result.must_include 'title'
    end

    it "should handle render Component.new with children" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            render Card.new(class: "featured") do
              h1 { "Title" }
              p { "Content" }
            end
          end
        end
      RUBY
      result.must_include 'Card.render'
      result.must_include '<h1>'
      result.must_include '<p>'
    end

    it "should handle nested component composition" do
      result = to_js(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            render Layout.new do
              render Header.new(title: "Hi")
              render Footer.new
            end
          end
        end
      RUBY
      result.must_include 'Layout.render'
      result.must_include 'Header.render'
      result.must_include 'Footer.render'
    end
  end

  describe 'custom elements' do
    it "should handle tag without children" do
      result = to_js(<<~RUBY)
        class Widget < Phlex::HTML
          def view_template
            tag("my-widget", class: "custom")
          end
        end
      RUBY
      result.must_include '<my-widget'
      result.must_include '</my-widget>'
      result.must_include 'class'
    end

    it "should handle tag with children" do
      result = to_js(<<~RUBY)
        class Widget < Phlex::HTML
          def view_template
            tag("my-card") do
              span { "inner content" }
            end
          end
        end
      RUBY
      result.must_include '<my-card>'
      result.must_include '<span>'
      result.must_include '</span>'
      result.must_include '</my-card>'
    end

    it "should handle tag with data attributes" do
      result = to_js(<<~RUBY)
        class Widget < Phlex::HTML
          def view_template
            tag("custom-element", data_id: "123", data_action: "click")
          end
        end
      RUBY
      result.must_include '<custom-element'
      result.must_include 'data-id'
      result.must_include 'data-action'
    end
  end

  describe 'fragments' do
    it "should handle fragment with multiple children" do
      result = to_js(<<~RUBY)
        class MultiRoot < Phlex::HTML
          def view_template
            fragment do
              h1 { "Title" }
              p { "Paragraph" }
            end
          end
        end
      RUBY
      result.must_include '<h1>'
      result.must_include '</h1>'
      result.must_include '<p>'
      result.must_include '</p>'
      # Fragment should not add wrapper
      result.wont_include '<fragment>'
    end
  end

  describe 'React integration (write once, target both)' do
    require 'ruby2js/filter/react'

    def to_react(string, eslevel: 2020)
      _(Ruby2JS.convert(string,
        filters: [Ruby2JS::Filter::Phlex, Ruby2JS::Filter::React],
        eslevel: eslevel).to_s)
    end

    it "should convert single element to React.createElement" do
      result = to_react(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: "card") { "Hello" }
          end
        end
      RUBY
      result.must_include 'React.createElement'
      result.must_include '"div"'
      result.must_include 'className: "card"'
      result.must_include '"Hello"'
      result.wont_include '_phlex_out'
    end

    it "should wrap multiple elements in React.Fragment" do
      result = to_react(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            h1 { "Title" }
            p { "Content" }
          end
        end
      RUBY
      result.must_include 'React.Fragment'
      result.must_include 'React.createElement("h1"'
      result.must_include 'React.createElement("p"'
      result.wont_include '_phlex_out'
    end

    it "should handle nested elements" do
      result = to_react(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div { span { "inner" } }
          end
        end
      RUBY
      result.must_include 'React.createElement'
      result.must_include '"div"'
      result.must_include '"span"'
      result.must_include '"inner"'
    end

    it "should convert instance variables to props" do
      result = to_react(<<~RUBY)
        class Card < Phlex::HTML
          def initialize(title:)
            @title = title
          end
          def view_template
            h1 { @title }
          end
        end
      RUBY
      result.must_include 'render({ title })'
      result.must_include 'React.createElement("h1", null, title)'
      result.wont_include '@title'
    end

    it "should handle dynamic attributes" do
      result = to_react(<<~RUBY)
        class Button < Phlex::HTML
          def initialize(variant:)
            @variant = variant
          end
          def view_template
            button(class: @variant) { "Click" }
          end
        end
      RUBY
      result.must_include 'className: variant'
    end

    it "should handle component composition" do
      result = to_react(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            render Header.new(title: "Welcome")
            div { "content" }
          end
        end
      RUBY
      result.must_include 'Header'
      result.must_include 'React.createElement("div"'
    end

    it "should handle void elements" do
      result = to_react(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input(type: "text")
            br
          end
        end
      RUBY
      result.must_include 'React.createElement("input"'
      result.must_include 'React.createElement("br"'
    end

    it "should handle custom elements" do
      result = to_react(<<~RUBY)
        class Widget < Phlex::HTML
          def view_template
            tag("my-widget", class: "custom") { "content" }
          end
        end
      RUBY
      result.must_include 'React.createElement'
      result.must_include '"my-widget"'
      result.must_include 'className: "custom"'
    end

    it "should return React element object (not string)" do
      # Verify the output doesn't use string concatenation
      result = to_react(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div { "Hello" }
          end
        end
      RUBY
      result.must_include 'return React.createElement'
      result.wont_include '+='
      result.wont_include '_phlex_out'
    end
  end

  describe 'JSX output (one-way migration)' do
    require 'ruby2js/filter/react'
    require 'ruby2js/filter/jsx'

    def to_jsx(string, eslevel: 2020)
      _(Ruby2JS.convert(string,
        filters: [Ruby2JS::Filter::Phlex, Ruby2JS::Filter::React, Ruby2JS::Filter::JSX],
        eslevel: eslevel).to_s)
    end

    it "should convert single element to JSX" do
      result = to_jsx(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div(class: "card") { "Hello" }
          end
        end
      RUBY
      result.must_include '<div className="card">'
      result.must_include 'Hello'
      result.must_include '</div>'
      result.wont_include 'React.createElement'
    end

    it "should handle nested elements" do
      result = to_jsx(<<~RUBY)
        class Card < Phlex::HTML
          def view_template
            div { span { "inner" } }
          end
        end
      RUBY
      result.must_include '<div>'
      result.must_include '<span>'
      result.must_include 'inner'
      result.must_include '</span>'
      result.must_include '</div>'
    end

    it "should wrap multiple elements in Fragment" do
      result = to_jsx(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            h1 { "Title" }
            p { "Content" }
          end
        end
      RUBY
      result.must_include '<React.Fragment>'
      result.must_include '<h1>'
      result.must_include '<p>'
    end

    it "should handle void elements" do
      result = to_jsx(<<~RUBY)
        class Form < Phlex::HTML
          def view_template
            input(type: "text")
            br
          end
        end
      RUBY
      result.must_include '<input type="text"/>'
      result.must_include '<br/>'
    end

    it "should handle component rendering" do
      result = to_jsx(<<~RUBY)
        class Page < Phlex::HTML
          def view_template
            render Header.new(title: "Welcome")
          end
        end
      RUBY
      result.must_include '<Header'
      result.must_include 'title='
    end

    it "should handle custom elements" do
      result = to_jsx(<<~RUBY)
        class Widget < Phlex::HTML
          def view_template
            tag("my-widget", class: "custom") { "content" }
          end
        end
      RUBY
      result.must_include '<my-widget'
      result.must_include 'className="custom"'
    end

    it "should handle dynamic expressions" do
      result = to_jsx(<<~RUBY)
        class Card < Phlex::HTML
          def initialize(title:)
            @title = title
          end
          def view_template
            h1 { @title }
          end
        end
      RUBY
      result.must_include '<h1>'
      result.must_include '{title}'
      result.must_include '</h1>'
    end

    it "should output function component instead of class" do
      result = to_jsx(<<~RUBY)
        class Card < Phlex::HTML
          def initialize(title:)
            @title = title
          end
          def view_template
            div { @title }
          end
        end
      RUBY
      result.must_include 'function Card('
      result.wont_include 'class Card'
      result.wont_include 'extends'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Phlex" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Phlex
    end
  end
end
