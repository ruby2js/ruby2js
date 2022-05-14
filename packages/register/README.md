# @ruby2js/register

[![npm][npm]][npm-url]

One of the ways you can use Ruby2JS is through the require hook. The require
hook will bind itself to node's `require` and automatically compile files on
the fly. This is equivalent to Babel's
[@babel/register](https://babeljs.io/docs/en/babel-register).

## Install

```sh
npm install @ruby2js/register --save-dev
```

## Usage

```js
require("@ruby2js/register");
```

All subsequent files required by node with the extensions `.rb`
will be transformed by Ruby2JS.

**NOTE:** all requires to `node_modules` will be ignored.

## Specifying options

```javascript
require("@ruby2js/register")({
  // Ruby2JS options
  options: {
    eslevel: 2021,
    autoexports: 'default',
    filters: ['cjs', 'functions']
  },

  // Array of ignore conditions, either a regex or a function. (Optional)
  // File paths that match any condition are not compiled.
  ignore: [
    // When a file path matches this regex then it is **not** compiled
    /regex/,

    // The file's path is also passed to any ignore functions. It will
    // **not** be compiled if `true` is returned.
    function(filepath) {
      return filepath !== "/path/to/ruby-file.rb";
    },
  ],

  // Array of accept conditions, either a regex or a function. (Optional)
  // File paths that match all conditions are compiled.
  only: [
    // File paths that **don't** match this regex are not compiled
    /my_ruby_folder/,

    // File paths that **do not** return true are not compiled
    function(filepath) {
      return filepath === "/path/to/ruby-file.rb";
    },
  ],

  // Setting this will remove the currently hooked extensions of `.rb`
  // so you'll have to it them back if you want it to be used
  // again.
  extensions: [".rb"],
});
```

### Notes:

 * No caching is provided at this time.

 * This code uses the same [require hook](https://github.com/ariporad/pirates#readme)
   that Babel uses, so the same caveats and limitations apply.  In particular,
   `@ruby2js/register` does _not_ support compiling native Node.js ES modules
   on the fly, since currently there is no stable API for intercepting ES
   modules loading.

[npm]: https://img.shields.io/npm/v/@ruby2js/register.svg
[npm-url]: https://npmjs.com/package/@ruby2js/register