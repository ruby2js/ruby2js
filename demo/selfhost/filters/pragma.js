// Transpiled Ruby2JS Filter: Pragma
// Generated from ../../lib/ruby2js/filter/pragma.rb
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

if (!Array.prototype.delete_at) {
  Array.prototype.delete_at = function(index) {
    if (index < 0) index = this.length + index;
    if (index < 0 || index >= this.length) return undefined;
    return this.splice(index, 1)[0]
  }
};

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

  const Pragma = (() => {
    include(SEXP);

    function reorder(filters) {
      let require_filter = typeof Ruby2JS.Filter.Require !== 'undefined' ? Ruby2JS.Filter.Require : null;
      let require_index = require_filter ? filters.indexOf(require_filter) : null;
      let pragma_index = filters.indexOf(Ruby2JS.Filter.Pragma);
      if (!pragma_index) return filters;

      if (require_index && pragma_index < require_index) {
        filters = filters.dup();
        filters.delete_at(pragma_index);
        filters.insert(require_index, Ruby2JS.Filter.Pragma)
      } else if (require_index && pragma_index > require_index + 1) {
        filters = filters.dup();
        filters.delete_at(pragma_index);
        filters.insert(require_index + 1, Ruby2JS.Filter.Pragma)
      };

      return filters
    };

    // Mapping from pragma comment text to internal symbol
    const PRAGMAS = Object.freeze({
      "??": "nullish",
      nullish: "nullish",
      "||": "logical",
      logical: "logical",
      noes2015: "noes2015",
      function: "noes2015",
      guard: "guard",

      // Type disambiguation pragmas
      array: "array",
      hash: "hash",
      string: "string",
      set: "set",

      // Behavior pragmas
      method: "method",
      self: "self_pragma",
      proto: "proto",
      entries: "entries",

      // Statement control pragmas
      skip: "skip"
    });

    function initialize(...args) {
      ;
      let _pragmas = {};
      let _pragma_scanned_count = 0
    };

    function set_options(options) {
      ;
      let _pragmas = {};
      let _pragma_scanned_count = 0;
      return _pragma_scanned_count
    };

    // Scan all comments for pragma patterns and build [source, line] => Set<pragma> map
    // Re-scans when new comments are added (e.g., from require filter merging files)
    // Uses both source buffer name and line number to avoid collisions across files
    // Process only new comments (from index @pragma_scanned_count onwards)
    // Use scan to find ALL pragmas on a line, not just the first
    // Get the source buffer name and line number of the comment
    // Try to get source buffer name from location
    // Use [source_name, line] as key to avoid cross-file collisions
    function scan_pragmas() {
      let raw_comments = _comments["_raw"] ?? [];
      if (raw_comments.length === _pragma_scanned_count) return;

      for (let comment of raw_comments.slice(_pragma_scanned_count)) {
        let text = typeof comment === "object" && comment !== null && "text" in comment ? comment.text : (comment ?? "").toString();

        for (let match of Array.from(
          text.matchAll(/#\s*Pragma:\s*(\S+)/gi),
          s => s.slice(1)
        )) {
          let pragma_name = match[0];
          let pragma_sym = PRAGMAS[pragma_name];
          if (!pragma_sym) continue;
          let source_name = null;
          let line = null;

          if (typeof comment === "object" && comment !== null && "loc" in comment && comment.loc) {
            let loc = comment.loc;

            if (typeof loc === "object" && loc !== null && "expression" in loc && loc.expression) {
              source_name = loc.expression.source_buffer?.name;
              line = loc.line
            } else if (typeof loc === "object" && loc !== null && "line" in loc) {
              line = loc.line
            }
          } else if (typeof comment === "object" && comment !== null && "location" in comment) {
            let loc = comment.location;
            line = typeof loc === "object" && loc !== null && "start_line" in loc ? loc.start_line : loc.line;

            if (typeof loc === "object" && loc !== null && "source_buffer" in loc) {
              source_name = loc.source_buffer?.name
            }
          };

          if (!line) continue;
          let key = [source_name, line];
          _pragmas[key] ??= new Set;
          _pragmas[key].push(pragma_sym)
        }
      };

      let _pragma_scanned_count = raw_comments.length;
      return _pragma_scanned_count
    };

    // Check if a node's line has a specific pragma
    // Try with source name first, then fall back to nil source for compatibility
    // Fallback: check without source name (for backward compatibility)
    function pragma(node, pragma_sym) {
      let scan_pragmas;
      let [source_name, line] = node_source_and_line(node);
      if (!line) return false;
      let key = [source_name, line];
      if (_pragmas[key]?.includes(pragma_sym)) return true;
      let key_no_source = [null, line];
      return _pragmas[key_no_source]?.includes(pragma_sym)
    };

    // Get the source buffer name and line number for a node
    function node_source_and_line(node) {
      if (typeof node !== "object" || node === null || !("loc" in node) || !node.loc) {
        return [null, null]
      };

      let loc = node.loc;
      let source_name = null;
      let line = null;

      if (typeof loc === "object" && loc !== null && "expression" in loc && loc.expression) {
        source_name = loc.expression.source_buffer?.name;
        line = loc.expression.line
      } else if (typeof loc === "object" && loc !== null && "line" in loc) {
        line = loc.line;

        if (typeof loc === "object" && loc !== null && "source_buffer" in loc) {
          source_name = loc.source_buffer?.name
        }
      } else if (typeof loc === "object" && loc !== null && !Array.isArray(loc) && loc.start_line) {
        line = loc.start_line
      };

      return [source_name, line]
    };

    // Handle || with nullish pragma -> ?? or with logical pragma -> || (forces logical)
    // Force || even when @or option would normally use ??
    function on_or(node) {
      if (pragma(node, "nullish") && es2020) {
        return process(s("nullish_or", ...node.children))
      } else if (pragma(node, "logical")) {
        return process(s("logical_or", ...node.children))
      } else {
        return process_children(node)
      }
    };

    // Handle ||= with nullish pragma -> ??= or with logical pragma -> ||= (forces logical)
    // Note: We check es2020 here because ?? is available then.
    // The converter will decide whether to use ??= (ES2021+) or expand to a = a ?? b
    // Force ||= even when @or option would normally use ??=
    function on_or_asgn(node) {
      if (pragma(node, "nullish") && es2020) {
        return process(s("nullish_asgn", ...node.children))
      } else if (pragma(node, "logical")) {
        return process(s("logical_asgn", ...node.children))
      } else {
        return process_children(node)
      }
    };

    // Handle def with skip pragma (remove method definition) or noes2015 pragma
    // Skip pragma: remove method definition entirely
    // Convert anonymous def to deff (forces function syntax)
    // Don't re-process - just update type and process children
    function on_def(node) {
      if (pragma(node, "skip")) return s("hide");

      return node.children[0] === null && pragma(node, "noes2015") ? node.updated(
        "deff",
        process_all(node.children)
      ) : process_children(node)
    };

    // Handle defs (class methods like self.foo) with skip pragma
    function on_defs(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle alias with skip pragma
    function on_alias(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle if/unless with skip pragma (remove entire block)
    function on_if(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle begin blocks with skip pragma
    function on_kwbegin(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle while loops with skip pragma
    function on_while(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle until loops with skip pragma
    function on_until(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle case statements with skip pragma
    function on_case(node) {
      if (pragma(node, "skip")) return s("hide");
      return process_children(node)
    };

    // Handle array splat with guard pragma -> ensure array even if null
    // [*a] with guard pragma becomes (a ?? [])
    // Look for splat nodes
    // Replace splat contents with (contents ?? [])
    // Process the guarded items, then return without re-checking pragma
    function on_array(node) {
      let items, changed, guarded_items;

      if (pragma(node, "guard") && es2020) {
        items = node.children;
        changed = false;

        guarded_items = items.map((item) => {
          let inner, guarded;

          if (ast_node(item) && item.type === "splat" && item.children.first) {
            inner = item.children.first;
            guarded = s("begin", s("nullish_or", inner, s("array")));
            changed = true;
            return s("splat", guarded)
          } else {
            return item
          }
        });

        return changed ? node.updated(null, process_all(guarded_items)) : process_children(node)
      } else {
        return process_children(node)
      }
    };

    // Handle send nodes with type disambiguation and behavior pragmas
    // Skip pragma: remove require/require_relative statements
    // Type disambiguation for ambiguous methods
    // .dup - Array: .slice(), Hash: {...obj}, String: str (no-op in JS)
    // target.slice() - creates shallow copy of array
    // {...target}
    // No-op for strings in JS (they're immutable)
    // << - Array: push, Set: add, String: +=
    // target.push(arg)
    // target.add(arg)
    // target += arg (returns new string)
    // .include? - Array: includes(), String: includes(), Set: has(), Hash: 'key' in obj
    // arg in target (uses :in? synthetic type)
    // target.has(arg) - Set membership check
    // Note: array and string both use .includes() which functions filter handles
    // .call - with method pragma, convert proc.call(args) to proc(args)
    // Direct invocation using :call type with nil method
    // .class - with proto pragma, use .constructor instead
    function on_send(node) {
      let [target, method, ...args] = node.children;

      if (target === null && ["require", "require_relative"].includes(method)) {
        if (pragma(node, "skip")) return s("hide")
      };

      switch (method) {
      case "dup":

        if (pragma(node, "array")) {
          return process(s("send", target, "slice"))
        } else if (pragma(node, "hash")) {
          return process(s("hash", s("kwsplat", target)))
        } else if (pragma(node, "string")) {
          return process(target)
        };

        break;

      case "<<":

        if (pragma(node, "array") && args.length === 1) {
          return process(s("send", target, "push", args.first))
        } else if (pragma(node, "set") && args.length === 1) {
          return process(s("send", target, "add", args.first))
        } else if (pragma(node, "string") && args.length === 1) {
          return process(s("op_asgn", target, "+", args.first))
        };

        break;

      case "include?":

        if (pragma(node, "hash") && args.length === 1) {
          return process(s("in?", args.first, target))
        } else if (pragma(node, "set") && args.length === 1) {
          return process(s("send", target, "has", args.first))
        };

        break;

      case "call":

        if (pragma(node, "method") && target) {
          return process(node.updated("call", [target, null, ...args]))
        };

        break;

      case "class":

        if (pragma(node, "proto") && target) {
          return process(s("attr", target, "constructor"))
        }
      };

      return process_children(node)
    };

    // Handle self with self pragma -> this
    function on_self(node) {
      return pragma(node, "self_pragma") ? s("send", null, "this") : process_children(node)
    };

    // Handle hash iteration methods with entries pragma
    // hash.each { |k,v| } -> Object.entries(hash).forEach(([k,v]) => {})
    // hash.map { |k,v| } -> Object.entries(hash).map(([k,v]) => {})
    // hash.select { |k,v| } -> Object.fromEntries(Object.entries(hash).filter(([k,v]) => {}))
    // Transform to use :deff which forces function syntax
    // Transform: hash.each { |k,v| body }
    // Into: Object.entries(hash).forEach(([k,v]) => body)
    // Wrap args in destructuring array pattern if multiple args
    // Create new block without location to avoid re-triggering pragma
    // Transform: hash.map { |k,v| expr }
    // Into: Object.entries(hash).map(([k,v]) => expr)
    // Create new block without location to avoid re-triggering pragma
    // Transform: hash.select { |k,v| expr }
    // Into: Object.fromEntries(Object.entries(hash).filter(([k,v]) => expr))
    // Create a new block node without location info to avoid re-triggering pragma
    // Process the inner block first, then wrap with fromEntries
    function on_block(node) {
      let target, method;
      let [call, args, body] = node.children;

      if (pragma(node, "noes2015")) {
        let $function = node.updated("deff", [null, args, body]);
        return process(s(call.type, ...call.children, $function))
      };

      if (pragma(node, "entries") && call.type === "send") {
        let [target, method] = [call.children[0], call.children[1]];

        if (["each", "each_pair"].includes(method) && target) {
          let entries_call = s(
            "send",
            s("const", null, "Object"),
            "entries",
            target
          );

          let new_args = args.children.length > 1 ? s(
            "args",
            s("mlhs", ...args.children)
          ) : args;

          return process(s(
            "block",
            s("send", entries_call, "forEach"),
            new_args,
            body
          ))
        } else if (method === "map" && target) {
          let entries_call = s(
            "send",
            s("const", null, "Object"),
            "entries",
            target
          );

          let new_args = args.children.length > 1 ? s(
            "args",
            s("mlhs", ...args.children)
          ) : args;

          return process(s(
            "block",
            s("send", entries_call, "map"),
            new_args,
            body
          ))
        } else if (method === "select" && target) {
          let entries_call = s(
            "send",
            s("const", null, "Object"),
            "entries",
            target
          );

          let new_args = args.children.length > 1 ? s(
            "args",
            s("mlhs", ...args.children)
          ) : args;

          let filter_block = s(
            "block",
            s("send", entries_call, "filter"),
            new_args,
            body
          );

          let processed_filter = process(filter_block);

          return s(
            "send",
            s("const", null, "Object"),
            "fromEntries",
            processed_filter
          )
        }
      };

      return process_children(node)
    };

    return {
      reorder,
      PRAGMAS,
      initialize,
      set_options,
      scan_pragmas,
      pragma,
      node_source_and_line,
      on_or,
      on_or_asgn,
      on_def,
      on_defs,
      on_alias,
      on_if,
      on_kwbegin,
      on_while,
      on_until,
      on_case,
      on_array,
      on_send,
      on_self,
      on_block
    }
  })();

// Register the filter
DEFAULTS.push(Pragma);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.Pragma = Pragma;

// Setup function to bind filter infrastructure
Pragma._setup = function(opts) {
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
export { Pragma as default, Pragma };
