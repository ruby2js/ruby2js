require 'minitest/autorun'
require 'ruby2js/filter/ink'

describe Ruby2JS::Filter::Ink do

  def to_js(string, eslevel: 2022)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Ink], eslevel: eslevel).to_s)
  end

  describe 'Ink component detection' do
    it "should detect Ink::Component inheritance" do
      result = to_js(<<~RUBY)
        class MyComponent < Ink::Component
          def view_template
            Box { Text { "hello" } }
          end
        end
      RUBY
      result.must_include 'function MyComponent'
      result.must_include 'React.createElement'
    end

    it "should not transform non-Ink classes" do
      result = to_js(<<~RUBY)
        class MyClass < BaseClass
          def view_template
            Box { Text { "hello" } }
          end
        end
      RUBY
      result.must_include 'view_template()'
      result.wont_include 'React.createElement'
    end
  end

  describe 'basic elements' do
    it "should convert Box element" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box { "content" }
          end
        end
      RUBY
      result.must_include 'React.createElement(Box'
    end

    it "should convert Text element" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Text { "hello" }
          end
        end
      RUBY
      result.must_include 'React.createElement(Text'
    end

    it "should handle nested elements" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box do
              Text { "hello" }
            end
          end
        end
      RUBY
      result.must_include 'React.createElement'
      result.must_include 'Box'
      result.must_include 'Text'
    end

    it "should handle multiple children" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box do
              Text { "first" }
              Text { "second" }
            end
          end
        end
      RUBY
      result.must_include 'React.createElement'
      result.must_include 'Box'
      # Should have two Text elements
      _(result.to_s.scan(/React\.createElement\(\s*Text/).length).must_equal 2
    end
  end

  describe 'props' do
    it "should pass props to elements" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box(flexDirection: "column") { "content" }
          end
        end
      RUBY
      result.must_include 'flexDirection: "column"'
    end

    it "should handle multiple props" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Text(bold: true, color: "green") { "styled" }
          end
        end
      RUBY
      result.must_include 'bold: true'
      result.must_include 'color: "green"'
    end

    it "should handle nil props" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box { "content" }
          end
        end
      RUBY
      result.must_include 'React.createElement(Box, null'
    end
  end

  describe 'instance variables' do
    it "should convert instance variables to destructured params" do
      result = to_js(<<~RUBY)
        class Greeting < Ink::Component
          def view_template
            Text { "Hello, \#{@name}!" }
          end
        end
      RUBY
      result.must_match(/function Greeting\(\s*\{\s*name\s*\}\s*\)/)
      result.wont_include '@name'
    end

    it "should handle multiple instance variables" do
      result = to_js(<<~RUBY)
        class Profile < Ink::Component
          def view_template
            Box do
              Text { @name }
              Text { @email }
            end
          end
        end
      RUBY
      result.must_include 'email'
      result.must_include 'name'
    end
  end

  describe 'key bindings' do
    it "should generate useInput hook for keys declaration" do
      result = to_js(<<~RUBY)
        class Input < Ink::Component
          keys return: :submit

          def view_template
            Box { "input" }
          end
        end
      RUBY
      result.must_include 'useInput'
    end

    it "should handle multiple key bindings" do
      result = to_js(<<~RUBY)
        class Nav < Ink::Component
          keys up: :previous, down: :next, return: :select

          def view_template
            Box { "nav" }
          end
        end
      RUBY
      result.must_include 'useInput'
      result.must_include 'upArrow'
      result.must_include 'downArrow'
      result.must_include 'key.return'
    end

    it "should handle character key bindings" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          keys "q" => :quit

          def view_template
            Box { "app" }
          end
        end
      RUBY
      result.must_include 'useInput'
      result.must_include '"q"'
    end
  end

  describe 'ecosystem elements' do
    it "should handle TextInput element" do
      result = to_js(<<~RUBY)
        class Form < Ink::Component
          def view_template
            TextInput(value: @query, onChange: @on_change)
          end
        end
      RUBY
      result.must_match(/React\.createElement\(\s*TextInput/)
    end

    it "should handle Spinner element" do
      result = to_js(<<~RUBY)
        class Loading < Ink::Component
          def view_template
            Spinner
          end
        end
      RUBY
      result.must_include 'React.createElement(Spinner'
    end
  end

  describe 'conditionals' do
    it "should handle if statements" do
      result = to_js(<<~RUBY)
        class App < Ink::Component
          def view_template
            Box do
              if @loading
                Text { "Loading..." }
              else
                Text { "Done" }
              end
            end
          end
        end
      RUBY
      # In React/JSX context, conditionals are typically rendered as ternary
      result.must_include 'loading ?'
    end

    it "should handle ternary in JSX context" do
      result = to_js(<<~RUBY)
        class Status < Ink::Component
          def view_template
            Text(color: @success ? "green" : "red") { @message }
          end
        end
      RUBY
      result.must_include 'success ?'
    end
  end
end
