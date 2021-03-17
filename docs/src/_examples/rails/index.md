---
top_section: Rails
order: 31
toc_title: Introduction
title: Rails Introduction
category: rails intro
---

Webpacker is installed by default in Rails 6.0 and up.  The following steps
will install Ruby2js and configure webpacker to use it:

Add the following line to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails rails webpacker:install:ruby2js
```

The following pages show examples of installing Ruby2JS preconfigured to
support other popular frameworks.

Once installed, further configuration of the options and filters is done in
`config/webpack/loaders/ruby2js.js` for Webpacker and
`config/initializers/ruby2js.rb` for Sprockets/asset-pipeline.
