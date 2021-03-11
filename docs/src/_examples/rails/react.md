---
top_section: Rails
order: 35
title: React
category: react-element
---

This example is based on the [React site](https://reactjs.org/), but based on
Ruby2JS instead and hosted by Ruby on Rails.

## Create a Project

Start a new project:

```
rails new ruby2js-react
cd ruby2js-react
```

Add the following line to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/rails'
```

Run the following commands:

```sh
./bin/bundle install
./bin/rails ruby2js:install:react
```

## Write some HTML and a matching React Component

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
class Timer < React
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
    React.createElement 'div', nil, 'Seconds: ', @seconds
  end
end

ReactDOM.render(
  React.createElement(Timer, nil),
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
