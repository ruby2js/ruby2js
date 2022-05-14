---
order: 1
title: Getting Started
top_section: Introduction
category: intro
---

Add the `ruby2js` gem to your Gemfile:

```sh
bundle add ruby2js
```

or manually install the `ruby2js` gem:

```sh
gem install ruby2js
```

If you'd like to use Ruby2JS with Node-based build tools, [read these additional instructions](/docs/integrations).

## Basic Usage
{:.mb-8}

Simple:

```ruby
require 'ruby2js'
puts Ruby2JS.convert("a={age:3}\na.age+=1")
```

With filter:

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert('"2A".to_i(16)')
```

Host variable substitution:

```ruby
 puts Ruby2JS.convert("@name", ivars: {:@name => "Joe"})
```

Enable ES2015 support:

```ruby
puts Ruby2JS.convert('"#{a}"', eslevel: 2015)
```

{% rendercontent "docs/note" %}
[Read more information](/docs/eslevels) on how ES level options affect the JS output.
{% endrendercontent %}

Enable strict support:

```ruby
puts Ruby2JS.convert('a=1', strict: true)
```

Emit strict equality comparisons:

```ruby
puts Ruby2JS.convert('a==1', comparison: :identity)
```

Emit nullish coalescing operators:

```ruby
puts Ruby2JS.convert('a || 1', or: :nullish)
```

Emit underscored private fields (allowing subclass access):

```ruby
puts Ruby2JS.convert('class C; def initialize; @f=1; end; end',
  eslevel: 2020, underscored_private: true)
```

With [ExecJS](https://github.com/sstephenson/execjs):
```ruby
require 'ruby2js/execjs'
require 'date'

context = Ruby2JS.compile(Date.today.strftime('d = new Date(%Y, %-m-1, %-d)'))
puts context.eval('d.getYear()')+1900
```

{% rendercontent "docs/note", extra_margin: true %}
Conversions can be explored interactively using the
[demo](/docs/running-the-demo) provided. (**[Online Version](/demo)**)
{% endrendercontent %}

## Create a Configuration

There are a number of [configuration options](/docs/options) available for both the converter itself as well as any filters you choose to add.

If you find yourself needing a centralized location to specify these options for your project, create an `rb2js.config.rb` file in your project root. Example:

```ruby
require "ruby2js/filter/functions"
require "ruby2js/filter/camelCase"
require "ruby2js/filter/return"
require "ruby2js/filter/esm"
require "ruby2js/filter/tagged_templates"

require "json"

module Ruby2JS
  class Loader
    def self.options
      # Change the options for your configuration here:
      {
        eslevel: 2021,
        include: :class,
        underscored_private: true
      }
    end

    def self.process(source)
      Ruby2JS.convert(source, self.options).to_s
    end

    def self.process_with_source_map(source)
      conv = Ruby2JS.convert(source, self.options)
      {
        code: conv.to_s,
        sourceMap: conv.sourcemap
      }.to_json
    end
  end
end
```

Then you can simply require this file from inside your project.

```ruby
# some_other_script.rb

require_relative "./rb2js.config"

ruby_code = <<~RUBY
  export toggle_menu_icon = ->(button) do
    button.query_selector_all(".icon").each do |item|
      item.class_list.toggle "not-shown"
    end
    button.query_selector(".icon:not(.not-shown)").class_list.add("shown")
  end
RUBY

js_code = Ruby2JS::Loader.process(ruby_code)
```
