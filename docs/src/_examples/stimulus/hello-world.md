---
top_section: Stimulus
title: Hello World
order: 3
---

# Diving in

Since you are already familiar with Stimulus, lets dive right in.  Add the
following to your `public/index.html` file.

```html
<div data-controller="hello">
  <input data-hello-target="name" type="text">
  <button data-action="click->hello#greet">Greet</button>
</div>
```

Now create a `src/controllers/hello_controller.js.rb` file with the following
contents:

```ruby
class HelloController < Stimulus::Controller
  def connect()
    puts "Hello, Stimulus!", element
  end

  def greet()
    puts "Hello, #{name}!"
  end

  def name
    nameTarget.value
  end
end
```

View the results in your browser.  Modify the source and see the browser
update.  View the generated
[hello_controller.js](http://localhost:8080/controllers/hello_controller.js).

# Commentary

Despite being written in Ruby, the code is instantly recognizable by people
familiar with Stimulus.  This code defines a Stimulus lifecycle method, an
action method, and what Ruby calls an attribute accessor and JavaScript calls
a property getter.  All of which is converted to the equivalent JavaScript.

The reference to the `name` target is detected and the `static targets` array
is added to the generated code.

Also, this code uses `puts`, which convieniently is mapped to JavaScript's
`console.log`.
