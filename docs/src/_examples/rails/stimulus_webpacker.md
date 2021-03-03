---
top_section: Rails
order: 32
title: Stimulus Webpacker
category: stimulus webpacker
---

Start a new project:

```
rails new stimulus-webpacker
cd stimulus-webpacker
```

## Install Stimulus support

Add the [stimulus-rails](https://github.com/hotwired/stimulus-rails) gem to your `Gemfile`:

```ruby
gem 'stimulus-rails'
```

Run `./bin/bundle install`

Run `./bin/rails stimulus:install`

## Add and configure Ruby2JS

Run `yarn add @ruby2js/webpack-loader`.

Replace the contents of `config/webpack/environment.js` with:

```javascript
const { environment } = require('@rails/webpacker')

const babelOptions = environment.loaders.get('babel').use[0].options

// Insert rb2js loader at the end of list
environment.loaders.append('rb2js', {
  test: /\.js\.rb$/,
  use: [
    {
      loader: "babel-loader",
      options: {...babelOptions}
    },

    {
      loader: "@ruby2js/webpack-loader",
      options: {
        autoexports: "default",
        eslevel: 2022,
        filters: ['esm', 'functions', 'stimulus']
      }
    },
  ]
})

module.exports = environment
```

Add `(\.rb)?` to the `require.context` line in
`app/javascript/controllers/index.js`:

```javascript
const context = require.context("controllers", true, /_controller\.js(\.rb)?$/)
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

Remove `app/javascripts/controllers/hello_controller.js`, and create
`app/javascripts/controllers/hello_controller.js.rb` with the following
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

Make a change to `app/javascripts/controllers/hello_controller.js.rb`
and see the results.

In case you are curious, the JavaScript that Ruby2JS returned back to webpack
was the following:

<div data-controller="js"></div>
