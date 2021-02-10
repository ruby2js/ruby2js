---
top_section: Stimulus
title: Content Loader
order: 6
---

{% rendercontent "docs/note", type: "warning", extra_margin: true %}
**Warning:** If you are using Firefox, go back to the
[Installation](installation) page and lower the `eslevel` to `2021` or lower
and restart your server before proceeding.
{% endrendercontent %}

# Deeper JavaScript integration

Add the following to your `public/index.html`:

```html
<div data-controller="content-loader"
     data-content-loader-url-value="/messages.txt"
     data-content-loader-refresh-interval-value="5000"></div>
```

Create a new file named `public/messages.txt` with the following contents:

```html
<ol>
  <li>New Message: Stimulus Launch Party</li>
  <li>Overdue: Finish Stimulus 1.0</li>
</ol>
```

Now create a `src/controllers/content_loader_controller.js.rb` file with the following
contents:

```ruby
class ContentLoaderController < Stimulus::Controller
  self.values = { refreshInterval: Number }

  def connect()
    load
    startRefreshing if hasRefreshIntervalValue
  end

  def disconnect()
    stopRefreshing
  end

  def load()
    fetch(urlValue).then {|response|
      response.text()
    }.then {|html|
      element.innerHTML = html
    }
  end

  def startRefreshing()
    @refreshTimer = setInterval(refreshIntervalValue) {load}
  end

  def stopRefreshing()
    clearInterval @refreshTimer if @refreshTimer
  end
end
```

View the results in your browser.  Modify the `messages.html` file and see it
update in your browser within 5 seconds.
View the generated
[content_loader_controller.js](http://localhost:8080/controllers/content_loader_controller.js).

# Commentary

First, lets get a few small things out of the way.  There are two instances of
`if` as a statement modifier in this example.  There also is an instance
variable (`@refreshTimer`).  Both of these work just as you would expect.

Next, there is the `self.values` statement at the top of the class again, but
this time only one of the two values is present.  As the `url` is a `String`
there is no need to add it.  In general, the Ruby2JS Stimulus filter will only
add to -- but never replace -- the definitions you provide.

More interestingly, there are two methods where Ruby blocks are used.  In both
cases, the blocks are converted to anonymous JavaScript functions.  Within 
the `load` action, `then` functions are passed callbacks in the form of
blocks.  In the `startRefresh` action, the `setInterval` function is passed a
callback.  Since the `setInterval` function is a known function, the
`functions` filter knows to insert the block as the first argument rather than
the last.

This is just one way these two actions can be defined.  Let's explore two
alternatives.

# Define an Async action

In JavaScript you can use `async` and `await` to code that deals with
`Promise`s cleaner.  You can do the same with Ruby2JS.  Replace the `load`
action above with the following:

```ruby
  async def load()
    response = await fetch(urlValue)
    html = await response.text()
    element.innerHTML = html
  end
```

View the generated
[content_loader_controller.js](http://localhost:8080/controllers/content_loader_controller.js).
It should be exactly what you would expect to see.

# Automatic binding

The above code calls `setInterval` with a Ruby block as this most closely
matches the code in the
[Stimulus Handbook](https://stimulus.hotwire.dev/handbook/working-with-external-resources#refreshing-automatically-with-a-timer).

But there is a deeper story here.
[SetInterval](https://developer.mozilla.org/en-US/docs/Web/API/WindowOrWorkerGlobalScope/setInterval)
accepts as a first argument a function to be executed, but you can't simply
pass `this.load` as that would be an unbound function meaning that when called
the value of `this` would be wrong.  There are multiple ways around this, one
is to define an anonymous function using the 
[fat arrow](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/Arrow_functions)
syntax.  Another is by calling
[bind](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Function/bind).

These are the *gotchas* that JavaScript programmers learn the hard way and have
learned to deal with every day.  But as it turns out, referencing a method as
a property in an expression within another method in the same class is a
common enough pattern that Ruby2JS handles it automatically.

Try replacing the `startRefreshing` method with the following:

```ruby
  def startRefreshing()
    refreshTimer = setInterval(load, refreshIntervalValue)
  end
```

Look at the generated
[content_loader_controller.js](http://localhost:8080/controllers/content_loader_controller.js).

Note that `load` is referenced twice, once in the `connect` method and the
other in the  `startRefreshing` method, but the code generated in each case is
different.  In one case, it is referenced as a statement, in the other case it
is referenced as an expression.

More on this on the next page.
