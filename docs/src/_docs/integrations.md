---
order: 5
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

A plugins is available for [Vite](https://www.npmjs.com/package/@ruby2js/vite-plugin) which supports Hot Module Replacement and Refresh.  The [ESM](/docs/filters/esm)
filter lets you author `import` and `export` statements, and the
[autoexports](/docs/options#auto-exports) and
[autoimports](/docs/options#auto-imports) options can often relieve you of the
need to do so.

# JavaScript bundlers

An [esbuild](https://www.npmjs.com/package/@ruby2js/esbuild-plugin) plugin,
[Rollup](https://www.npmjs.com/package/@ruby2js/rollup-plugin) plugin,
and a [Webpack](https://www.npmjs.com/package/@ruby2js/webpack-loader) loader are
available.  Again, the [ESM](/docs/filters/esm)
filter and [autoexports](/docs/options#auto-exports) and
[autoimports](/docs/options#auto-imports) options are useful with bundlers.

# Web Components

Filters are available for [jQuery](/docs/filters/jquery), [Lit](/docs/filters/lit),
[React](/docs/filters/react), and [Stimulus](/docs/filters/stimulus).  The
[React](/docs/filters/react) filter also supports Preact.

A [Vue](/docs/filters/vue) filter is available, but it has not yet been
upgraded to support Vue3.

# Node.js

A [Node](/docs/filters/node) filter is available, as well as a 
[register](https://www.npmjs.com/package/@ruby2js/register) module.  In most
cases it will be the [CJS](/docs/filters/cjs) filter rather than the
[ESM](/docs/filters/esm) filter that you will want to use.

