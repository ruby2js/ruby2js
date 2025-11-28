Ruby2JS
=======

Minimal yet extensible Ruby to JavaScript conversion.  

[![Gem Version](https://badge.fury.io/rb/ruby2js.svg)](https://badge.fury.io/rb/ruby2js)

## Documentation
---

* Visit **[ruby2js.com](https://www.ruby2js.com)** for detailed setup instructions and API reference.

* [Try Ruby2JS online](https://ruby2js.com/demo?preset=true)


## Synopsis


Basic:

```ruby
require 'ruby2js'
puts Ruby2JS.convert("a={age:3}\na.age+=1", preset: true)
```

## Contributing

### Running Tests

1. Run `bundle install`
2. Run `bundle exec rake test_all`

### Running the Website Locally

The [ruby2js.com](https://www.ruby2js.com) website (including the live demo) can be run locally from the `docs` folder:

```sh
cd docs
bundle install
yarn install
bundle exec rake            # build demo assets (Opal-compiled ruby2js, etc.)
bin/bridgetown start        # run the site's dev server
```

The site will be available at `http://localhost:4000`. The live demo uses [Opal](https://opalrb.com) to run ruby2js entirely in the browser.

## Release Process for Maintainers

1. Update the version in both `packages/ruby2js/package.json` and `lib/ruby2js/version`, ensuring they match.
2. Run `bundle exec rake release_core`

## License

(The MIT License)

Copyright (c) 2009, 2020 Macario Ortega, Sam Ruby, Jared White

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
