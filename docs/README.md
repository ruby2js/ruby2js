# Source of the Ruby2JS Website

The `docs` folder of the monorepo contains the source of the Ruby2JS website at ruby2js.com. It's built with [Bridgetown](https://www.bridgetownrb.com), a Ruby-powered static site generator along with an esbuild frontend build process. The live demo uses [Opal](https://opalrb.com) to run ruby2js entirely in the browser.

To get started, you'll need recent versions of Ruby and Node installed. Then simply run:

```sh
bundle install
yarn install
bundle exec rake   # build demo assets (Opal-compiled ruby2js, etc.)
bin/bridgetown start   # run the site's dev server
```

To deploy the site, simply run `bundle exec rake deploy` and it will generate production output to the `output` folder which can be deployed on any web server.

Currently the ruby2js.com website is hosted by Render.
