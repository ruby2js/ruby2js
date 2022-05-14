---
# Feel free to add content and custom Front Matter to this file.

layout: home
---

## Ruby2JS is an extensible Ruby to modern JavaScript transpiler you can use in production today.
{:.has-text-centered .mx-auto .mb-10 .title}
{:style="max-width: 40rem"}

<button-group class="buttons is-centered mb-10">
  <a href="/docs" class="button is-info is-large has-mixed-case">Get Started</a>
  <a href="/demo" class="button is-warning is-large has-mixed-case">Try It Online!</a>
</button-group>

**Ruby2JS** is for Ruby developers who want to produce JavaScript that looks hand-crafted, rather than machine generated. You can convert Ruby-like syntax and semantics as cleanly and “natively” as possible. This means that (most of the time) you’ll get a line-by-line, 1:1 correlation between your source code and the JS output.

For example:

<div data-controller="ruby" data-options='{
  "eslevel": 2020,
  "filters": ["functions", "camelCase", "return"]
}'></div>

```ruby
class MyClass
  # Cowabunga, dude!
  def my_method(str)
    ret = "Nice #{str} you got there!"
    ret.upcase()
  end
end

puts MyClass.new.my_method('pizza')
```

will get converted to:

<div data-controller="js"></div>

```js
class MyClass {
  // Cowabunga, dude!
  myMethod(str) {
    let ret = `Nice ${str} you got there!`;
    return ret.toUpperCase()
  }
}

console.log((new MyClass).myMethod("pizza"))
```

<div data-controller="eval"></div>

Filters may be provided to add Ruby-specific or framework specific behavior. Filters are essentially macro facilities that operate on an AST (Abstract Syntax Tree) representation of the code.

Ruby2JS can be used to write back-end code for execution by
[Node](https://www.npmjs.com/package/@ruby2js/register), or for the front-end in a variety of configurations
including 
[Rails](/examples/rails/),
[esbuild](https://www.npmjs.com/package/@ruby2js/esbuild-plugin),
[Rollup](https://www.npmjs.com/package/@ruby2js/rollup-plugin),
[Snowpack](https://www.npmjs.com/package/@ruby2js/snowpack-plugin),
[Vite](https://www.npmjs.com/package/@ruby2js/vite-plugin), and
[Webpack](https://www.npmjs.com/package/@ruby2js/webpack-loader).
Our examples and installation instructions will help you get set up in no time.

A note about this site: many of the examples are interactive.  If you change
the Ruby code above, the JavaScript code below it will be updated to match.
If you open your browser's JavaScript console, you can see the results of
executing this script.

This example has been pre-configured with [ECMAScript
2020](docs/eslevels#es2020-support) support and the
[functions](docs/filters/functions), [camelCase](docs/filters/camelCase) and
[return](docs/filters/return) filters.  Other examples may be configured
differently.  The [Try It Online!](/demo) button above will take you to a page
where you can select your own configuration.

<button-group class="buttons is-centered mt-12 mb-4">
  <a href="/docs" class="button is-info is-large has-mixed-case">Install Now</a>
  <a href="/docs/community/" class="button is-warning is-large has-mixed-case">Need Help?</a>
</button-group>
