---
top_section: Rails
order: 31
title: Stimulus Sprockets
category: stimulus sprockets
---

Start a new project:

```
rails new stimulus-sprockets
cd stimulus-sprockets
```

## Install Stimulus support

Add the [stimulus-rails](https://github.com/hotwired/stimulus-rails) gem to your `Gemfile`:

```ruby
gem 'stimulus-rails'
```

Run `./bin/bundle install`

Run `./bin/rails stimulus:install:asset_pipeline`

## Add and configure Ruby2JS

Add the ruby2js gem to your `Gemfile`:

```ruby
gem 'ruby2js', require: 'ruby2js/sprockets'
```

Run `./bin/bundle install`

Add a file named `config/initializers/ruby2js.rb`:

```ruby
require 'ruby2js/filter/esm'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/stimulus'

Ruby2JS::SprocketsTransformer.options = {
  autoexports: :default,
  eslevel: 2020
}

require 'stimulus/importmap_helper'

module Stimulus::ImportmapHelper
  def find_javascript_files_in_tree(path)
     exts = {'.js' => '.js', '.jsm' => '.jsm'}.merge(
       Sprockets.mime_exts.map {|key, value|
         next unless Sprockets.transformers[value]["application/javascript"]
         [key, '.js']
       }.compact.to_h)

     Dir[path.join('**/*')].map {|file|
       file_ext, web_ext = Sprockets::PathUtils.match_path_extname(file, exts)
       next unless file_ext

       next unless File.file? file

       Pathname.new(file.chomp(file_ext) + web_ext)
     }.compact
  end
end
```

{% rendercontent "docs/note", type: "warning", extra_margin: true %}
**Note**: the `find_javascript_files_in_tree` method above is a (hopefully
temporary) monkey patch to make stimulus_rails aware of sprocket
transformations that produce JavaScript.
See [stimulus-rails issue #54](https://github.com/hotwired/stimulus-rails/issues/54) for status.
{% endrendercontent %}

## Write some HTML and a matching Stimulus controller

Generate a Rails controller:

```
./bin/rails generate controller Greeter hello
```

Add the following to `app/views/greeter/hello.html.erb`:

```html
<div data-controller="hello">
  <input data-hello-target="name" type="text">

  <button data-action="click->hello#greet">
    Greet
  </button>

  <span data-hello-target="output">
  </span>
</div>
```

Remove `app/assets/javascript/controllers/hello_controller.js`, and create
`app/assets/javascript/controllers/hello_controller.js.rb` with the following
contents:

<div data-controller="ruby" data-options='{
  "eslevel": 2020,
  "autoexports": "default",
  "filters": ["esm", "stimulus", "functions"]
}'></div>

```ruby
class HelloController < Stimulus::Controller
  def greet()
    outputTarget.textContent =
      "Hello, #{nameTarget.value} from Ruby!"
  end
end
```

## Try it out!

Start your server:

```
./bin/rails server
```

Visit <http://localhost:3000/greeter/hello>.  What you should see:

<p data-controller="eval" data-html="div.language-html"></p>

Browse <http://localhost:3000/assets/controllers/hello_controller.js>.  This
should match the following:

<div data-controller="js"></div>

Make a change to `app/assets/javascript/controllers/hello_controller.js.rb`
and see the results.

{% rendercontent "docs/note" %}
**Note**: The assignment to `HelloController.targets` at the bottom of the
above differs from most Stimulus examples you may have seen.  This is due to
[Static Public Fields](https://github.com/tc39/proposal-static-class-features#static-public-fields)
being only a stage 3 proposal right now and
[not yet supported](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Classes/static#browser_compatibility)
on all major browsers.  If your browser supports it, feel free to change
`2020` to `2022` in `config/initializers/ruby2js.rb` and restart your rails
server.
{% endrendercontent %}
