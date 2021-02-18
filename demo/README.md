TL;DR. add the following before a ruby code block in Markdown, adjusting the
options as needed:

```html
<div data-controller="ruby" data-options='{
 "eslevel": 2020,
 "filters": ["functions", "camelCase", "return"]
}'></div>
```

Then add the following before a js code block in Markdown:

```html
<div data-controller="js"></div>
```

If there is only one of each of these on a given page, they will find one
another and updates made to the Ruby editor will be reflected in the JS
editor.

# Contents of this directory

* `ruby2js.rb` is a multi-purpose tool, it is a command line conversion tool,
  capable of launching a web server or being used as a part of a build process
  to convert Ruby source into JavaScript.  It also can be used as a CGI.
  Finally, it is used to produce the template for the demo page.

* `*.opal` is a wrapper for the `Ruby2JS.parse` and `Ruby2JS.convert`
  functions, which is converted using [Opal](https://opalrb.com/) to
  JavaScript which can be run in the browser.  Specifically:

    * `ruby2js.opal` is the code needed to bridge the native calling
      conventions of JavaScript to the ones employed in Opal generated code.
      In particular, it deals with mapping options from a JS object literal to
      a Ruby hash, and mapping a Ruby2JS SyntaxError exception to a JS
      SyntaxError exception.

    * `patch.opal` contains the monkey-patches needed to make this work.  Some
      of these are lifted from the Opal project itself which contains these
      patches in order to host the [Opal try](https://opalrb.com/try/) page;
      the rest are additions needed to support the Ruby2JS livedemo usage.

    * `filters.opal` is generated and contains both require statements and a
      mapping of file names to filter module names.  This is needed in order
      to get all filters included in the generated JavaScript and selectable
      by name.

* `editor.js` contains the [CodeMirror](https://codemirror.net/6/) definitions
  for a read/write Ruby editor and a read/only JS editor.

* `livedemo.js.rb` contains the definitions for the Stimulus controllers:

    * `RubyController` hosts the Ruby editor and sends generated JS content to
      the `JSController`

    * `OptionsController` manages the dropdowns and checkboxes for ESLevel,
      AST?, Filers, and Options.  The results are sent to the RubyController.

    * `JSController` manages the JS read-only editor.
