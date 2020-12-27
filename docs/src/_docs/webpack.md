---
order: 2
title: Webpack Setup
top_section: Introduction
category: webpack
---

The `@ruby2js/webpack-loader` lets you compile `.rb.js` files to JavaScript via Webpack.

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