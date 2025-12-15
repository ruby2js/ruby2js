// Transpiled Ruby2JS Filter: ESM
// Generated from ../../lib/ruby2js/filter/esm.rb
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

Ruby2JS.module_default = "esm";

  const ESM = (() => {
    include(SEXP);

    function initialize(...args) {
      let _esm_require_seen = {};

    };

    function set_options(options) {
      ;
      let _esm_autoexports = !_disable_autoexports && options.autoexports;
      let _esm_autoexports_option = _esm_autoexports;
      let _esm_autoimports = options.autoimports;
      let _esm_defs = options.defs ?? {};
      let _esm_explicit_tokens = new Set;
      let _esm_top = null;
      let _esm_require_recursive = options.require_recursive;
      let filters = options.filters ?? Filter.DEFAULTS;

      if (typeof Ruby2JS.Filter.Require !== 'undefined' && filters.includes(Ruby2JS.Filter.Require)) {
        let _esm_skip_require = true;
        return _esm_skip_require
      }
    };

    // preserve for require-to-import
    // don't convert requires if Require filter is included (it will inline them)
    function process(node) {
      if (_esm_top) return process_children(node);
      let list = [node];

      while (list.length === 1 && list.first.type === "begin") {
        list = list.first.children.dup()
      };

      let _esm_top = list;
      if (!_esm_autoexports) return process_children(node);
      let replaced = [];

      list.splice(...[0, list.length].concat(list.map((child) => {
        let replacement = child;

        if (["module", "class"].includes(child.type) && child.children.first.type === "const" && child.children.first.children.first === null) {
          replacement = s("export", child)
        } else if (child.type === "casgn" && child.children.first === null) {
          replacement = s("export", child)
        } else if (child.type === "def") {
          replacement = s("export", child)
        };

        if (replacement !== child) {
          replaced.push(replacement);
          if (_comments[child]) _comments[replacement] = _comments[child]
        };

        return replacement
      })));

      if (replaced.length === 1 && _esm_autoexports === "default") {
        list.splice(...[0, list.length].concat(list.map((child) => {
          let replacement;

          if (child === replaced.first) {
            replacement = s(
              "export",
              s("send", null, "default", ...child.children)
            );

            if (_comments[child]) _comments[replacement] = _comments[child];
            return replacement
          } else {
            return child
          }
        })))
      };

      let _esm_autoexports = false;
      return process(s("begin", ...list))
    };

    function on_class(node) {
      _esm_explicit_tokens.push(node.children.first.children.last);
      return process_children(node)
    };

    function on_def(node) {
      _esm_explicit_tokens.push(node.children.first);
      return process_children(node)
    };

    function on_lvasgn(node) {
      _esm_explicit_tokens.push(node.children.first);
      return process_children(node)
    };

    function on_send(node) {
      let imports;
      let [target, method, ...args] = node.children;

      if (method === "meta" && target?.type === "send" && target.children[0] === null && target.children[1] === "import" && target.children.length === 2) {
        return process(s("attr", null, "import.meta", ...args))
      };

      if (target !== null) return process_children(node);

      if (["require", "require_relative"].includes(method) && !_esm_skip_require && _esm_top?.includes(_ast) && args.length === 1 && args[0].type === "str") {
        if (_options.file) {
          return convert_require_to_import(
            node,
            method,
            args[0].children.first
          )
        } else {
          return s("import", args[0].children.first)
        }
      };

      if (method === "import") {
        if (args.length === 0) return process_children(node);

        if (typeof node.loc === "object" && node.loc !== null && "selector" in node.loc) {
          let selector = node.loc.selector;

          if (selector?.source_buffer) {
            if (selector.source_buffer.source[selector.end_pos] === "(") {
              return process_children(node)
            }
          }
        };

        if (args[0].type === "str" && args.length === 1) {
          return s("import", args[0].children[0])
        } else if (args.length === 1 && args[0].type === "send" && args[0].children[0] === null && args[0].children[2].type === "send" && args[0].children[2].children[0] === null && args[0].children[2].children[1] === "from" && args[0].children[2].children[2].type === "str") {
          _esm_explicit_tokens.push(args[0].children[1]);

          return s(
            "import",
            [args[0].children[2].children[2].children[0]],
            process(s("attr", null, args[0].children[1]))
          )
        } else {
          imports = [];

          if (["const", "send", "str"].includes(args[0].type)) {
            _esm_explicit_tokens.push(args[0].children.last);
            imports.push(process(args.shift()))
          };

          if (args[0].type === "array") {
            for (let i of args[0].children) {
              _esm_explicit_tokens.push(i.children.last)
            };

            imports.push(process_all(args.shift().children))
          };

          if (args[0] !== null) return s("import", args[0].children, ...imports)
        }
      } else if (method === "export") {
        return s("export", ...process_all(args))
      } else if (target === null && (found_import = find_autoimport(method))) {
        prepend_list.push(s("import", found_import[0], found_import[1]));
        return process_children(node)
      } else {
        return process_children(node)
      }
    };

    // import.meta => s(:attr, nil, :"import.meta")
    // This bypasses jsvar escaping of the reserved word 'import'
    // Handle require/require_relative when Require filter is NOT present
    // Simple conversion without file analysis
    // handle import with no arguments (e.g., import.meta.url)
    // don't do the conversion if the word import is followed by a paren
    // import "file.css"
    //   => import "file.css"
    // import name from "file.js"
    //  => import name from "file.js"
    // import Stuff, "file.js"
    //   => import Stuff from "file.js"
    // import Stuff, from: "file.js"
    //   => import Stuff from "file.js"
    // import Stuff, as: "*", from: "file.js"
    //   => import Stuff as * from "file.js"
    // import [ Some, Stuff ], from: "file.js"
    //   => import { Some, Stuff } from "file.js"
    // import Some, [ More, Stuff ], from: "file.js"
    //   => import Some, { More, Stuff } from "file.js"
    function on_const(node) {
      if (node.children.first === null && (found_import = find_autoimport(node.children.last))) {
        prepend_list.push(s("import", found_import[0], found_import[1]));
        let values = _esm_defs[node.children.last];

        if (values) {
          values = Object.fromEntries(values.map(value => (
            (value ?? "").toString().startsWith("@") ? [
              (value ?? "").toString().slice(1),
              s("self")
            ] : [value, s("autobind", s("self"))]
          )));

          _namespace.defineProps(values, [node.children.last])
        }
      };

      return process_children(node)
    };

    function on_export(node) {
      return s("export", ...process_all(node.children))
    };

    // Convert require/require_relative to import statement by parsing the file
    // and detecting its exports
    function convert_require_to_import(node, method, basename) {
      let base_dirname = File.dirname(File.expand_path(_options.file));

      return collect_imports_from_file(
        base_dirname,
        basename,
        base_dirname,
        node
      )
    };

    // Recursively collect imports from a file
    function collect_imports_from_file(base_dirname, basename, current_dirname, fallback_node) {
      let imports, importname;
      let filename = File.join(current_dirname, basename);

      if (!File.file(filename) && File.file(filename + ".rb")) {
        filename += ".rb"
      } else if (!File.file(filename) && File.file(filename + ".js.rb")) {
        filename += ".js.rb"
      };

      if (!File.file(filename)) return fallback_node;
      let realpath = File.realpath(filename);

      if (_esm_require_seen[realpath]) {
        imports = _esm_require_seen[realpath];
        importname = (new Pathname(filename).relative_path_from(new Pathname(base_dirname)) ?? "").toString();
        if (!importname.startsWith(".")) importname = `./${importname ?? ""}`;
        return s("import", importname, ...imports)
      };

      let [ast, _comments] = Ruby2JS.parse(File.read(filename), filename);
      let children = ast.type === "begin" ? ast.children : [ast];
      let named_exports = [];
      let default_exports = [];
      let recursive_imports = [];
      let file_dirname = File.dirname(filename);

      for (let child of children) {
        let target;
        if (!child) continue;

        if (_esm_require_recursive && child.type === "send" && child.children[0] === null && [
          "require",
          "require_relative"
        ].includes(child.children[1]) && child.children[2]?.type === "str") {
          let nested_basename = child.children[2].children.first;

          let nested_result = collect_imports_from_file(
            base_dirname,
            nested_basename,
            file_dirname,
            null
          );

          if (nested_result) {
            if (nested_result.type === "begin") {
              recursive_imports.concat(nested_result.children)
            } else if (nested_result.type === "import") {
              recursive_imports.push(nested_result)
            }
          };

          continue
        };

        if (child.type === "send" && child.children[0] === null && child.children[1] === "export") {
          let export_child = child.children[2];

          if (export_child?.type === "send" && export_child.children[0] === null && export_child.children[1] === "default") {
            export_child = export_child.children[2];
            target = default_exports
          } else {
            target = named_exports
          };

          extract_export_names(export_child, target, default_exports)
        } else if (_esm_autoexports_option) {
          extract_export_names(child, named_exports, default_exports)
        }
      };

      if (_esm_autoexports_option === "default" && named_exports.length === 1 && default_exports.length === 0) {
        default_exports = named_exports;
        named_exports = []
      };

      default_exports.splice(...[0, default_exports.length].concat(default_exports.map(name => (
        normalize_export_name(name)
      ))));

      named_exports.splice(...[0, named_exports.length].concat(named_exports.map(name => (
        normalize_export_name(name)
      ))));

      imports = [];

      if (default_exports.length !== 0) {
        imports.push(s("const", null, default_exports.first))
      };

      if (named_exports.length !== 0) {
        imports.push(named_exports.map(id => s("const", null, id)))
      };

      _esm_require_seen[realpath] = imports;

      if (_esm_require_recursive && recursive_imports.length !== 0) {
        let all_imports = [];

        if (imports.length !== 0) {
          importname = (new Pathname(filename).relative_path_from(new Pathname(base_dirname)) ?? "").toString();
          if (!importname.startsWith(".")) importname = `./${importname ?? ""}`;
          all_imports.push(s("import", importname, ...imports))
        };

        all_imports.concat(recursive_imports);
        if (all_imports.length > 1) return s("begin", ...all_imports);
        if (all_imports.length === 1) return all_imports.first;
        return fallback_node
      };

      if (imports.length === 0) return fallback_node;
      importname = (new Pathname(filename).relative_path_from(new Pathname(base_dirname)) ?? "").toString();
      if (!importname.startsWith(".")) importname = `./${importname ?? ""}`;
      return s("import", importname, ...imports)
    };

    // If we've already seen this file, return a reference to it
    // Parse the file to find exports
    // Check for require_relative statements when require_recursive is enabled
    // Flatten nested begin nodes (multiple imports)
    // Check for explicit export statements
    // export default ...
    // Auto-export mode: export top-level definitions
    // Handle autoexports :default mode
    // Normalize export names
    // Build imports list for this file
    // Cache for future references
    // If require_recursive, return a begin node with all imports
    // Add current file's import first (before its dependencies)
    // Then add nested imports (dependencies come after)
    // If no exports found, just return the fallback (original require)
    // Generate import statement
    // Extract exportable names from an AST node
    function extract_export_names(child, named_target, default_target) {
      if (!child) return;

      if (["class", "module"].includes(child.type) && child.children[0]?.type === "const" && child.children[0].children[0] === null) {
        return named_target << child.children[0].children[1]
      } else if (child.type === "casgn" && child.children[0] === null) {
        return named_target << child.children[1]
      } else if (child.type === "def") {
        return named_target << child.children[0]
      } else if (child.type === "send" && child.children[1] === "async") {
        return named_target << child.children[2].children[0]
      } else if (child.type === "const") {
        return named_target << child.children[1]
      } else if (child.type === "array") {
        for (let export_stmt of child.children) {
          if (export_stmt.type === "const") {
            named_target.push(export_stmt.children[1])
          } else if (export_stmt.type === "hash") {
            for (let pair of export_stmt.children) {
              let key, value;

              if (pair.type === "pair") {
                let [key, value] = pair.children;

                if (key.type === "sym" && key.children[0] === "default" && value.type === "const") {
                  default_target.push(value.children[1])
                }
              }
            }
          }
        }
      }
    };

    // Handle { default: Name } syntax
    // Normalize export name (remove ?! suffix, apply camelCase if needed)
    function normalize_export_name(name) {
      name = (name ?? "").toString().replace(/[?!]$/m, "");

      if (typeof this === "object" && this !== null && "camelCase" in this) {
        name = camelCase(name)
      };

      return name
    };

    function find_autoimport(token) {
      if (_esm_autoimports === null) return null;
      if (_esm_explicit_tokens.includes(token)) return null;

      if (typeof this === "object" && this !== null && "camelCase" in this) {
        token = camelCase(token)
      };

      if (_esm_autoimports[token]) {
        return [_esm_autoimports[token], s("const", null, token)]
      } else if (found_key = Object.keys(_esm_autoimports).find(key => (
        Array && key?.includes(token)
      ))) {
        return [
          _esm_autoimports[found_key],
          found_key.map(key => s("const", null, key))
        ]
      }
    };

    return {
      initialize,
      set_options,
      process,
      on_class,
      on_def,
      on_lvasgn,
      on_send,
      on_const,
      on_export
    }
  })();

// Register the filter
DEFAULTS.push(ESM);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.ESM = ESM;

// Setup function to bind filter infrastructure
ESM._setup = function(opts) {
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
export { ESM as default, ESM };
