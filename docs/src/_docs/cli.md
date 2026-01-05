---
order: 140
title: CLI
top_section: Introduction
category: CLI
---

## Command Line Interface (CLI)

Installing the `ruby2js` gem adds a `ruby2js` executable to your path.
Invoking this executable with the `--help` option provides a list of options:

```
Usage: ruby2js [options] [file]
        --preset                     use sane defaults (modern eslevel & common filters)
    -C, --config [FILE]              configuration file to use (default is config/ruby2js.rb)
        --autoexports [default]      add export statements for top level constants
        --autoimports=mappings       automatic import mappings, without quotes
        --defs=mappings              class and module definitions
        --equality                   double equal comparison operators
        --es2020                     ECMAScript level es2020
        --es2021                     ECMAScript level es2021
        --es2022                     ECMAScript level es2022
        --exclude METHOD,...         exclude METHOD(s) from filters
    -f, --filter NAME,...            process using NAME filter(s)
        --filepath [PATH]            supply a path if stdin is related to a source file
        --identity                   triple equal comparison operators
        --include METHOD,...         have filters process METHOD(s)
        --include-all                have filters include all methods
        --include-only METHOD,...    have filters only process METHOD(s)
        --ivars @name:value,...      set ivars
        --logical                    use '||' for 'or' operators
        --nullish                    use '??' for 'or' operators
        --nullish_to_s               nil-safe string coercion (to_s, String(), interpolation)
        --truthy MODE                truthy semantics: 'ruby' or 'js'
        --require_recursive          import all symbols defined by processing the require recursively
        --strict                     strict mode
        --template_literal_tags tag,...
                                     process TAGS as template literals
        --underscored_private        prefix private properties with an underscore
        --sourcemap                  Provide a JSON object with the code and sourcemap
        --ast                        Output the parsed AST instead of JavaScript
        --filtered-ast               Output the filtered AST instead of JavaScript
        --show-comments              Show the comments map after filtering
        --filter-trace               Show AST after each filter is applied
    -e CODE                          Evaluate inline Ruby code

        --port n                     start a webserver
```

If no file is specified, input will be read from STDIN.

A full description of the options can be found on the [Options](options) page
of the documentation.
