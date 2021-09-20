---
order: 5
title: Integrations
top_section: Introduction
category: integrations
---

# Ruby back-ends servers

* [Rails](../examples/rails/) integration is provided
   for both WebPacker and Sprockets.  Rake tasks are provided to assist with
   the configuration.

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

Plugins are available for both
[Snowpack](https://www.npmjs.com/package/@ruby2js/snowpack-plugin) and
[Vite](https://www.npmjs.com/package/@ruby2js/vite-plugin).  These plugins
support Hot Module Replacement and Refresh.  The [ESM](/docs/filters/esm)
filter lets you author `import` and `export` statements, and the
[autoexports](/docs/options#auto-exports) and
[autoimports](/docs/options#auto-imports) options can often relieve you of the
need to do so.

# JavaScript bundlers

A [Rollup](https://www.npmjs.com/package/@ruby2js/rollup-plugin) plugin and
a [Webpack](https://www.npmjs.com/package/@ruby2js/webpack-loader) loader are
available.  Again, the [ESM](/docs/filters/esm)
filter and [autoexports](/docs/options#auto-exports) and
[autoimports](/docs/options#auto-imports) options are useful with bundlers.

# Web Components

Filters are available for [jQuery](/docs/filters/jquery), [litElement](/docs/filters/litelement),
[React](/docs/filters/react), and [Stimulus](/docs/filters/stimulus).  The
[React](/docs/filters/react) filter also supports Preact.

A [Vue](/docs/filters/vue) filter is available, but it has not yet been
upgraded to support Vue3.

# Node.js

A [Node](/docs/filters/node) filter is available, as well as a 
[register](https://www.npmjs.com/package/@ruby2js/register) module.  In most
cases it will be the [CJS](/docs/filters/cjs) filter rather than the
[ESM](/docs/filters/esm) filter that you will want to use.

