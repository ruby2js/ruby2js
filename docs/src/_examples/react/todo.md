---
top_section: React
order: 24
title: A Todo Application
category: todo
---

### A Todo Application

<div data-controller="combo" data-options='{
  "eslevel": 2020,
  "filters": ["react", "functions"]
}'></div>

```ruby
class TodoApp < React
  def initialize
    @items = []
    @text = ''
  end

  def render
    _h3 "TODO"
    _TodoList items: @items

    _form onSubmit: handleSubmit do
      _label 'What needs to be done?', for: 'new-todo'
      _input.new_todo! value: @text
      _button "Add ##{@items.length + 1}"
    end
  end

  def handleSubmit(e)
    e.preventDefault()
    return if @text.empty?
    @items = @items.concat(text: @text, id: Date.now())
    @text = ''
  end
end

class TodoList < React
  def render
    _ul @@items do |item|
      _li item.text, key: item.id
    end
  end
end

ReactDOM.render(
  _TodoApp,
  document.getElementById('todos-example')
)
```

### Results

<template id="todos-template">
  <style>input {display: block; width: 100%}</style>
  <div id="todos-example"></div>
</template>

<div data-controller="eval" data-html="#todos-template"></div>

### Commentary

Notable:

 * Again, The `initialize` method does not have to worry about setting up
   `props` or initializing the `this.state` property.  More importantly, it
   does not have to `bind` methods that are called as event handlers.  All of
   this mindless administrivia is taken care of for you, allowing you to focus
   on your application logic, resulting in code that better expresses the
   developer's intent.

 * This `render` method uses a third method to define the HTML result, based
   on the approach the [Wunderbar](https://github.com/rubys/wunderbar#readme)
   gem provides, which in turn was influenced by Jim Weirich's
   [Builder](https://github.com/jimweirich/builder#readme) as well as
   [Markaby](https://github.com/markaby/markaby#readme).  It differs from
   those libraries in the tags are prefixed by an *underbar* character,
   enabling tags to be unambiguously intermixed with control structures and
   other statements with a minimum of visual clutter.

     * The outermost `div` element is not needed and omitted.  It is only
       required in the JavaScript implementation of this method as the JSX
       used in the `render` method can only return one value.  The
       **react** filter will automatically detect such cases and wrap
       the set of elements in a
       [React.fragment](https://react.dev/reference/react/Fragment).

     * HTML elements (like, `h3`) are expressed in lowercase and invoking
       other React components (like `TodoList`) is expressed in uppercase.

     * If the element name is followed by a `.`, the next token is taken as a
       `id` value if it is followed by an exclamation point, otherwise it is
       treated as a class name.  This syntax was popularized by
       [Markaby](https://github.com/markaby/markaby#readme).  Underscores in
       these names are converted to dashes.  This is entirely optional, you can
       explicity code `id` and `class` attributes yourself.

     * Arguments that are Strings become the element's textContent, hashes
       that are passed as the last argument become the element's attributes,
       and blocks are used to express nesting.

   Taken together, the result is often much more compact and easier to read
   without all the angle brackets and curly braces.  It also involves a lot
   less mental context switches to read as it is all Ruby.

 * In this example, there is no need to code a `handleChange` method at all,
   nor to bind it.  The reason for this is the in React, `input` elements are
   required to include an `onChange` handler, so if one is not provided, the
   Ruby2JS **react** filter will provide one for you.  Again, this is in the
   spirit of there being less boiler plate and allowing you to focus on the
   application logic.

 * The `handleSubmit` method remains as it contains true application logic.

     * Calling this method is done with `handleSubmit`, prefixing it with
       either `this.` or `self.` is entirely optional.

     * Calling JavaScript/DOM functions is done exactly as one would expect:
       `e.preventDefault()`.

     * Testing for an empty string is done via the more direct `@text.empty?`
       rather than the more cumbersome `this.state.text.length === 0`.  The
       [functions](functions) filter assists with this conversion.

     * As before, updating state is done via assignment statements to instance
       variables.

 * Moving on to the `TodoList` component, the call to `_ul` takes advantage
   of the ability of blocks to not only express containment, but also to
   iterate over a list.  This is done by passing an argument to the block.

   `@@items` is the way the `TodoList` component references
   `this.props.items`.  This is not a direct mapping to Ruby semantics, but
   can be a convenient shorthand.  If, for whatever reason, you don't approve,
   the longer version is still available to you.

 * In the `ReactDOM.render` call, the element to be rendered is expressed
   using wunderbar syntax.
