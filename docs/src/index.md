---
layout: home
exclude_from_search: true
---

## Ruby2JS is an extensible Ruby to modern JavaScript transpiler you can use in production today.
{:.has-text-centered .mx-auto .mb-10 .title}
{:style="max-width: 40rem"}

<button-group class="buttons is-centered mb-10">
  <a href="/docs" class="button is-info is-large has-mixed-case">Get Started</a>
  <a href="/demo?preset=true" class="button is-warning is-large has-mixed-case">Try It Online!</a>
</button-group>

**Ruby2JS** is for Ruby developers who want to produce JavaScript that looks hand-crafted, rather than machine generated. You can convert Ruby-like syntax and semantics as cleanly and “natively” as possible. This means that (most of the time) you’ll get a line-by-line, 1:1 correlation between your source code and the JS output.

For example:

<div data-controller="ruby" data-options='{
  "preset": true,
  "filters": ["camelCase"]
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

Filters may be provided to add Ruby-specific or framework specific behavior. Filters are essentially macro facilities that operate on an AST (Abstract Syntax Tree) representation of the code. A `preset` option lets you load the most common filters and a recent ES level for broad code compatibility between Ruby2JS projects.

A note about this site: many of the examples are interactive.  If you change
the Ruby code above, the JavaScript code below it will be updated to match.
If you open your browser's JavaScript console, you can see the results of
executing this script. And you can [try writing your own Ruby2JS code](/demo?preset=true) and see how it converts!

<button-group class="buttons is-centered mt-12 mb-4">
  <a href="/docs" class="button is-info is-large has-mixed-case">Install Now</a>
  <a href="/docs/community/" class="button is-warning is-large has-mixed-case">Need Help?</a>
</button-group>
