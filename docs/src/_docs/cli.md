---
order: 7
top_section: Introduction
category: CLI
---

## Command Line Interface (CLI)

Installing the `ruby2js` gem adds a `ruby2js` executable to your path.
Invoking this executable with the `--help` option provides a list of options:

```
Usage: ruby2js [options] [file]
        --autoexports [default]      add export statements for top level constants
        --autoimports=mappings       automatic import mappings, without quotes
        --defs=mappings              class and module definitions
        --equality                   double equal comparison operators
        --es2015                     ECMAScript level es2015
        --es2016                     ECMAScript level es2016
        --es2017                     ECMAScript level es2017
        --es2018                     ECMAScript level es2018
        --es2019                     ECMAScript level es2019
        --es2020                     ECMAScript level es2020
        --es2021                     ECMAScript level es2021
        --es2022                     ECMAScript level es2022
        --exclude METHOD,...         exclude METHOD(s) from filters
    -f, --filter NAME,...            process using NAME filter(s)
        --identity                   triple equal comparison operators
        --import_from_skypack        use Skypack for internal functions import statements
        --include METHOD,...         have filters process METHOD(s)
        --include-all                have filters include all methods
        --include-only METHOD,...    have filters only process METHOD(s)
        --ivars @name:value,...      set ivars
        --logical                    use '||' for 'or' operators
        --nullish                    use '??' for 'or' operators
        --truthy MODE                truthy semantics: 'ruby' or 'js'
        --require_recursive          import all symbols defined by processing the require recursively
        --strict                     strict mode
        --template_literal_tags tag,...
                                     process TAGS as template literals
        --underscored_private        prefix private properties with an underscore

        --port n                     start a webserver
        --install path               install as a CGI program
```

If no file is specified, input will be read from STDIN.

A full description of the options can be found on the [Options](options) page
of the documentation.

Installing the [wunderbar](https://rubygems.org/gems/wunderbar) gem is
required if you want to make use of the `--port` or `--install` options.
