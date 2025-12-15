// Transpiled Ruby2JS Filter: CJS
// Generated from ../../lib/ruby2js/filter/cjs.rb
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

Object.defineProperty(
  Array.prototype,
  "first",
  {get() {return this[0]}, configurable: true}
);

Ruby2JS.module_default ??= "cjs";

  const CJS = (() => {
    include(SEXP);

    function set_options(options) {
      ;
      let _cjs_autoexports = !_disable_autoexports && options.autoexports;
      return _cjs_autoexports
    };

    function process(node) {
      if (!_cjs_autoexports) return process_children(node);
      let list = [node];

      while (list.length === 1 && list.first.type === "begin") {
        list = list.first.children.dup()
      };

      let replaced = [];

      list.splice(...[0, list.length].concat(list.map((child) => {
        let replacement = child;

        if (["module", "class"].includes(child.type) && child.children.first.type === "const" && child.children.first.children.first === null) {
          replacement = s("send", null, "export", child)
        } else if (child.type === "casgn" && child.children.first === null) {
          replacement = s("send", null, "export", child)
        } else if (child.type === "def") {
          replacement = s("send", null, "export", child)
        };

        if (replacement !== child) {
          replaced.push(replacement);
          if (_comments[child]) _comments[replacement] = _comments[child]
        };

        return replacement
      })));

      if (replaced.length === 1 && _cjs_autoexports === "default") {
        list.splice(...[0, list.length].concat(list.map((child) => {
          let replacement;

          if (child === replaced.first) {
            replacement = s(
              "send",
              null,
              "export",
              s("send", null, "default", ...child.children.slice(2))
            );

            if (_comments[child]) _comments[replacement] = _comments[child];
            return replacement
          } else {
            return child
          }
        })))
      };

      let _cjs_autoexports = false;
      return process(s("begin", ...list))
    };

    function on_send(node) {
      let fn, assign;
      if (node.children[1] !== "export") return process_children(node);

      if (node.children[2].type === "def") {
        fn = node.children[2];

        return node.updated(null, [
          s("attr", null, "exports"),
          (fn.children[0] ?? "").toString() + "=",

          s(
            "block",
            s("send", null, "proc"),
            ...process_all(fn.children.slice(1))
          )
        ])
      } else if (node.children[2].type === "lvasgn") {
        assign = node.children[2];

        return node.updated(null, [
          s("attr", null, "exports"),
          (assign.children[0] ?? "").toString() + "=",
          ...process_all(assign.children.slice(1))
        ])
      } else if (node.children[2].type === "casgn") {
        assign = node.children[2];

        return assign.children[0] === null ? node.updated(null, [
          s("attr", null, "exports"),
          (assign.children[1] ?? "").toString() + "=",
          ...process_all(assign.children.slice(2))
        ]) : node
      } else if (node.children[2].type === "class") {
        assign = node.children[2];

        if (assign.children[0].children[0] !== null) {
          return node
        } else if (assign.children[1] === null) {
          return node.updated(null, [
            s("attr", null, "exports"),
            (assign.children[0].children[1] ?? "").toString() + "=",

            s(
              "block",
              s("send", s("const", null, "Class"), "new"),
              s("args"),
              ...process_all(assign.children.slice(2))
            )
          ])
        } else {
          return node.updated(null, [
            s("attr", null, "exports"),
            (assign.children[0].children[1] ?? "").toString() + "=",

            s(
              "block",
              s("send", s("const", null, "Class"), "new", assign.children[1]),
              s("args"),
              ...process_all(assign.children.slice(2))
            )
          ])
        }
      } else if (node.children[2].type === "module") {
        assign = node.children[2];

        return assign.children[0].children[0] !== null ? node : node.updated(
          null,

          [
            s("attr", null, "exports"),
            (assign.children[0].children[1] ?? "").toString() + "=",

            s(
              "class_module",
              null,
              null,
              ...process_all(assign.children.slice(1))
            )
          ]
        )
      } else if (node.children[2].type === "send" && node.children[2].children[0] === null && node.children[2].children[1] === "async" && node.children[2].children[2].type === "def") {
        fn = node.children[2].children[2];

        return node.updated(null, [
          s("attr", null, "exports"),
          (fn.children[0] ?? "").toString() + "=",

          s("send", null, "async", s(
            "block",
            s("send", null, "proc"),
            ...process_all(fn.children.slice(1))
          ))
        ])
      } else if (node.children[2].type === "send" && node.children[2].children[0] === null && node.children[2].children[1] === "default") {
        node = node.children[2];

        return node.updated(
          null,
          [s("attr", null, "module"), "exports=", process(node.children[2])]
        )
      } else {
        return process_children(node)
      }
    };

    function on_block(node) {
      let child = node.children[0];

      if (child.type !== "send" || child.children[0] !== null || child.children[1] !== "export") {
        return process_children(node)
      };

      let send = child.children[2];

      if (send.type !== "send" || send.children[0] !== null || send.children[1] !== "default") {
        return process_children(node)
      };

      if (nodesEqual(send.children[2], s("send", null, "proc"))) {
        return node.updated(
          "send",

          [s("attr", null, "module"), "exports=", s(
            "block",
            s("send", null, "proc"),
            ...process_all(node.children.slice(1))
          )]
        )
      } else if (nodesEqual(
        send.children[2],
        s("send", null, "async", s("send", null, "proc"))
      )) {
        return node.updated(
          "send",

          [s("attr", null, "module"), "exports=", s("send", null, "async", s(
            "block",
            s("send", null, "proc"),
            ...process_all(node.children.slice(1))
          ))]
        )
      } else {
        return process_children(node)
      }
    };

    return {set_options, process, on_send, on_block}
  })();

// Register the filter
DEFAULTS.push(CJS);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.CJS = CJS;

// Setup function to bind filter infrastructure
CJS._setup = function(opts) {
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
export { CJS as default, CJS };
