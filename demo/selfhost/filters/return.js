// Transpiled Ruby2JS Filter: Return
// Generated from ../../lib/ruby2js/filter/return.rb
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

Object.defineProperty(
  Array.prototype,
  "last",
  {get() {return this.at(-1)}, configurable: true}
);

  const Return = (() => {
    include(SEXP);

    const EXPRESSIONS = [
      "array",
      "float",
      "hash",
      "if",
      "int",
      "lvar",
      "nil",
      "send"
    ];

    // Methods where blocks become arrow functions with implicit returns
    // These shouldn't get explicit return added
    const IMPLICIT_RETURN_METHODS = Object.freeze([
      "map",
      "select",
      "filter",
      "reject",
      "find",
      "find_all",
      "detect",
      "collect",
      "each",
      "each_with_index",
      "each_with_object",
      "reduce",
      "inject",
      "fold",
      "sort",
      "sort_by",
      "any?",
      "all?",
      "none?",
      "one?",
      "take_while",
      "drop_while",
      "group_by",
      "partition",
      "min_by",
      "max_by",
      "minmax_by",
      "forEach"
    ]);

    function on_block(node) {
      node = process_children(node);
      if (node.type !== "block") return node;
      let call = node.children.first;

      if (call.type === "send" && call.children[0]?.type === "const" && call.children[0].children === [
        null,
        "Class"
      ] && call.children[1] === "new") return node;

      if (call.type === "send" && IMPLICIT_RETURN_METHODS.includes(call.children[1])) {
        return node
      };

      let children = node.children.dup();
      if (children.last === null) children[children.length - 1] = s("nil");

      return node.updated(
        null,
        [...children.slice(0, 2), s("autoreturn", ...children.slice(2))]
      )
    };

    // Don't wrap Class.new blocks - they contain method definitions, not return values
    // Don't wrap blocks for methods that become arrow functions with implicit returns
    function on_def(node) {
      node = process_children(node);

      if (node.type !== "def" && node.type !== "deff" && node.type !== "defm") {
        return node
      };

      if (["constructor", "initialize"].includes(node.children.first)) return node;
      let children = node.children.slice(1);
      if (children.last === null) children[children.length - 1] = s("nil");

      return node.updated(null, [
        node.children[0],
        children.first,
        s("autoreturn", ...children.slice(1))
      ])
    };

    function on_deff(node) {
      return on_def(node)
    };

    function on_defm(node) {
      return on_def(node)
    };

    function on_defs(node) {
      node = process_children(node);
      if (node.type !== "defs") return node;
      let children = node.children.slice(3);
      if (children.last === null) children[children.length - 1] = s("nil");

      return node.updated(
        null,
        [...node.children.slice(0, 3), s("autoreturn", ...children)]
      )
    };

    return {
      EXPRESSIONS,
      IMPLICIT_RETURN_METHODS,
      on_block,
      on_def,
      on_deff,
      on_defm,
      on_defs
    }
  })();

// Register the filter
DEFAULTS.push(Return);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.Return = Return;

// Setup function to bind filter infrastructure
Return._setup = function(opts) {
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
export { Return as default, Return };
