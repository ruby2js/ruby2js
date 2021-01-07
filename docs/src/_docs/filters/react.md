---
order: 21
title: React
top_section: Filters
category: react
---

The **React** filter enables you to build [React](https://reactjs.org/) components.

The examples below are based on the examples from the
[React](https://reactjs.org/) website.  For best results:

 * Bring up the [React](https://reactjs.org/) website and this page side by
   side.  Compare the JavaScript and Ruby sources for each example.

 * Download and run the
   [demo](https://github.com/ruby2js/ruby2js/tree/master/demo/reactjs.org#readme).
   Feel free to make changes and see the results live.

 * View source on the demo pages that you are serving locally.  Go back to
   [React](https://reactjs.org/) and uncheck the _JSX?_ checkbox in the top
   right of the corresponding example.  Compare the sources

## Examples

As you go through these examples, you will see that there are multiple ways
to do this (for example, three ways to express HTML, two ways to access
state).  This enables you to chose to adopt a more JavaScript/JSX style or
a more Ruby/Markaby/builder style.  Feel free to mix and match the various
approaches, even within the scope of a single method.

### A Simple Component

The first example focuses on the `render` method and the `JSX` syntax which
is popular among React developers, and along the way accesses input data via
`props`.

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

### A Stateful Component

This example focuses on managing state, and making use of
[React component lifecycle methods](https://reactjs.org/docs/react-component.html#the-component-lifecycle).

While it is possible to use `this.state` to reference state and
`this.setState` to update state within React components expressed in Ruby
syntax, the more natural way to express state in Ruby classes is with
instance variables (for example, `@seconds`).

```ruby
class Timer < React
  def initialize
    @seconds = 0
  end

  def tick()
    @seconds += 1
  end

  def componentDidMount()
    self.interval = setInterval(1000) {tick()}
  end

  def componentWillUnmount()
    clearInterval(self.interval)
  end

  def render
    React.createElement 'div', nil, 'Seconds: ', @seconds
  end
end

ReactDOM.render(
  React.createElement(Timer, nil),
  document.getElementById('timer-example')
)
```

Statement by statement:

 * For convenience, this filter will convert classes that inherit simply from
   `React` as well as `React::Component` to React components. 

 * JavaScript `constructor` becomes Ruby's `initialize`.  Calling defining
   a `props` argument and calling `super` is optional, and will be done for
   you automatically if necessary (in this example, `props` is not needed).
   Defining initial values is done by instance variable assignment rather than
   explicitly creating a `this.state` object.

 * The `tick` method updates state via an assignment statement rather than
   by calling the `setState` method.

 * The `componentDidMount` lifecycle method will cause the `tick` method to
   be called every 1,000 milliseconds.

 * The `componentWillUnmount` lifecycle method will cancel the timer.

 * The `render` method display the number of seconds within an HTML `div`
   element.  With React.js, the use of JSX is optional and you can directly
   code calls to `React.createElement`, and this works in Ruby2JS too.

 * The `ReactDOM.render` method also accepts calls to `React.createElement`.

### A Todo Application

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

Notable:

 * The `initialize` method does not have to worry about setting up `props` or
   initializing the `this.state` property.  More importantly, it does not have
   to `bind` methods that are called as event handlers.  All of this mindless
   administrivia is taken care of for you, allowing you to focus on your
   application logic, resulting in code that better expresses the developer's
   intent.

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
       [React.fragment](https://reactjs.org/docs/fragments.html).

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
   less context switches to read as it is all Ruby.

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

### A Markdown editor

This example highlights invoking third party components, and *dangerously*
setting HTML from the results.

```ruby
class MarkdownEditor < React
  def initialize
    self.md = Remarkable.new
    @value = 'Hello, **world**!'
  end

  def handleChange(e)
    @value = e.target.value
  end

  def getRawMarkup
    {__html: self.md.render(@value)}
  end

  def render
    _h3 "Input"
    _label 'Enter some markdown', for: 'markdown-content'
    _textarea.markdown_content! onChange: handleChange,
      defaultValue: @value

    _h3 "Output"
    _div.content dangerouslySetInnerHTML: getRawMarkup
  end
end

ReactDOM.render(
  _MarkdownEditor,
  document.getElementById('markdown-example')
);
```

There is not a whole lot new in this example:

 * setting an adhoc property on a React component is done via `self.name=`
   assignments and referenced using `self.name`.

 * Creating an instance of a third party component is done by calling the
   `.new` operator.  As an aside, with Ruby2js, this can also be done using
   the JavaScript syntax of `new Remarkable()`.

 * In this case, a `handleChange` method is provided and referenced as an
   `onChange` handler.  This is necessary as a `onChange` handler is only
   necessary and therefore automatically provided by the **react** filter when
   a `value` attribute is provided on a `textarea`, not when a `defaultValue`
   is provided.  See the React document for
   [Uncontrolled Components](https://reactjs.org/docs/uncontrolled-components.html)
   for more details.

 * `getRawMarkup` returns a Ruby hash/JavaScript object, and is invoked via
   `getRawMarkup` (i.e., no `this.` nor `()`).


{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/react_spec.rb).
{% endrendercontent %}
