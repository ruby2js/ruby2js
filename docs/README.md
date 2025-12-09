# Source of the Ruby2JS Website

The `docs` folder of the monorepo contains the source of the Ruby2JS website at ruby2js.com. It's built with [Bridgetown](https://www.bridgetownrb.com), a Ruby-powered static site generator along with an esbuild frontend build process.

## Demos

There are two live demos:

1. **Opal Demo** (main demo) - Uses [Opal](https://opalrb.com) to run ruby2js entirely in the browser (~24MB)
2. **Self-Hosted Demo** - Uses the transpiled Ruby2JS converter running in JavaScript (~2.5MB, ~10x smaller)

The self-hosted demo transpiles `lib/ruby2js/converter.rb` and related files to JavaScript using Ruby2JS itself. It passes 90% of the transliteration test suite.

## Getting Started

You'll need recent versions of Ruby and Node installed. Then:

```sh
bundle exec rake install  # install all dependencies (gems, yarn, selfhost npm)
bundle exec rake          # build demo assets (Opal + selfhost)
bin/bridgetown start      # run the site's dev server
```

To deploy the site, simply run `bundle exec rake deploy` and it will generate production output to the `output` folder which can be deployed on any web server.

Currently the ruby2js.com website is hosted by Render.
