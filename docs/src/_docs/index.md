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

With our recommended "preset" configuration:

```ruby
puts Ruby2JS.convert("a={age:3}\na.age+=1", preset: true)
```

With just the functions filter:

```ruby
puts Ruby2JS.convert('"2A".to_i(16)', filters: [:functions])
```

Host variable substitution:

```ruby
 puts Ruby2JS.convert("@name", ivars: {:@name => "Joe"})
```

Enable ES2021 support (default with the preset configuration):

```ruby
puts Ruby2JS.convert('"#{a}"', eslevel: 2020)
```

{% rendercontent "docs/note" %}
[Read more information](/docs/eslevels) on how ES level options affect the JS output.
{% endrendercontent %}

Emit strict equality comparisons (aka `==` becomes `===`):

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

{% rendercontent "docs/note", extra_margin: true %}
Conversions can be explored interactively using the
[demo](/docs/running-the-demo) provided. (**[Try It Online](/demo?preset=true)**)
{% endrendercontent %}

## Next Steps

- **[Options](/docs/options)** - Learn about the "preset" configuration or build your own
- **[User's Guide](/docs/users-guide/introduction)** - Best practices for writing dual-target Ruby/JavaScript code
- **[Filters](/docs/filters/functions)** - Available transformations for your code
- **[Juntos](/docs/juntos/)** - Rails-compatible framework for browsers, servers, and edge
- **[Ruby2JS on Rails](/docs/users-guide/ruby2js-on-rails)** - Quick start guide for Rails apps
