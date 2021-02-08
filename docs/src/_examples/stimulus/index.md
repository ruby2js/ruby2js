---
top_section: Stimulus
title: Introduction
order: 1
---

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

```ruby
class Hellocontroller < Stimulus::Controller
  def greet()
    outputTarget.textContent =
      "Hello, #{nameTarget.value}!"
  end
end
```

Notably, there are no `imports`, no `exports`, no `static targets`, and no
`this.`.  All you need to do is follow the naming conventions and drop the
file in the right location and everything will JustWork™.

In two pages, you will have this and more up and running so you can see for
yourself, but meanwhile if you are curious as to what the generated JavaScript
for this class would look like, copy the code from above and paste it into
the [demo](../../demo/?es2022&filter=stimulus) page.
