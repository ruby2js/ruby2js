// Transpiled Ruby2JS Filter: Polyfill
// Generated from ../../lib/ruby2js/filter/polyfill.rb
//
// This is an ES module that exports the filter for use with the selfhost test harness.
// It imports shared infrastructure from the bundle to minimize duplication.

// Import from the transpiled bundle - this provides:
// - Ruby2JS.ast_node (AST node check)
// - Ruby2JS.Filter.SEXP (s, S, ast_node helpers)
// - Ruby2JS.Filter.Processor (AST walker with process/process_children/process_all)
// - Array polyfills (none, all, any, compact, etc.)
import { Ruby2JS } from '../ruby2js.js';

// Alias Parser.AST.Node to Ruby2JS.Node so transpiled code works
// (Ruby source uses Parser gem's AST nodes, JS uses Ruby2JS.Node)
const Parser = { AST: { Node: Ruby2JS.Node } };

// Get SEXP helpers from transpiled bundle
const SEXP = Ruby2JS.Filter.SEXP;
const s = SEXP.s.bind(SEXP);
let S = s;  // S is reassigned by _setup to use @ast.updated() for location preservation

// AST node type checker (Ruby's ast_node? method)
// Checks if an object is an AST node (has type and children properties)
const ast_node = (node) => {
  if (!node || typeof node !== 'object') return false;
  return 'type' in node && 'children' in node;
};

// Setup: make include() a no-op (Ruby's include SEXP doesn't apply in JS)
const include = () => {};

// Setup: Filter global for exclude/include calls (no-op, handled by test harness)
const Filter = {
  exclude: (...methods) => {},
  include: (...methods) => {}
};

// Setup: DEFAULTS array for filter registration
const DEFAULTS = [];

// Filter infrastructure functions (bound by FilterProcessor at runtime)
// Default implementations return false/do nothing until bound
let excluded = () => false;
let included = () => false;
let process = (node) => node;
let process_children = (node) => node;  // Processes child nodes, bound at runtime
let process_all = (nodes) => nodes ? nodes.map(node => process(node)) : [];
let _options = {};

// ES level helper functions - use getter pattern so Ruby's `es2020` (no parens) works in JS
// These must be globals because filters use them without `this.` prefix
let _eslevel = 0;
Object.defineProperty(globalThis, 'es2015', { get: () => _eslevel >= 2015, configurable: true });
Object.defineProperty(globalThis, 'es2016', { get: () => _eslevel >= 2016, configurable: true });
Object.defineProperty(globalThis, 'es2017', { get: () => _eslevel >= 2017, configurable: true });
Object.defineProperty(globalThis, 'es2018', { get: () => _eslevel >= 2018, configurable: true });
Object.defineProperty(globalThis, 'es2019', { get: () => _eslevel >= 2019, configurable: true });
Object.defineProperty(globalThis, 'es2020', { get: () => _eslevel >= 2020, configurable: true });
Object.defineProperty(globalThis, 'es2021', { get: () => _eslevel >= 2021, configurable: true });
Object.defineProperty(globalThis, 'es2022', { get: () => _eslevel >= 2022, configurable: true });
Object.defineProperty(globalThis, 'es2023', { get: () => _eslevel >= 2023, configurable: true });
Object.defineProperty(globalThis, 'es2024', { get: () => _eslevel >= 2024, configurable: true });
Object.defineProperty(globalThis, 'es2025', { get: () => _eslevel >= 2025, configurable: true });

// Wrapper to provide 'this' context with _options for filter functions
const filterContext = {
  get _options() { return _options; }
};

// AST node structural comparison (Ruby's == compares structure, JS's === compares references)
// This is unique to filter testing - not in the Ruby sources
function nodesEqual(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  if (typeof a !== 'object' || typeof b !== 'object') return a === b;
  if (a.type !== b.type) return false;
  if (!a.children || !b.children) return false;
  if (a.children.length !== b.children.length) return false;
  for (let i = 0; i < a.children.length; i++) {
    if (!nodesEqual(a.children[i], b.children[i])) return false;
  }
  return true;
}

if (!Array.prototype.insert) {
  Array.prototype.insert = function(index, ...items) {
    this.splice(index, 0, ...items);
    return this
  }
};

Object.defineProperty(
  Array.prototype,
  "first",
  {get() {return this[0]}, configurable: true}
);

  const Polyfill = (() => {
    include(SEXP);

    function reorder(filters) {
      if (typeof Ruby2JS.Filter.Functions !== 'undefined' && filters.includes(Ruby2JS.Filter.Functions)) {
        filters = filters.dup();
        let polyfill = delete filters[Ruby2JS.Filter.Polyfill];
        filters.insert(filters.indexOf(Ruby2JS.Filter.Functions), polyfill)
      };

      return filters
    };

    // Ensure polyfill runs before functions filter so that
    // the polyfill methods can be transformed by functions
    function initialize(comments) {
      ;
      let _polyfills_added = new Set
    };

    // Build AST for: Object.defineProperty(Array.prototype, 'name', {get() {...}, configurable: true})
    function define_property_getter(prototype, name, body) {
      return s(
        "send",
        s("const", null, "Object"),
        "defineProperty",
        s("attr", s("const", null, prototype), "prototype"),
        s("str", (name ?? "").toString()),

        s(
          "hash",
          s("pair", s("sym", "get"), s("defm", null, s("args"), body)),
          s("pair", s("sym", "configurable"), s("true"))
        )
      )
    };

    // Build AST for: if (!Prototype.prototype.name) { Prototype.prototype.name = function(...) {...} }
    function define_prototype_method(prototype, name, args, body) {
      let proto_attr = s("attr", s("const", null, prototype), "prototype");

      return s(
        "if",
        s("send", s("attr", proto_attr, name), "!"),

        s(
          "send",
          proto_attr,
          "[]=",
          s("str", (name ?? "").toString()),
          s("deff", null, args, body)
        ),

        null
      )
    };

    // Generate polyfill AST nodes
    // Object.defineProperty(Array.prototype, 'first', {get() { return this[0] }, configurable: true})
    // Object.defineProperty(Array.prototype, 'last', {get() { return this.at(-1) }, configurable: true})
    // Object.defineProperty(Array.prototype, 'compact', {get() {...}, configurable: true})
    // Non-mutating: returns new array without null/undefined (matches Ruby's compact)
    // For compact! (mutating), the Functions filter converts it to splice-based code
    // if (!Array.prototype.rindex) { Array.prototype.rindex = function(fn) {...} }
    // Using while loop: let i = this.length - 1; while (i >= 0) { ...; i-- }
    // if (!Array.prototype.insert) { Array.prototype.insert = function(index, ...items) {...} }
    // if (!Array.prototype.delete_at) { Array.prototype.delete_at = function(index) {...} }
    // if (!String.prototype.chomp) { String.prototype.chomp = function(suffix) {...} }
    // if (!String.prototype.count) { String.prototype.count = function(chars) {...} }
    // Counts occurrences of any character in chars string
    // for (const c of this) { if (chars.includes(c)) count++ }
    // Object.defineProperty(Object.prototype, 'to_a', {get() { return Object.entries(this) }, configurable: true})
    // if (!RegExp.escape) { RegExp.escape = function(str) { return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') } }
    function polyfill_ast(name) {
      switch (name) {
      case "array_first":

        return define_property_getter(
          "Array",
          "first",
          s("return", s("send", s("self"), "[]", s("int", 0)))
        );

      case "array_last":

        return define_property_getter(
          "Array",
          "last",
          s("return", s("send", s("self"), "at", s("int", -1)))
        );

      case "array_compact":

        return define_property_getter("Array", "compact", s("return", s(
          "send",
          s("self"),
          "filter",

          s("block", s("send", null, "lambda"), s("args", s("arg", "x")), s(
            "and",
            s("send", s("lvar", "x"), "!==", s("nil")),
            s("send", s("lvar", "x"), "!==", s("lvar", "undefined"))
          ))
        )));

      case "array_rindex":

        return define_prototype_method(
          "Array",
          "rindex",
          s("args", s("arg", "fn")),

          s(
            "begin",

            s(
              "lvasgn",
              "i",
              s("send", s("attr", s("self"), "length"), "-", s("int", 1))
            ),

            s("while", s("send", s("lvar", "i"), ">=", s("int", 0)), s(
              "begin",

              s(
                "if",

                s(
                  "send!",
                  s("lvar", "fn"),
                  null,
                  s("send", s("self"), "[]", s("lvar", "i"))
                ),

                s("return", s("lvar", "i")),
                null
              ),

              s("op_asgn", s("lvasgn", "i"), "-", s("int", 1))
            )),

            s("return", s("nil"))
          )
        );

      case "array_insert":

        return define_prototype_method(
          "Array",
          "insert",
          s("args", s("arg", "index"), s("restarg", "items")),

          s(
            "begin",

            s(
              "send",
              s("self"),
              "splice",
              s("lvar", "index"),
              s("int", 0),
              s("splat", s("lvar", "items"))
            ),

            s("return", s("self"))
          )
        );

      case "array_delete_at":

        return define_prototype_method(
          "Array",
          "delete_at",
          s("args", s("arg", "index")),

          s(
            "begin",

            s(
              "if",
              s("send", s("lvar", "index"), "<", s("int", 0)),

              s(
                "lvasgn",
                "index",
                s("send", s("attr", s("self"), "length"), "+", s("lvar", "index"))
              ),

              null
            ),

            s(
              "if",

              s(
                "or",
                s("send", s("lvar", "index"), "<", s("int", 0)),
                s("send", s("lvar", "index"), ">=", s("attr", s("self"), "length"))
              ),

              s("return", s("lvar", "undefined")),
              null
            ),

            s("return", s(
              "send",
              s("send", s("self"), "splice", s("lvar", "index"), s("int", 1)),
              "[]",
              s("int", 0)
            ))
          )
        );

      case "string_chomp":

        return define_prototype_method(
          "String",
          "chomp",
          s("args", s("arg", "suffix")),

          s(
            "begin",

            s(
              "if",
              s("send", s("lvar", "suffix"), "===", s("lvar", "undefined")),

              s("return", s(
                "send",
                s("self"),
                "replace",
                s("regexp", s("str", "\\r?\\n$"), s("regopt")),
                s("str", "")
              )),

              null
            ),

            s(
              "if",
              s("send", s("self"), "endsWith", s("lvar", "suffix")),

              s("return", s("send", s("self"), "slice", s("int", 0), s(
                "send",
                s("attr", s("self"), "length"),
                "-",
                s("attr", s("lvar", "suffix"), "length")
              ))),

              null
            ),

            s("return", s("send", null, "String", s("self")))
          )
        );

      case "string_count":

        return define_prototype_method(
          "String",
          "count",
          s("args", s("arg", "chars")),

          s(
            "begin",
            s("lvasgn", "count", s("int", 0)),

            s("for_of", s("lvasgn", "c"), s("self"), s(
              "if",
              s("send", s("lvar", "chars"), "includes", s("lvar", "c")),
              s("op_asgn", s("lvasgn", "count"), "+", s("int", 1)),
              null
            )),

            s("return", s("lvar", "count"))
          )
        );

      case "object_to_a":

        return define_property_getter("Object", "to_a", s(
          "return",
          s("send", s("const", null, "Object"), "entries", s("self"))
        ));

      case "regexp_escape":

        return s(
          "if",
          s("send", s("attr", s("const", null, "RegExp"), "escape"), "!"),

          s(
            "send",
            s("const", null, "RegExp"),
            "[]=",
            s("str", "escape"),

            s("deff", null, s("args", s("arg", "str")), s("return", s(
              "send",
              s("lvar", "str"),
              "replace",
              s("regexp", s("str", "[.*+?^${}()|[\\]\\\\]"), s("regopt", "g")),
              s("str", "\\$&")
            )))
          ),

          null
        )
      }
    };

    // Helper to add a polyfill only once
    function add_polyfill(name) {
      if (_polyfills_added.includes(name)) return;
      _polyfills_added.push(name);
      return prepend_list << polyfill_ast(name)
    };

    // Only process calls with a receiver
    // Use :attr for property access (no parens) - it's a getter
    // Use :attr for property access (no parens) - it's a getter
    // rindex with block (block handled separately)
    // Use :attr for property access (no parens) - it's a getter
    // String#count(chars) - count occurrences of any char in chars
    // Hash#to_a / Object#to_a - convert to array of entries
    // RegExp.escape(str) => RegExp.escape(str) with polyfill for pre-ES2025
    function on_send(node) {
      let [target, method, ...args] = node.children;

      if (target) {
        switch (method) {
        case "first":

          if (args.length === 0) {
            add_polyfill("array_first");
            return s("attr", process(target), "first")
          };

          break;

        case "last":

          if (args.length === 0) {
            add_polyfill("array_last");
            return s("attr", process(target), "last")
          };

          break;

        case "rindex":

          if (args.length === 0) {
            add_polyfill("array_rindex");
            return s("send!", process(target), "rindex")
          };

          break;

        case "compact":

          if (args.length === 0) {
            add_polyfill("array_compact");
            return s("attr", process(target), "compact")
          };

          break;

        case "insert":
          add_polyfill("array_insert");

          return s(
            "send!",
            process(target),
            "insert",
            ...args.map(a => process(a))
          );

        case "delete_at":

          if (args.length === 1) {
            add_polyfill("array_delete_at");
            return s("send!", process(target), "delete_at", process(args.first))
          };

          break;

        case "chomp":

          if (args.length <= 1) {
            add_polyfill("string_chomp");

            return s(
              "send!",
              process(target),
              "chomp",
              ...args.map(a => process(a))
            )
          };

          break;

        case "count":

          if (args.length === 1) {
            add_polyfill("string_count");
            return s("send!", process(target), "count", process(args.first))
          };

          break;

        case "to_a":

          if (args.length === 0) {
            add_polyfill("object_to_a");
            return s("attr", process(target), "to_a")
          };

          break;

        case "escape":

          if (nodesEqual(target, s("const", null, "Regexp")) && args.length === 1) {
            if (!es2025) add_polyfill("regexp_escape");

            return s(
              "send",
              s("const", null, "RegExp"),
              "escape",
              process(args.first)
            )
          }
        }
      };

      return process_children(node)
    };

    // Handle .first/.last when already converted to attr by another filter
    // (e.g., selfhost/converter transforms these before polyfill runs)
    function on_attr(node) {
      let [target, method] = node.children;

      switch (method) {
      case "first":
        add_polyfill("array_first");
        break;

      case "last":
        add_polyfill("array_last");
        break;

      case "compact":
        add_polyfill("array_compact")
      };

      return process_children(node)
    };

    // Handle rindex with block
    // Process the block but keep as :send! to prevent further transformation
    function on_block(node) {
      let target, method;
      let call = node.children.first;

      if (call.type === "send") {
        let [target, method] = call.children;

        if (target && method === "rindex") {
          add_polyfill("array_rindex");

          return node.updated(null, [
            s("send!", process(target), "rindex"),
            process(node.children[1]),
            process(node.children[2])
          ])
        }
      };

      return process_children(node)
    };

    return {
      reorder,
      initialize,
      define_property_getter,
      define_prototype_method,
      polyfill_ast,
      add_polyfill,
      on_send,
      on_attr,
      on_block
    }
  })();

// Register the filter
DEFAULTS.push(Polyfill);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.Polyfill = Polyfill;

// Setup function to bind filter infrastructure
Polyfill._setup = function(opts) {
  if (opts.excluded) excluded = opts.excluded;
  if (opts.included) included = opts.included;
  if (opts.process) process = opts.process;
  if (opts.process_children) process_children = opts.process_children;
  if (opts.S) S = opts.S;  // S uses @ast.updated() for location preservation
  if (opts._options) {
    _options = opts._options;
    _eslevel = opts._options.eslevel || 0;
  }
};

// Export the filter for ES module usage
export { Polyfill as default, Polyfill };
