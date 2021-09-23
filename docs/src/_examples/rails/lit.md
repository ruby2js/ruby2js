---
top_section: Rails
order: 34
title: Lit
category: lit
---

{% rendercontent "docs/note" %}
**This example is based on Rails Version: 6**
{% endrendercontent %}

This example is based on the 
[LitElement tutorial](https://lit-element.polymer-project.org/try/style), but
based on Ruby2JS instead and hosted by Ruby on Rails.  See the
[lit filter](../../docs/filters/lit) for more details.

## Create a Project

Start a new project:

```
rails new ruby2js-litelement
cd ruby2js-litelement
```

Add the following line to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:lit-webpacker
```

## Write some HTML and a matching Custom Element

Generate a Rails controller:

```
./bin/rails generate controller Demo run
```

Create `app/javascript/elements/my_element_element.js.rb` with the following
contents:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "lit", "functions"]
}'></div>

```ruby
class MyElement < LitElement
   def self.styles
    %{
      p {
        font-family: Roboto;
        font-size: 16px;
        font-weight: 500;
      }
      .red {
        color: red;
      }
      .blue {
        color: blue;
      }
    }
  end

  def initialize
    @message = 'Hello world! From my-element'
    @myArray = %w(an array of test data)
    @myBool = true
  end

  def render
    %{
      <p class="#{@myBool ? 'red' : 'blue'}">styled paragraph</p>
      <p>#{@message}</p>
      <ul>#{@myArray.map {|item| "<li>#{item}</li>"}}</ul>
      #{@myBool ?
        "<p>Render some HTML if myBool is true</p>" :
        "<p>Render some other HTML if myBool is false</p>"}
      <button @click="#{clickHandler}">Click</button>
    }
  end

  def clickHandler(event)
    puts event.target
    @myBool = !@myBool
  end
end

customElements.define('my-element', MyElement)
```

Add the following to `app/views/demo/run.html.erb`:

```html
<my-element></my-element>
```

## Try it out!

Start your server:

```
./bin/rails server
```

Visit <http://localhost:3000/demo/run>.  What you should see:

<p data-controller="eval" data-html="div.language-html"></p>
