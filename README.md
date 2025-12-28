# Ruby2JS

Minimal yet extensible Ruby to JavaScript conversion.

[![Gem Version](https://badge.fury.io/rb/ruby2js.svg)](https://badge.fury.io/rb/ruby2js)
[![CI](https://github.com/ruby2js/ruby2js/actions/workflows/ci.yml/badge.svg)](https://github.com/ruby2js/ruby2js/actions/workflows/ci.yml)

**[Documentation](https://www.ruby2js.com)** | **[Live Demo](https://ruby2js.com/demo?preset=true)**

## Installation

```ruby
# Gemfile
gem 'ruby2js'
```

Or install directly:

```sh
gem install ruby2js
```

## Examples

Ruby2JS converts Ruby syntax to clean, readable JavaScript:

```ruby
# Ruby                              # JavaScript
a = { age: 3 }                      # let a = {age: 3}
a.age += 1                          # a.age++

items.map { |x| x * 2 }             # items.map(x => x * 2)

class Dog < Animal                  # class Dog extends Animal {
  def bark                          #   bark() {
    puts "woof!"                    #     console.log("woof!")
  end                               #   }
end                                 # }
```

## Quick Start

```ruby
require 'ruby2js'

puts Ruby2JS.convert("a = {age: 3}; a.age += 1", preset: true)
# => let a = {age: 3}; a.age++
```

### Command Line

```sh
ruby2js --preset file.rb
echo "puts 'hello'" | ruby2js --preset
```

## Features

- **[Filters](https://www.ruby2js.com/docs/filters)** - Transform Ruby methods to JavaScript equivalents (e.g., `.each` → `.forEach`)
- **[ES Level Support](https://www.ruby2js.com/docs/eslevels)** - Target specific JavaScript versions (ES2020 through ES2025)
- **[Framework Integrations](https://www.ruby2js.com/docs/integrations)** - Rails, Stimulus, React, Lit, and more
- **[Live Demo](https://ruby2js.com/demo?preset=true)** - Try it in your browser (runs entirely client-side via Opal)

## Demos

- **[Opal Demo](https://ruby2js.com/demo?preset=true)** - Full-featured demo using Opal (~5MB)
- **[Selfhost Demo](https://ruby2js.com/demo/selfhost/)** - Lightweight demo using transpiled Ruby2JS (~200KB + Prism WASM)
- **[Ruby2JS-on-Rails](https://ruby2js.com/demo/ruby2js-on-rails/)** - Rails-like blog app running entirely in JavaScript

The selfhost demo runs Ruby2JS transpiled to JavaScript, demonstrating that Ruby2JS can convert itself. The Ruby2JS-on-Rails demo shows a complete Rails-style MVC application with ActiveRecord, controllers, and ERB views running in the browser or on Node.js/Bun/Deno.

## Contributing

### Running Tests

```sh
bundle install
bundle exec rake test_all
```

### Running the Website Locally

The [ruby2js.com](https://www.ruby2js.com) website (including the live demo) can be run locally from the `docs` folder:

```sh
cd docs
bundle install
yarn install
bundle exec rake            # build demo assets (Opal-compiled ruby2js, etc.)
bin/bridgetown start        # run the site's dev server
```

The site will be available at `http://localhost:4000`.

## Release Process for Maintainers

1. Update the version in both `packages/ruby2js/package.json` and `lib/ruby2js/version`, ensuring they match.
2. Run `bundle exec rake release_core`

## License

MIT License - Copyright (c) 2009, 2025 Macario Ortega, Sam Ruby, Jared White

See [LICENSE](LICENSE) for details.
