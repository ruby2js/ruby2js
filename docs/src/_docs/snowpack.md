---
order: 4
title: Snowpack Setup
top_section: Introduction
category: snowpack
---

{% rendercontent "docs/note", type: "warning", extra_margin: true %}
**Note:** This plugin is currently in beta, and has not yet been pushed to npm.
It will be shortly, once the beta testing is completed.
{% endrendercontent %}

The [`@ruby2js/snowpack-plugin`](https://github.com/ruby2js/ruby2js/tree/master/packages/snowpack-plugin)
lets you compile `.rb.js` files to JavaScript via Snowpack.

This guide takes you through the process of creating a Snowpack project using
the Ruby2JS plugin.  It is based on the [Snowpack plugin
guide](https://www.snowpack.dev/guides/plugins).

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

In the near future, the plugin will be pushed to npm.  For now, copy the
[`@ruby2js/snowpack-plugin`](https://github.com/ruby2js/ruby2js/blob/master/packages/snowpack-plugin/src/index.js)
plugin into your `my-first-snowpack` directory and name the file
`ruby2js-snowpack-plugin.js`.

Configure the plugin by placing the following into `snowpack.config.json`:

```json
{
  "plugins": [
    ["./ruby2js-snowpack-plugin.js", {
      "eslevel": 2020,
      "autoexports": true,
      "filters": ["camelCase", "functions", "esm"]
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
def helloWorld
  puts "Hello Ruby World!"
end
```

Check your console on your Snowpack site. You should see “Hello Ruby World!”
Try making a change to the module. 
