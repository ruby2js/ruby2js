// Transpiled Ruby2JS Filter: Functions
// Generated from ../../lib/ruby2js/filter/functions.rb
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

Object.defineProperty(Array.prototype, "compact", {
  get() {
    return this.filter(x => x !== null && x !== undefined)
  },

  configurable: true
});

Object.defineProperty(
  Array.prototype,
  "last",
  {get() {return this.at(-1)}, configurable: true}
);

if (!RegExp.escape) {
  RegExp.escape = function(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }
};

  const Functions = (() => {
    include(SEXP);

    // require explicit opt-in to call => direct invocation mapping
    // (JS uses Function.prototype.call() which would break)
    Filter.exclude("call");

    // Methods that convert only when is_method? is true (parentheses present)
    // OR when explicitly included via include: option.
    const REQUIRE_PARENS = [
      "keys",
      "values",
      "entries",
      "index",
      "rindex",
      "clear",
      "reverse!",
      "max",
      "min"
    ];

    // Check if a REQUIRE_PARENS method should convert:
    // - Always convert if node.is_method? (has parentheses)
    // - Also convert if explicitly included via include: option
    // Check if method was explicitly included via include: option
    function parens_or_included(node, method) {
      if (node.is_method()) return true;
      return explicitly_included(method)
    };

    // Check if a method was explicitly included via the include: or include_all: option
    function explicitly_included(method) {
      return _options.include_all ?? _options.include?.includes(method)
    };

    const VAR_TO_ASSIGN = {
      lvar: "lvasgn",
      ivar: "ivasgn",
      cvar: "cvasgn",
      gvar: "gvasgn"
    };

    // Helper to replace local variable references in an AST node
    function replace_lvar(node, old_name, new_name) {
      if (!Ruby2JS.ast_node(node)) return node;

      return node.type === "lvar" && node.children.first === old_name ? node.updated(
        null,
        [new_name]
      ) : node.updated(
        null,
        node.children.map(c => replace_lvar(c, old_name, new_name))
      )
    };

    function initialize(...args) {
      let _jsx = false;

    };

    // Handle empty? specially for csend - we want obj?.length === 0
    // not obj.length?.==(0)
    // process csend (safe navigation) nodes the same as send nodes
    // so method names get converted (e.g., include? -> includes)
    // then restore the csend type if needed
    // Handle &.call -> ccall (conditional call) for optional chaining
    function on_csend(node) {
      let [target, method, ...args] = node.children;

      if (method === "empty?" && args.length === 0 && !excluded(method)) {
        return process(S(
          "send",
          S("csend", target, "length"),
          "==",
          s("int", 0)
        ))
      };

      let result = on_send(node);

      if (result?.type === "send" && node.type === "csend") {
        result = result.updated("csend")
      } else if (result?.type === "call" && node.type === "csend") {
        result = result.updated("ccall")
      };

      return result
    };

    // Class.new { }.new -> object literal {}
    // Transform anonymous class instantiation to object literal
    // no inheritance
    // Extract body from block
    // Convert method definitions to hash pairs
    // Setter: def foo=(v) -> prop with set
    // Check if there's already a getter for this property
    // Merge with existing getter
    // Getter: def foo (no parens, no args) -> prop with get
    // Check if there's already a setter for this property
    // Merge with existing setter
    // Regular method with args/parens -> shorthand method syntax
    // debugger as a standalone statement -> JS debugger statement
    // typeof(x) -> typeof x (JS type checking operator)
    // hash.keys → Object.keys(hash)
    // define_method(name, block_var) inside a method body
    // -> this.constructor.prototype[name] = block_var
    // identify groups
    // rewrite regex
    // 
    // arr[-1] = x => arr[arr.length - 1] = x
    // input: arr[start..finish] = value or arr[start...finish] = value
    // output: arr.splice(start, length, ...value)
    // exclusive range: start...finish
    // no finish means to end of array
    // inclusive range: start..finish
    // start..-1 means from start to end
    // Spread the value if it's an array-like
    // (x ?? '').toString() - nil-safe conversion matching Ruby's nil.to_s => ""
    // String(x ?? '') - nil-safe conversion matching Ruby's String(nil) => ""
    // Wrap the argument in nullish coalescing, then let the converter handle it
    // Array.from(str.matchAll(/.../g), s => s.slice(1))
    // (str.match(/.../g) || []).map(s => s.match(/.../).slice(1))
    // str.match(/.../g)
    // arr.any? => arr.some(Boolean)
    // arr.all? => arr.every(Boolean)
    // arr.none? => !arr.some(Boolean)
    // target.send(:method, arg1, arg2) => target.method(arg1, arg2)
    // target.send(method_var, arg1) => target[method_var](arg1)
    // Static method name: target.send(:foo, x) => target.foo(x)
    // Dynamic method name: target.send(m, x) => target[m](x)
    // hash.has_key?(k) => k in hash
    // Ruby's join defaults to "", JS defaults to ","
    // JSON.generate(x) / JSON.dump(x) => JSON.stringify(x)
    // JSON.parse(x) / JSON.load(x) => JSON.parse(x)
    // resolve negative literal indexes
    // str[start, length] => str.slice(start, start + length)
    // Ruby's 2-arg slice: str[start, length] extracts length chars starting at start
    // Handle negative start index (only for literal integers)
    // No need for the last argument if it's -1
    // This means take all to the end of array
    // input: a.slice!(start..-1)
    // output: a.splice(start)
    // input: a.slice!(start..finish)
    // output: a.splice(start, finish - start + 1)
    // input: a.slice!(start...finish)
    // output: a.splice(start, finish - start)
    // input: a.slice!(index) or a.slice!(start, length)
    // output: a.splice(index, 1) or a.splice(start, length)
    // input: a.reverse!
    // output: a.splice(0, a.length, *a.reverse)
    // [a, b] * n => Array.from({length: n}, () => [a, b]).flat()
    // For single-element arrays: [a] * n => Array(n).fill(a)
    // Single element: Array(n).fill(element)
    // Multiple elements: Array.from({length: n}, () => [a, b]).flat()
    // Array.from with length object and mapper, then flatten
    // Use send! to force method call syntax (with parens)
    // [a, b] + [c] => [...[a, b], ...[c]] or [a, b].concat([c])
    // Using concat for clarity
    // expr + [c] where expr might be an array - use concat
    // This handles cases like Array(n).fill(x) + [y]
    // Array.isArray(obj)
    // typeof obj === "number" && Number.isInteger(obj)
    // typeof obj === "number"
    // typeof obj === "string"
    // typeof obj === "symbol"
    // typeof obj === "object" && obj !== null && !Array.isArray(obj)
    // obj === null || obj === undefined
    // obj === true
    // obj === false
    // typeof obj === "boolean"
    // typeof obj === "function"
    // obj instanceof RegExp
    // obj instanceof Error
    // User-defined classes: obj instanceof ClassName
    // instance_of? checks exact class (not subclasses)
    // obj.instance_of?(Foo) => obj.constructor === Foo
    // For Array, check constructor directly
    // typeof + isInteger + not float
    // For Float, check it's a number but NOT an integer
    // Check it's a plain object (constructor === Object)
    // User-defined classes: obj.constructor === ClassName
    // prevent chained delete methods from being converted to undef
    // array.compact -> array.filter(x => x != null)
    // This removes nil/null values from the array (non-mutating)
    // array.compact! -> array.splice(0, array.length, ...array.filter(x => x != null))
    // This mutates the array in place, removing nil/null values
    // Only convert to lastIndexOf when no block - with block, keep rindex
    // Foo.superclass => Object.getPrototypeOf(Foo.prototype).constructor
    // Only applies to constants (class names), not to variables like node.superclass
    // RegExp.escape(str) => RegExp.escape(str) for ES2025+
    // (polyfill filter handles pre-ES2025 with polyfill)
    // reduce(:+) → reduce((a, b) => a + b)
    // reduce(:merge) → reduce((a, b) => ({...a, ...b}))
    // Hash merge: spread both objects
    // Arithmetic/other operators: a.op(b) or a op b
    // .freeze → Object.freeze(target), bare freeze → Object.freeze(this)
    // .to_sym is a no-op - symbols are strings in JS
    // .reject(&:method) → .filter with negated block
    // reject(&:empty?) → filter(item => !item.empty())
    // method(:name) => this.name.bind(this) or this[name].bind(this)
    // method(:foo) => this.foo.bind(this)
    // method(name) => this[name].bind(this)
    function on_send(node) {
      let body, index, regex, tokens, groups, stack, group, prepend, append, expr, neg_index, new_index, range, value, start, finish, len, arg, pattern, gpattern, before, after, method_name, method_args, i, length, start_expr, end_expr, final, length_obj, mapper, parent, multiplier, raw, first, op, block_pass, name_arg;
      let [target, method, ...args] = node.children;
      if (excluded(method) && method !== "call") return process_children(node);

      if (method === "new" && target && target.type === "block") {
        let block_call = target.children[0];

        if (block_call.type === "send" && block_call.children[0]?.type === "const" && block_call.children[0].children === [
          null,
          "Class"
        ] && block_call.children[1] === "new" && block_call.children.length === 2) {
          body = target.children[2];
          if (body?.type === "begin") body = body.children;
          if (!Array.isArray(body)) body = [body].compact;
          let pairs = [];

          for (let m of body) {
            if (m.type !== "def") continue;
            let name = m.children[0];
            let method_args = m.children[1];
            let method_body = m.children[2];

            if ((name ?? "").toString().endsWith("=")) {
              let base_name = (name ?? "").toString().slice(0, -1);
              let setter = s("defm", null, method_args, method_body);

              let existing = pairs.find(p => (
                p.children[0].type === "prop" && p.children[0].children[0] === base_name
              ));

              if (existing) {
                delete pairs[existing];

                pairs.push(s(
                  "pair",
                  s("prop", base_name),
                  {get: existing.children[1].get, set: setter}
                ))
              } else {
                pairs.push(s("pair", s("prop", base_name), {set: setter}))
              }
            } else if (!m.is_method() && method_args.children.length === 0) {
              let getter = s(
                "defm",
                null,
                method_args,
                s("autoreturn", method_body)
              );

              let existing = pairs.find(p => (
                p.children[0].type === "prop" && p.children[0].children[0] === name
              ));

              if (existing) {
                delete pairs[existing];

                pairs.push(s(
                  "pair",
                  s("prop", name),
                  {get: getter, set: existing.children[1].set}
                ))
              } else {
                pairs.push(s("pair", s("prop", name), {get: getter}))
              }
            } else {
              pairs.push(s(
                "pair",
                s("sym", name),
                s("defm", null, method_args, method_body)
              ))
            }
          };

          return process(s("hash", ...pairs))
        }
      };

      if (method === "debugger" && target === null && args.length === 0) {
        return s("debugger")
      };

      if (method === "typeof" && target === null && args.length === 1) {
        return s("typeof", process(args.first))
      };

      if (["max", "min"].includes(method) && args.length === 0) {
        if (target.type === "array") {
          return process(S(
            "send",
            s("const", null, "Math"),
            node.children[1],
            ...target.children
          ))
        } else if (parens_or_included(node, method)) {
          return process(S(
            "send",
            s("const", null, "Math"),
            node.children[1],
            s("splat", target)
          ))
        } else {
          return process_children(node)
        }
      } else if (method === "call" && target && (["ivar", "cvar"].includes(target.type) || !excluded("call"))) {
        return S("call", process(target), null, ...process_all(args))
      } else if (method === "keys" && args.length === 0 && parens_or_included(
        node,
        method
      )) {
        return process(S("send", s("const", null, "Object"), "keys", target))
      } else if (method === "define_method" && target === null && args.length === 2) {
        return process(S(
          "send",
          s("attr", s("attr", s("self"), "constructor"), "prototype"),
          "[]=",
          args[0],
          args[1]
        ))
      } else if (method === "[]=" && args.length === 3 && args[0].type === "regexp" && args[1].type === "int") {
        index = args[1].children.first;
        regex = args[0].children.first.children.first;

        tokens = Array.from(
          RegExp.Scanner.matchAll(new RegExp(regex, "g")),
          s => s.slice(1)
        );

        groups = [];
        stack = [];

        for (let token of tokens) {
          if (token[0] !== "group") continue;

          if (token[1] === "capture") {
            groups.push(token.dup());

            if (groups.length === index && stack.length !== 0) {
              return process_children(node)
            };

            stack.push(groups.last)
          } else if (token[1] === "close") {
            stack.pop()[stack.pop().length - 1] = token.last
          }
        };

        group = groups[index - 1];
        prepend = null;
        append = null;

        if (group[4] < regex.length) {
          regex = (regex.slice(0, group[4]) + "(" + regex.slice(group[4]) + ")").replace(
            /\$\)$/m,
            ")$"
          );

          append = 2
        };

        if (group[4] - group[3] === 2) {
          regex = regex.slice(0, group[3]) + regex.slice(group[4]);
          if (append) append = 1
        };

        if (group[3] > 0) {
          regex = ("(" + regex.slice(0, group[3]) + ")" + regex.slice(group[3])).replace(
            /^\(\^/m,
            "^("
          );

          prepend = 1;
          if (append) append++
        };

        regex = process(s("regexp", s("str", regex), args[0].children.last));

        if (args.last.type === "str") {
          let str = args.last.children.first.replaceAll("$", "$$");
          if (prepend) str = `$${prepend ?? ""}${str ?? ""}`;
          if (append) str = `${str ?? ""}$${append ?? ""}`;
          expr = s("send", target, "replace", regex, s("str", str))
        } else {
          let dstr = args.last.type === "dstr" ? args.last.children.dup() : [args.last];

          if (prepend) {
            dstr.unshift(s(
              "send",
              s("lvar", "match"),
              "[]",
              s("int", prepend - 1)
            ))
          };

          if (append) {
            dstr.push(s("send", s("lvar", "match"), "[]", s("int", append - 1)))
          };

          expr = s(
            "block",
            s("send", target, "replace", regex),
            s("args", s("arg", "match")),
            process(s("dstr", ...dstr))
          )
        };

        if (Object.keys(VAR_TO_ASSIGN).includes(target.type)) {
          return S(VAR_TO_ASSIGN[target.type], target.children.first, expr)
        } else if (target.type === "send") {
          return target.children[0] === null ? S(
            "lvasgn",
            target.children[1],
            expr
          ) : S(
            "send",
            target.children[0],
            `${target.children[1] ?? ""}=`,
            expr
          )
        } else {
          return process_children(node)
        }
      } else if (method === "[]=" && args.length === 2 && args[0].type === "int" && args[0].children.first < 0) {
        neg_index = -args[0].children.first;

        new_index = S(
          "send",
          S("attr", target, "length"),
          "-",
          s("int", neg_index)
        );

        return process(S("send", target, "[]=", new_index, args[1]))
      } else if (method === "[]=" && args.length === 2 && [
        "irange",
        "erange"
      ].includes(args[0].type)) {
        range = args[0];
        value = args[1];
        let [start, finish] = range.children;

        if (range.type === "erange") {
          if (finish) {
            len = S("send", finish, "-", start)
          } else {
            len = S("send", s("attr", target, "length"), "-", start)
          }
        } else if (finish?.type === "int" && finish.children.first === -1) {
          len = S("send", s("attr", target, "length"), "-", start)
        } else if (finish) {
          len = S("send", S("send", finish, "-", start), "+", s("int", 1))
        } else {
          len = S("send", s("attr", target, "length"), "-", start)
        };

        return process(S(
          "send",
          target,
          "splice",
          start,
          len,
          s("splat", value)
        ))
      } else if (method === "merge") {
        args.unshift(target);
        return process(S("hash", ...args.map(arg => s("kwsplat", arg))))
      } else if (method === "merge!") {
        return process(S("assign", target, ...args))
      } else if (method === "delete" && args.length === 1) {
        if (!target) {
          return process(S("undef", args.first))
        } else if (args.first.type === "str") {
          return process(S(
            "undef",
            S("attr", target, args.first.children.first)
          ))
        } else {
          return process(S("undef", S("send", target, "[]", args.first)))
        }
      } else if (method === "to_s") {
        return _options.nullish_to_s && es2020 && args.length === 0 ? process(S(
          "call",
          s("begin", s("nullish", target, s("str", ""))),
          "toString"
        )) : process(S("call", target, "toString", ...args))
      } else if (method === "Array" && target === null) {
        return process(S("send", s("const", null, "Array"), "from", ...args))
      } else if (method === "String" && target === null && args.length === 1) {
        return _options.nullish_to_s && es2020 ? node.updated(null, [
          null,
          "String",
          s("begin", s("nullish", process(args.first), s("str", "")))
        ]) : process_children(node)
      } else if (method === "to_i") {
        return process(node.updated(
          "send",
          [null, "parseInt", target, ...args]
        ))
      } else if (method === "to_f") {
        return process(node.updated(
          "send",
          [null, "parseFloat", target, ...args]
        ))
      } else if (method === "to_json") {
        return process(node.updated(
          "send",
          [s("const", null, "JSON"), "stringify", target, ...args]
        ))
      } else if (method === "sub" && args.length === 2) {
        if (args[1].type === "str") {
          args[1] = s(
            "str",
            args[1].children.first.replaceAll(/\\(\d)/g, "$$1")
          )
        };

        return process(node.updated(null, [target, "replace", ...args]))
      } else if (["sub!", "gsub!"].includes(method)) {
        method = `${(method ?? "").toString().slice(0, -1) ?? ""}`;

        if (Object.keys(VAR_TO_ASSIGN).includes(target.type)) {
          return process(S(
            VAR_TO_ASSIGN[target.type],
            target.children[0],
            S("send", target, method, ...node.children.slice(2))
          ))
        } else if (target.type === "send") {
          return target.children[0] === null ? process(S(
            "lvasgn",
            target.children[1],

            S(
              "send",
              S("lvar", target.children[1]),
              method,
              ...node.children.slice(2)
            )
          )) : process(S(
            "send",
            target.children[0],
            `${target.children[1] ?? ""}=`,
            S("send", target, method, ...node.children.slice(2))
          ))
        } else {
          return process_children(node)
        }
      } else if (method === "scan" && args.length === 1) {
        arg = args.first;

        if (arg.type === "str") {
          arg = arg.updated(
            "regexp",
            [s("str", RegExp.escape(arg.children.first)), s("regopt")]
          )
        };

        if (arg.type === "regexp") {
          pattern = arg.children.first.children.first;
          pattern = pattern.replaceAll(/\\./g, "").replaceAll(/\[.*\]/g, "");

          gpattern = arg.updated("regexp", [
            ...arg.children.slice(0, -1),
            s("regopt", "g", ...(arg.children.last.children || []))
          ])
        } else {
          gpattern = s(
            "send",
            s("const", null, "RegExp"),
            "new",
            arg,
            s("str", "g")
          )
        };

        if (arg.type !== "regexp" || pattern.includes("(")) {
          return es2020 ? s(
            "send",
            s("const", null, "Array"),
            "from",
            s("send", process(target), "matchAll", gpattern),

            s(
              "block",
              s("send", null, "proc"),
              s("args", s("arg", "s")),
              s("send", s("lvar", "s"), "slice", s("int", 1))
            )
          ) : s(
            "block",

            s(
              "send",
              s("or", s("send", process(target), "match", gpattern), s("array")),
              "map"
            ),

            s("args", s("arg", "s")),

            s("return", s(
              "send",
              s("send", s("lvar", "s"), "match", arg),
              "slice",
              s("int", 1)
            ))
          )
        } else {
          return S("send", process(target), "match", gpattern)
        }
      } else if (method === "gsub" && args.length === 2) {
        let [before, after] = args;

        if (before.type === "regexp") {
          before = before.updated("regexp", [
            ...before.children.slice(0, -1),
            s("regopt", "g", ...(before.children.last.children || []))
          ])
        } else if (before.type === "str" && !es2021) {
          before = before.updated(
            "regexp",
            [s("str", RegExp.escape(before.children.first)), s("regopt", "g")]
          )
        };

        if (after.type === "str") {
          after = s("str", after.children.first.replaceAll(/\\(\d)/g, "$$1"))
        };

        return es2021 ? process(node.updated(
          null,
          [target, "replaceAll", before, after]
        )) : process(node.updated(null, [target, "replace", before, after]))
      } else if (method === "ord" && args.length === 0) {
        return target.type === "str" ? process(S(
          "int",
          target.children.last.charCodeAt(0)
        )) : process(S("send", target, "charCodeAt", s("int", 0)))
      } else if (method === "chr" && args.length === 0) {
        return target.type === "int" ? process(S(
          "str",
          String.fromCharCode(target.children.last)
        )) : process(S(
          "send",
          s("const", null, "String"),
          "fromCharCode",
          target
        ))
      } else if (method === "empty?" && args.length === 0) {
        return process(S(
          "send",
          S("attr", target, "length"),
          "==",
          s("int", 0)
        ))
      } else if (method === "nil?" && args.length === 0) {
        return process(S("send", target, "==", s("nil")))
      } else if (method === "zero?" && args.length === 0) {
        return process(S("send", target, "===", s("int", 0)))
      } else if (method === "positive?" && args.length === 0) {
        return process(S("send", target, ">", s("int", 0)))
      } else if (method === "negative?" && args.length === 0) {
        return process(S("send", target, "<", s("int", 0)))
      } else if (method === "any?" && args.length === 0) {
        return process(S("send", target, "some", s("const", null, "Boolean")))
      } else if (method === "all?" && args.length === 0) {
        return process(S(
          "send",
          target,
          "every",
          s("const", null, "Boolean")
        ))
      } else if (method === "none?" && args.length === 0) {
        return process(S(
          "send",
          S("send", target, "some", s("const", null, "Boolean")),
          "!"
        ))
      } else if (["start_with?", "end_with?"].includes(method) && args.length === 1) {
        return method === "start_with?" ? process(S(
          "send",
          target,
          "startsWith",
          ...args
        )) : process(S("send", target, "endsWith", ...args))
      } else if (method === "clear" && args.length === 0 && parens_or_included(
        node,
        method
      )) {
        return process(S("send", target, "length=", s("int", 0)))
      } else if (method === "replace" && args.length === 1) {
        return process(S(
          "begin",
          S("send", target, "length=", s("int", 0)),
          S("send", target, "push", s("splat", node.children[2]))
        ))
      } else if (method === "include?" && args.length === 1) {
        while (target.type === "begin" && target.children.length === 1) {
          target = target.children.first
        };

        if (target.type === "irange") {
          return S(
            "and",
            s("send", args.first, ">=", target.children.first),
            s("send", args.first, "<=", target.children.last)
          )
        } else if (target.type === "erange") {
          return S(
            "and",
            s("send", args.first, ">=", target.children.first),
            s("send", args.first, "<", target.children.last)
          )
        } else {
          return process(S("send", target, "includes", args.first))
        }
      } else if (method === "respond_to?" && args.length === 1) {
        return process(S("in?", args.first, target))
      } else if (method === "send" && args.length >= 1) {
        method_name = args.first;
        method_args = args.slice(1);

        return method_name.type === "sym" ? process(S(
          "send",
          target,
          method_name.children.first,
          ...method_args
        )) : process(S(
          "send!",
          S("send", target, "[]", method_name),
          null,
          ...method_args
        ))
      } else if (["has_key?", "key?", "member?"].includes(method) && args.length === 1) {
        return process(S("in?", args.first, target))
      } else if (method === "each") {
        return process(S("send", target, "forEach", ...args))
      } else if (method === "downcase" && args.length === 0) {
        return process(s("send!", target, "toLowerCase"))
      } else if (method === "upcase" && args.length === 0) {
        return process(s("send!", target, "toUpperCase"))
      } else if (method === "strip" && args.length === 0) {
        return process(s("send!", target, "trim"))
      } else if (method === "join" && args.length === 0) {
        return process(node.updated(null, [target, "join", s("str", "")]))
      } else if (node.children[0] === null && node.children[1] === "puts") {
        return process(S("send", s("attr", null, "console"), "log", ...args))
      } else if (method === "first") {
        if (node.children.length === 2) {
          return process(S("send", target, "[]", s("int", 0)))
        } else if (node.children.length === 3) {
          return process(on_send(S(
            "send",
            target,
            "[]",
            s("erange", s("int", 0), node.children[2])
          )))
        } else {
          return process_children(node)
        }
      } else if (method === "last") {
        if (node.children.length === 2) {
          return es2022 ? process(S("send", target, "at", s("int", -1))) : process(on_send(S(
            "send",
            target,
            "[]",
            s("int", -1)
          )))
        } else if (node.children.length === 3) {
          return process(S(
            "send",
            target,
            "slice",
            s("send", s("attr", target, "length"), "-", node.children[2]),
            s("attr", target, "length")
          ))
        } else {
          return process_children(node)
        }
      } else if (method === "[]" && nodesEqual(
        target,
        s("const", null, "Hash")
      )) {
        return s(
          "send",
          s("const", null, "Object"),
          "fromEntries",
          ...process_all(args)
        )
      } else if (nodesEqual(target, s("const", null, "JSON"))) {
        if (method === "generate" || method === "dump") {
          return process(node.updated(null, [target, "stringify", ...args]))
        } else if (method === "parse" || method === "load") {
          return process_children(node)
        } else {
          return process_children(node)
        }
      } else if (method === "[]") {
        i = (index) => {
          if (index.type === "int" && index.children.first < 0) {
            if (es2022) {
              return process(S("send", target, "at", index))
            } else {
              return process(S(
                "send",
                S("attr", target, "length"),
                "-",
                s("int", -index.children.first)
              ))
            }
          } else {
            return index
          }
        };

        index = args.first;

        if (!index) {
          return process_children(node)
        } else if (index.type === "regexp") {
          return es2020 ? process(S(
            "csend",
            S("send", process(target), "match", index),
            "[]",
            args[1] ?? s("int", 0)
          )) : process(S(
            "send",
            s("or", S("send", process(target), "match", index), s("array")),
            "[]",
            args[1] ?? s("int", 0)
          ))
        } else if (args.length === 2) {
          start = args[0];
          length = args[1];

          if (start.type === "int" && start.children.first < 0) {
            start_expr = S(
              "send",
              S("attr", target, "length"),
              "-",
              s("int", -start.children.first)
            )
          } else {
            start_expr = start
          };

          end_expr = S("send", start_expr, "+", length);
          return process(S("send", target, "slice", start_expr, end_expr))
        } else if (node.children.length !== 3) {
          return process_children(node)
        } else if (index.type === "int" && index.children.first < 0) {
          return process(S("send", target, "[]", i(index)))
        } else if (index.type === "erange") {
          [start, finish] = index.children;

          if (!finish) {
            return process(S("send", target, "slice", start))
          } else if (finish.type === "int") {
            return process(S("send", target, "slice", i(start), finish))
          } else {
            return process(S("send", target, "slice", i(start), i(finish)))
          }
        } else if (index.type === "irange") {
          [start, finish] = index.children;

          if (finish && finish.type === "int") {
            final = S("int", finish.children.first + 1)
          } else {
            final = S("send", finish, "+", s("int", 1))
          };

          return !finish || finish.children.first === -1 ? process(S(
            "send",
            target,
            "slice",
            start
          )) : process(S("send", target, "slice", start, final))
        } else {
          return process_children(node)
        }
      } else if (method === "slice!" && args.length === 1) {
        arg = args.first;

        if (arg.type === "irange") {
          [start, finish] = arg.children;

          if (finish?.type === "int" && finish.children.first === -1) {
            return process(S("send", target, "splice", process(start)))
          } else {
            len = S(
              "send",
              S("send", process(finish), "-", process(start)),
              "+",
              s("int", 1)
            );

            return process(S("send", target, "splice", process(start), len))
          }
        } else if (arg.type === "erange") {
          [start, finish] = arg.children;

          if (finish) {
            len = S("send", process(finish), "-", process(start));
            return process(S("send", target, "splice", process(start), len))
          } else {
            return process(S("send", target, "splice", process(start)))
          }
        } else if (args.length === 1) {
          return process(S("send", target, "splice", process(arg), s("int", 1)))
        } else {
          return process(S("send", target, "splice", ...process_all(args)))
        }
      } else if (method === "reverse!" && parens_or_included(node, method)) {
        return process(S(
          "send",
          target,
          "splice",
          s("int", 0),
          s("attr", target, "length"),
          s("splat", S("send", target, "reverse", ...node.children.slice(2)))
        ))
      } else if (method === "each_with_index") {
        return process(S("send", target, "forEach", ...args))
      } else if (method === "inspect" && args.length === 0) {
        return S(
          "send",
          s("const", null, "JSON"),
          "stringify",
          process(target)
        )
      } else if (method === "*" && target.type === "str") {
        return process(S("send", target, "repeat", args.first))
      } else if (method === "*" && target.type === "array" && args.length === 1) {
        if (target.children.length === 1) {
          return process(S(
            "send",
            s("send", s("const", null, "Array"), null, args.first),
            "fill",
            target.children.first
          ))
        } else {
          length_obj = s("hash", s("pair", s("sym", "length"), args.first));
          mapper = s("block", s("send", null, "proc"), s("args"), target);

          return process(S(
            "send!",
            s("send", s("const", null, "Array"), "from", length_obj, mapper),
            "flat"
          ))
        }
      } else if (method === "+" && target.type === "array" && args.length === 1 && args.first.type === "array") {
        return process(S("send", target, "concat", args.first))
      } else if (method === "+" && args.length === 1 && args.first.type === "array") {
        return process(S("send", target, "concat", args.first))
      } else if (["is_a?", "kind_of?"].includes(method) && args.length === 1) {
        if (args[0].type === "const") {
          parent = args[0].children.last;

          if (parent === "Array") {
            return S("send", s("const", null, "Array"), "isArray", target)
          } else if (parent === "Integer") {
            return S(
              "and",

              s(
                "send",
                s("send", null, "typeof", target),
                "===",
                s("str", "number")
              ),

              s("send", s("const", null, "Number"), "isInteger", target)
            )
          } else if (["Float", "Numeric"].includes(parent)) {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "number")
            )
          } else if (parent === "String") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "string")
            )
          } else if (parent === "Symbol") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "symbol")
            )
          } else if (parent === "Hash") {
            return S(
              "and",

              s(
                "and",

                s(
                  "send",
                  s("send", null, "typeof", target),
                  "===",
                  s("str", "object")
                ),

                s("send", target, "!==", s("nil"))
              ),

              s(
                "send",
                s("send", s("const", null, "Array"), "isArray", target),
                "!"
              )
            )
          } else if (parent === "NilClass") {
            return S(
              "or",
              s("send", target, "===", s("nil")),
              s("send", target, "===", s("send", null, "undefined"))
            )
          } else if (parent === "TrueClass") {
            return S("send", target, "===", s("true"))
          } else if (parent === "FalseClass") {
            return S("send", target, "===", s("false"))
          } else if (parent === "Boolean") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "boolean")
            )
          } else if (parent === "Proc" || parent === "Function") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "function")
            )
          } else if (parent === "Regexp") {
            return S("instanceof", target, s("const", null, "RegExp"))
          } else if (parent === "Exception" || parent === "Error") {
            return S("instanceof", target, s("const", null, "Error"))
          } else {
            return S("instanceof", target, args[0])
          }
        } else {
          return process_children(node)
        }
      } else if (method === "instance_of?" && args.length === 1) {
        if (args[0].type === "const") {
          parent = args[0].children.last;

          if (parent === "Array") {
            return S(
              "send",
              s("attr", target, "constructor"),
              "===",
              s("const", null, "Array")
            )
          } else if (parent === "Integer") {
            return S(
              "and",

              s(
                "and",

                s(
                  "send",
                  s("send", null, "typeof", target),
                  "===",
                  s("str", "number")
                ),

                s("send", s("const", null, "Number"), "isInteger", target)
              ),

              s("send", s("send", target, "%", s("int", 1)), "===", s("int", 0))
            )
          } else if (["Float", "Numeric"].includes(parent)) {
            return S(
              "and",

              s(
                "send",
                s("send", null, "typeof", target),
                "===",
                s("str", "number")
              ),

              s(
                "send",
                s("send", s("const", null, "Number"), "isInteger", target),
                "!"
              )
            )
          } else if (parent === "String") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "string")
            )
          } else if (parent === "Symbol") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "symbol")
            )
          } else if (parent === "Hash") {
            return S(
              "send",
              s("attr", target, "constructor"),
              "===",
              s("const", null, "Object")
            )
          } else if (parent === "NilClass") {
            return S(
              "or",
              s("send", target, "===", s("nil")),
              s("send", target, "===", s("send", null, "undefined"))
            )
          } else if (parent === "TrueClass") {
            return S("send", target, "===", s("true"))
          } else if (parent === "FalseClass") {
            return S("send", target, "===", s("false"))
          } else if (parent === "Boolean") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "boolean")
            )
          } else if (parent === "Proc" || parent === "Function") {
            return S(
              "send",
              s("send", null, "typeof", target),
              "===",
              s("str", "function")
            )
          } else if (parent === "Regexp") {
            return S(
              "send",
              s("attr", target, "constructor"),
              "===",
              s("const", null, "RegExp")
            )
          } else if (parent === "Exception" || parent === "Error") {
            return S(
              "send",
              s("attr", target, "constructor"),
              "===",
              s("const", null, "Error")
            )
          } else {
            return S("send", s("attr", target, "constructor"), "===", args[0])
          }
        } else {
          return process_children(node)
        }
      } else if (target && target.type === "send" && target.children[1] === "delete") {
        return S("send", target.updated("sendw"), ...node.children.slice(1))
      } else if (method === "entries" && args.length === 0 && parens_or_included(
        node,
        method
      )) {
        return process(node.updated(
          null,
          [s("const", null, "Object"), "entries", target]
        ))
      } else if (method === "values" && args.length === 0 && parens_or_included(
        node,
        method
      )) {
        return process(node.updated(
          null,
          [s("const", null, "Object"), "values", target]
        ))
      } else if (method === "rjust") {
        return process(node.updated(null, [target, "padStart", ...args]))
      } else if (method === "ljust") {
        return process(node.updated(null, [target, "padEnd", ...args]))
      } else if (method === "flatten" && args.length === 0) {
        return process(node.updated(
          null,
          [target, "flat", s("lvar", "Infinity")]
        ))
      } else if (method === "compact" && args.length === 0) {
        return process(s("send", target, "filter", s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", "x")),
          s("send", s("lvar", "x"), "!=", s("nil"))
        )))
      } else if (method === "compact!" && args.length === 0) {
        return process(s(
          "send",
          target,
          "splice",
          s("int", 0),
          s("attr", target, "length"),

          s("splat", s("send", target, "filter", s(
            "block",
            s("send", null, "proc"),
            s("args", s("arg", "x")),
            s("send", s("lvar", "x"), "!=", s("nil"))
          )))
        ))
      } else if (method === "to_h" && args.length === 0) {
        return process(node.updated(
          null,
          [s("const", null, "Object"), "fromEntries", target]
        ))
      } else if (method === "rstrip") {
        return process(node.updated(null, [target, "trimEnd", ...args]))
      } else if (method === "lstrip" && args.length === 0) {
        return process(s("send!", target, "trimStart"))
      } else if (method === "index" && parens_or_included(node, method)) {
        return process(node.updated(null, [target, "indexOf", ...args]))
      } else if (method === "rindex" && parens_or_included(node, method) && !args.some(arg => (
        arg.type === "block_pass"
      ))) {
        return process(node.updated(null, [target, "lastIndexOf", ...args]))
      } else if (method === "class" && args.length === 0 && !node.is_method()) {
        return process(node.updated("attr", [target, "constructor"]))
      } else if (method === "superclass" && args.length === 0 && target?.type === "const" && !node.is_method()) {
        return process(S(
          "attr",

          s(
            "send",
            s("const", null, "Object"),
            "getPrototypeOf",
            s("attr", target, "prototype")
          ),

          "constructor"
        ))
      } else if (method === "new" && nodesEqual(
        target,
        s("const", null, "Exception")
      )) {
        return process(S("send", s("const", null, "Error"), "new", ...args))
      } else if (method === "escape" && nodesEqual(
        target,
        s("const", null, "Regexp")
      ) && es2025) {
        return process(S(
          "send",
          s("const", null, "RegExp"),
          "escape",
          ...args
        ))
      } else if (method === "block_given?" && target === null && args.length === 0) {
        return process(process(s("lvar", "_implicitBlockYield")))
      } else if (method === "abs" && args.length === 0) {
        return process(S("send", s("const", null, "Math"), "abs", target))
      } else if (method === "round" && args.length === 0) {
        return process(S("send", s("const", null, "Math"), "round", target))
      } else if (method === "ceil" && args.length === 0) {
        return process(S("send", s("const", null, "Math"), "ceil", target))
      } else if (method === "floor" && args.length === 0) {
        return process(S("send", s("const", null, "Math"), "floor", target))
      } else if (method === "rand" && target === null) {
        if (args.length === 0) {
          return process(S("send!", s("const", null, "Math"), "random"))
        } else if (["irange", "erange"].includes(args.first.type)) {
          range = args.first;

          multiplier = s(
            "send",
            range.children.last,
            "-",
            range.children.first
          );

          if (range.children.every(child => child.type === "int")) {
            multiplier = s(
              "int",
              range.children.last.children.last - range.children.first.children.last
            );

            if (range.type === "irange") {
              multiplier = s("int", multiplier.children.first + 1)
            }
          } else if (range.type === "irange") {
            if (multiplier.children.last.type === "int") {
              let diff = multiplier.children.last.children.last - 1;

              multiplier = s(
                "send",
                ...multiplier.children.slice(0, 2),
                s("int", diff)
              );

              if (diff === 0) multiplier = multiplier.children.first;

              if (diff < 0) {
                multiplier = s("send", multiplier.children[0], "+", s("int", -diff))
              }
            } else {
              multiplier = s("send", multiplier, "+", s("int", 1))
            }
          };

          raw = s(
            "send",
            s("send", s("const", null, "Math"), "random"),
            "*",
            multiplier
          );

          first = range.children.first;

          if (first.type !== "int" || first.children.first !== 0) {
            raw = s("send", raw, "+", first)
          };

          return process(S("send", null, "parseInt", raw))
        } else {
          return process(S("send", null, "parseInt", s(
            "send",
            s("send", s("const", null, "Math"), "random"),
            "*",
            args.first
          )))
        }
      } else if (method === "sum" && args.length === 0) {
        return process(S(
          "send",
          target,
          "reduce",

          s(
            "block",
            s("send", null, "proc"),
            s("args", s("arg", "a"), s("arg", "b")),
            s("send", s("lvar", "a"), "+", s("lvar", "b"))
          ),

          s("int", 0)
        ))
      } else if (["reduce", "inject"].includes(method) && args.length === 1 && args[0].type === "sym") {
        op = args[0].children[0];

        return op === "merge" ? process(S("send", target, "reduce", s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", "a"), s("arg", "b")),
          s("hash", s("kwsplat", s("lvar", "a")), s("kwsplat", s("lvar", "b")))
        ))) : process(S("send", target, "reduce", s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", "a"), s("arg", "b")),
          s("send", s("lvar", "a"), op, s("lvar", "b"))
        )))
      } else if (method === "method_defined?" && args.length >= 1) {
        if (nodesEqual(args[1], s("false"))) {
          return process(S(
            "send",
            s("attr", target, "prototype"),
            "hasOwnProperty",
            args[0]
          ))
        } else if (args.length === 1 || nodesEqual(args[1], s("true"))) {
          return process(S("in?", args[0], s("attr", target, "prototype")))
        } else {
          return process(S(
            "if",
            args[1],
            s("in?", args[0], s("attr", target, "prototype")),
            s("send", s("attr", target, "prototype"), "hasOwnProperty", args[0])
          ))
        }
      } else if (method === "alias_method" && args.length === 2) {
        return process(S(
          "send",
          s("attr", target, "prototype"),
          "[]=",
          args[0],
          s("attr", s("attr", target, "prototype"), args[1].children[0])
        ))
      } else if (method === "new" && args.length === 2 && nodesEqual(
        target,
        s("const", null, "Array")
      )) {
        return s(
          "send",
          S("send", target, "new", args.first),
          "fill",
          args.last
        )
      } else if (method === "freeze" && args.length === 0) {
        return process(S(
          "send",
          s("const", null, "Object"),
          "freeze",
          target ?? s("self")
        ))
      } else if (method === "to_sym" && args.length === 0) {
        return process(target)
      } else if (method === "reject" && args.length === 1 && args[0]?.type === "block_pass") {
        block_pass = args[0];

        if (block_pass.children[0]?.type === "sym") {
          let method_sym = block_pass.children[0].children[0];
          arg = s("arg", "item");

          body = s(
            "send",
            s("begin", s("send", s("lvar", "item"), method_sym)),
            "!"
          );

          let new_block = s(
            "block",
            s("send", target, "filter"),
            s("args", arg),
            s("autoreturn", body)
          );

          return process(new_block)
        };

        return process_children(node)
      } else if (method === "chars" && args.length === 0) {
        return S("send", s("const", null, "Array"), "from", target)
      } else if (method === "method" && target === null && args.length === 1) {
        name_arg = args.first;

        return name_arg.type === "sym" ? process(S(
          "send",
          s("attr", s("self"), name_arg.children.first),
          "bind",
          s("self")
        )) : process(S(
          "send",
          s("send", s("self"), "[]", name_arg),
          "bind",
          s("self")
        ))
      } else {
        return process_children(node)
      }
    };

    // compact with a block is NOT the array compact method
    // (e.g., serializer.compact { ... } should not become filter)
    // Skip on_send processing by constructing the call node directly
    // arr.reject { |x| cond } => arr.filter(x => !(cond))
    // Process the body first, then negate - use :send with :! to wrap
    // arr.none? { |x| cond } => !arr.some(x => cond)
    // Ruby's flat_map → JavaScript's flatMap
    // array.group_by { |x| x.category }
    // array.group_by { |k, v| k.to_s }  # with destructuring
    // Check if we have multiple args (destructuring case)
    // Multiple args: use destructuring and push the whole item as array
    // Create mlhs for destructuring: ([a, b]) => ...
    // Push the reconstructed array [a, b]
    // Single arg: simple case
    // ES2024+: Object.groupBy(array, x => x.category)
    // For destructuring, wrap args in mlhs: ([a, b]) => ...
    // Pre-ES2024: array.reduce((acc, x) => { const key = ...; (acc[key] = acc[key] || []).push(x); return acc }, {})
    // Build: (acc[key] = acc[key] || []).push(item)
    // Build the reduce block body
    // array.sort_by { |x| x.name } => array.slice().sort((a, b) => ...)
    // With ES2023+: array.toSorted((a, b) => ...)
    // Create two argument names for the comparison function
    // Replace references to the block argument with arg_a and arg_b
    // Build comparison: key_a < key_b ? -1 : key_a > key_b ? 1 : 0
    // Use toSorted for ES2023+
    // Use slice().sort() for older versions
    // Use :send! for slice to force method call output
    // array.max_by { |x| x.score } => array.reduce((a, b) => key(a) > key(b) ? a : b)
    // Build: a, b => key(a) >= key(b) ? a : b
    // array.min_by { |x| x.score } => array.reduce((a, b) => key(a) <= key(b) ? a : b)
    // Build: a, b => key(a) <= key(b) ? a : b
    // (a..b).map { |i| ... }
    // Calculate length: end - start + 1 for irange, end - start for erange
    // (0..n) or (0...n) - length is just end+1 or end
    // Both are literals - compute length
    // (1..n) - length is just n
    // General case: end - start + 1 (irange) or end - start (erange)
    // If starting from 0, use simpler form: Array.from({length}, (_, i) => ...)
    // General case: need to offset the index
    // Array.from({length}, (_, $i) => { let i = $i + start; return ... })
    // For destructuring (multiple args), wrap in mlhs: ([a, b]) => ...
    // input: a.map! {expression}
    // output: a.splice(0, a.length, *a.map {expression})
    // input: loop {statements}
    // output: while(true) {statements}
    // input: n.times { |i| ... }
    // output: for (let i = 0; i < n; i++) { ... }
    // If no block variable provided, create a dummy one
    // Convert to range iteration: (0...n).each { |var| body }
    // restore delete methods that are prematurely mapped to undef
    // (a..b).step(n) {|v| ...}
    // i.step(j, n).each {|v| ...}
    // (a..b).each {|v| ...}
    // Object.entries(a).forEach(([key, value]) => {})
    // Requires explicit receiver (receiver is added by on_class for calls without one)
    // array.each_with_index { |item, i| ... } => array.forEach((item, i) => ...)
    function on_block(node) {
      let block, target, processed_call, processed_body, negated_body, some_result, args, block_body, item_to_push, reduce_arg, arg_name, callback_args, callback, acc_key, acc_key_or_empty, assign_and_push, reduce_body, reduce_block, arg_a, arg_b, key_a, key_b, comparison, compare_block, range, start_node, end_node, length, temp_var, callback_body, processed_args, count, result, step;
      let call = node.children.first;
      let method = call.children[1];
      if (excluded(method)) return process_children(node);

      if (["setInterval", "setTimeout", "set_interval", "set_timeout"].includes(method)) {
        if (call.children.first !== null) return process_children(node);

        block = process(s(
          "block",
          s("send", null, "proc"),
          ...node.children.slice(1)
        ));

        return on_send(call.updated(
          null,
          [...call.children.slice(0, 2), block, ...call.children.slice(2)]
        ))
      } else if (["sub", "gsub", "sub!", "gsub!", "sort!"].includes(method)) {
        if (call.children.first === null) return process_children(node);

        block = s(
          "block",
          s("send", null, "proc"),
          node.children[1],
          s("autoreturn", ...node.children.slice(2))
        );

        return process(call.updated(null, [...call.children, block]))
      } else if (method === "compact" && call.children.length === 2) {
        target = call.children.first;
        processed_call = call.updated(null, [process(target), "compact"]);

        return node.updated(null, [
          processed_call,
          process(node.children[1]),
          ...process_all(node.children.slice(2))
        ])
      } else if (method === "select" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "filter"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "reject" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "filter"]);
        processed_body = process_all(node.children.slice(2));
        negated_body = s("send", s("begin", ...processed_body), "!");

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", negated_body)
        ])
      } else if (method === "any?" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "some"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "all?" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "every"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "none?" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "some"]);

        some_result = node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ]);

        return s("send", some_result, "!")
      } else if (method === "find" && call.children.length === 2) {
        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "flat_map" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "flatMap"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "group_by" && call.children.length === 2) {
        target = call.children.first;
        args = node.children[1];
        block_body = node.children[2];

        if (args.children.length > 1) {
          let arg_names = args.children.map(arg => arg.children.first);
          let mlhs_arg = s("mlhs", ...args.children);
          item_to_push = s("array", ...arg_names.map(name => s("lvar", name)));
          reduce_arg = s("args", s("arg", "$acc"), mlhs_arg)
        } else {
          arg_name = args.children.first.children.first;
          item_to_push = s("lvar", arg_name);
          reduce_arg = s("args", s("arg", "$acc"), s("arg", arg_name))
        };

        if (es2024) {
          callback_args = args.children.length > 1 ? s(
            "args",
            s("mlhs", ...args.children)
          ) : node.children[1];

          callback = s(
            "block",
            s("send", null, "proc"),
            callback_args,
            s("autoreturn", ...node.children.slice(2))
          );

          return process(s(
            "send",
            s("const", null, "Object"),
            "groupBy",
            target,
            callback
          ))
        } else {
          acc_key = s("send", s("lvar", "$acc"), "[]", s("lvar", "$key"));
          acc_key_or_empty = s("or", acc_key, s("array"));

          assign_and_push = s(
            "send",

            s(
              "send",
              s("lvar", "$acc"),
              "[]=",
              s("lvar", "$key"),
              acc_key_or_empty
            ),

            "push",
            item_to_push
          );

          reduce_body = s(
            "begin",
            s("lvasgn", "$key", block_body),
            assign_and_push,
            s("return", s("lvar", "$acc"))
          );

          reduce_block = s(
            "block",
            s("send", null, "proc"),
            reduce_arg,
            reduce_body
          );

          return process(s("send", target, "reduce", reduce_block, s("hash")))
        }
      } else if (method === "sort_by" && call.children.length === 2) {
        target = call.children.first;
        args = node.children[1];
        block_body = node.children[2];
        arg_name = args.children.first.children.first;
        arg_a = `${arg_name ?? ""}_a`;
        arg_b = `${arg_name ?? ""}_b`;
        key_a = replace_lvar(block_body, arg_name, arg_a);
        key_b = replace_lvar(block_body, arg_name, arg_b);

        comparison = s(
          "if",
          s("send", key_a, "<", key_b),
          s("int", -1),
          s("if", s("send", key_a, ">", key_b), s("int", 1), s("int", 0))
        );

        compare_block = s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", arg_a), s("arg", arg_b)),
          s("autoreturn", comparison)
        );

        return es2023 ? process(s("send", target, "toSorted", compare_block)) : process(s(
          "send",
          s("send!", target, "slice"),
          "sort",
          compare_block
        ))
      } else if (method === "max_by" && call.children.length === 2) {
        target = call.children.first;
        args = node.children[1];
        block_body = node.children[2];
        arg_name = args.children.first.children.first;
        key_a = replace_lvar(block_body, arg_name, "a");
        key_b = replace_lvar(block_body, arg_name, "b");

        comparison = s(
          "if",
          s("send", key_a, ">=", key_b),
          s("lvar", "a"),
          s("lvar", "b")
        );

        reduce_block = s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", "a"), s("arg", "b")),
          s("autoreturn", comparison)
        );

        return process(s("send", target, "reduce", reduce_block))
      } else if (method === "min_by" && call.children.length === 2) {
        target = call.children.first;
        args = node.children[1];
        block_body = node.children[2];
        arg_name = args.children.first.children.first;
        key_a = replace_lvar(block_body, arg_name, "a");
        key_b = replace_lvar(block_body, arg_name, "b");

        comparison = s(
          "if",
          s("send", key_a, "<=", key_b),
          s("lvar", "a"),
          s("lvar", "b")
        );

        reduce_block = s(
          "block",
          s("send", null, "proc"),
          s("args", s("arg", "a"), s("arg", "b")),
          s("autoreturn", comparison)
        );

        return process(s("send", target, "reduce", reduce_block))
      } else if (method === "find_index" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "findIndex"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "index" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "findIndex"]);

        return node.updated(null, [
          process(call),
          process(node.children[1]),
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (method === "map" && call.children[0].type === "begin" && call.children[0].children.length === 1 && [
        "irange",
        "erange"
      ].includes(call.children[0].children[0].type) && node.children[1].children.length === 1) {
        range = call.children[0].children[0];
        start_node = range.children[0];
        end_node = range.children[1];
        arg_name = node.children[1].children[0].children[0];
        block_body = node.children[2];

        if (start_node.type === "int" && start_node.children[0] === 0) {
          length = range.type === "irange" ? s(
            "send",
            end_node,
            "+",
            s("int", 1)
          ) : end_node
        } else if (start_node.type === "int" && end_node.type === "int") {
          let len_val = end_node.children[0] - start_node.children[0];
          if (range.type === "irange") len_val++;
          length = s("int", len_val)
        } else if (start_node.type === "int" && start_node.children[0] === 1 && range.type === "irange") {
          length = end_node
        } else {
          length = s("send", end_node, "-", start_node);
          if (range.type === "irange") length = s("send", length, "+", s("int", 1))
        };

        if (start_node.type === "int" && start_node.children[0] === 0) {
          callback = s(
            "block",
            s("send", null, "proc"),
            s("args", s("arg", "_"), s("arg", arg_name)),
            s("autoreturn", block_body)
          );

          return process(s(
            "send",
            s("const", null, "Array"),
            "from",
            s("hash", s("pair", s("sym", "length"), length)),
            callback
          ))
        } else {
          temp_var = `$${arg_name ?? ""}`;

          callback_body = s(
            "begin",

            s(
              "lvasgn",
              arg_name,
              s("send", s("lvar", temp_var), "+", start_node)
            ),

            s("autoreturn", block_body)
          );

          callback = s(
            "block",
            s("send", null, "proc"),
            s("args", s("arg", "_"), s("arg", temp_var)),
            callback_body
          );

          return process(s(
            "send",
            s("const", null, "Array"),
            "from",
            s("hash", s("pair", s("sym", "length"), length)),
            callback
          ))
        }
      } else if (method === "map" && call.children.length === 2) {
        args = node.children[1];

        processed_args = args.children.length > 1 ? s(
          "args",
          s("mlhs", ...args.children)
        ) : process(args);

        return node.updated(null, [
          process(call),
          processed_args,
          s("autoreturn", ...process_all(node.children.slice(2)))
        ])
      } else if (["map!", "select!"].includes(method)) {
        method = method === "map!" ? "map" : "select";
        target = call.children.first;

        return process(call.updated("send", [target, "splice", s("splat", s(
          "send",
          s("array", s("int", 0), s("attr", target, "length")),
          "concat",

          s(
            "block",
            s("send", target, method, ...call.children.slice(2)),
            ...node.children.slice(1)
          )
        ))]))
      } else if (nodesEqual(node.children[0], s("send", null, "loop")) && nodesEqual(
        node.children[1],
        s("args")
      )) {
        return S("while", s("true"), process(node.children[2]))
      } else if (method === "times" && call.children.length === 2) {
        count = call.children[0];

        if (node.children[1].children.length === 0) {
          args = s("args", s("arg", "_"))
        } else {
          args = node.children[1]
        };

        return process(node.updated(null, [
          s("send", s("begin", s("erange", s("int", 0), count)), "each"),
          args,
          node.children[2]
        ]))
      } else if (method === "delete") {
        result = process_children(node);

        if (result.children[0].type === "undef") {
          call = result.children[0].children[0];

          if (call.type === "attr") {
            call = call.updated(
              "send",
              [call.children[0], "delete", s("str", call.children[1])]
            );

            result = result.updated(null, [call, ...result.children.slice(1)])
          } else {
            call = call.updated(
              null,
              [call.children[0], "delete", ...call.children.slice(2)]
            );

            result = result.updated(null, [call, ...result.children.slice(1)])
          }
        };

        return result
      } else if (method === "downto") {
        range = s("irange", call.children[0], call.children[2]);
        call = call.updated(null, [s("begin", range), "step", s("int", -1)]);
        return process(node.updated(null, [call, ...node.children.slice(1)]))
      } else if (method === "upto") {
        range = s("irange", call.children[0], call.children[2]);
        call = call.updated(null, [s("begin", range), "step", s("int", 1)]);
        return process(node.updated(null, [call, ...node.children.slice(1)]))
      } else if (method === "step" && call.children[0].type === "begin" && call.children[0].children.length === 1 && [
        "irange",
        "erange"
      ].includes(call.children[0].children[0].type) && node.children[1].children.length === 1) {
        range = call.children[0].children[0];
        step = call.children[2] ?? s("int", 1);

        return process(s(
          "for",
          s("lvasgn", node.children[1].children[0].children[0]),
          s("send", range, "step", step),
          node.children[2]
        ))
      } else if (method === "each" && call.children[0].type === "send" && call.children[0].children[1] === "step") {
        range = call.children[0];
        step = range.children[3] ?? s("int", 1);

        call = call.updated(null, [
          s("begin", s("irange", range.children[0], range.children[2])),
          "step",
          step
        ]);

        return process(node.updated(null, [call, ...node.children.slice(1)]))
      } else if (method === "each" && call.children[0].type === "begin" && call.children[0].children.length === 1 && [
        "irange",
        "erange"
      ].includes(call.children[0].children[0].type) && node.children[1].children.length === 1) {
        return process(s(
          "for",
          s("lvasgn", node.children[1].children[0].children[0]),
          call.children[0].children[0],
          node.children[2]
        ))
      } else if (["each", "each_value"].includes(method)) {
        if (node.children[1].children.length > 1) {
          return process(node.updated("for_of", [
            s(
              "mlhs",
              ...node.children[1].children.map(child => s("lvasgn", child.children[0]))
            ),

            node.children[0].children[0],
            node.children[2]
          ]))
        } else if (node.children[1].children[0].type === "mlhs") {
          return process(node.updated("for_of", [
            s("mlhs", ...node.children[1].children[0].children.map(child => (
              s("lvasgn", child.children[0])
            ))),

            node.children[0].children[0],
            node.children[2]
          ]))
        } else {
          return process(node.updated("for_of", [
            s("lvasgn", node.children[1].children[0].children[0]),
            node.children[0].children[0],
            node.children[2]
          ]))
        }
      } else if (method === "each_key" && ["each", "each_key"].includes(method) && node.children[1].children.length === 1) {
        return process(node.updated("for", [
          s("lvasgn", node.children[1].children[0].children[0]),
          node.children[0].children[0],
          node.children[2]
        ]))
      } else if (method === "inject") {
        return process(node.updated("send", [
          call.children[0],
          "reduce",
          s("block", s("send", null, "lambda"), ...node.children.slice(1, 3)),
          ...call.children.slice(2)
        ]))
      } else if (method === "each_pair" && node.children[1].children.length === 2) {
        return process(node.updated(null, [
          s(
            "send",
            s("send", s("const", null, "Object"), "entries", call.children[0]),
            "each"
          ),

          node.children[1],
          node.children[2]
        ]))
      } else if (method === "scan" && call.children.length === 3) {
        return process(call.updated(null, [
          ...call.children,
          s("block", s("send", null, "proc"), ...node.children.slice(1))
        ]))
      } else if (method === "yield_self" && call.children.length === 2) {
        return process(node.updated("send", [
          s(
            "block",
            s("send", null, "proc"),
            node.children[1],
            s("autoreturn", node.children[2])
          ),

          "[]",
          call.children[0]
        ]))
      } else if (method === "tap" && call.children.length === 2) {
        return process(node.updated("send", [
          s("block", s("send", null, "proc"), node.children[1], s(
            "begin",
            node.children[2],
            s("return", s("lvar", node.children[1].children[0].children[0]))
          )),

          "[]",
          call.children[0]
        ]))
      } else if (method === "define_method" && call.children.length === 3 && call.children[0]) {
        return process(node.updated("send", [
          s("attr", call.children[0], "prototype"),
          "[]=",
          call.children[2],
          s("deff", null, ...node.children.slice(1))
        ]))
      } else if (method === "each_with_index" && call.children.length === 2) {
        call = call.updated(null, [call.children.first, "forEach"]);

        return node.updated(
          null,
          [process(call), ...node.children.slice(1).map(c => process(c))]
        )
      } else {
        return process_children(node)
      }
    };

    // Recursively add class name as receiver to define_method and method_defined? calls
    // This handles define_method/method_defined? inside loops like:
    //   %i[a b].each { |t| define_method(t) { ... } unless method_defined?(t) }
    // Recursively process children
    function add_class_receiver(node, class_name) {
      if (!ast_node(node)) return node;

      if (node.type === "block") {
        let call = node.children.first;

        if (call.type === "send" && call.children[0] === null && call.children[1] === "define_method") {
          let new_call = call.updated(
            "send",
            [class_name, ...call.children.slice(1)]
          );

          return node.updated("block", [
            new_call,
            ...node.children.slice(1).map(c => add_class_receiver(c, class_name))
          ])
        }
      } else if (node.type === "send" && node.children[0] === null && node.children[1] === "method_defined?") {
        return node.updated("send", [class_name, ...node.children.slice(1)])
      };

      let new_children = node.children.map(child => (
        ast_node(child) ? add_class_receiver(child, class_name) : child
      ));

      return new_children !== node.children ? node.updated(
        null,
        new_children
      ) : node
    };

    // alias_method without receiver -> add class name as receiver
    // method_defined? without receiver -> add class name as receiver
    // define_method without receiver -> add class name as receiver
    // Recursively search for define_method/method_defined? inside nested blocks (e.g., .each loops)
    // Process children of begin node (class body wrapped in begin)
    function on_class(node) {
      let [name, inheritance, ...body] = node.children;
      body.splice(0, body.length, ...body.filter(x => x !== null));

      body.forEach((child, i) => {
        if (child.type === "send" && child.children[0] === null && child.children[1] === "alias_method") {
          body[i] = child.updated("send", [name, ...child.children.slice(1)])
        } else if (child.type === "send" && child.children[0] === null && child.children[1] === "method_defined?") {
          body[i] = child.updated("send", [name, ...child.children.slice(1)])
        } else if (child.type === "block") {
          let call = child.children.first;

          if (call.type === "send" && call.children[0] === null && call.children[1] === "define_method") {
            let new_call = call.updated(
              "send",
              [name, ...call.children.slice(1)]
            );

            body[i] = child.updated(
              "block",
              [new_call, ...child.children.slice(1)]
            )
          } else {
            body[i] = add_class_receiver(child, name)
          }
        } else if (child.type === "begin") {
          body[i] = add_class_receiver(child, name)
        }
      });

      if (nodesEqual(inheritance, s("const", null, "Exception"))) {
        if (!body.some(statement => (
          statement.type === "def" && statement.children.first === "initialize"
        ))) {
          body.unshift(s(
            "def",
            "initialize",
            s("args", s("arg", "message")),

            s(
              "begin",
              s("send", s("self"), "message=", s("lvar", "message")),
              s("send", s("self"), "name=", s("sym", name.children[1])),

              s(
                "send",
                s("self"),
                "stack=",
                s("attr", s("send", null, "Error", s("lvar", "message")), "stack")
              )
            )
          ))
        };

        if (body.length > 1) body = [s("begin", ...body)];
        return S("class", name, s("const", null, "Error"), ...body)
      } else {
        if (body.length > 1) body = [s("begin", ...body)];
        return process(S("class", name, inheritance, ...body))
      }
    };

    return {
      REQUIRE_PARENS,
      parens_or_included,
      explicitly_included,
      VAR_TO_ASSIGN,
      replace_lvar,
      initialize,
      on_csend,
      on_send,
      on_block,
      add_class_receiver,
      on_class
    }
  })();

// Register the filter
DEFAULTS.push(Functions);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.Functions = Functions;

// Setup function to bind filter infrastructure
Functions._setup = function(opts) {
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
export { Functions as default, Functions };
