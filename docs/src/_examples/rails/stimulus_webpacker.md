---
top_section: Rails
order: 33
title: Stimulus Webpacker
category: stimulus webpacker
---

{% rendercontent "docs/note" %}
**This example is based on Rails Version: 6**
{% endrendercontent %}

This example is based on the [Stimulus site](https://stimulus.hotwired.dev/), but based on
Ruby2JS instead and hosted by Ruby on Rails.  It uses Webpacker.
See the [stimulus filter](../../docs/filters/stimulus) for more details.

## Create a Project

Start a new project:

```
rails new stimulus-webpacker
cd stimulus-webpacker
```

Add the following lines to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
gem 'stimulus-rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:stimulus:webpacker
```

## Write some HTML and a matching Stimulus controller

Generate a Rails controller:

```
./bin/rails generate controller Greeter hello
```

Add the following to `app/views/greeter/hello.html.erb`:

```html
<div data-controller="hello">
  <input data-hello-target="name" type="text">

  <button data-action="click->hello#greet">
    Greet
  </button>

  <span data-hello-target="output">
  </span>
</div>
```

Remove `app/javascript/controllers/hello_controller.js`, and create
`app/javascript/controllers/hello_controller.js.rb` with the following
contents:

<div data-controller="ruby" data-options='{
  "eslevel": 2022,
  "autoexports": "default",
  "filters": ["esm", "stimulus", "functions"]
}'></div>

```ruby
class HelloController < Stimulus::Controller
  def greet()
    outputTarget.textContent =
      "Hello, #{nameTarget.value} from Ruby!"
  end
end
```

## Try it out!

Start your server:

```
./bin/rails server
```

Visit <http://localhost:3000/greeter/hello>.  What you should see:

<p data-controller="eval" data-html="div.language-html"></p>

Make a change to `app/javascript/controllers/hello_controller.js.rb`
and see the results.

In case you are curious, the JavaScript that Ruby2JS returned back to webpack
was the following:

<div data-controller="js"></div>
