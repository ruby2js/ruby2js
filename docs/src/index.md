---
# Feel free to add content and custom Front Matter to this file.

layout: home
---

## Ruby2JS is an extensible Ruby to modern JavaScript transpiler you can use in production today.
{:.has-text-centered .mx-auto .mb-10 .title}
{:style="max-width: 40rem"}

<button-group class="buttons is-centered mb-10">
  <a href="/docs" class="button is-info is-large has-mixed-case">Get Started</a>
  <a href="https://intertwingly.net/projects/ruby2js.cgi" class="button is-warning is-large has-mixed-case" target="_blank">Try It Online!</a>
</button-group>

**Ruby2JS** is for Ruby developers who want to produce JavaScript that looks hand-crafted, rather than machine generated. You can convert Ruby-like syntax and semantics as cleanly and “natively” as possible. This means that (most of the time) you’ll get a line-by-line, 1:1 correlation between your source code and the JS output.

For example:

```ruby
class MyClass
  def my_method(str)
    ret = "Nice #{str} you got there!"
    ret.upcase()
  end
end
```

will get converted to:

```js
class MyClass {
  myMethod(str) {
    let ret = `Nice ${str} you got there!`;
    return ret.toUpperCase()
  }
}
```

Filters may be provided to add Ruby-specific or framework specific behavior. Filters are essentially macro facilities that operate on an AST (Abstract Syntax Tree) representation of the code.

Ruby2JS can be used to write backend code for execution by Node, or for the frontend in a variety of configurations [including Webpack](/docs/webpack). Our installation guide will help you get set up in no time.

<button-group class="buttons is-centered mt-12 mb-4">
  <a href="/docs" class="button is-info is-large has-mixed-case">Install Now</a>
  <a href="/docs/community/" class="button is-warning is-large has-mixed-case">Need Help?</a>
</button-group>
