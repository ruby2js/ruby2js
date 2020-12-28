# Source of the Ruby2JS Website

The `docs` folder of the monorepo contains the source of the Ruby2JS website at ruby2js.com. It's built with [Bridgetown](https://www.bridgetownrb.com), a Ruby-powered static site generator along with a Webpack frontend build process.

To get started, you'll need recent versions of Ruby and Node installed. Then simply run:

```sh
bundle install
yarn install
yarn start # to run the site's dev server
```

To deploy the site, simply run `yarn deploy` and it will generate production output to the `output` folder which can be deployed on any web server.

Currently the ruby2js.com website is hosted by Render.
