---
top_section: React
order: 22
title: A Simple Component
category: simple
---

### A Simple Component

The first example focuses on the `render` method and the `JSX` syntax which
is popular among React developers, and along the way accesses input data via
`props`.

<div data-controller="combo" data-options='{
  "eslevel": 2020,
  "filters": ["react"]
}'></div>

```ruby
class HelloMessage < React::Component
  def render
    %x(
      <div>
        Hello {this.props.name}
      </div>
    )
  end
end

ReactDOM.render(
  %x(<HelloMessage name="Taylor" />),
  document.getElementById('hello-example')
)
```

This example has a near one-to-one correspondence to the JavaScript example on
the ReactJS site, just with less curly braces, more `end` statements, and no
semicolons.

The one notable difference is the `%x()` notation.  Because (X)HTML notation
is not valid Ruby syntax, it needs to be wrapped.

The expression inside the `%x()` notation is JSX-like, but there are notable
differences.  Any expressions inside curly braces evaluated as Ruby using the
same filters and options as the rest of the code, so feel free to substitute
`self` for `this` in the example above.  The elements are executed as
statements rather than evaluated as expressions.  Taken together, that means
that you can code true `if`, `elsif`, 'else', and `end` statements instead of
nesting `?` and `:' operators.  Or use `case` statements.  And proper loops
instead of `map` methods.  All the while not having to worry about limiting
expressions to a single value.
