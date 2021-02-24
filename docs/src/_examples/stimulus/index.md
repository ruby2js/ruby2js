---
top_section: Stimulus
title: Stimulus Introduction
toc_title: Introduction
order: 11
category: stimulus intro
---


# Example

The front page of the [Stimulus](https://stimulus.hotwire.dev/) web site
contains the following example:

```javascript
// hello_controller.js
import { Controller } from "stimulus"

export default class extends Controller {
  static targets = [ "name", "output" ]

  greet() {
    this.outputTarget.textContent =
      `Hello, ${this.nameTarget.value}!`
  }
}
```

The equivalent code using the Ruby2JS Stimulus filter:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "autoexports": "default",
  "filters": ["esm", "stimulus"]
}'></div>

```ruby
class HelloController < Stimulus::Controller
  def greet()
    outputTarget.textContent =
      "Hello, #{nameTarget.value}!"
  end
end
```

### Results

<template id="stimulus-template">
  <style>
    input {
      padding: 0.5em;
      border: 2px solid #000;
      font-family: "Jost",sans-serif;
    }

    button {
      background-color: #000;
      color: #77e8b9;
      font-family: "Jost",sans-serif;
      padding: 0.5em 1em;
    }
  </style>

  <div data-controller="hello">
    <input data-hello-target="name" type="text" placeholder="enter a name">

    <button data-action="click->hello#greet">
      Greet
    </button>

    <span data-hello-target="output">
    </span>
  </div>
</template>

<div data-controller="eval" data-html="#stimulus-template"></div>

### Commentary

Notably, there are no `imports`, no `exports`, no `static targets`, and no
`this.`.  All you need to do is follow the naming conventions and drop the
file in the right location and everything will JustWork™.

Try it out!  Enter your name and press the **Greet** button.  Now make a
change to the controller - perhaps change the exclamation point to a question
mark.  Press the **Greet** button again.

# Elevator Pitch

The Ruby2JS Stimulus filter is for people who both:
  * Like the features and minimal footprint of Stimulus.js
  * Appreciate the [Ruby on Rails Doctrine](https://rubyonrails.org/doctrine/), particularly:
      * [Optimize for programmer happiness](https://rubyonrails.org/doctrine/#optimize-for-programmer-happiness)
      * [Convention over Configuration](https://rubyonrails.org/doctrine/#convention-over-configuration)

# Technical Background

JavaScript programmers are familiar with the concept of transpilers such as
Babel and CoffeeScript, which take inputs in one language and convert it to
JavaScript.

Ruby programmers are familiar with the concept of Domain Specific Languages
(DSLs) that expresses framework and library concepts using Ruby syntax.

Rails programmers are familiar with conventions over configuration, whereby
where you place logic and how you name things affects how things work.

The Ruby2JS Stimulus filter is a hybrid approach pulling all three together.
You write your code in Ruby, interacting with Stimulus *Targets*, *Values*,
and *Classes*.  This code is transpiled to JavaScript and delivered to the
browser.  As a result, you can seamlessly interact with JavaScript and the
browsers Document Object Model (DOM).

