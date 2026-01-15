---
order: 120
title: Integrations
top_section: Introduction
category: integrations
---

{% rendercontent "docs/note", type: "warning" %}
Heads up: we're in the process of consolidating our supported tech stack. Going forward we'll primarily focus on [frontend code compiled via esbuild](https://github.com/ruby2js/ruby2js/tree/master/packages/esbuild-plugin), which can work in Rails, Bridgetown, and other web projects. (And of course you can build more elaborate solutions using the [CLI](/docs/cli) or direct Ruby API.) [Read the announcement for further details.](/updates/future-of-ruby2js/)
{% endrendercontent %}

# Ruby back-end servers

* [Rails](../examples/rails/) integration is provided
   for both Webpacker and Sprockets.  Rake tasks are provided to assist with
   the configuration. If you're using the new [jsbundling](https://github.com/rails/jsbundling-rails)
   Rails 7 plugin, you'll likely want to look at the front-end bundling instructions below.

* [Sinatra](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/sinatra.rb)
  views may be used to produce JavaScript from Ruby, enabled by
  `require "ruby2js/sinatra"`

* [CGI](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/cgi.rb)
  scripts may also be used to produce JavaScript from Ruby.
  This can be combined with [Wunderbar](https://github.com/rubys/wunderbar) to
  produce both HTML and JavaScript, enabled by `require "wunderbar/script"`.

* [Haml](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/haml.rb)
  scripts can be written in Ruby via a filter enabled by `require
  "ruby2js/haml"`

# JavaScript front-end build tools

[Vite](/docs/vite) is the recommended build tool for Ruby2JS projects. The `vite-plugin-ruby2js` package provides Hot Module Replacement, source maps, and framework-specific presets (Rails, Juntos, and more). See the [Vite Integration](/docs/vite) guide for details.

The [ESM](/docs/filters/esm) filter lets you author `import` and `export` statements, and the [autoexports](/docs/options#auto-exports) and [autoimports](/docs/options#auto-imports) options can often relieve you of the need to do so.

# JavaScript bundlers

An [esbuild](/docs/esbuild) plugin is available for fast builds of CLI tools,
serverless functions, and other non-web projects. For web applications with
hot module replacement, see the [Vite](/docs/vite) integration.

The [ESM](/docs/filters/esm) filter and [autoexports](/docs/options#auto-exports)
and [autoimports](/docs/options#auto-imports) options are useful with bundlers.

# Web Components

Filters are available for [Lit](/docs/filters/lit),
[React](/docs/filters/react), and [Stimulus](/docs/filters/stimulus).  The
[React](/docs/filters/react) filter also supports Preact.

# Node.js

A [Node](/docs/filters/node) filter is available, as well as a
[register](https://www.npmjs.com/package/@ruby2js/register) module.  In most
cases it will be the [CJS](/docs/filters/cjs) filter rather than the
[ESM](/docs/filters/esm) filter that you will want to use.

# Ruby2JS on Rails

The [Rails filter](/docs/filters/rails) enables transpiling entire Rails applications to JavaScript. Models, controllers, routes, and ERB templates are converted to run in browsers or JavaScript server runtimes (Node.js, Bun, Deno).

This approach is ideal for offline-first applications, static deployment, and edge computing. See the [Ruby2JS on Rails guide](/docs/users-guide/ruby2js-on-rails) for details.
