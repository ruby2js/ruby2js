---
top_section: Rails
order: 32
title: Stimulus Rollup
category: stimulus rollup
---

{% rendercontent "docs/note" %}
**This example is based on Rails Version: 7**
{% endrendercontent %}

This example makes use of the new jsbundling-rails support included in Rails
7.

## Create a Project

Start a new project:

```
rails new stimulus-rollup -j rollup
cd stimulus-rollup
```

Add the following line to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:stimulus:rollup
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

As you created a new controller, you will need to update the stimulus
manifest.  You will also need to build and bundle your change (this can be done with a
`--watch` parameter to automatically be run every time a controller changes).
Finally you will need to start your server.

This can be accomplished with the following three commands:

```
./bin/rails stimulus:manifest:update
yarn build
./bin/rails server
```

Visit <http://localhost:3000/greeter/hello>.  What you should see:

<p data-controller="eval" data-html="div.language-html"></p>

Browse <http://localhost:3000/assets/controllers/hello_controller.js>.  This
should match the following:

<div data-controller="js"></div>

Make a change to `app/assets/javascript/controllers/hello_controller.js.rb`
and see the results.  Make sure you either have `yarn build --watch` running,
or you have rerun `yarn build` manually.
