# master

# unreleased

* continued demo upgrades ([see here](https://intertwingly.net/projects/ruby2js))
    * dropdowns and checkbox updates are applied immediately
    * more options supported and increased test coverage
    * auto launch a browser when --port is specified
* no need for spread syntax for .max and .min if target is a literal array

# 3.6.0 / 2020-12-26

* New project logos!
* Large overhaul of the Ruby2JS Demo application ([see here](https://intertwingly.net/projects/ruby2js))
* New `active_functions` filter which will provide methods inspired by ActiveSupport
* The `rb2js-loader` package has been merged into the repo, now `webpack-loader`
* `path` and `os` imports added to the `node` filter
* Numeric separator support added for ES2021 (aka `10_000_000`)
* `method_missing` enabled via the `Proxy` object in ES2015+
* `.sum` added to the `functions` filter
* Autoimport configuration is now available when using the `esm` filter
