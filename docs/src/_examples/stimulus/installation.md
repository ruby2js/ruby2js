---
top_section: Stimulus
title: Installation
order: 12
category: installation
---

# Prerequisites

Before you get started, make sure that you have:
  * Read and tried out the 
    [Stimulus Handbook](https://stimulus.hotwire.dev/handbook/introduction)
    The following pages do not attempt to describe Stimulus concepts, but
    instead focus on how to write Stimulus controllers using a familiar
    Ruby syntax.
  * Ruby and bundler installed.

{% rendercontent "docs/note" %}
Feeling impatient and wanting a quick start?  Feel free to jump to the
[Hello World](hello-world) step.  Don't worry, you can always come back here
afterwards when you want to dive in deeper.
{% endrendercontent %}

# Installation

The process here is pretty much the same as the one described in the Stimulus
handbook, with the addition of a `bundle install` step:

```shell
$ git clone https://github.com/ruby2js/stimulus-starter.git
$ cd stimulus-starter
$ bundle install
$ yarn install
$ yarn start
```

If you are using Google Chrome, Mozilla Firefox, or Microsoft Edge, you should
see a browser window with the words **It works!** displayed.  If you are using
Apple Safari or another browser, you may need to tweak the configuration, see
below.

{% rendercontent "docs/note" %}
Once again, if you are looking for a quick start, feel free to jump to
[Hello World](hello-world) at this point.  Just make sure that **It works!**
is displayed in your browser before you proceed.
{% endrendercontent %}

# Configuration

This starter kit uses [Snowpack](https://www.snowpack.dev/), which is
configured using `snowpack.config.js`:

```javascript
module.exports = {
  mount: {
    public: {url: "/", static: true, resolve: false},
    src: "/"
  },

  plugins: [
    ["@rubys/snowpack-plugin-require-context", {
      input: ['application.js']
    }],

    ["@ruby2js/snowpack-plugin", {
      eslevel: 2022,
      autoexports: "default",
      filters: ["stimulus", "esm", "functions"]
    }]
  ]
}
```

We mount two directories.  `public` which contains static resources and `src`
which contains our logic.

We are also making use of two plugins.  The first is
[require-context](https://github.com/rubys/snowpack-plugin-require-context/)
which rebuilds
[`application.js`](https://github.com/ruby2js/stimulus-starter/blob/main/application.js#L5)
whenever files in the directory it specifies changes.  You can see the
generated application by visiting `http://localhost:8080/application.js` in
your browser.

The second plugin is the one that adds Ruby2JS support to Snowpack.  A
description of the available configuration options can be found on the 
[Ruby2JS site](https://www.ruby2js.com/docs/snowpack#installing-the-ruby2js-plugin).

The option that is of most interest here is the `eslevel` option.  It is
currently set to 2022, meaning that it enables some JavaScript features which
are not yet standardized and/or widely deployed.  This explains why this code
doesn't yet work on Safari.  Feel free to change this value to 2021 (or lower)
and restart the server by pressing control-C and then executing `yarn start`
again.

The only downside to using a lower `eslevel` is that the code generated to run
in the browser might be slightly more verbose and/or slightly less elegant,
but rest assured that it still will work.

# Technical Background

The [Hotwired Stimulus Starter kit](https://github.com/hotwired/stimulus-starter) 
is based on [Babel](https://babeljs.io/) and
[Webpack](https://webpack.js.org/).  It uses Babel to convert a (slightly
future) version of JavaScript to a (possibly backlevel) version of JavaScript
that will be understood by your browser.  This is configured via a
[plugin](https://github.com/hotwired/stimulus-starter/blob/7721a76cd89d21102de3d6ebbd5a58b77ac7c301/.babelrc#L6).

The [Ruby2JS Stimulus Starter kit](https://github.com/ruby2js/stimulus-starter)
is based on [Ruby2JS](https://www.ruby2js.com/) and
[Snowpack](https://www.snowpack.dev/).  Ruby2JS fulfils the role that Babel
plays in the Hotwired Stimulus Starter in that it converts a modern Ruby
syntax to a (possibly backlevel) version of Javascript that will be understood
by your browser.  

The generated JavaScript is functionally equivalent to the JavaScript that
you would hand generate to perform the same function.  This means that the
generated production bundle will be just as small as if you had coded the
JavaScript yourself, and will be fully compatible with other JavaScript
classes you may have.  In other words, you can freely mix and match
Ruby and JavaScript components in the same application.

For this reason, there is no lock-in.  You can start in Ruby and if you should
ever decide to convert a class to JavaScript, feel free to check in the
generated code as a starting point and evolve it from there.

With this starter kit, Snowpack is used instead of Webpack as it will serve up
individual files unbundled, making viewing the generated source practical.

See for yourself.  Compare
[example_controller.js](http://localhost:8080/controllers/example_controller.js)
with
[example_controller.js.rb](https://github.com/ruby2js/stimulus-starter/blob/main/src/controllers/example_controller.js.rb#L1).

Make a change.  See it deployed in milliseconds.


