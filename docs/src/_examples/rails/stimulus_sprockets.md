---
top_section: Rails
order: 32
title: Stimulus Sprockets
category: stimulus sprockets
---

This example is based on the [Stimulus site](https://reactjs.org/), but based on
Ruby2JS instead and hosted by Ruby on Rails.  It also uses the
Sprockets/asset-pipeline instead of Webpacker.  The Rails Guides have more
information on how [Sprockets is different than
Webpacker](https://edgeguides.rubyonrails.org/webpacker.html#how-is-webpacker-different-from-sprockets-questionmark).

## Create a Project

Start a new project:

```
rails new stimulus-sprockets
cd stimulus-sprockets
```

Add the following lines to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
gem 'stimulus-rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:stimulus:sprockets
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

Remove `app/assets/javascripts/controllers/hello_controller.js`, and create
`app/assets/javascripts/controllers/hello_controller.js.rb` with the following
contents:

<div data-controller="ruby" data-options='{
  "eslevel": 2020,
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

Browse <http://localhost:3000/assets/controllers/hello_controller.js>.  This
should match the following:

<div data-controller="js"></div>

Make a change to `app/assets/javascript/controllers/hello_controller.js.rb`
and see the results.

{% rendercontent "docs/note" %}
**Note**: The assignment to `HelloController.targets` at the bottom of the
above differs from most Stimulus examples you may have seen.  This is due to
[Static Public Fields](https://github.com/tc39/proposal-static-class-features#static-public-fields)
being only a stage 3 proposal right now and
[not yet supported](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Classes/static#browser_compatibility)
on all major browsers.  If your browser supports it, feel free to change
`2020` to `2022` in `config/initializers/ruby2js.rb` and restart your rails
server.
{% endrendercontent %}
