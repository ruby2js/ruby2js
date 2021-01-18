---
order: 31
title: Running the Demo
top_section: Behind the Scenes
category: demo
---

**Ruby2JS** provides a web + CLI based demo tool you can use to try out Ruby code and see how it converts to JavaScript. (This is same tool used for the [online demo](/demo)).

## Usage

The following two commands will start a server and a launch a browser:

```
git clone https://github.com/ruby2js/ruby2js.git
ruby ruby2js/demo/ruby2js.rb --port 8080
```

From the page that is loaded, enter some Ruby code into the text area
and press the convert button.  Dropdowns are provided to change the ECMAScript
level, filters, and options.  A checkbox is provided to show the Abstract
Symbol Tree (AST) produced.
