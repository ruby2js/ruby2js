---
order: 4
title: Snowpack Setup
top_section: Introduction
category: snowpack
---

The [`@ruby2js/snowpack-plugin`](https://github.com/ruby2js/ruby2js/tree/master/packages/snowpack-plugin)
lets you compile `.rb.js` files to JavaScript via Snowpack.

Prerequisites needed to run this code:

  * Node.js
  * Ruby installed and available in your PATH as `ruby`
  * Both ruby2js and rack, either installed as gems or in your RUBYLIB path


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
    ["./ruby2js-snowpack-plugin.js", {
      eslevel: 2020,
      autoexports: true,
      filters: ["camelCase", "functions", "esm"]
    }]
  ]
}
```

Note that [Ruby2JS options](options) are expressed in JSON format instead of
as a Ruby Hash.  The following rules will help explain the conversions
necessary:

  * use strings for symbols
  * for `functions`, specify string names not module names
  * for `autoimports`, specify keys as strings, even if key is an array
  * not supported: `binding`, `ivars`, `scope`

An example of all of the supported options:

```json
{
  "autoexports": true,
  "autoimports": {"[:LitElement]": "lit-element"},
  "comparison": "identity",
  "defs": {"A": ["x", "@y"]},
  "eslevel": 2021,
  "exclude": ["each"],
  "filters": "functions",
  "include": ["class"],
  "include_all": true,
  "include_only": ["max"],
  "import_from_skypack": true,
  "or": "nullish",
  "require_recurse": true,
  "strict": true,
  "template_literal_tags": ["color"],
  "underscored_private": true,
  "width": 40
}
```

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
