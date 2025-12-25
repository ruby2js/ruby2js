---
order: 31
title: Running the Demo
top_section: Behind the Scenes
category: demo
---

**Ruby2JS** provides a web-based demo tool you can use to try out Ruby code and see how it converts to JavaScript. This is the same tool used for the [online demo](/demo?preset=true).

## Web Demo

The following commands will start a server and launch a browser:

```
git clone https://github.com/ruby2js/ruby2js.git
ruby ruby2js/demo/ruby2js.rb --port 8080
```

From the page that is loaded, enter some Ruby code into the text area and press the convert button. Dropdowns are provided to change the ECMAScript level, filters, and options. A checkbox is provided to show the Abstract Syntax Tree (AST) produced.

## Command Line Usage

The demo script also works as a full-featured CLI tool, supporting all the same options as the main `ruby2js` executable. See the [CLI documentation](cli) for the complete list of options.

### Examples

Convert a file:
```
ruby demo/ruby2js.rb myfile.rb
```

Convert inline code:
```
ruby demo/ruby2js.rb -e 'puts "Hello, World!"'
```

Use preset defaults with filters:
```
ruby demo/ruby2js.rb --preset --filter camelCase myfile.rb
```

Show the parsed AST:
```
ruby demo/ruby2js.rb --ast -e 'x = 1 + 2'
```

Show the AST after filters are applied:
```
ruby demo/ruby2js.rb --filtered-ast --filter functions -e '[1,2,3].map {|x| x * 2}'
```

Trace how each filter transforms the AST:
```
ruby demo/ruby2js.rb --filter-trace --filter functions -e 'puts "hello"'
```
