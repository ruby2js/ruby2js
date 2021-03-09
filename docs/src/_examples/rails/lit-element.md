---
top_section: Rails
order: 33
title: LitElement
category: lit-element
---

This example is based on the 
[LitElement tutorial](https://lit-element.polymer-project.org/try/style), but
based on Ruby2JS instead and hosted by Ruby on Rails.

Notable differences from the original JavaScript:

  * No need for `static get properties`.
  * No need for `this.`.
  * No need to identify which strings are `css` and which are `html`.
  * No need to code a call to `super()`.

## Create a Project

Start a new project:

```
rails new ruby2js-litelement
cd ruby2js-litelement
```

## Install Lit-element

Install `lit-element`:

```
yarn add lit-element
```

Make a directory for the elements you will be creating:

```
mkdir app/javascript/elements
```

Place the following in `app/javascript/elements/index.js` to load the elements:

```
function importAll(r) { r.keys().forEach(r) }
importAll(require.context("elements", true, /_elements?\.js(\.rb)?$/)
```

Add the following line to `app/javascript/packs/application.js` to load the
index:
 
```javascript
import "elements"
```

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
        eslevel: 2021,
        filters: ['esm', 'functions', 'lit-element']
      }
    },
  ]
})

module.exports = environment
```

Add `.js.rb` to `config/webpacker.yml` in the `default`.`extensions` section:

```
    - .js.rb
```

## Write some HTML and a matching Stimulus controller

Generate a Rails controller:

```
./bin/rails generate controller Demo run
```

Create `app/javascript/elements/my_element_element.js.rb` with the following
contents:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "lit-element", "functions"]
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
    console.log(event.target)
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
