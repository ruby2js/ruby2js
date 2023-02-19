---
order: 4
title: Snowpack Setup
top_section: Introduction
category: snowpack
hide_in_toc: true
---

{% rendercontent "docs/note", type: "warning" %}
This package is no longer supported. We recommend that you use esbuild for frontend compilation and bundling.
{% endrendercontent %}

The [`@ruby2js/snowpack-plugin`](https://github.com/ruby2js/ruby2js/tree/master/packages/snowpack-plugin)
lets you compile `.rb.js` files to JavaScript via Snowpack.

For testing, [create a new, example Snowpack project](https://www.snowpack.dev/tutorials/getting-started).
For now, all you need to do is the following steps from that tutorial:

 * Install Snowpack
 * Snowpack’s development server
 * Using JavaScript

## Installing the ruby2js plugin

Install the plugin using npm or yarn:

```
$ npm install @ruby2js/snowpack-plugin
$ yarn add @ruby2js/snowpack-plugin
```

Configure the plugin by placing the following into `snowpack.config.js`:

```js
module.exports = {
  plugins: [
    ["@ruby2js/snowpack-plugin", {
      eslevel: 2020,
      autoexports: true,
      filters: ["camelCase", "functions", "esm"]
    }]
  ]
}
```

See [Ruby2JS Options](https://www.ruby2js.com/docs/options) docs for a list of available options.

Restart the snowpack server to pick up the configuration changes.

## Test the plugin

Delete `hello-world.js`.

Create `hello-world.rb.js` with the following contents:

```
def hello_world
  puts "Hello Ruby World!"
end
```

Check your console on your Snowpack site. You should see “Hello Ruby World!”
Try making a change to the module. 
