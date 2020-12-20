# @ruby2js/webpack-loader

[![npm][npm]][npm-url]
[![node][node]][node-url]

Webpack loader to compile [Ruby2JS](https://github.com/rubys/ruby2js) (`.js.rb`) files to JavaScript.

**Fun fact:** this loader itself is written in Ruby and compiles via Ruby2JS + Babel. 😁

## Installation

Add the following to your Gemfile:

```ruby
gem "ruby2js", ">= 3.5"
```

and run `bundle install`.

Then run `yarn add @ruby2js/webpack-loader` to pull in this Webpack loader plugin.

You will need to add a config file for Ruby2JS in order to perform the file conversions. In your root folder (alongside `Gemfile`, `package.json`, etc.), create `rb2js.config.rb`:

```ruby
require "ruby2js/filter/functions"
require "ruby2js/filter/camelCase"
require "ruby2js/filter/return"
require "ruby2js/filter/esm"
require "ruby2js/filter/tagged_templates"

require "json"

module Ruby2JS
  class Loader
    def self.options
      # Change the options for your configuration here:
      {
        eslevel: 2021,
        include: :class,
        underscored_private: true
      }
    end

    def self.process(source)
      Ruby2JS.convert(source, self.options).to_s
    end

    def self.process_with_source_map(source)
      conv = Ruby2JS.convert(source, self.options)
      {
        code: conv.to_s,
        sourceMap: conv.sourcemap
      }.to_json
    end
  end
end
```

That's just one possible configuration—you can edit this file as needed to modify or add additional Ruby2JS filters, pass options to the converter, and so forth.

## Webpack Configuration

(For Rails-specific configuration, see below.)

You'll need to edit your Webpack config so it can use the `@ruby2js/webpack-loader` plugin. In your `webpack.config.js` file, add the following in the `modules.rules` section:

```js
{
  test: /\.js\.rb$/,
  use: [
    {
      loader: "babel-loader",
      options: {
      presets: ["@babel/preset-env"],
        plugins: [
          [
            "@babel/plugin-transform-runtime",
            {
              helpers: false,
            },
          ],
        ],
      }
    },
    "@ruby2js/webpack-loader"
  ]
}
```

(If you currently use other Babel plugins elsewhere in your Webpack config, feel free to copy them here, or define them once in a variable up top and simply add them to both parts of the config tree.)

Now wherever you save your `.js` files, you can write `.js.rb` files which will be converted to Javascript and processed through Babel. You'll probably have a main `index.js` file already, so you can simply import the Ruby files from there and elsewhere. You'll have to include the full extension in the import statement, i.e. `import MyClass from "./lib/my_class.js.rb"`.

See the next example in the Rails section for how to write a web component based on open standards using [LitElement](https://lit-element.polymer-project.org).

## Source Maps

By default, `@ruby2js/webpack-loader` will provide source maps if requested by Webpack. If you're having trouble debugging code and want to inspect the JS output from Ruby2JS, you can keep source maps on at the Webpack level but _turn them off_ at the loader level in your config:

```js
{
  use: [
    // …
    {
      loader: "@ruby2js/webpack-loader",
      options: { provideSourceMaps: false }
    }
  ]
}
```

Of course to get back to the default behavior, simply change `provideSourceMaps` to `true` or remove it from the options.

## Usage with Rails and ViewComponent

In your existing Rails + ViewComponent setup, add the following configuration initializer:

`app/config/initializers/rb2js.rb`:

```ruby
Rails.autoloaders.each do |autoloader|
  autoloader.ignore("app/components/**/*.js.rb")
end
```

This ensures any `.js.rb` files in your components folder won't get picked up by the Zeitwerk autoloader. Only Webpack + Ruby2JS should look at those files.

You'll also need to tell Webpacker how to use the `@ruby2js/webpack-loader` plugin. In your `config/webpack/environment.js` file, add the following above the ending `module.exports = environment` line:

```js
const babelOptions = environment.loaders.get('babel').use[0].options

// Insert rb2js loader at the end of list
environment.loaders.append('rb2js', {
  test: /\.js\.rb$/,
  use: [
    {
      loader: "babel-loader",
      options: {...babelOptions}
    },
    "@ruby2js/webpack-loader"
  ]
})
```

Now, by way of example, let's create a wrapper component around the [Duet Date Picker](https://duetds.github.io/date-picker/) component we can use to customize the picker component and handle change events.

First, run `yarn add lit-element @duetds/date-picker` to add the Javascript dependencies.

Next, in `app/javascript/packs/application.js`, add:

```js
import "../components"
```

Then create `app/javascript/components.js`:

```js
function importAll(r) {
  r.keys().forEach(r)
}

importAll(require.context("../components", true, /_component\.js$/))
importAll(require.context("../components", true, /_elements?\.js\.rb$/))
```

Now we'll write the ViewComponent in `app/components/date_picker_component.rb`:

```ruby
class DatePickerComponent < ApplicationComponent
  def initialize(identifier:, date:)
    @identifier = identifier
    @date = date
  end
end
```

And the Rails view template: `app/components/date_picker_component.html.erb`:

```eruby
<app-date-picker identifier="<%= @identifier %>" value="<%= @date.strftime("%Y-%m-%d") %>"></app-date-picker>
```

Hey, what's all this custom element stuff? Well that's what we're going to define now! Let's use Ruby to write a web component using the [LitElement library](https://lit-element.polymer-project.org).

Simply create `app/components/date_picker_element.js.rb`:

```ruby
import [ LitElement, html ], from: "lit-element"
import [ DuetDatePicker ], from: "@duetds/date-picker/custom-element"
import "@duetds/date-picker/dist/duet/themes/default.css"

customElements.define("duet-date-picker", DuetDatePicker)

class AppDatePicker < LitElement
  self.properties = {
    identifier: { type: String },
    value: { type: String }
  }

#  If you need to add custom styles:
#
#  self.styles = css <<~CSS
#    :host {
#      background: yellow;
#    }
#  CSS

  def _handle_change(event)
    console.log(event)
    # Perhaps set a hidden form field with the value in event.detail.value...
  end

  def updated()
    date_format = %r(^(\d{1,2})/(\d{1,2})/(\d{4})$)

    self.shadow_root.query_selector("duet-date-picker")[:date_adapter] = {
      parse: ->(value = "", create_date) {
        matches = value.match(date_format)
        create_date(matches[3], matches[2], matches[1]) if matches
      },
      format: ->(date) {
        "#{date.get_month() + 1}/#{date.get_date()}/#{date.get_full_year()}"
      },
    }
  end

  def render()
    html <<~HTML
      <duet-date-picker @duetChange="#{@handle_change}" identifier="#{self.identifier}" value="#{self.value}"></duet-date-picker>
    HTML
  end
end

customElements.define("app-date-picker", AppDatePicker)
```

Now all you have to do is render the ViewComponent in a Rails view somewhere, and you're done!

```eruby
Date picker: <%= render DatePickerComponent.new(identifier: "closing_date", date: @model.date) %>
```

Framework-less open standard web components compiled and bundled with Webpack, yet written in Ruby. How cool is that?!

## Testing

_To be continued…_

## Contributing

1. Fork it (https://github.com/rubys/ruby2js/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT

[npm]: https://img.shields.io/npm/v/@ruby2js/webpack-loader.svg
[npm-url]: https://npmjs.com/package/@ruby2js/webpack-loader
[node]: https://img.shields.io/node/v/@ruby2js/webpack-loader.svg
[node-url]: https://nodejs.org
