// Transpiled Ruby2JS Filter: CamelCase
// Generated from ../../lib/ruby2js/filter/camelCase.rb
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

// Note care is taken to run all the filters first before camelCasing.
// This ensures that Ruby methods like each_pair can be mapped to
// JavaScript before camelcasing.
  const CamelCase = (() => {
    include(SEXP);

    const ALLOWLIST = [
      "attr_accessor",
      "attr_reader",
      "attr_writer",
      "method_missing",
      "is_a?",
      "kind_of?",
      "instance_of?"
    ];

    const CAPS_EXCEPTIONS = {
      innerHtml: "innerHTML",
      "innerHtml=": "innerHTML=",
      outerHtml: "outerHTML",
      "outerHtml=": "outerHTML=",
      encodeUri: "encodeURI",
      encodeUriComponent: "encodeURIComponent",
      decodeUri: "decodeURI",
      decodeUriComponent: "decodeURIComponent"
    };

    function camelCase(symbol) {
      if (ALLOWLIST.includes((symbol ?? "").toString())) return symbol;
      let should_symbolize = typeof symbol === "symbol";

      symbol = (symbol ?? "").toString().replaceAll(
        /(?!^)_[a-z0-9]/g,
        match => match[1].toUpperCase()
      ).replaceAll(/^(.*)$/gm, match => CAPS_EXCEPTIONS[match] ?? match);

      return should_symbolize ? symbol : symbol
    };

    function on_send(node) {
      node = process_children(node);
      if (!["send", "csend", "attr"].includes(node.type)) return node;

      if (node.children[0] === null && ALLOWLIST.includes((node.children[1] ?? "").toString())) {
        return node
      } else if (node.children[0] && ["ivar", "cvar"].includes(node.children[0].type)) {
        return S(
          node.type,
          s(node.children[0].type, camelCase(node.children[0].children[0])),
          camelCase(node.children[1]),
          ...node.children.slice(2)
        )
      } else if (/_.*\w[=!?]?$/m.test(node.children[1])) {
        return S(
          node.type,
          node.children[0],
          camelCase(node.children[1]),
          ...node.children.slice(2)
        )
      } else {
        return node
      }
    };

    function on_csend(node) {
      return on_send(node)
    };

    function on_attr(node) {
      return on_send(node)
    };

    function handle_generic_node(node, node_type) {
      if (node.type !== node_type) return node;

      return /_.*[?!\w]$/m.test((node.children[0] ?? "").toString()) && !ALLOWLIST.includes((node.children[0] ?? "").toString()) ? S(
        node_type,
        camelCase(node.children[0]),
        ...node.children.slice(1)
      ) : node
    };

    function on_def(node) {
      return handle_generic_node(process_children(node), "def")
    };

    function on_optarg(node) {
      return handle_generic_node(process_children(node), "optarg")
    };

    function on_kwoptarg(node) {
      return handle_generic_node(process_children(node), "kwoptarg")
    };

    function on_lvar(node) {
      return handle_generic_node(process_children(node), "lvar")
    };

    function on_ivar(node) {
      return handle_generic_node(process_children(node), "ivar")
    };

    function on_cvar(node) {
      return handle_generic_node(process_children(node), "cvar")
    };

    function on_arg(node) {
      return handle_generic_node(process_children(node), "arg")
    };

    function on_kwarg(node) {
      return handle_generic_node(process_children(node), "kwarg")
    };

    function on_lvasgn(node) {
      return handle_generic_node(process_children(node), "lvasgn")
    };

    function on_ivasgn(node) {
      return handle_generic_node(process_children(node), "ivasgn")
    };

    function on_cvasgn(node) {
      return handle_generic_node(process_children(node), "cvasgn")
    };

    function on_match_pattern(node) {
      return handle_generic_node(process_children(node), "match_pattern")
    };

    function on_match_var(node) {
      return handle_generic_node(process_children(node), "match_var")
    };

    function on_sym(node) {
      return handle_generic_node(process_children(node), "sym")
    };

    function on_assign(node) {
      return S(
        "assign",
        node.children[0],
        ...node.children.slice(1).map(_1 => process(_1))
      )
    };

    function on_defs(node) {
      node = process_children(node);
      if (node.type !== "defs") return node;

      return /_.*[?!\w]$/m.test(node.children[1]) ? S(
        "defs",
        node.children[0],
        camelCase(node.children[1]),
        ...node.children.slice(2)
      ) : node
    };

    return {
      ALLOWLIST,
      CAPS_EXCEPTIONS,
      camelCase,
      on_send,
      on_csend,
      on_attr,
      handle_generic_node,
      on_def,
      on_optarg,
      on_kwoptarg,
      on_lvar,
      on_ivar,
      on_cvar,
      on_arg,
      on_kwarg,
      on_lvasgn,
      on_ivasgn,
      on_cvasgn,
      on_match_pattern,
      on_match_var,
      on_sym,
      on_assign,
      on_defs
    }
  })();

// Register the filter
DEFAULTS.push(CamelCase);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.CamelCase = CamelCase;

// Setup function to bind filter infrastructure
CamelCase._setup = function(opts) {
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
export { CamelCase as default, CamelCase };
