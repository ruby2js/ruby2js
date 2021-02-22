---
top_section: React
order: 23
title: A Stateful Component
category: stateful
---

### A Stateful Component

This example focuses on managing state, and making use of
[React component lifecycle methods](https://reactjs.org/docs/react-component.html#the-component-lifecycle).

While it is possible to use `this.state` to reference state and
`this.setState` to update state within React components expressed in Ruby
syntax, the more natural way to express state in Ruby classes is with
instance variables (for example, `@seconds`).

<div data-controller="combo" data-options='{
  "eslevel": 2020,
  "filters": ["react"]
}'></div>

```ruby
class Timer < React
  def initialize
    @seconds = 0
  end

  def tick()
    @seconds += 1
  end

  def componentDidMount()
    self.interval = setInterval(tick, 1000)
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

### Results

<template id="timer-template">
  <div id="timer-example"></div>
</template>

<div data-controller="eval" data-html="#timer-template"></div>

### Commentary

Statement by statement:

 * For convenience, this filter will convert classes that inherit simply from
   `React` as well as `React::Component` to React components. 

 * JavaScript `constructor` becomes Ruby's `initialize`.  Defining
   a `props` argument and calling `super` is optional, and will be done for
   you automatically if necessary (in this example, `props` is not needed).
   Defining initial values is done by instance variable assignment rather than
   explicitly creating a `this.state` object.

 * The `tick` method updates state via an assignment statement rather than
   by calling the `setState` method.

 * The `componentDidMount` lifecycle method will cause the `tick` method to
   be called every 1,000 milliseconds.  Notes:
     * The `tick` method can be passed directly without the need for an
       anonymous function.
     * `self.instance` is a property on the instance that is not a part of
       React's state for the object.

 * The `componentWillUnmount` lifecycle method will cancel the timer.

 * The `render` method display the number of seconds within an HTML `div`
   element.  With React.js, the use of JSX is optional and you can directly
   code calls to `React.createElement`, and this works in Ruby2JS too.

 * The `ReactDOM.render` method also accepts calls to `React.createElement`.

