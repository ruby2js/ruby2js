# master

* handle block arguments
* filter now supports `.call`, but requires an explicit `include` option
* require with esm now always produces relative path links
* support added for is_a? kind_of and instance_of?
* provide default for all optional kwargs; handle undefined as default

# 4.0.0 / 2021-02-10

* Support static method calls with blocks in es2015+
* Auto-bind instance methods referenced as properties within a class
* New defs option to add definitions for autoimported classes/methods
* Open classes/modules, inheritance, and module include of props/methods
* Handle begin, if, and case as expressions
* Handle modules with exactly one method
* Handle empty edge cases like `` `#{}` `` and `()`
* Live demo based on Opal ([see here](https://ruby2js.com/demo))
* Demo: Hidden AST syntax enables copy/paste of syntactically correct AST
* Anonymous classes via Class.new
* Autoexport :default option
* Support both default and named imports on same import statement
* requires for modules containing exports statements generate import statements
* require_recursive option

# 3.6.1 / 2020-12-31

* Bugfix: ensure ActiveFunctions autoimports aren't included multiple times
* Chained method bugfix in Nokogiri filter
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
