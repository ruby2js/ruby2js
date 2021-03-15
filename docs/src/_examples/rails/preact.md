---
top_section: Rails
order: 36
title: Preact
category: preact
---

With a few small changes, the [React demo](./react) can be adapted to use
[Preact](https://preactjs.com/) instead

## Create a Project

Start a new project:

```
rails new ruby2js-preact
cd ruby2js-preact
```

Add the following line to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:preact
```

## Write some HTML and a matching Preact Component

Generate a Rails controller:

```
./bin/rails generate controller Demo run
```

Create `app/javascript/packs/timer.js.rb` with the following
contents:

<div data-controller="combo" data-options='{
  "eslevel": 2021,
  "filters": ["esm", "react", "functions"]
}'></div>

```ruby
class Timer < Preact
  def initialize
    @seconds = 0
  end

  def tick()
    @seconds += 1
  end

  def componentDidMount()
    self.interval = setInterval(tick, 1_000)
  end

  def componentWillUnmount()
    clearInterval(self.interval)
  end

  def render
    h 'div', nil, 'Seconds: ', @seconds
  end
end

Preact.render(
  h(Timer),
  document.getElementById('timer-example')
)
```

Add the following to `app/views/demo/run.html.erb`:

```erb
<div id="timer-example"></div>

<%= javascript_pack_tag 'timer' %>
```

## Try it out!

Start your server:

```
./bin/rails server
```

Visit <http://localhost:3000/demo/run>.  What you should see:

<p data-controller="eval" data-html="div.language-erb"></p>
