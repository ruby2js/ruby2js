// Transpiled Ruby2JS Filter: Node
// Generated from ../../lib/ruby2js/filter/node.rb
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

Ruby2JS.module_default ??= "cjs";

  const Node = (() => {
    include(SEXP);
    extend(SEXP);

    const IMPORT_CHILD_PROCESS = s(
      "import",
      ["child_process"],
      s("attr", null, "child_process")
    );

    const IMPORT_FS = s("import", ["fs"], s("attr", null, "fs"));
    const IMPORT_OS = s("import", ["os"], s("attr", null, "os"));
    const IMPORT_PATH = s("import", ["path"], s("attr", null, "path"));

    const SETUP_ARGV = s("lvasgn", "ARGV", s(
      "send",
      s("attr", s("attr", null, "process"), "argv"),
      "slice",
      s("int", 2)
    ));

    function on_send(node) {
      let list, prefix;
      let [target, method, ...args] = node.children;

      if (target === null) {
        if (method === "__dir__" && args.length === 0) {
          return S("attr", null, "__dirname")
        } else if (method === "exit" && args.length <= 1) {
          return s(
            "send",
            s("attr", null, "process"),
            "exit",
            ...process_all(args)
          )
        } else if (method === "system") {
          prepend_list.push(IMPORT_CHILD_PROCESS);

          return args.length === 1 ? S(
            "send",
            s("attr", null, "child_process"),
            "execSync",
            process(args.first),
            s("hash", s("pair", s("sym", "stdio"), s("str", "inherit")))
          ) : S(
            "send",
            s("attr", null, "child_process"),
            "execFileSync",
            process(args.first),
            s("array", ...process_all(args.slice(1))),
            s("hash", s("pair", s("sym", "stdio"), s("str", "inherit")))
          )
        } else if (method === "require" && args.length === 1 && args.first.type === "str" && [
          "fileutils",
          "tmpdir"
        ].includes(args.first.children.first)) {
          return s("begin")
        } else {
          return process_children(node)
        }
      } else if (["File", "IO"].includes(target.children.last) && target.type === "const" && target.children.first === null) {
        if (method === "read" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "readFileSync",
            ...process_all(args),
            s("str", "utf8")
          )
        } else if (method === "write" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "writeFileSync",
            ...process_all(args)
          )
        } else if (target.children.last === "IO") {
          return process_children(node)
        } else if (["exist?", "exists?"].includes(method) && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "existsSync",
            process(args.first)
          )
        } else if (method === "readlink" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "readlinkSync",
            process(args.first)
          )
        } else if (method === "realpath" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "realpathSync",
            process(args.first)
          )
        } else if (method === "rename" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "renameSync",
            ...process_all(args)
          )
        } else if (["chmod", "lchmod"].includes(method) && args.length > 1 && args.first.type === "int") {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...args.slice(1).map(file => (
            S(
              "send",
              s("attr", null, "fs"),
              (method ?? "").toString() + "Sync",
              process(file),
              s("octal", ...args.first.children)
            )
          )))
        } else if (["chown", "lchown"].includes(method) && args.length > 2 && args[0].type === "int" && args[1].type === "int") {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...args.slice(2).map(file => (
            s(
              "send",
              s("attr", null, "fs"),
              (method ?? "").toString() + "Sync",
              process(file),
              ...process_all(args.slice(0, 2))
            )
          )))
        } else if (["ln", "link"].includes(method) && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return s(
            "send",
            s("attr", null, "fs"),
            "linkSync",
            ...process_all(args)
          )
        } else if (method === "symlink" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "symlinkSync",
            ...process_all(args)
          )
        } else if (method === "truncate" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "truncateSync",
            ...process_all(args)
          )
        } else if (["stat", "lstat"].includes(method) && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            (method ?? "").toString() + "Sync",
            process(args.first)
          )
        } else if (method === "unlink" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...args.map(file => (
            S("send", s("attr", null, "fs"), "unlinkSync", process(file))
          )))
        } else if (target.children.last === "File") {
          if (method === "absolute_path") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "resolve",
              ...process_all(args.reverse())
            )
          } else if (method === "absolute_path?") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "isAbsolute",
              ...process_all(args)
            )
          } else if (method === "basename") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "basename",
              ...process_all(args)
            )
          } else if (method === "dirname") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "dirname",
              ...process_all(args)
            )
          } else if (method === "extname") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "extname",
              ...process_all(args)
            )
          } else if (method === "join") {
            prepend_list.push(IMPORT_PATH);

            return S(
              "send",
              s("attr", null, "path"),
              "join",
              ...process_all(args)
            )
          } else {
            return process_children(node)
          }
        } else {
          return process_children(node)
        }
      } else if (target.children.last === "FileUtils" && target.type === "const" && target.children.first === null) {
        list = arg => arg.type === "array" ? arg.children : [arg];

        if (["cp", "copy"].includes(method) && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return s(
            "send",
            s("attr", null, "fs"),
            "copyFileSync",
            ...process_all(args)
          )
        } else if (["mv", "move"].includes(method) && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "renameSync",
            ...process_all(args)
          )
        } else if (method === "mkdir" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.last].map(file => (
            s("send", s("attr", null, "fs"), "mkdirSync", process(file))
          )))
        } else if (method === "cd" && args.length === 1) {
          return S(
            "send",
            s("attr", null, "process"),
            "chdir",
            ...process_all(args)
          )
        } else if (method === "pwd" && args.length === 0) {
          return S("send!", s("attr", null, "process"), "cwd")
        } else if (method === "rmdir" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.last].map(file => (
            s("send", s("attr", null, "fs"), "rmdirSync", process(file))
          )))
        } else if (method === "ln" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "linkSync",
            ...process_all(args)
          )
        } else if (method === "ln_s" && args.length === 2) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "symlinkSync",
            ...process_all(args)
          )
        } else if (method === "rm" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.last].map(file => (
            s("send", s("attr", null, "fs"), "unlinkSync", process(file))
          )))
        } else if (method === "chmod" && args.length === 2 && args.first.type === "int") {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.last].map(file => (
            S(
              "send",
              s("attr", null, "fs"),
              (method ?? "").toString() + "Sync",
              process(file),
              s("octal", ...args.first.children)
            )
          )))
        } else if (method === "chown" && args.length === 3 && args[0].type === "int" && args[1].type === "int") {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.last].map(file => (
            s(
              "send",
              s("attr", null, "fs"),
              (method ?? "").toString() + "Sync",
              process(file),
              ...process_all(args.slice(0, 2))
            )
          )))
        } else if (method === "touch") {
          prepend_list.push(IMPORT_FS);

          return S("begin", ...list[args.first].map(file => (
            S(
              "send",
              s("attr", null, "fs"),
              "closeSync",
              s("send", s("attr", null, "fs"), "openSync", file, s("str", "w"))
            )
          )))
        } else {
          return process_children(node)
        }
      } else if (target.type === "const" && target.children.first === null && target.children.last === "Dir") {
        if (method === "chdir" && args.length === 1) {
          return S(
            "send",
            s("attr", null, "process"),
            "chdir",
            ...process_all(args)
          )
        } else if (method === "pwd" && args.length === 0) {
          return S("send!", s("attr", null, "process"), "cwd")
        } else if (method === "entries") {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "readdirSync",
            ...process_all(args)
          )
        } else if (method === "mkdir" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "mkdirSync",
            process(args.first)
          )
        } else if (method === "rmdir" && args.length === 1) {
          prepend_list.push(IMPORT_FS);

          return S(
            "send",
            s("attr", null, "fs"),
            "rmdirSync",
            process(args.first)
          )
        } else if (method === "mktmpdir" && args.length <= 1) {
          prepend_list.push(IMPORT_FS);

          if (args.length === 0) {
            prefix = s("str", "d")
          } else if (args.first.type === "array") {
            prefix = args.first.children.first
          } else {
            prefix = args.first
          };

          return S(
            "send",
            s("attr", null, "fs"),
            "mkdtempSync",
            process(prefix)
          )
        } else if (method === "home" && args.length === 0) {
          prepend_list.push(IMPORT_OS);
          return S("send!", s("attr", null, "os"), "homedir")
        } else if (method === "tmpdir" && args.length === 0) {
          prepend_list.push(IMPORT_OS);
          return S("send!", s("attr", null, "os"), "tmpdir")
        } else {
          return process_children(node)
        }
      } else {
        return process_children(node)
      }
    };

    function on_block(node) {
      let call = node.children.first;
      let [target, method, ...args] = call.children;

      return method === "chdir" && args.length === 1 && target.children.last === "Dir" && target.type === "const" && target.children.first === null ? s(
        "begin",
        s("gvasgn", "$oldwd", s("send", s("attr", null, "process"), "cwd")),

        s("kwbegin", s(
          "ensure",
          s("begin", process(call), process(node.children.last)),
          s("send", s("attr", null, "process"), "chdir", s("gvar", "$oldwd"))
        ))
      ) : process_children(node)
    };

    function on_const(node) {
      if (node.children === [null, "ARGV"]) {
        prepend_list.push(SETUP_ARGV);
        return process_children(node)
      } else if (node.children === [null, "ENV"]) {
        return S("attr", s("attr", null, "process"), "env")
      } else if (node.children === [null, "STDIN"]) {
        return S("attr", s("attr", null, "process"), "stdin")
      } else if (node.children === [null, "STDOUT"]) {
        return S("attr", s("attr", null, "process"), "stdout")
      } else if (node.children === [null, "STDERR"]) {
        return S("attr", s("attr", null, "process"), "stderr")
      } else if (nodesEqual(node.children.first, s("const", null, "File"))) {
        if (node.children.last === "SEPARATOR") {
          prepend_list.push(IMPORT_PATH);
          return S("attr", s("attr", null, "path"), "sep")
        } else if (node.children.last === "PATH_SEPARATOR") {
          prepend_list.push(IMPORT_PATH);
          return S("attr", s("attr", null, "path"), "delimiter")
        } else {
          return process_children(node)
        }
      } else {
        return process_children(node)
      }
    };

    function on_gvar(node) {
      if (node.children === ["$stdin"]) {
        return S("attr", s("attr", null, "process"), "stdin")
      } else if (node.children === ["$stdout"]) {
        return S("attr", s("attr", null, "process"), "stdout")
      } else if (node.children === ["$stderr"]) {
        return S("attr", s("attr", null, "process"), "stderr")
      } else {
        return process_children(node)
      }
    };

    function on_xstr(node) {
      prepend_list.push(IMPORT_CHILD_PROCESS);
      let children = node.children.dup();
      let command = children.shift();

      while (children.length > 0) {
        let child = children.shift();

        if (child.type === "begin" && child.children.length === 1 && child.children.first.type === "send" && child.children.first.children.first === null) {
          child = child.children.first
        };

        command = s("send", command, "+", child)
      };

      return s(
        "send",
        s("attr", null, "child_process"),
        "execSync",
        command,
        s("hash", s("pair", s("sym", "encoding"), s("str", "utf8")))
      )
    };

    function on___FILE__(node) {
      return s("attr", null, "__filename")
    };

    // Handle __FILE__ from Prism::Translation::Parser which produces :str nodes
    function on_str(node) {
      if (typeof node.loc === "object" && node.loc !== null && "expression" in node.loc && node.loc.expression) {
        let source = node.loc.expression.source;
        let buffer_name = node.loc.expression.source_buffer.name;

        if (source === "__FILE__" && node.children.first === buffer_name) {
          return s("attr", null, "__filename")
        }
      };

      return process_children(node)
    };

    return {
      IMPORT_CHILD_PROCESS,
      IMPORT_FS,
      IMPORT_OS,
      IMPORT_PATH,
      SETUP_ARGV,
      on_send,
      on_block,
      on_const,
      on_gvar,
      on_xstr,
      on___FILE__,
      on_str
    }
  })();

  // Prism converts __FILE__ to s(:str, filename) where filename matches buffer name
  // Only check if location has expression method (Parser::AST::Node style)
// Register the filter
DEFAULTS.push(Node);

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.Node = Node;

// Setup function to bind filter infrastructure
Node._setup = function(opts) {
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
export { Node as default, Node };
