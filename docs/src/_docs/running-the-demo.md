---
order: 510
title: Running the Demo
top_section: Behind the Scenes
category: demo
---

**Ruby2JS** provides a web-based demo tool you can use to try out Ruby code and see how it converts to JavaScript. (This is same tool used for the [online demo](/demo?preset=true)).

## Usage

The following commands will start a local demo server:

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js
bundle install
ruby demo/app.rb
```

Then open http://localhost:4567 in your browser.

The demo provides a live editing experience - JavaScript output updates as you type Ruby code. Dropdowns are provided to change the ECMAScript level, filters, and options. A checkbox is provided to show the Abstract Syntax Tree (AST) produced.
