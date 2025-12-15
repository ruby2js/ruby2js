// Ruby2JS Self-hosted Library
// Generated from lib/ruby2js/selfhost/bundle.rb
//
// This is the core Ruby2JS library. Import it to convert Ruby to JavaScript:
//   import { convert, Ruby2JS } from './ruby2js.js'
//
// For CLI usage, see ruby2js-cli.js
//
// External dependencies: @ruby/prism only

// Suppress the "WASI is an experimental feature" warning from @ruby/prism
// This MUST run before any imports that load @ruby/prism (which uses WASI internally).
if (typeof process !== 'undefined' && process.emit) {
  const originalEmit = process.emit.bind(process);
  process.emit = function(event, ...args) {
    if (event === 'warning' && args[0]?.name === 'ExperimentalWarning' &&
        args[0]?.message?.includes('WASI')) {
      return false;
    }
    return originalEmit(event, ...args);
  };
}

// Preamble: Ruby built-ins needed by the transpiled code
class NotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotImplementedError';
  }
}

// Parser stub - the Ruby source uses defined?(Parser::AST::Node) checks
// which transpile to typeof Parser.AST.Node !== 'undefined'.
// We define Parser with AST.Node = undefined so the check safely returns false.
const Parser = { AST: { Node: undefined } };

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

Object.defineProperty(Array.prototype, "compact", {
  get() {
    return this.filter(x => x !== null && x !== undefined)
  },

  configurable: true
});

if (!Array.prototype.insert) {
  Array.prototype.insert = function(index, ...items) {
    this.splice(index, 0, ...items);
    return this
  }
};

if (!Array.prototype.rindex) {
  Array.prototype.rindex = function(fn) {
    let i = this.length - 1;

    while (i >= 0) {
      if (fn(this[i])) return i;
      i--
    };

    return null
  }
};

if (!Array.prototype.delete_at) {
  Array.prototype.delete_at = function(index) {
    if (index < 0) index = this.length + index;
    if (index < 0 || index >= this.length) return undefined;
    return this.splice(index, 1)[0]
  }
};

Object.defineProperty(
  Object.prototype,
  "to_a",
  {get() {return Object.entries(this)}, configurable: true}
);

if (!String.prototype.chomp) {
  String.prototype.chomp = function(suffix) {
    if (suffix === undefined) return this.replace(/\r?\n$/m, "");
    if (this.endsWith(suffix)) return this.slice(0, this.length - suffix.length);
    return String(this)
  }
};

if (!String.prototype.count) {
  String.prototype.count = function(chars) {
    let count = 0;

    for (let c of this) {
      if (chars.includes(c)) count++
    };

    return count
  }
};

const Prism = typeof window !== "undefined" ? await import("./prism_browser.js") : await import("@ruby/prism");
export { Prism };

export class PrismSourceBuffer {
  constructor(source, file) {
    this._source = source;
    this._name = file ?? "(eval)";
    this._lineOffsets = [0];
    let i = 0;

    while (i < source.length) {
      if (source[i] === "\n") this._lineOffsets.push(i + 1);
      i++
    }
  };

  get source() {
    return this._source
  };

  get name() {
    return this._name
  };

  lineForPosition(pos) {
    let idx = this._lineOffsets.findIndex(offset => offset > pos);
    return idx === -1 ? this._lineOffsets.length : idx
  };

  columnForPosition(pos) {
    let lineIdx = this._lineOffsets.findIndex(offset => offset > pos);
    if (lineIdx === -1) lineIdx = this._lineOffsets.length;
    return pos - this._lineOffsets[lineIdx - 1]
  }
};

export class PrismSourceRange {
  constructor(sourceBuffer, beginPos, endPos) {
    this._source_buffer = sourceBuffer;
    this._begin_pos = beginPos;
    this._end_pos = endPos
  };

  get source_buffer() {
    return this._source_buffer
  };

  get begin_pos() {
    return this._begin_pos
  };

  get end_pos() {
    return this._end_pos
  };

  get source() {
    return this._source_buffer.source.slice(
      this._begin_pos,
      this._end_pos
    )
  };

  get line() {
    return this._source_buffer.lineForPosition(this._begin_pos)
  };

  get column() {
    return this._source_buffer.columnForPosition(this._begin_pos)
  }
};

export class Hash {
};

export class PrismComment {
  constructor(prismComment, source, sourceBuffer) {
    let start = prismComment.location.startOffset;
    let end_ = start + prismComment.location.length;
    this._text = source.slice(start, end_);

    this._location = {
      startOffset: start,
      endOffset: end_,
      end_offset: end_
    };

    this._loc = {start_offset: start, expression: {
      source_buffer: sourceBuffer,
      begin_pos: start,
      end_pos: end_
    }}
  };

  get text() {
    return this._text
  };

  get location() {
    return this._location
  };

  get loc() {
    return this._loc
  }
};

const CommentsMap = Map;
export { CommentsMap };

export const associateComments = (ast, comments) => {
  let result = new CommentsMap;
  if (comments === null || comments.length === 0 || ast === null) return result;
  let nodes_by_pos = [];

  let collect_nodes = (node, depth) => {
    if (!node || !node.loc) return;
    let start_pos = node.loc.startOffset;

    if (start_pos && node.type !== "begin") {
      nodes_by_pos.push([start_pos, depth, node])
    };

    if (node.children) {
      for (let child of node.children) {
        if (child?.type) collect_nodes(child, depth + 1)
      }
    }
  };

  collect_nodes(ast, 0);

  nodes_by_pos.sort((a, b) => {
    let cmp = a[0] - b[0];
    return cmp !== 0 ? cmp : a[1] - b[1]
  });

  for (let comment of comments) {
    let comment_end = comment.location.startOffset + comment.location.length;
    let candidate = nodes_by_pos.find(item => item[0] >= comment_end);
    if (!candidate) continue;
    let node = candidate[2];
    if (!result.has(node)) result.set(node, []);
    result.get(node).push(comment)
  };

  return result
};

export const setupGlobals = (ruby2js_module) => {
  globalThis.Prism = Prism;
  globalThis.PrismSourceBuffer = PrismSourceBuffer;
  globalThis.PrismSourceRange = PrismSourceRange;
  globalThis.Hash = Hash;
  globalThis.RUBY_VERSION = "3.4.0";
  globalThis.RUBY2JS_PARSER = "prism";
  if (ruby2js_module) return globalThis.Ruby2JS = ruby2js_module
};

// Shared runtime classes for selfhosted Ruby2JS
// These provide Parser-compatible source location tracking for the JS environment.
//
// Note: This file is "Ruby-syntax JavaScript" - it's designed to be transpiled
// to JavaScript, not to run in Ruby. The transpiled output provides the runtime
// support needed by the selfhosted converter.
// Conditionally load Prism based on environment:
// - Browser: use prism_browser.js (fetch + WASI polyfill)
// - Node.js: use @ruby/prism (native WASI)
// ============================================================================
// Source Location Classes (Prism-independent)
// ============================================================================
// PrismSourceBuffer - provides source buffer for location tracking
// Build line offsets for line/column calculation
// PrismSourceRange - provides source range for location tracking
// Hash class placeholder - used for instanceof checks
// ============================================================================
// Comment Handling
// ============================================================================
// PrismComment wrapper - provides interface expected by converter
// CommentsMap - alias for Map (object key support)
// Associate comments with AST nodes based on position
// Set up globals for modules that expect them
// Set up Ruby2JS global with Node class for prism_walker
// Initialize Prism WASM parser (module-level variable for caching)
let prismParse_ = null;

export async function initPrism() {
  prismParse_ ??= await Prism.loadPrism();
  return prismParse_
};

export function getPrismParse() {
  return prismParse_
};

const Ruby2JS = (() => {
  class Namespace {
    constructor() {
      this._active = [];
      this._seen = {}
    };

    resolve(token, result=[]) {
      if (token?.type !== "const") return [];
      this.resolve(token.children.first, result);
      result.push(token.children.last);
      return result
    };

    get active() {
      return this._active.flat(Infinity).compact
    };

    enter(name) {
      this._active.push(this.resolve(name));
      let key = JSON.stringify(this.active);
      let previous = this._seen[key];
      this._seen[key] ??= {};
      return previous
    };

    getOwnProps(name=null) {
      let key = JSON.stringify([...this.active, ...this.resolve(name)]);
      let props = this._seen[key];
      return props ? {...props} : {}
    };

    defineProps(props, namespace=this.active) {
      let key = JSON.stringify(namespace);
      this._seen[key] ??= {};
      Object.assign(this._seen[key], props ?? {})
    };

    find(name) {
      name = this.resolve(name);
      let prefix = this.active.slice();

      while (prefix.pop()) {
        let key = JSON.stringify([...prefix, ...name]);
        let result = this._seen[key];
        if (result) return result
      };

      return {}
    };

    leave() {
      return this._active.pop()
    }
  };

  class Node {
    get type() {
      return this._type
    };

    get children() {
      return this._children
    };

    get location() {
      return this._location
    };

    get loc() {
      return this._location
    };

    constructor(type, children=[], properties={}) {
      this._type = type;
      this._children = Object.freeze(children);
      this._location = properties.location;
      Object.freeze(this)
    };

    updated(type=null, children=null, properties=null) {
      let new_props = {location: this._location};
      if (properties) Object.assign(new_props, properties);
      return new Node(type ?? this._type, children ?? this._children, new_props)
    };

    get to_a() {
      return this._children
    };

    is_method() {
      let selector;
      if (this._type === "attr") return false;
      if (this._type === "call") return true;
      if (!this._location) return true;

      if (typeof this._location === "object" && this._location !== null && "selector" in this._location) {
        if (this._children.length > 2) return true;
        selector = this._location.selector
      } else if (this._type === "defs") {
        if (/[!?]$/m.test(this._children[1])) return true;
        if (this._children[2].children.length > 0) return true;
        selector = typeof this._location === "object" && this._location !== null && "name" in this._location ? this._location.name : null
      } else if (this._type === "def") {
        if (/[!?]$/m.test(this._children[0])) return true;
        if (this._children[1].children.length > 0) return true;
        selector = typeof this._location === "object" && this._location !== null && "name" in this._location ? this._location.name : null
      };

      if (!selector || typeof selector !== "object" || selector === null || !("source_buffer" in selector) || !selector.source_buffer) {
        return true
      };

      return selector.source_buffer.source[selector.end_pos] === "("
    };
  };

  ;
  ;
  ;
  ;
  ;
  ;
  ;
  ;

  class SimpleLocation {
    get start_offset() {
      return this._start_offset
    };

    get end_offset() {
      return this._end_offset
    };

    get expression() {
      return this._expression
    };

    constructor({ start_offset, end_offset, assignment=null, end_loc=null, source=null, file=null, source_buffer=null }) {
      this._start_offset = start_offset;
      this._end_offset = end_offset;
      this._assignment = assignment;
      this._end_loc = end_loc;

      if (source_buffer) {
        this._expression = new PrismSourceRange(source_buffer, start_offset, end_offset)
      } else if (source) {
        let buffer = new PrismSourceBuffer(source, file);
        this._expression = new PrismSourceRange(buffer, start_offset, end_offset)
      }
    };

    get assignment() {
      return this._assignment
    };

    get end() {
      return this._end_loc
    };
  };

  ;

  class FakeSourceBuffer {
    get source() {
      return this._source
    };

    constructor(source) {
      this._source = source
    }
  };

  class FakeSourceRange {
    get end_pos() {
      return this._end_pos
    };

    get begin_pos() {
      return this._begin_pos
    };

    get source_buffer() {
      return this._source_buffer
    };

    constructor(source_buffer, begin_pos, end_pos) {
      this._source_buffer = source_buffer;
      this._begin_pos = begin_pos;
      this._end_pos = end_pos
    }
  };

  class XStrLocation {
    get start_offset() {
      return this._start_offset
    };

    get end_offset() {
      return this._end_offset
    };

    constructor({ source, start_offset, end_offset, opening_end, closing_start }) {
      this._source = source;
      this._start_offset = start_offset;
      this._end_offset = end_offset;
      this._opening_end = opening_end;
      this._closing_start = closing_start;
      this._source_buffer = new FakeSourceBuffer(source)
    };

    get begin() {
      return new FakeSourceRange(this._source_buffer, this._start_offset, this._opening_end)
    };

    get end() {
      return new FakeSourceRange(this._source_buffer, this._closing_start, this._end_offset)
    }
  };

  class SendLocation {
    get start_offset() {
      return this._start_offset
    };

    get end_offset() {
      return this._end_offset
    };

    get selector() {
      return this._selector
    };

    get expression() {
      return this._expression
    };

    constructor({ source, start_offset, end_offset, selector_end_pos, file=null, source_buffer=null }) {
      this._start_offset = start_offset;
      this._end_offset = end_offset;
      this._fake_source_buffer = new FakeSourceBuffer(source);
      this._selector = new FakeSourceRange(this._fake_source_buffer, 0, selector_end_pos);
      let prism_buffer = source_buffer ?? new PrismSourceBuffer(source, file);
      this._expression = new PrismSourceRange(prism_buffer, start_offset, end_offset)
    };
  };

  ;

  class DefLocation {
    get start_offset() {
      return this._start_offset
    };

    get end_offset() {
      return this._end_offset
    };

    get name() {
      return this._name
    };

    get assignment() {
      return this._assignment
    };

    get expression() {
      return this._expression
    };

    constructor({ source, start_offset, end_offset, name_end_pos, endless=false, file=null, source_buffer=null }) {
      this._start_offset = start_offset;
      this._end_offset = end_offset;
      this._fake_source_buffer = new FakeSourceBuffer(source);
      this._name = new FakeSourceRange(this._fake_source_buffer, 0, name_end_pos);
      this._assignment = endless;
      this._end_loc = endless ? null : true;
      let prism_buffer = source_buffer ?? new PrismSourceBuffer(source, file);
      this._expression = new PrismSourceRange(prism_buffer, start_offset, end_offset)
    };

    get end() {
      return this._end_loc
    };
  };

  ;

  class PrismWalker extends Prism.Visitor {
    get source() {
      return this._source
    };

    get file() {
      return this._file
    };

    get source_buffer() {
      return this._source_buffer
    };

    constructor(source, file=null) {
      super();
      this._source = source;
      this._file = file;
      this._source_buffer = new PrismSourceBuffer(source, file)
    };

    s(type, ...children) {
      return new Node(type, children)
    };

    sl(node, type, ...children) {
      let $kwargs = children.at(-1);

      if (typeof $kwargs === "object" && $kwargs !== null && $kwargs.constructor === Object) {
        children.pop()
      } else {
        $kwargs = {}
      };

      let endless = $kwargs.endless ?? false;
      let loc = node.location;

      let location = new SimpleLocation({
        start_offset: loc.startOffset,
        end_offset: loc.startOffset + loc.length,
        assignment: endless ? true : null,
        end_loc: endless ? null : true,
        source_buffer: this._source_buffer
      });

      return new Node(type, children, {location})
    };

    send_node(node, type, ...children) {
      let location;
      let loc = node.location;

      if (node.messageLoc) {
        let selector_end = node.messageLoc.startOffset + node.messageLoc.length;

        location = new SendLocation({
          source: this._source,
          start_offset: loc.startOffset,
          end_offset: loc.startOffset + loc.length,
          selector_end_pos: selector_end,
          source_buffer: this._source_buffer
        })
      } else {
        location = new SimpleLocation({
          start_offset: loc.startOffset,
          end_offset: loc.startOffset + loc.length,
          source_buffer: this._source_buffer
        })
      };

      return new Node(type, children, {location})
    };

    send_with_loc(node, type, ...children) {
      let location;
      let loc = node.location;

      if (typeof node === "object" && node !== null && "messageLoc" in node && node.messageLoc) {
        let selector_end = node.messageLoc.startOffset + node.messageLoc.length;

        location = new SendLocation({
          source: this._source,
          start_offset: loc.startOffset,
          end_offset: loc.startOffset + loc.length,
          selector_end_pos: selector_end,
          source_buffer: this._source_buffer
        })
      } else {
        location = new SimpleLocation({
          start_offset: loc.startOffset,
          end_offset: loc.startOffset + loc.length,
          source_buffer: this._source_buffer
        })
      };

      return new Node(type, children, {location})
    };

    def_node(node, type, ...children) {
      let $kwargs = children.at(-1);

      if (typeof $kwargs === "object" && $kwargs !== null && $kwargs.constructor === Object) {
        children.pop()
      } else {
        $kwargs = {}
      };

      let endless = $kwargs.endless ?? false;
      let loc = node.location;
      let name_end = node.nameLoc.startOffset + node.nameLoc.length;

      let location = new DefLocation({
        source: this._source,
        start_offset: loc.startOffset,
        end_offset: loc.startOffset + loc.length,
        name_end_pos: name_end,
        endless,
        source_buffer: this._source_buffer
      });

      return new Node(type, children, {location})
    };

    visit(node) {
      if (!node) return null;
      return this[`visit${node.constructor.name ?? ""}`].call(this, node)
    };

    visit_all(nodes) {
      if (nodes === null) return [];
      return nodes.map(node => this.visit(node)).compact
    };

    visitIntegerNode(node) {
      return this.sl(node, "int", node.value)
    };

    visitFloatNode(node) {
      return this.sl(node, "float", node.value)
    };

    visitRationalNode(node) {
      return this.sl(node, "rational", node.value)
    };

    visitImaginaryNode(node) {
      return this.sl(node, "complex", node.value)
    };

    visitStringNode(node) {
      let opening, parts, children;

      if (node.openingLoc) {
        opening = this._source.slice(
          node.openingLoc.startOffset,
          node.openingLoc.startOffset + node.openingLoc.length
        )
      };

      let is_heredoc = opening?.startsWith("<<");
      let is_multiline = node.location.startLine !== node.location.endLine;

      if (is_heredoc && node.unescaped.value.length === 0) {
        return this.sl(node, "dstr")
      } else if (is_multiline && node.unescaped.value.includes("\n")) {
        parts = node.unescaped.value.split(/(\n)/).filter(item => !(item.length === 0));
        children = [];

        parts.forEach((part, i) => {
          if (part === "\n") {
            if (children.last) {
              children[children.length - 1] = this.s(
                "str",
                children.last.children.first + "\n"
              )
            } else {
              children.push(this.s("str", "\n"))
            }
          } else {
            children.push(this.s("str", part))
          }
        });

        if (node.unescaped.value.endsWith("\n") && children.last && !children.last.children.first.endsWith("\n")) {
          children[children.length - 1] = this.s(
            "str",
            children.last.children.first + "\n"
          )
        };

        return this.sl(node, "dstr", ...children)
      } else {
        return this.sl(node, "str", node.unescaped.value)
      }
    };

    visitSymbolNode(node) {
      return this.sl(node, "sym", node.unescaped.value)
    };

    visitNilNode(node) {
      return this.sl(node, "nil")
    };

    visitTrueNode(node) {
      return this.sl(node, "true")
    };

    visitFalseNode(node) {
      return this.sl(node, "false")
    };

    visitSelfNode(node) {
      return this.sl(node, "self")
    };

    visitSourceFileNode(node) {
      return this.sl(node, "str", node.filepath)
    };

    visitSourceLineNode(node) {
      return this.sl(node, "int", node.location.startLine)
    };

    visitSourceEncodingNode(node) {
      return this.sl(node, "__ENCODING__")
    };

    visitLocalVariableReadNode(node) {
      return this.sl(node, "lvar", node.name)
    };

    visitLocalVariableWriteNode(node) {
      return this.sl(node, "lvasgn", node.name, this.visit(node.value))
    };

    visitLocalVariableTargetNode(node) {
      return this.sl(node, "lvasgn", node.name)
    };

    visitInstanceVariableReadNode(node) {
      return this.sl(node, "ivar", node.name)
    };

    visitInstanceVariableWriteNode(node) {
      return this.sl(node, "ivasgn", node.name, this.visit(node.value))
    };

    visitInstanceVariableTargetNode(node) {
      return this.sl(node, "ivasgn", node.name)
    };

    visitClassVariableReadNode(node) {
      return this.sl(node, "cvar", node.name)
    };

    visitClassVariableWriteNode(node) {
      return this.sl(node, "cvasgn", node.name, this.visit(node.value))
    };

    visitClassVariableTargetNode(node) {
      return this.sl(node, "cvasgn", node.name)
    };

    visitGlobalVariableReadNode(node) {
      return this.sl(node, "gvar", node.name)
    };

    visitGlobalVariableWriteNode(node) {
      return this.sl(node, "gvasgn", node.name, this.visit(node.value))
    };

    visitGlobalVariableTargetNode(node) {
      return this.sl(node, "gvasgn", node.name)
    };

    visitConstantReadNode(node) {
      return this.sl(node, "const", null, node.name)
    };

    visitConstantWriteNode(node) {
      return this.sl(
        node,
        "casgn",
        null,
        node.name,
        this.visit(node.value)
      )
    };

    visitConstantTargetNode(node) {
      return this.sl(node, "casgn", null, node.name)
    };

    visitConstantPathNode(node) {
      let parent = node.parent ? this.visit(node.parent) : this.s("cbase");
      let name = typeof node === "object" && node !== null && "name" in node ? node.name : node.child.name;
      return this.sl(node, "const", parent, name)
    };

    visitConstantPathWriteNode(node) {
      let target = this.visit(node.target);

      return this.sl(
        node,
        "casgn",
        target.children[0],
        target.children[1],
        this.visit(node.value)
      )
    };

    visitConstantPathTargetNode(node) {
      let parent = node.parent ? this.visit(node.parent) : this.s("cbase");
      return this.sl(node, "casgn", parent, node.name)
    };

    visitBackReferenceReadNode(node) {
      return this.sl(node, "back_ref", node.name)
    };

    visitNumberedReferenceReadNode(node) {
      return this.sl(node, "nth_ref", node.number)
    };

    visitItLocalVariableReadNode(node) {
      return this.sl(node, "lvar", "it")
    };

    visitArrayNode(node) {
      let elements = this.visit_all(node.elements);
      return this.sl(node, "array", ...elements)
    };

    visitHashNode(node) {
      let elements = this.visit_all(node.elements);
      return this.sl(node, "hash", ...elements)
    };

    visitAssocNode(node) {
      let value;
      let key = this.visit(node.key);

      if (node.value instanceof Prism.ImplicitNode) {
        let name = node.key.unescaped.value;
        value = this.s("send", null, name)
      } else {
        value = this.visit(node.value)
      };

      return this.sl(node, "pair", key, value)
    };

    visitAssocSplatNode(node) {
      return node.value ? this.sl(node, "kwsplat", this.visit(node.value)) : this.sl(
        node,
        "forwarded_kwrestarg"
      )
    };

    visitRangeNode(node) {
      let left = this.visit(node.left);
      let right = this.visit(node.right);
      let type = node.isExcludeEnd() ? "erange" : "irange";
      return this.sl(node, type, left, right)
    };

    visitSplatNode(node) {
      return node.expression ? this.sl(
        node,
        "splat",
        this.visit(node.expression)
      ) : this.sl(node, "splat")
    };

    visitInterpolatedSymbolNode(node) {
      let parts;

      if (node.parts.length === 1 && node.parts.first instanceof Prism.StringNode) {
        return this.sl(node, "sym", node.parts.first.unescaped.value)
      } else {
        parts = node.parts.map(part => (
          part instanceof Prism.StringNode ? this.s(
            "str",
            part.unescaped.value
          ) : this.visit(part)
        ));

        return this.sl(node, "dsym", ...parts)
      }
    };

    visitCallNode(node) {
      let block_args, block_body;
      let receiver = this.visit(node.receiver);
      let method_name = node.name;
      let args = [];
      if (node.arguments_) args = this.visit_all(node.arguments_.arguments_);

      if (node.block instanceof Prism.BlockArgumentNode) {
        args.push(this.visit(node.block))
      };

      let type = node.isSafeNavigation() ? "csend" : "send";

      let result = this.send_node(
        node,
        type,
        receiver,
        method_name,
        ...args
      );

      if (node.block instanceof Prism.BlockNode) {
        block_args = node.block.parameters ? this.visit(node.block.parameters) : this.s("args");
        block_body = this.visit(node.block.body);

        return node.block.parameters instanceof Prism.NumberedParametersNode ? this.sl(
          node,
          "numblock",
          result,
          node.block.parameters.maximum,
          block_body
        ) : this.sl(node, "block", result, block_args, block_body)
      } else {
        return result
      }
    };

    visitBlockArgumentNode(node) {
      return node.expression ? this.sl(
        node,
        "block_pass",
        this.visit(node.expression)
      ) : this.sl(node, "block_pass")
    };

    visitSuperNode(node) {
      let result, block_args, block_body;

      if (node.arguments_) {
        let args = this.visit_all(node.arguments_.arguments_);
        result = this.sl(node, "super", ...args)
      } else {
        result = this.sl(node, "super")
      };

      if (node.block instanceof Prism.BlockNode) {
        block_args = node.block.parameters ? this.visit(node.block.parameters) : this.s("args");
        block_body = this.visit(node.block.body);
        return this.sl(node, "block", result, block_args, block_body)
      } else {
        return result
      }
    };

    visitForwardingSuperNode(node) {
      return this.sl(node, "zsuper")
    };

    visitYieldNode(node) {
      let args;

      if (node.arguments_) {
        args = this.visit_all(node.arguments_.arguments_);
        return this.sl(node, "yield", ...args)
      } else {
        return this.sl(node, "yield")
      }
    };

    visitForwardingArgumentsNode(node) {
      return this.sl(node, "forwarded_args")
    };

    is_numbered_params(node) {
      return node && node.constructor.name === "NumberedParametersNode"
    };

    is_implicit_rest(node) {
      return node && node.constructor.name === "ImplicitRestNode"
    };

    visitBlockNode(node) {
      let args;
      let call = this.visit(node());
      let body = this.visit(node.body);

      if (this.is_numbered_params(node.parameters)) {
        return this.sl(node, "numblock", call, node.parameters.maximum, body)
      } else {
        args = node.parameters ? this.visit(node.parameters) : this.s("args");
        return this.sl(node, "block", call, args, body)
      }
    };

    visitLambdaNode(node) {
      let args;
      let body = this.visit(node.body);
      let lambda_call = this.s("send", null, "lambda");

      if (this.is_numbered_params(node.parameters)) {
        return this.sl(
          node,
          "numblock",
          lambda_call,
          node.parameters.maximum,
          body
        )
      } else {
        args = node.parameters ? this.visit(node.parameters) : this.s("args");
        return this.sl(node, "block", lambda_call, args, body)
      }
    };

    visitBlockParametersNode(node) {
      let params = [];
      if (node.parameters) params.push(...this.visit_parameters(node.parameters));

      if (node.locals && node.locals.length !== 0) {
        for (let local of node.locals) {
          params.push(this.s("shadowarg", local.name))
        }
      };

      return this.sl(node, "args", ...params)
    };

    visitNumberedParametersNode(node) {
      return node.maximum
    };

    visit_parameters(params) {
      let result = [];

      for (let param of params.requireds) {
        result.push(this.visit(param))
      };

      for (let param of params.optionals) {
        result.push(this.visit(param))
      };

      if (params.rest && !this.is_implicit_rest(params.rest)) {
        result.push(this.visit(params.rest))
      };

      for (let param of params.posts) {
        result.push(this.visit(param))
      };

      for (let param of params.keywords) {
        result.push(this.visit(param))
      };

      if (params.keywordRest) result.push(this.visit(params.keywordRest));
      if (params.block) result.push(this.visit(params.block));
      return result
    };

    visitRequiredParameterNode(node) {
      return this.sl(node, "arg", node.name)
    };

    visitOptionalParameterNode(node) {
      return this.sl(node, "optarg", node.name, this.visit(node.value))
    };

    visitRestParameterNode(node) {
      return node.name ? this.sl(node, "restarg", node.name) : this.sl(
        node,
        "restarg"
      )
    };

    visitRequiredKeywordParameterNode(node) {
      return this.sl(node, "kwarg", node.name)
    };

    visitOptionalKeywordParameterNode(node) {
      return this.sl(node, "kwoptarg", node.name, this.visit(node.value))
    };

    visitKeywordRestParameterNode(node) {
      return node.name ? this.sl(node, "kwrestarg", node.name) : this.sl(
        node,
        "kwrestarg"
      )
    };

    visitBlockParameterNode(node) {
      return node.name ? this.sl(node, "blockarg", node.name) : this.sl(
        node,
        "blockarg"
      )
    };

    visitForwardingParameterNode(node) {
      return this.sl(node, "forward_args")
    };

    visitImplicitRestNode(node) {
      return null
    };

    visitMultiTargetNode(node) {
      let targets = [];

      for (let target of node.lefts) {
        targets.push(this.visit(target))
      };

      if (node.rest && !this.is_implicit_rest(node.rest)) {
        targets.push(this.visit(node.rest))
      };

      for (let target of node.rights) {
        targets.push(this.visit(target))
      };

      return this.sl(node, "mlhs", ...targets)
    };

    visitRequiredDestructuredParameterNode(node) {
      let params = [];

      for (let param of node.parameters) {
        params.push(this.visit(param))
      };

      return this.sl(node, "mlhs", ...params)
    };

    visitIfNode(node) {
      let condition = this.visit(node.predicate);
      let then_body = this.visit(node.statements);
      let else_clause = typeof node === "object" && node !== null && "subsequent" in node ? node.subsequent : node.consequent;
      let else_body = this.visit(else_clause);
      return this.sl(node, "if", condition, then_body, else_body)
    };

    visitUnlessNode(node) {
      let condition = this.visit(node.predicate);
      let then_body = this.visit(node.statements);
      let else_body = this.visit(node.elseClause) ? this.visit(node.elseClause.statements) : null;
      return this.sl(node, "if", condition, else_body, then_body)
    };

    visitCaseNode(node) {
      let predicate = this.visit(node.predicate);
      let conditions = this.visit_all(node.conditions);
      let else_body = node.elseClause ? this.visit(node.elseClause.statements) : null;
      return this.sl(node, "case", predicate, ...conditions, else_body)
    };

    visitWhenNode(node) {
      let conditions = this.visit_all(node.conditions);
      let body = this.visit(node.statements);
      return this.sl(node, "when", ...conditions, body)
    };

    visitCaseMatchNode(node) {
      let predicate = this.visit(node.predicate);
      let conditions = this.visit_all(node.conditions);
      let else_body = node.elseClause ? this.visit(node.elseClause.statements) : null;

      return this.sl(
        node,
        "case_match",
        predicate,
        ...conditions,
        else_body
      )
    };

    visitInNode(node) {
      let pattern = this.visit(node.pattern);
      let body = this.visit(node.statements);
      return this.sl(node, "in_pattern", pattern, null, body)
    };

    visitWhileNode(node) {
      let condition = this.visit(node.predicate);
      let body = this.visit(node.statements);

      return node.isBeginModifier() ? this.sl(
        node,
        "while_post",
        condition,
        body
      ) : this.sl(node, "while", condition, body)
    };

    visitUntilNode(node) {
      let condition = this.visit(node.predicate);
      let body = this.visit(node.statements);

      return node.isBeginModifier() ? this.sl(
        node,
        "until_post",
        condition,
        body
      ) : this.sl(node, "until", condition, body)
    };

    visitForNode(node) {
      let $var = this.visit(node.index);
      let collection = this.visit(node.collection);
      let body = this.visit(node.statements);
      return this.sl(node, "for", $var, collection, body)
    };

    visitBreakNode(node) {
      let args;

      if (node.arguments_) {
        args = this.visit_all(node.arguments_.arguments_);
        return this.sl(node, "break", ...args)
      } else {
        return this.sl(node, "break")
      }
    };

    visitNextNode(node) {
      let args;

      if (node.arguments_) {
        args = this.visit_all(node.arguments_.arguments_);
        return this.sl(node, "next", ...args)
      } else {
        return this.sl(node, "next")
      }
    };

    visitReturnNode(node) {
      let args;

      if (node.arguments_) {
        args = this.visit_all(node.arguments_.arguments_);

        return args.length === 1 ? this.sl(node, "return", args.first) : this.sl(
          node,
          "return",
          this.s("array", ...args)
        )
      } else {
        return this.sl(node, "return")
      }
    };

    visitRedoNode(node) {
      return this.sl(node, "redo")
    };

    visitRetryNode(node) {
      return this.sl(node, "retry")
    };

    visitElseNode(node) {
      return this.visit(node.statements)
    };

    visitMatchWriteNode(node) {
      return this.visit(node())
    };

    visitCapturePatternNode(node) {
      let value = this.visit(node.value);
      let target = this.visit(node.target);
      return this.sl(node, "match_as", value, target)
    };

    visitAlternationPatternNode(node) {
      let left = this.visit(node.left);
      let right = this.visit(node.right);
      return this.sl(node, "match_alt", left, right)
    };

    visit_local_variable_target_in_pattern(node) {
      return this.sl(node, "match_var", node.name)
    };

    visitPinnedVariableNode(node) {
      return this.sl(node, "pin", this.visit(node.variable))
    };

    visitPinnedExpressionNode(node) {
      return this.sl(node, "pin", this.visit(node.expression))
    };

    visitDefNode(node) {
      let receiver;
      let name = node.name;

      let args = node.parameters ? this.s(
        "args",
        ...this.visit_parameters(node.parameters)
      ) : this.s("args");

      let body = this.visit(node.body);
      let endless = !!(node.equalLoc && node.endKeywordLoc === null);

      if (node.receiver) {
        receiver = this.visit(node.receiver);

        return this.def_node(
          node,
          "defs",
          receiver,
          name,
          args,
          body,
          {endless}
        )
      } else {
        return this.def_node(node, "def", name, args, body, {endless})
      }
    };

    visitClassNode(node) {
      let name = this.visit(node.constantPath);
      let superclass = this.visit(node.superclass);
      let body = this.visit(node.body);
      return this.sl(node, "class", name, superclass, body)
    };

    visitModuleNode(node) {
      let name = this.visit(node.constantPath);
      let body = this.visit(node.body);
      return this.sl(node, "module", name, body)
    };

    visitSingletonClassNode(node) {
      let expression = this.visit(node.expression);
      let body = this.visit(node.body);
      return this.sl(node, "sclass", expression, body)
    };

    visitAliasMethodNode(node) {
      let new_name = this.visit(node.newName);
      let old_name = this.visit(node.oldName);
      return this.sl(node, "alias", new_name, old_name)
    };

    visitAliasGlobalVariableNode(node) {
      let new_name = this.visit(node.newName);
      let old_name = this.visit(node.oldName);
      return this.sl(node, "alias", new_name, old_name)
    };

    visitUndefNode(node) {
      let names = this.visit_all(node.names);
      return this.sl(node, "undef", ...names)
    };

    visitDefinedNode(node) {
      let value = this.visit(node.value);
      return this.sl(node, "defined?", value)
    };

    visitPreExecutionNode(node) {
      let body = this.visit(node.statements);
      return this.sl(node, "preexe", body)
    };

    visitPostExecutionNode(node) {
      let body = this.visit(node.statements);
      return this.sl(node, "postexe", body)
    };

    visitAndNode(node) {
      let left = this.visit(node.left);
      let right = this.visit(node.right);
      return this.sl(node, "and", left, right)
    };

    visitOrNode(node) {
      let left = this.visit(node.left);
      let right = this.visit(node.right);
      return this.sl(node, "or", left, right)
    };

    visit_call_operator_not(node) {
      return null
    };

    visitMultiWriteNode(node) {
      let rhs;
      let targets = [];

      for (let target of node.lefts) {
        targets.push(this.visit(target))
      };

      if (node.rest && !node.rest instanceof Prism.ImplicitRestNode) {
        targets.push(this.visit(node.rest))
      };

      for (let target of node.rights) {
        targets.push(this.visit(target))
      };

      let lhs = this.s("mlhs", ...targets);

      if (node.value instanceof Prism.ArrayNode && node.value.elements) {
        let rhs_values = this.visit_all(node.value.elements);

        if (rhs_values.length === 1) {
          rhs = rhs_values.first
        } else {
          rhs = this.s("array", ...rhs_values)
        }
      } else {
        rhs = this.visit(node.value)
      };

      return this.sl(node, "masgn", lhs, rhs)
    };

    visit_splat_node_in_mlhs(node) {
      return node.expression ? this.s("splat", this.visit(node.expression)) : this.s("splat")
    };

    visitLocalVariableOperatorWriteNode(node) {
      let target = this.s("lvasgn", node.name);

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitLocalVariableOrWriteNode(node) {
      let target = this.s("lvasgn", node.name);
      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitLocalVariableAndWriteNode(node) {
      let target = this.s("lvasgn", node.name);
      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitInstanceVariableOperatorWriteNode(node) {
      let target = this.s("ivasgn", node.name);

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitInstanceVariableOrWriteNode(node) {
      let target = this.s("ivasgn", node.name);
      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitInstanceVariableAndWriteNode(node) {
      let target = this.s("ivasgn", node.name);
      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitClassVariableOperatorWriteNode(node) {
      let target = this.s("cvasgn", node.name);

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitClassVariableOrWriteNode(node) {
      let target = this.s("cvasgn", node.name);
      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitClassVariableAndWriteNode(node) {
      let target = this.s("cvasgn", node.name);
      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitGlobalVariableOperatorWriteNode(node) {
      let target = this.s("gvasgn", node.name);

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitGlobalVariableOrWriteNode(node) {
      let target = this.s("gvasgn", node.name);
      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitGlobalVariableAndWriteNode(node) {
      let target = this.s("gvasgn", node.name);
      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitConstantOperatorWriteNode(node) {
      let target = this.s("casgn", null, node.name);

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitConstantOrWriteNode(node) {
      let target = this.s("casgn", null, node.name);
      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitConstantAndWriteNode(node) {
      let target = this.s("casgn", null, node.name);
      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitConstantPathOperatorWriteNode(node) {
      let target_path = this.visit(node.target);

      let target = this.s(
        "casgn",
        target_path.children[0],
        target_path.children[1]
      );

      return this.sl(
        node,
        "op_asgn",
        target,
        node.binaryOperator,
        this.visit(node.value)
      )
    };

    visitConstantPathOrWriteNode(node) {
      let target_path = this.visit(node.target);

      let target = this.s(
        "casgn",
        target_path.children[0],
        target_path.children[1]
      );

      return this.sl(node, "or_asgn", target, this.visit(node.value))
    };

    visitConstantPathAndWriteNode(node) {
      let target_path = this.visit(node.target);

      let target = this.s(
        "casgn",
        target_path.children[0],
        target_path.children[1]
      );

      return this.sl(node, "and_asgn", target, this.visit(node.value))
    };

    visitIndexOperatorWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let args = this.visit_all(node.arguments_.arguments_ ?? []);
      let value = this.visit(node.value);

      let call_args = node.callOperatorLoc ? this.s(
        "csend",
        receiver,
        "[]",
        ...args
      ) : this.s("send", receiver, "[]", ...args);

      return this.sl(
        node,
        "op_asgn",
        call_args,
        node.binaryOperator,
        value
      )
    };

    visitIndexOrWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let args = this.visit_all(node.arguments_.arguments_ ?? []);
      let value = this.visit(node.value);
      let call_args = this.s("send", receiver, "[]", ...args);
      return this.sl(node, "or_asgn", call_args, value)
    };

    visitIndexAndWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let args = this.visit_all(node.arguments_.arguments_ ?? []);
      let value = this.visit(node.value);
      let call_args = this.s("send", receiver, "[]", ...args);
      return this.sl(node, "and_asgn", call_args, value)
    };

    visitCallOperatorWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let read_name = node.readName;
      let value = this.visit(node.value);
      let call_type = node.isSafeNavigation() ? "csend" : "send";
      let target = this.send_with_loc(node, call_type, receiver, read_name);
      return this.sl(node, "op_asgn", target, node.binaryOperator, value)
    };

    visitCallOrWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let read_name = node.readName;
      let value = this.visit(node.value);
      let call_type = node.isSafeNavigation() ? "csend" : "send";
      let target = this.send_with_loc(node, call_type, receiver, read_name);
      return this.sl(node, "or_asgn", target, value)
    };

    visitCallAndWriteNode(node) {
      let receiver = this.visit(node.receiver);
      let read_name = node.readName;
      let value = this.visit(node.value);
      let call_type = node.isSafeNavigation() ? "csend" : "send";
      let target = this.send_with_loc(node, call_type, receiver, read_name);
      return this.sl(node, "and_asgn", target, value)
    };

    visitFlipFlopNode(node) {
      let left = this.visit(node.left);
      let right = this.visit(node.right);
      let type = node.isExcludeEnd() ? "eflipflop" : "iflipflop";
      return this.sl(node, type, left, right)
    };

    visitBeginNode(node) {
      let body, handlers, current, else_body, rescue_node, ensure_body;

      if (node.rescueClause || node.ensureClause) {
        body = this.visit(node.statements);

        if (node.rescueClause) {
          handlers = [];
          current = node.rescueClause;

          while (current) {
            handlers.push(this.visit_resbody(current));
            current = current.subsequent
          };

          else_body = node.elseClause ? this.visit(node.elseClause.statements) : null;
          rescue_node = this.s("rescue", body, ...handlers, else_body);

          if (node.ensureClause) {
            ensure_body = this.visit(node.ensureClause.statements);

            return this.sl(
              node,
              "kwbegin",
              this.s("ensure", rescue_node, ensure_body)
            )
          } else {
            return this.sl(node, "kwbegin", rescue_node)
          }
        } else {
          ensure_body = this.visit(node.ensureClause.statements);
          return this.sl(node, "kwbegin", this.s("ensure", body, ensure_body))
        }
      } else {
        body = this.visit(node.statements);

        return body ? this.sl(node, "kwbegin", body) : this.sl(
          node,
          "kwbegin"
        )
      }
    };

    visit_resbody(node) {
      let exceptions = node.exceptions && node.exceptions.length !== 0 ? (() => {
        let types = this.visit_all(node.exceptions);
        return this.s("array", ...types)
      })() : null;

      let exception_var = node.reference ? node.reference instanceof Prism.LocalVariableTargetNode ? this.s(
        "lvasgn",
        node.reference.name
      ) : this.visit(node.reference) : null;

      let body = this.visit(node.statements);
      return this.s("resbody", exceptions, exception_var, body)
    };

    visitRescueModifierNode(node) {
      let expression = this.visit(node.expression);
      let rescue_expr = this.visit(node.rescueExpression);

      return this.sl(
        node,
        "rescue",
        expression,
        this.s("resbody", null, null, rescue_expr),
        null
      )
    };

    visitEnsureNode(node) {
      return this.visit(node.statements)
    };

    visitRescueNode(node) {
      return this.visit_resbody(node)
    };

    visitInterpolatedStringNode(node) {
      let parts = node.parts.map((part) => {
        if (part instanceof Prism.StringNode) {
          return this.s("str", part.unescaped.value)
        } else if (part instanceof Prism.EmbeddedStatementsNode) {
          return this.visit(part)
        } else {
          return this.visit(part)
        }
      });

      return this.sl(node, "dstr", ...parts)
    };

    visitEmbeddedStatementsNode(node) {
      if (node.statements === null || node.statements.body.length === 0) {
        return this.s("begin")
      } else if (node.statements.body.length === 1) {
        return this.visit(node.statements.body.first)
      } else {
        return this.s("begin", ...this.visit_all(node.statements.body))
      }
    };

    visitEmbeddedVariableNode(node) {
      return this.visit(node.variable)
    };

    visitXStringNode(node) {
      let location = new XStrLocation({
        source: this._source,
        start_offset: node.location.startOffset,
        end_offset: node.location.startOffset + node.location.length,
        opening_end: node.openingLoc.startOffset + node.openingLoc.length,
        closing_start: node.closingLoc.startOffset
      });

      return new Node("xstr", [this.s("str", node.unescaped.value)], {location})
    };

    visitInterpolatedXStringNode(node) {
      let parts = node.parts.map(part => (
        part instanceof Prism.StringNode ? this.s(
          "str",
          part.unescaped.value
        ) : this.visit(part)
      ));

      let location = new XStrLocation({
        source: this._source,
        start_offset: node.location.startOffset,
        end_offset: node.location.startOffset + node.location.length,
        opening_end: node.openingLoc.startOffset + node.openingLoc.length,
        closing_start: node.closingLoc.startOffset
      });

      return new Node("xstr", parts, {location})
    };

    visitWordsNode(node) {
      let elements = node.elements.map(element => (
        element instanceof Prism.StringNode ? this.s(
          "str",
          element.unescaped.value
        ) : this.visit(element)
      ));

      return this.sl(node, "array", ...elements)
    };

    visitInterpolatedWordsNode(node) {
      return this.visitWordsNode(node)
    };

    visitSymbolsNode(node) {
      let elements = node.elements.map(element => (
        element instanceof Prism.SymbolNode ? this.s(
          "sym",
          element.unescaped.value
        ) : this.visit(element)
      ));

      return this.sl(node, "array", ...elements)
    };

    visitInterpolatedSymbolsNode(node) {
      return this.visitSymbolsNode(node)
    };

    visitRegularExpressionNode(node) {
      let opts = this.build_regopt_from_node(node);

      return this.sl(
        node,
        "regexp",
        this.s("str", node.unescaped.value),
        opts
      )
    };

    visitInterpolatedRegularExpressionNode(node) {
      let parts = node.parts.map(part => (
        part instanceof Prism.StringNode ? this.s(
          "str",
          part.unescaped.value
        ) : this.visit(part)
      ));

      let opts = this.build_regopt_from_node(node);
      return this.sl(node, "regexp", ...parts, opts)
    };

    visitMatchLastLineNode(node) {
      let opts = this.build_regopt_from_node(node);

      let regexp = this.s(
        "regexp",
        this.s("str", node.unescaped.value),
        opts
      );

      return this.sl(node, "match_current_line", regexp)
    };

    visitInterpolatedMatchLastLineNode(node) {
      let parts = node.parts.map(part => (
        part instanceof Prism.StringNode ? this.s(
          "str",
          part.unescaped.value
        ) : this.visit(part)
      ));

      let opts = this.build_regopt_from_node(node);
      let regexp = this.s("regexp", ...parts, opts);
      return this.sl(node, "match_current_line", regexp)
    };

    build_regopt_from_node(node) {
      let opts = [];
      if (node.isIgnoreCase()) opts.push("i");
      if (node.isMultiLine()) opts.push("m");
      if (node.isExtended()) opts.push("x");
      if (node.isOnce()) opts.push("o");
      if (node.ascii_8bit) opts.push("n");
      if (node.isEucJp()) opts.push("e");
      if (node.windows_31j) opts.push("s");
      if (node.utf_8) opts.push("u");
      return this.s("regopt", ...opts)
    };

    visitProgramNode(node) {
      return this.visit(node.statements)
    };

    visitStatementsNode(node) {
      let statements = this.visit_all(node.body);

      if (statements.length === 0) {
        return null
      } else if (statements.length === 1) {
        return statements.first
      } else {
        return this.sl(node, "begin", ...statements)
      }
    };

    visitParenthesesNode(node) {
      let body;

      if (node.body === null) {
        return this.sl(node, "begin")
      } else {
        body = this.visit(node.body);

        return body === null ? this.sl(node, "begin") : this.sl(
          node,
          "begin",
          body
        )
      }
    };

    visitImplicitNode(node) {
      return this.visit(node.value)
    };

    visitMissingNode(node) {
      return null
    };

    visitKeywordHashNode(node) {
      let elements = this.visit_all(node.elements);
      return this.sl(node, "hash", ...elements)
    };

    visitArgumentsNode(node) {
      return this.visit_all(node.arguments_)
    };

    visit_splat_in_array(node) {
      return node.expression ? this.s("splat", this.visit(node.expression)) : this.s("splat")
    };

    visitBlockLocalVariableNode(node) {
      return this.s("shadowarg", node.name)
    };

    visitMatchRequiredNode(node) {
      let value = this.visit(node.value);
      let pattern = this.visit_pattern(node.pattern);
      return this.sl(node, "match_pattern", value, pattern)
    };

    visitMatchPredicateNode(node) {
      let value = this.visit(node.value);
      let pattern = this.visit_pattern(node.pattern);
      return this.sl(node, "match_pattern_p", value, pattern)
    };

    visit_pattern(node) {
      if (node instanceof Prism.LocalVariableTargetNode) {
        return this.s("match_var", node.name)
      } else if (node instanceof Prism.HashPatternNode) {
        return this.visitHashPatternNode(node)
      } else if (node instanceof Prism.ArrayPatternNode) {
        return this.visitArrayPatternNode(node)
      } else if (node instanceof Prism.PinnedVariableNode) {
        return this.sl(node, "pin", this.visit(node.variable))
      } else if (node instanceof Prism.PinnedExpressionNode) {
        return this.sl(node, "pin", this.visit(node.expression))
      } else {
        return this.visit(node)
      }
    };

    visitHashPatternNode(node) {
      let elements = node.elements.map((assoc) => {
        let value;

        if (assoc instanceof Prism.AssocNode) {
          value = assoc.value;
          if (value instanceof Prism.ImplicitNode) value = value.value;
          return this.visit_pattern(value)
        } else {
          return this.visit(assoc)
        }
      });

      return this.sl(node, "hash_pattern", ...elements)
    };

    visitArrayPatternNode(node) {
      let elements = [];

      for (let req of node.requireds) {
        elements.push(this.visit_pattern(req))
      };

      if (node.rest) elements.push(this.visit_pattern(node.rest));

      for (let post of node.posts) {
        elements.push(this.visit_pattern(post))
      };

      return this.sl(node, "array_pattern", ...elements)
    };

    visitFindPatternNode(node) {
      let elements = [];
      if (node.left) elements.push(this.visit(node.left));
      elements.concat(this.visit_all(node.requireds));
      if (node.right) elements.push(this.visit(node.right));
      return this.sl(node, "find_pattern", ...elements)
    };

    visitNoKeywordsParameterNode(node) {
      return this.sl(node, "kwnilarg")
    };

    visitShareableConstantNode(node) {
      return this.visit(node.write)
    };

    visitCallTargetNode(node) {
      let receiver = this.visit(node.receiver);
      let type = node.isSafeNavigation() ? "csend" : "send";
      return this.sl(node, type, receiver, node.name)
    };

    visitIndexTargetNode(node) {
      let receiver = this.visit(node.receiver);
      let args = this.visit_all(node.arguments_.arguments_ ?? []);
      return this.sl(node, "send", receiver, "[]", ...args)
    };

    visitParametersNode(node) {
      return this.s("args", ...this.visit_parameters(node))
    };

    visitSourceFileNode(node) {
      return this.sl(node, "__FILE__")
    };

    visitSourceLineNode(node) {
      return this.sl(node, "int", node.location.startLine)
    };

    visitSourceEncodingNode(node) {
      return this.sl(
        node,
        "send",
        this.s("const", null, "Encoding"),
        "default_external"
      )
    }
  };

  ;
  ;
  ;
  ;

  class Token {
    get loc() {
      return this._loc
    };

    set loc(loc) {
      this._loc = loc
    };

    get ast() {
      return this._ast
    };

    set ast(ast) {
      this._ast = ast
    };

    constructor(string, ast) {
      this._string = (string ?? "").toString();
      this._ast = ast;

      if (ast && typeof ast === "object" && ast !== null && "location" in ast) {
        this._loc = ast.location
      }
    };

    get to_s() {
      return this._string
    };

    get to_str() {
      return this._string
    };

    get length() {
      return this._string.length
    };

    empty() {
      return this._string.length === 0
    };

    start_with(...args) {
      return this._string.startsWith(...args)
    };

    startsWith(...args) {
      return this._string.startsWith(...args)
    };

    end_with(...args) {
      return this._string.endsWith(...args)
    };

    endsWith(...args) {
      return this._string.endsWith(...args)
    };

    at(index) {
      return index < 0 ? this._string[index + this._string.length] : this._string[index]
    };

    toString(_=null) {
      return this.to_s
    }
  };

  ;

  class Line {
    get indent() {
      return this._indent
    };

    set indent(indent) {
      this._indent = indent
    };

    constructor(...tokens) {
      this._tokens = tokens;
      this._indent = 0
    };

    append(token) {
      this._tokens.push(token);
      return this
    };

    push(...tokens) {
      this._tokens.push(...tokens);
      return this
    };

    pop() {
      return this._tokens.pop()
    };

    get first() {
      return this._tokens.first
    };

    get last() {
      return this._tokens.last
    };

    get length() {
      return this._tokens.length
    };

    at(index) {
      return this._tokens[index]
    };

    set(index, value) {
      return this._tokens[index] = value
    };

    find(block) {
      return this._tokens.find(block)
    };

    rindex(block) {
      return this._tokens.rindex(block)
    };

    each(block) {
      return this._tokens.forEach(block)
    };

    each_with_index(block) {
      return this._tokens.forEach(block)
    };

    map(block) {
      return this._tokens.map(block)
    };

    include(item) {
      return this._tokens.some(t => (t ?? "").toString() === (item ?? "").toString())
    };

    insert(index, ...items) {
      return this._tokens.insert(index, ...items)
    };

    slice(arg) {
      let start_idx;

      if (typeof arg === "object" && arg !== null && "begin" in arg) {
        start_idx = arg.begin
      } else {
        start_idx = arg
      };

      let result = this._tokens.slice(start_idx) ?? [];
      this._tokens = this._tokens.slice(0, start_idx) ?? [];
      return result
    };

    unshift(...items) {
      this._tokens.unshift(...items);
      return this
    };

    get to_a() {
      return this._tokens.map(item => (item ?? "").toString())
    };

    join(sep="") {
      return this._tokens.map(item => (item ?? "").toString()).join(sep)
    };

    comment() {
      let first_token = this.find(token => token.length !== 0);
      return first_token?.startsWith("//")
    };

    get _comment() {
      let first_token = this.find(token => token.length !== 0);
      return first_token?.startsWith("//")
    };

    empty() {
      return this._tokens.every(token => token.length === 0)
    };

    get _empty() {
      return this._tokens.every(token => token.length === 0)
    };

    get to_s() {
      if (this._empty) {
        return ""
      } else if (["case ", "default:"].includes((this._tokens[0] ?? "").toString())) {
        return " ".repeat(Math.max(0, this.indent - 2)) + this.join("")
      } else if (this.indent > 0) {
        return " ".repeat(this.indent) + this.join("")
      } else {
        return this.join("")
      }
    };

    toString(_=null) {
      return this.to_s
    };

    get to_ary() {
      return this._tokens
    }
  };

  ;
  ;
  ;
  Line.prototype.splice = Line.prototype.slice;

  class Serializer {
    get timestamps() {
      return this._timestamps
    };

    get file_name() {
      return this._file_name
    };

    set file_name(file_name) {
      this._file_name = file_name
    };

    constructor() {
      this._sep = "; ";
      this._nl = "";
      this._ws = " ";
      this._width = 80;
      this._indent = 0;
      this._lines = [new Line];
      this._line = this._lines.last;
      this._timestamps = {};
      this._ast = null;
      this._file_name = ""
    };

    timestamp(file) {
      if (file) {
        if (File.exist(file)) return this._timestamps[file] = File.mtime(file)
      }
    };

    uptodate() {
      if (this._timestamps.length === 0) return false;
      return this._timestamps.every((file, mtime) => File.mtime(file) === mtime)
    };

    get mtime() {
      if (this._timestamps.length === 0) return Time.now;
      return this._timestamps.values.max
    };

    get enable_vertical_whitespace() {
      this._sep = ";\n";
      this._nl = "\n";
      this._ws = this._nl;
      this._indent = 2;
      return this._indent
    };

    reindent(lines) {
      let indent = 0;

      for (let line of lines) {
        let first = line.find(token => token.length !== 0);

        if (first) {
          let last = line.at(line.rindex(token => token.length !== 0));

          if ((first.startsWith("<") && line.includes(">")) || (last.endsWith(">") && line.includes("<"))) {
            let node = line.join("").match(/.*?(<.*)/)?.[1];
            if (node.startsWith("</")) indent -= this._indent;
            line.indent = indent;
            node = line.join("").match(/.*(<.*)/)?.[1];
            if (!node.includes("</") && !node.includes("/>")) indent += this._indent
          } else {
            if (")}]".includes((first ?? "").toString()[0]) && indent >= this._indent) {
              indent -= this._indent
            };

            line.indent = indent;
            if ("({[".includes((last ?? "").toString().at(-1))) indent += this._indent
          }
        } else {
          line.indent = indent
        }
      }
    };

    get respace() {
      if (this._indent === 0) return;
      this.reindent(this._lines);

      for (let i = this._lines.length - 3; i >= 0; i--) {
        if (this._lines[i].length === 0) {
          this._lines.delete_at(i)
        } else if (this._lines[i + 1]._comment && !this._lines[i]._comment && this._lines[i].indent === this._lines[i + 1].indent) {
          this._lines.insert(i + 1, new Line)
        } else if (this._lines[i].indent === this._lines[i + 1].indent && this._lines[i + 1].indent < parseInt(this._lines[i + 2]?.indent) && !this._lines[i]._comment) {
          this._lines.insert(i + 1, new Line)
        } else if (this._lines[i].indent > this._lines[i + 1].indent && this._lines[i + 1].indent === parseInt(this._lines[i + 2]?.indent) && this._lines[i + 2]?.length !== 0) {
          this._lines.insert(i + 2, new Line)
        }
      }
    };

    put(string) {
      let parts, first;

      if (typeof string === "string" && string.includes("\n")) {
        parts = string.split("\n");

        while (parts.length !== 0 && parts.last.length === 0) {
          parts.pop()
        };

        first = parts.shift();
        if (first !== null) this._line.push(new Token(first, this._ast));

        for (let part of parts) {
          this._lines.push(new Line(new Token(part, this._ast)))
        };

        if (string.endsWith("\n")) this._lines.push(new Line);
        this._line = this._lines.last;
        return this._line
      } else {
        return this._line.push(new Token(string, this._ast))
      }
    };

    put_raw(string) {
      return this._line.push(new Token(string.replaceAll("\r", "\n"), this._ast))
    };

    puts(string) {
      if (typeof string === "string" && string.includes("\n")) {
        this.put(string)
      } else {
        this._line.push(new Token(string, this._ast))
      };

      this._line = new Line;
      return this._lines.push(this._line)
    };

    sput(string) {
      if (typeof string === "string" && string.includes("\n")) {
        this._line = new Line;
        this._lines.push(this._line);
        return this.put(string)
      } else {
        this._line = new Line(new Token(string, this._ast));
        return this._lines.push(this._line)
      }
    };

    get output_location() {
      return [this._lines.length - 1, this._line.length]
    };

    insert(mark, line) {
      return mark.last === 0 ? this._lines.insert(
        mark.first,
        new Line(new Token(line.chomp(), this._ast))
      ) : this._lines[mark.first].insert(
        mark.last,
        new Token(line, this._ast)
      )
    };

    capture(block) {
      let mark = this.output_location;
      block();
      let lines = this._lines.splice(mark.first + 1) ?? [];
      this._line = this._lines.last;

      if (lines.length === 0) {
        lines = [this._line.splice(mark.last) ?? []]
      } else if (this._line.length !== mark.last) {
        lines.unshift(this._line.splice(mark.last) ?? [])
      };

      return lines.map(l => (
        typeof l === "object" && l !== null && "join" in l ? l.join("") : l.map(item => (
          (item ?? "").toString()
        )).join("")
      )).join(this._ws)
    };

    wrap(open="{", close="}", block) {
      let popped;

      if (!block) {
        if (typeof open === "function") {
          block = open;
          open = "{";
          close = "}"
        }
      };

      this.puts(open);
      let mark = this.output_location;
      block();

      if (this._lines.length > mark.first + 1 || this._lines[mark.first - 1].join("").length + this._line.join("").length >= this._width) {
        return this.sput(close)
      } else {
        this._line = this._lines[mark.first - 1];
        this._line.pop();
        popped = this._lines.pop();
        return this._line.push(...popped.to_ary)
      }
    };

    compact(block) {
      let close;
      let mark = this.output_location;
      block();
      if (this._lines.length - mark.first <= 1) return;
      if (this._indent === 0) return;
      let work = [];
      let len = 0;
      let trail = null;
      let split = null;
      let slice = this._lines.slice(mark.first);
      this.reindent(slice);
      let index = 0;

      while (index < slice.length) {
        let line = slice[index];
        if (line.length === 0) line.push(new Token("", null));

        if (line.first.startsWith("//")) {
          len += this._width
        } else {
          if (trail === line.indent && this._indent > 0) {
            work.push(new Token(" ", null));
            len++
          };

          len += line.map(item => item.length).reduce((a, b) => a + b, 0);
          work.push(...line.to_ary);

          if (trail === this._indent && line.indent === this._indent) {
            split = [len, work.length, index];
            if (len >= this._width - 10) break
          };

          trail = line.indent
        };

        index++
      };

      if (len < this._width - 10) {
        this._lines.splice(mark.first);
        this._lines.push(new Line(...work));
        this._line = this._lines.last;
        return this._line
      } else if (split && split[0] < this._width - 10) {
        if (slice[split[2]].indent < parseInt(slice[split[2] + 1]?.indent)) {
          close = slice.pop();
          slice.at(-1).push(...close.to_ary);
          this._lines[mark.first] = new Line(...work.slice(0, split[1] - 1 + 1));
          this._lines.splice(mark.first + 1);

          for (let line of slice.slice(split[2] + 1)) {
            this._lines.push(line)
          };

          this._line = this._lines.last;
          return this._line
        }
      }
    };

    get to_s() {
      if (this._str) return this._str;
      this.respace;
      this._str = this._lines.map(item => (item ?? "").toString()).join(this._nl);
      return this._str
    };

    get to_str() {
      return this._str ??= (null ?? "").toString()
    };

    toString(_=null) {
      if (this._str) return this._str;
      this.respace;
      this._str = this._lines.map(item => (item ?? "").toString()).join(this._nl);
      return this._str
    };

    static BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    vlq(...mark) {
      let diffs;

      if (!this._mark) {
        diffs = mark;
        this._mark = [0, 0, 0, 0, 0, 0]
      } else {
        if (this._mark[0] === mark[0]) {
          if (this._mark[4] === mark[4] && this._mark[3] === mark[3]) return;
          if (this._mappings !== "") this._mappings += ","
        };

        diffs = mark.zip(this._mark).map(([a, b]) => a - b)
      };

      while (this._mark[0] < mark[0]) {
        this._mappings += ";";
        this._mark[0]++;
        diffs[1] = mark[1]
      };

      this._mark.splice(0, mark.length - 0, ...mark);

      for (let diff of diffs.slice(1)) {
        let data, encoded;

        if (diff < 0) {
          data = (-diff << 1) + 1
        } else {
          data = diff << 1
        };

        if (data <= 31) {
          encoded = Serializer.BASE64[data]
        } else {
          encoded = "";

          do {
            let digit = data & 31;
            data >>= 5;
            if (data > 0) digit |= 32;
            encoded += Serializer.BASE64[digit]
          } while (data > 0)
        };

        this._mappings += encoded
      }
    };

    get sourcemap() {
      this.respace;
      this._mappings = "";
      let sources = [];
      let names = [];
      this._mark = null;

      this._lines.forEach((line, row) => {
        let col = line.indent;

        for (let token of line) {
          if (typeof token === "object" && token !== null && "loc" in token && token.loc && typeof token.loc === "object" && token.loc !== null && "expression" in token.loc && token.loc.expression) {
            let pos = token.loc.expression.begin_pos;
            let buffer = token.loc.expression.source_buffer;
            let source_index = sources.indexOf(buffer);

            if (!source_index) {
              source_index = sources.length;
              this.timestamp(buffer.name);
              sources.push(buffer)
            };

            let line_num = buffer.line_for_position(pos) - 1;
            let column = buffer.column_for_position(pos);
            let name = null;

            if (["lvasgn", "lvar"].includes(token.ast.type)) {
              name = token.ast.children.first
            } else if (["casgn", "const"].includes(token.ast.type)) {
              if (token.ast.children.first === null) name = token.ast.children[1]
            };

            if (name) {
              let index = names.find_index(name);

              if (!index) {
                index = names.length;
                names.push(name)
              };

              this.vlq(row, col, source_index, line_num, column, index)
            } else {
              this.vlq(row, col, source_index, line_num, column)
            }
          };

          col += token.length
        }
      });

      this._sourcemap = {
        version: 3,
        file: this._file_name,
        sources: sources.map(item => item.name),
        names: names.map(item => (item ?? "").toString()),
        mappings: this._mappings
      };

      return this._sourcemap
    }
  };

  Serializer.prototype._compact = Serializer.prototype.compact;

  class Error extends NotImplementedError {
    constructor(message, ast) {
      let loc = ast.loc;

      if (loc) {
        if (typeof loc === "object" && loc !== null && "expression" in loc && loc.expression) {
          message += " at " + (loc.expression.source_buffer.name ?? "").toString();
          message += ":" + JSON.stringify(loc.expression.line);
          message += ":" + (loc.expression.column ?? "").toString()
        } else if (typeof loc === "object" && loc !== null && !Array.isArray(loc) && loc.start_offset) {
          message += " at offset " + (loc.start_offset ?? "").toString()
        }
      };

      super(message)
    }
  };

  class Converter extends Serializer {
    get ast() {
      return this._ast
    };

    set ast(ast) {
      this._ast = ast
    };

    static LOGICAL = ["and", "not", "or"];

    static OPERATORS = [
      ["[]", "[]="],
      ["not", "!"],
      ["**"],
      ["*", "/", "%"],
      ["+", "-"],
      [">>", "<<"],
      ["&"],
      ["^", "|"],
      ["<=", "<", ">", ">="],
      ["==", "!=", "===", "!==", "=~", "!~"],
      ["and", "or"]
    ];

    static INVERT_OP = {
      "<": ">=",
      "<=": ">",
      "==": "!=",
      "!=": "==",
      ">": "<=",
      ">=": "<",
      "===": "!=="
    };

    static GROUP_OPERATORS = [
      "begin",
      "dstr",
      "dsym",
      "and",
      "or",
      "nullish",
      "casgn",
      "if"
    ];

    static VASGN = ["cvasgn", "ivasgn", "gvasgn", "lvasgn"];

    static JS_RESERVED = Object.freeze([
      "catch",
      "const",
      "continue",
      "debugger",
      "default",
      "delete",
      "enum",
      "export",
      "extends",
      "finally",
      "function",
      "import",
      "instanceof",
      "new",
      "switch",
      "throw",
      "try",
      "typeof",
      "var",
      "void",
      "with",
      "let",
      "static",
      "implements",
      "interface",
      "package",
      "private",
      "protected",
      "public"
    ]);

    get binding() {
      return this._binding
    };

    set binding(binding) {
      this._binding = binding
    };

    get ivars() {
      return this._ivars
    };

    set ivars(ivars) {
      this._ivars = ivars
    };

    get namespace() {
      return this._namespace
    };

    set namespace(namespace) {
      this._namespace = namespace
    };

    constructor(ast, comments, vars={}) {
      super();
      [this._ast, this._comments, this._vars] = [ast, comments, {...vars}];
      this._varstack = [];
      this._scope = ast;
      this._inner = null;
      this._rbstack = [];
      this._next_token = "return";
      this._handlers = {};

      for (let name of Converter._handlers) {
        this._handlers[name] = this[`on_${(name ?? "").toString().replace(
          /!$/m,
          "_bang"
        ).replace(/\?$/m, "_q") ?? ""}`].bind(this)
      };

      this._state = null;
      this._block_this = null;
      this._block_depth = null;
      this._prop = null;
      this._instance_method = null;
      this._prototype = null;
      this._class_parent = null;
      this._class_name = null;
      this._jsx = false;
      this._autobind = true;
      this._eslevel = 2_020;
      this._strict = false;
      this._comparison = "equality";
      this._or = "auto";
      this._truthy = "js";
      this._boolean_context = false;
      this._need_truthy_helpers = [];
      this._underscored_private = true;
      this._nullish_to_s = false;
      this._redoable = false
    };

    set width(width) {
      this._width = width;
      return this._width
    };

    get convert() {
      let helpers;
      this.scope(this._ast);

      if (this._strict) {
        if (this._sep === "; ") {
          this._lines.first.unshift(`"use strict"${this._sep ?? ""}`)
        } else {
          this._lines.unshift(new Line("\"use strict\";"))
        }
      };

      if (this._need_truthy_helpers.length !== 0) {
        helpers = [];

        if (this._need_truthy_helpers.includes("T")) {
          helpers.push("let $T = (v) => v !== false && v != null")
        };

        if (this._need_truthy_helpers.includes("ror")) {
          helpers.push("let $ror = (a, b) => $T(a) ? a : b()")
        };

        if (this._need_truthy_helpers.includes("rand")) {
          helpers.push("let $rand = (a, b) => $T(a) ? b() : a")
        };

        if (this._sep === "; ") {
          return this._lines.first.unshift(helpers.join(this._sep) + this._sep)
        } else {
          for (let helper of helpers.reverse()) {
            this._lines.unshift(new Line(helper + ";"))
          }
        }
      }
    };

    operator_index(op) {
      return Converter.OPERATORS.indexOf(Converter.OPERATORS.find(el => (
        el.includes(op)
      ))) ?? -1
    };

    scope(ast, args=null) {
      {
        let scope;
        let inner;

        try {
          scope = this._scope;
          this._scope = ast;
          inner = this._inner;
          this._inner = null;
          let mark = this.output_location;
          this._varstack.push(this._vars);
          if (args) this._vars = args;

          this._vars = Object.fromEntries(Object.entries(this._vars).map(([key, value]) => (
            [key, true]
          )));

          this.parse(ast, "statement");

          let vars = Object.keys(Object.fromEntries(Object.entries(this._vars).filter(([key, value]) => (
            value === "pending"
          ))));

          if (vars.length !== 0) {
            this.insert(
              mark,
              `let ${vars.map(v => this.jsvar(v)).join(", ") ?? ""}${this._sep ?? ""}`
            );

            for (let $var of vars) {
              this._vars[$var] = true
            }
          }
        } finally {
          this._vars = this._varstack.pop();
          this._scope = scope;
          this._inner = inner
        }
      }
    };

    jscope(ast, args=null) {
      try {
        this._varstack.push(this._vars);
        if (args) this._vars = args;

        this._vars = Object.fromEntries(Object.entries(this._vars).map(([key, value]) => (
          [key, true]
        )));

        this.parse(ast, "statement")
      } finally {
        let pending = Object.fromEntries(Object.entries(this._vars).filter(([key, value]) => (
          value === "pending"
        )));

        this._vars = this._varstack.pop();
        Object.assign(this._vars, pending)
      }
    };

    s(type, ...args) {
      return new globalThis.Ruby2JS.Node(type, args)
    };

    jsvar(name) {
      name = (name ?? "").toString();
      return Converter.JS_RESERVED.includes(name) ? `$${name ?? ""}` : name
    };

    get strict() {
      return this._strict
    };

    set strict(strict) {
      this._strict = strict
    };

    get eslevel() {
      return this._eslevel
    };

    set eslevel(eslevel) {
      this._eslevel = eslevel
    };

    get module_type() {
      return this._module_type
    };

    set module_type(module_type) {
      this._module_type = module_type
    };

    get comparison() {
      return this._comparison
    };

    set comparison(comparison) {
      this._comparison = comparison
    };

    get or() {
      return this._or
    };

    set or(or) {
      this._or = or
    };

    get truthy() {
      return this._truthy
    };

    set truthy(truthy) {
      this._truthy = truthy
    };

    get underscored_private() {
      return this._underscored_private
    };

    set underscored_private(underscored_private) {
      this._underscored_private = underscored_private
    };

    get nullish_to_s() {
      return this._nullish_to_s
    };

    set nullish_to_s(nullish_to_s) {
      this._nullish_to_s = nullish_to_s
    };

    get es2020() {
      return this._eslevel >= 2_020
    };

    get es2021() {
      return this._eslevel >= 2_021
    };

    get es2022() {
      return this._eslevel >= 2_022
    };

    get es2023() {
      return this._eslevel >= 2_023
    };

    get es2024() {
      return this._eslevel >= 2_024
    };

    get es2025() {
      return this._eslevel >= 2_025
    };

    static handle(...types) {
      let block = types.pop();

      for (let type of types) {
        this.constructor.prototype[`on_${type ?? ""}`] = block;
        Converter._handlers.push(type)
      }
    };

    comments(ast) {
      let list;
      let [comment_list, comment_key] = this.find_comment_entry(ast);

      if (ast.loc && typeof ast.loc === "object" && ast.loc !== null && "expression" in ast.loc && ast.loc.expression) {
        let expression = ast.loc.expression;

        list = comment_list.filter((comment) => {
          if (!comment.loc || typeof comment.loc !== "object" || comment.loc === null || !("expression" in comment.loc) || !comment.loc.expression) {
            return false
          };

          return expression.source_buffer === comment.loc.expression.source_buffer && comment.loc.expression.begin_pos < expression.end_pos
        })
      } else {
        list = comment_list
      };

      if (comment_key in this._comments && this._comments[comment_key]) {
        this._comments[comment_key] -= list
      };

      return list.map((comment) => {
        let text = comment.text;
        if (/#\s*Pragma:/i.test(text)) return null;

        if (text.startsWith("=begin")) {
          return text.includes("*/") ? text.replace(/^=begin/, "").replace(
            /^=end\Z/m,
            ""
          ).replaceAll(/^/gm, "//") : text.replace(/^=begin/, "/*").replace(
            /^=end\Z/m,
            "*/"
          )
        } else if (text.startsWith("#")) {
          return text.replace(/^#/m, "//") + "\n"
        } else {
          return "// " + text + "\n"
        }
      }).compact
    };

    find_comment_entry(ast) {
      let comment_list = typeof this._comments === "object" && this._comments !== null && "get" in this._comments ? this._comments.get(ast) : this._comments[ast];
      if (Array.isArray(comment_list)) return [comment_list, ast];
      return [[], ast]
    };

    find_first_location(ast) {
      if (typeof ast !== "object" || ast === null || !("children" in ast)) {
        return null
      };

      if (ast.loc && typeof ast.loc === "object" && ast.loc !== null && "expression" in ast.loc && ast.loc.expression) {
        return ast.loc.expression
      };

      for (let child of ast.children) {
        if (!this.ast_node(child)) continue;
        let loc = this.find_first_location(child);
        if (loc) return loc
      };

      return null
    };

    ast_node(obj) {
      if (!obj) return false;
      return typeof obj === "object" && obj !== null && "type" in obj && typeof obj === "object" && obj !== null && "children" in obj
    };

    parse(ast, state="expression") {
      {
        let oldstate;
        let oldast;

        try {
          oldstate = this._state;
          this._state = state;
          oldast = this._ast;
          this._ast = ast;
          if (!ast) return;
          let handler = this._handlers[ast.type];
          if (!handler) throw new Error(`unknown AST type ${ast.type ?? ""}`, ast);

          if (state === "statement") {
            for (let comment of this.comments(ast)) {
              this.puts(comment.chomp())
            }
          };

          handler(...ast.children)
        } finally {
          this._ast = oldast;
          this._state = oldstate
        }
      }
    };

    parse_all(...args) {
      let last_arg = args.at(-1);
      this._options = typeof last_arg === "object" && last_arg !== null && !Array.isArray(last_arg) && typeof last_arg !== "object" || last_arg === null || !("type" in last_arg) ? args.pop() : {};
      let sep = (this._options.join ?? "").toString();
      let state = this._options.state ?? "expression";
      let index = 0;

      for (let arg of args) {
        if (index !== 0) this.put(sep);
        this.parse(arg, state);
        if (arg !== this.s("begin")) index++
      }
    };

    group(ast) {
      if (["dstr", "dsym"].includes(ast.type)) {
        return this.parse(ast)
      } else {
        this.put("(");
        this.parse(ast);
        return this.put(")")
      }
    };

    redoable(block) {
      {
        let save_redoable;

        try {
          save_redoable = this._redoable;

          let has_redo = node => (
            node.children.some((child) => {
              if (typeof child !== "object" || child === null || !("type" in child) || typeof child !== "object" || child === null || !("children" in child)) {
                return false
              };

              if (child.type === "redo") return true;

              if (["for", "while", "while_post", "until", "until_post"].includes(child.type)) {
                return false
              };

              return has_redo(child)
            })
          );

          this._redoable = has_redo(this._ast);

          if (this._redoable) {
            this.put("let ");
            this.put(`redo$${this._sep ?? ""}`);
            this.puts("do {");
            this.put(`redo$ = false${this._sep ?? ""}`);
            this.scope(block);
            this.put(`${this._nl ?? ""}} while(redo$)`)
          } else {
            this.scope(block)
          }
        } finally {
          this._redoable = save_redoable
        }
      }
    };

    timestamp(file) {
      super.timestamp(file);
      if (!file) return;

      let walk = (ast) => {
        if (ast.loc && typeof ast.loc === "object" && ast.loc !== null && "expression" in ast.loc && ast.loc.expression) {
          let filename = ast.loc.expression.source_buffer.name;

          if (filename && filename.length !== 0) {
            this._timestamps[filename] ??= (() => {
              try {
                File.mtime(filename)
              } catch {
                null
              }
            })()
          }
        };

        for (let child of ast.children) {
          if (typeof child === "object" && child !== null && "type" in child && typeof child === "object" && child !== null && "children" in child) {
            walk(child)
          }
        }
      };

      if (this._ast) return walk(this._ast)
    };

    on_arg(arg, unknown=null) {
      if (unknown) {
        throw new Error(`argument ${JSON.stringify(unknown) ?? ""}`, this._ast)
      };

      return this.put(this.jsvar(arg))
    };

    on_blockarg(arg, unknown=null) {
      if (unknown) {
        throw new Error(`argument ${JSON.stringify(unknown) ?? ""}`, this._ast)
      };

      return this.put(this.jsvar(arg))
    };

    on_shadowarg(arg, unknown=null) {
      if (unknown) {
        throw new Error(`argument ${JSON.stringify(unknown) ?? ""}`, this._ast)
      };

      return null
    };

    on_args(...args) {
      let kwargs = [];

      while (args.last && ["kwarg", "kwoptarg", "kwrestarg"].includes(args.last.type)) {
        kwargs.unshift(args.pop())
      };

      if (kwargs.length === 1 && kwargs.last.type === "kwrestarg") {
        args.push(this.s("arg", ...kwargs.last.children))
      };

      this.parse_all(...args, {join: ", "});

      if (kwargs.length !== 0) {
        if (args.length !== 0) this.put(", ");
        this.put("{ ");

        kwargs.forEach((kw, index) => {
          if (index !== 0) this.put(", ");

          if (kw.type === "kwarg") {
            this.put(this.jsvar(kw.children.first))
          } else if (kw.type === "kwoptarg") {
            this.put(this.jsvar(kw.children.first));
            let default_val = kw.children.last;
            let is_undefined = default_val.type === "send" && default_val.children[0] === null && default_val.children[1] === "undefined";

            if (!is_undefined) {
              this.put("=");
              this.parse(kw.children.last)
            }
          } else if (kw.type === "kwrestarg") {
            this.put("...");
            this.put(this.jsvar(kw.children.first))
          }
        });

        this.put(" }");
        if (!kwargs.some(kw => kw.type === "kwarg")) return this.put(" = {}")
      }
    };

    on_mlhs(...args) {
      this.put("[");
      this.parse_all(...args, {join: ", "});
      return this.put("]")
    };

    on_forward_args() {
      return this.put("...args")
    };

    on_forwarded_args() {
      return this.put("...args")
    };

    on_array(...items) {
      let splat = items.rindex(a => a.type === "splat");

      if (splat) {
        if (items.length <= 1) {
          this.put("[");
          this.parse_all(...items, {join: ", "});
          return this.put("]")
        } else {
          return this._compact(() => {
            this.puts("[");
            this.parse_all(...items, {join: `,${this._ws ?? ""}`});
            return this.sput("]")
          })
        }
      } else if (items.length <= 1) {
        this.put("[");
        this.parse_all(...items, {join: ", "});
        return this.put("]")
      } else {
        return this._compact(() => {
          this.puts("[");
          this.parse_all(...items, {join: `,${this._ws ?? ""}`});
          return this.sput("]")
        })
      }
    };

    on_assign(target, ...args) {
      let copy, shadow, body;
      let collapsible = false;

      let nonprop = (node) => {
        if (!this.ast_node(node)) return false;
        if (node.type === "pair" && node.children.first.type === "prop") return false;
        if (node.type !== "def") return true;
        if ((node.children.first ?? "").toString().endsWith("=")) return false;
        return node.is_method()
      };

      if (args.length === 1 && args.first.type === "hash" && args.first.children.length === 1) {
        collapsible = true
      };

      if (args.length === 1 && args.first.type === "class_module" && args.first.children.length === 3 && nonprop(args.first.children.last)) {
        collapsible = true
      };

      if (!collapsible && args.every((arg) => {
        switch (arg.type) {
        case "pair":
        case "hash":
        case "class_module":
          return arg.children.every(child => nonprop(child));

        case "const":
          return false;

        default:
          return true
        }
      })) {
        return this.parse(this.s(
          "send",
          this.s("const", null, "Object"),
          "assign",
          target,
          ...args
        ))
      } else {
        if (target === this.s("hash")) {
          copy = [this.s("gvasgn", "$$", target)];
          target = this.s("gvar", "$$");
          shadow = [this.s("shadowarg", "$$")]
        } else if (collapsible || (["send", "const"].includes(target.type) && target.children.length === 2 && target.children[0] === null) || (target.type === "attr" && target.children.length === 2)) {
          copy = [];
          shadow = []
        } else {
          copy = [this.s("gvasgn", "$0", target)];
          target = this.s("gvar", "$0");
          shadow = [this.s("shadowarg", "$0")]
        };

        body = [...copy, ...args.map((modname) => {
          let pair;

          if (modname.type === "hash" && modname.children.every(pair => (
            pair.children.first.type === "prop"
          ))) {
            if (modname.children.length === 1) {
              pair = modname.children.first;

              return this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperty",
                target,
                this.s("sym", pair.children.first.children.last),

                this.s("hash", ...Object.entries(pair.children.last).map(entry => (
                  this.s("pair", this.s("sym", entry[0]), entry[1])
                )))
              )
            } else {
              pair = modname.children.first;

              return this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperties",
                target,

                this.s("hash", ...modname.children.map(pair => (
                  this.s(
                    "pair",
                    this.s("sym", pair.children.first.children.last),

                    this.s("hash", ...Object.entries(pair.children.last).map(entry => (
                      this.s("pair", this.s("sym", entry[0]), entry[1])
                    )))
                  )
                )))
              )
            }
          } else if (modname.type === "hash" && modname.children.every(child => (
            nonprop(child)
          ))) {
            return this.s("begin", ...modname.children.map(pair => (
              pair.children.first.type === "prop" ? this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperty",
                target,
                this.s("sym", pair.children.first.children.last),

                this.s("hash", ...Object.entries(pair.children.last).map(entry => (
                  this.s("pair", this.s("sym", entry[0]), entry[1])
                )))
              ) : this.s("send", target, "[]=", ...pair.children)
            )))
          } else if (modname.type === "class_module" && modname.children.slice(2).every(child => (
            nonprop(child)
          ))) {
            return this.s("begin", ...modname.children.slice(2).map(pair => (
              this.s(
                "send",
                target,
                "[]=",
                this.s("sym", pair.children.first),
                pair.updated("defm", [null, ...pair.children.slice(1)])
              )
            )))
          } else {
            return this.s(
              "send",
              this.s("const", null, "Object"),
              "defineProperties",
              target,

              this.s(
                "send",
                this.s("const", null, "Object"),
                "getOwnPropertyDescriptors",
                modname
              )
            )
          }
        })];

        if (this._state === "statement" && shadow.length === 0) {
          return this.parse(this.s("begin", ...body))
        } else {
          if (this._state === "expression") body.push(this.s("return", target));

          return this.parse(this.s(
            "send",

            this.s(
              "block",
              this.s("send", null, "lambda"),
              this.s("args", ...shadow),
              this.s("begin", ...body)
            ),

            "[]"
          ))
        }
      }
    };

    on_begin(...statements) {
      let state = this._state;
      let props = false;

      if (state === "expression" && statements.length === 0) {
        this.puts("null");
        return
      };

      statements.splice(...[0, statements.length].concat(statements.map((statement) => {
        switch (statement && statement.type) {
        case "defs":
        case "defp":
          props = true;
          this._ast = statement;
          this.transform_defs(...statement.children);
          break;

        case "prop":
          props = true;
          statement;
          break;

        default:
          return statement
        }
      })));

      if (props) {
        if (props) this.combine_properties(statements);

        statements.splice(
          0,
          statements.length,
          ...statements.filter(x => x !== null)
        )
      };

      statements = statements.filter(s => (
        !(typeof s === "object" && s !== null && "type" in s && s.type === "hide")
      ));

      return this.parse_all(...statements, {state, join: this._sep})
    };

    combine_properties(body) {
      for (let i = 0; i < body.length - 1; i++) {
        if (!body[i] || body[i].type !== "prop") continue;

        for (let j = i + 1; j < body.length; j++) {
          if (!body[j] || body[j].type !== "prop") break;

          if (body[i].children[0] === body[j].children[0]) {
            for (let node of [body[i], body[j]]) {
              let node_comments = this._comments[node];

              if (node_comments && node_comments.length !== 0) {
                for (let [key, value] of node.children[1].values.first) {
                  if (["get", "set"].includes(key) && this.ast_node(value)) {
                    this._comments[value] = this._comments[node];
                    break
                  }
                }
              }
            };

            let merge = Object.fromEntries([
              ...body[i].children[1].to_a,
              ...body[j].children[1].to_a
            ].reduce(
              ($acc, [name, value]) => {
                let $key = (name ?? "").toString();
                ($acc[$key] = $acc[$key] ?? []).push([name, value]);
                return $acc
              },

              {}
            ).map(([name, values]) => (
              [
                name,
                values.map(item => item.last).reduce((a, b) => ({...a, ...b}))
              ]
            )));

            body[j] = this.s("prop", body[j].children[0], merge);
            body[i] = null;
            break
          }
        }
      }
    };

    on_block(call, args, block) {
      let $function;
      let last_arg = call.children.last;
      let is_async_arg = typeof last_arg === "object" && last_arg !== null && "type" in last_arg && last_arg.type === "send" && last_arg.children[0] === null && last_arg.children[1] === "async" && last_arg.children.length === 2;

      if (is_async_arg) {
        return this.parse(call.updated(
          null,

          [...call.children.slice(0, -1), this.s(
            "send",
            null,
            "async",
            this.s("block", this.s("send", null, "proc"), args, block)
          )]
        ))
      };

      if (this._state === "statement" && args.children.length === 1 && call.children.first && call.children.first.type === "begin" && call.children[1] === "step" && [
        "irange",
        "erange"
      ].includes(call.children.first.children.first.type)) {
        {
          let vars;
          let next_token;

          try {
            vars = {...this._vars};
            next_token = this._next_token;
            this._next_token = "continue";
            let $var = args.children.first;
            let expression = call.children.first.children.first;
            let comp = expression.type === "irange" ? "<=" : "<";
            this.put("for (let ");
            this.parse($var);
            this.put(" = ");
            this.parse(expression.children.first);
            this.put("; ");
            this.parse($var);

            if (call.children[2].type === "int" && call.children[2].children[0] < 0) {
              this.put(` ${comp.replace("<", ">") ?? ""} `);
              this.parse(expression.children.last);
              this.put("; ");

              this.parse(
                this.s(
                  "op_asgn",
                  $var,
                  "-",
                  this.s("int", -call.children[2].children[0])
                ),

                "statement"
              )
            } else {
              this.put(` ${comp ?? ""} `);
              this.parse(expression.children.last);
              this.put("; ");

              this.parse(
                this.s("op_asgn", $var, "+", call.children[2]),
                "statement"
              )
            };

            this.puts(") {");
            this.scope(block);
            this.sput("}")
          } finally {
            this._next_token = next_token;
            this._vars = vars
          }
        }
      } else if (call.children[0] === null && call.children[1] === "function" && call.children.slice(2).every(child => (
        child.type === "lvar" || (child.type === "send" && child.children.length === 2 && child.children[0] === null && typeof child.children[1] !== "object" || child.children[1] === null || !("type" in child.children[1]))
      ))) {
        args = call.children.slice(2).map(arg => this.s("arg", arg.children.last));

        return this.parse(this._ast.updated(
          "block",
          [this.s("send", null, "proc"), this.s("args", ...args), block]
        ))
      } else {
        block ??= this.s("begin");
        $function = this._ast.updated("def", [null, args, block]);

        return this.parse(
          this.s(call.type, ...call.children, $function),
          this._state
        )
      }
    };

    on_numblock(call, count, block) {
      return this.parse(this.s(
        "block",
        call,

        this.s("args", ...Array.from({length: count}, (_, $i) => {
          let i = $i + 1;
          return this.s("arg", `_${i ?? ""}`)
        })),

        block
      ))
    };

    on_block_pass(arg) {
      return this.parse(arg)
    };

    on_true() {
      return this.put((this._ast.type ?? "").toString())
    };

    on_false() {
      return this.put((this._ast.type ?? "").toString())
    };

    on_break(n=null) {
      if (n) throw new Error(`break argument ${JSON.stringify(n) ?? ""}`, this._ast);

      if (this._next_token === "return") {
        throw new Error("break outside of loop", this._ast)
      };

      return this.put("break")
    };

    on_case(expr, ...rest) {
      let other;
      let whens = rest;
      if (whens.last?.type !== "when") other = whens.pop();

      {
        let inner;

        try {
          if (this._state === "expression") {
            this.parse(this.s("kwbegin", this._ast), this._state);
            return
          };

          inner = this._inner;
          this._inner = this._ast;

          let has_range = whens.some(node => (
            node.children.some(child => ["irange", "erange"].includes(child?.type))
          ));

          if (has_range) {
            this.puts("switch (true) {")
          } else {
            this.put("switch (");
            this.parse(expr);
            this.puts(") {")
          };

          whens.forEach((node, index) => {
            if (index !== 0) this.puts("");
            let $masgn_temp = node.children.slice();
            let code = $masgn_temp.pop();
            let values = $masgn_temp;

            for (let value of values) {
              this.put("case ");

              if (has_range) {
                if (value.type === "irange") {
                  this.parse(expr);
                  this.put(" >= ");
                  this.parse(value.children.first);
                  this.put(" && ");
                  this.parse(expr);
                  this.put(" <= ");
                  this.parse(value.children.last);
                  this.put(`:${this._ws ?? ""}`)
                } else if (value.type === "erange") {
                  this.parse(expr);
                  this.put(" >= ");
                  this.parse(value.children.first);
                  this.put(" && ");
                  this.parse(expr);
                  this.put(" < ");
                  this.parse(value.children.last);
                  this.put(`:${this._ws ?? ""}`)
                } else {
                  this.parse(expr);
                  this.put(" == ");
                  this.parse(value);
                  this.put(`:${this._ws ?? ""}`)
                }
              } else {
                this.parse(value);
                this.put(`:${this._ws ?? ""}`)
              }
            };

            this.parse(code, "statement");
            let last = code;

            while (last?.type === "begin") {
              last = last.children.last
            };

            if (other || index < whens.length - 1) {
              this.put(`${this._sep ?? ""}`);
              if (last?.type !== "return") this.put(`break${this._sep ?? ""}`)
            }
          });

          if (other) {
            this.put(`${this._nl ?? ""}default:${this._ws ?? ""}`);
            this.parse(other, "statement")
          };

          this.sput("}")
        } finally {
          this._inner = inner
        }
      }
    };

    on_casgn(cbase, $var, value) {
      if (this._state === "statement") this.multi_assign_declarations;

      try {
        cbase ??= this._rbstack.map(rb => rb[$var]).compact.last;
        if (this._state === "statement" && !cbase) this.put("const ");

        if (cbase) {
          this.parse(cbase);
          this.put(".")
        };

        this.put(`${$var ?? ""} = `);
        this.parse(value)
      } finally {
        this._vars[$var] = true
      }
    };

    on_class(name, inheritance, ...body) {
      let extend, init;
      if (this._ast.type !== "class_module") extend = this._namespace.enter(name);

      if (!["class", "class_hash"].includes(this._ast.type) || extend) {
        init = null
      } else {
        if (this._ast.type === "class_hash") {
          this.parse(this._ast.updated(
            "class2",
            [null, ...this._ast.children.slice(1)]
          ))
        } else {
          this.parse(this._ast.updated("class2"))
        };

        if (this._ast.type !== "class_module") this._namespace.leave();
        return
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));

      if (body.length === 1 && body.first.type === "begin") {
        body = body.first.children.slice()
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));
      let visible = this._namespace.getOwnProps();

      body.splice(...[0, body.length].concat(body.map((m) => {
        if (this._ast.type === "class_module" && m.type === "defs" && m.children.first === this.s("self")) {
          m = m.updated("def", m.children.slice(1))
        };

        let node = ["def", "defm", "deff"].includes(m.type) ? m.children.first === "initialize" && !visible.initialize ? (() => {
          init = m;
          return null
        })() : /=/.test(m.children.first) ? (() => {
          let sym = `${(m.children.first ?? "").toString().slice(0, -1) ?? ""}`;

          return this.s("prop", this.s("attr", name, "prototype"), {[sym]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("defm", null, ...m.children.slice(1))
          }})
        })() : !m.is_method() ? (() => {
          visible[m.children[0]] = this.s("self");

          return this.s(
            "prop",
            this.s("attr", name, "prototype"),

            {[m.children.first]: {
              enumerable: this.s("true"),
              configurable: this.s("true"),

              get: this.s(
                "defm",
                null,
                m.children[1],
                m.updated("autoreturn", m.children.slice(2))
              )
            }}
          )
        })() : (() => {
          visible[m.children[0]] = this.s("autobind", this.s("self"));

          return this.s(
            "method",
            this.s("attr", name, "prototype"),
            `${(m.children[0] ?? "").toString().chomp("!").chomp("?") ?? ""}=`,
            this.s("defm", null, ...m.children.slice(1))
          )
        })() : ["defs", "defp"].includes(m.type) && m.children.first === this.s("self") ? /=$/m.test(m.children[1]) ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString().slice(0, -1)]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("def", null, ...m.children.slice(2))
          }}
        ) : !m.is_method() ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString()]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              m.children[2],
              m.updated("autoreturn", m.children.slice(3))
            )
          }}
        ) : this.s("prototype", this.s(
          "send",
          name,
          `${m.children[1] ?? ""}=`,
          this.s("defm", null, ...m.children.slice(2))
        )) : m.type === "send" && m.children.first === null ? m.children[1] === "attr_accessor" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            )
          }})
        }) : m.children[1] === "attr_reader" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "attr_writer" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "include" ? this.s(
          "send",

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),

            this.s("begin", ...m.children.slice(2).map((modname) => {
              this._namespace.defineProps(this._namespace.find(modname));

              return this.s("for", this.s("lvasgn", "$_"), modname, this.s(
                "send",
                this.s("attr", name, "prototype"),
                "[]=",
                this.s("lvar", "$_"),
                this.s("send", modname, "[]", this.s("lvar", "$_"))
              ))
            }))
          ),

          "[]"
        ) : ["private", "protected", "public"].includes(m.children[1]) ? (() => { throw new Error(`class ${m.children[1] ?? ""} is not supported`, this._ast) })() : this.s(
          "send",
          name,
          ...m.children.slice(1)
        ) : m.type === "block" && m.children.first.children.first === null ? this.s(
          "block",
          this.s("send", name, ...m.children.first.children.slice(1)),
          ...m.children.slice(1)
        ) : ["send", "block"].includes(m.type) ? m : m.type === "lvasgn" ? this.s(
          "send",
          name,
          `${m.children[0] ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "cvasgn" ? this.s(
          "send",
          name,
          `_${m.children[0].slice(2) ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "send" && m.children[0].type === "cvar" ? this.s(
          "send",
          this.s("attr", name, `_${m.children[0].children[0].slice(2) ?? ""}`),
          ...m.children.slice(1)
        ) : m.type === "casgn" && m.children[0] === null ? (() => {
          visible[m.children[1]] = name;

          return this.s(
            "send",
            name,
            `${m.children[1] ?? ""}=`,
            ...m.children.slice(2)
          )
        })() : m.type === "alias" ? this.s(
          "send",
          this.s("attr", name, "prototype"),

          `${(m.children[0].children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          ) ?? ""}=`,

          this.s(
            "attr",
            this.s("attr", name, "prototype"),
            (m.children[1].children.first ?? "").toString().replace(/[?!]$/m, "")
          )
        ) : m.type === "class" || m.type === "module" ? (() => {
          let innerclass_name = m.children.first;

          if (innerclass_name.children.first) {
            innerclass_name = innerclass_name.updated(null, [
              this.s("attr", name, innerclass_name.children[0].children.last),
              innerclass_name.children[1]
            ])
          } else {
            innerclass_name = innerclass_name.updated(
              null,
              [name, innerclass_name.children[1]]
            )
          };

          return m.updated(null, [innerclass_name, ...m.children.slice(1)])
        })() : this._ast.type === "class_module" ? m : m.type === "defineProps" ? (() => {
          this._namespace.defineProps(m.children.first);
          Object.assign(visible, m.children.first);
          return null
        })() : (() => { throw new Error(`class ${m.type ?? ""} not supported`, this._ast) })();

        if (node && this._comments[m]) {
          if (Array.isArray(node)) {
            node[0] = m.updated(node.first.type, node.first.children);
            this._comments[node.first] = this._comments[m]
          } else {
            node = m.updated(node.type, node.children);
            this._comments[node] = this._comments[m]
          }
        };

        return node
      })));

      body.flatten;
      this.combine_properties(body);

      if (inheritance && (this._ast.type !== "class_extend" && !extend)) {
        body.unshift(
          this.s("send", name, "prototype=", this.s(
            "send",
            this.s("const", null, "Object"),
            "create",
            this.s("attr", inheritance, "prototype")
          )),

          this.s(
            "send",
            this.s("attr", name, "prototype"),
            "constructor=",
            name
          )
        )
      } else {
        body.splice(0, body.length, ...body.filter(x => x !== null));
        let methods = 0;
        let start = 0;

        for (let node of body) {
          if ((node.type === "method" || node.type === "prop") && node.children[0].type === "attr" && node.children[0].children[1] === "prototype") {
            methods++
          } else if (node.type === "class" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (node.type === "module" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (methods === 0) {
            start++
          } else {
            break
          }
        };

        if (this._ast.type === "class_module" || methods > 1 || body[start]?.type === "prop") {
          let pairs = body.slice(start, start + methods).map((node) => {
            let replacement;

            if (node.type === "method") {
              replacement = node.updated("pair", [
                this.s("str", (node.children[1] ?? "").toString().chomp("=")),
                node.children[2]
              ])
            } else if (node.type === "class" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s("pair", this.s("sym", sym), this.s(
                "class_hash",
                this.s("const", null, sym),
                null,
                node.children.last
              ))
            } else if (node.type === "module" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s(
                "pair",
                this.s("sym", sym),
                this.s("module_hash", this.s("const", null, sym), node.children.last)
              )
            } else {
              replacement = node.children[1].to_a.map((pair) => {
                let [prop, descriptor] = [pair[0], pair[1]];
                return node.updated("pair", [this.s("prop", prop), descriptor])
              })
            };

            if (this._comments[node]) {
              if (Array.isArray(replacement)) {
                this._comments[replacement.first] = this._comments[node]
              } else {
                this._comments[replacement] = this._comments[node]
              }
            };

            return replacement
          });

          if (this._ast.type === "class_module") {
            if (methods === 0) start = 0;

            if (name) {
              body.splice(start, start + methods - start, ...[this.s(
                "casgn",
                ...name.children,
                this.s("hash", ...pairs.flat(Infinity))
              )])
            } else {
              body.splice(
                start,
                start + methods - start,
                ...[this.s("hash", ...pairs.flat(Infinity))]
              )
            }
          } else if (this._ast.type === "class_extend" || extend) {
            body.splice(start, start + methods - start, ...[this.s(
              "assign",
              body[start].children.first,
              this.s("hash", ...pairs.flat(Infinity))
            )])
          } else {
            body.splice(start, start + methods - start, ...[this.s(
              "send",
              name,
              "prototype=",
              this.s("hash", ...pairs.flat(Infinity))
            )])
          }
        } else if ((this._ast.type === "class_extend" || extend) && methods > 1) {
          let pairs = body.slice(start, start + methods).map(node => (
            node.updated("pair", [
              this.s("sym", (node.children[1] ?? "").toString().slice(0, -1)),
              node.children[2]
            ])
          ));

          body.splice(start, start + methods - start, ...[this.s(
            "assign",
            body[start].children.first,
            this.s("hash", ...pairs)
          )])
        }
      };

      if (init) {
        let constructor = init.updated(
          "constructor",
          [name, ...init.children.slice(1)]
        );

        visible.constructor = init.children[1];

        if (this._ast.type === "class_extend" || extend) {
          constructor = this.s(
            "masgn",

            this.s("mlhs", this.s(
              "attr",
              this.s("casgn", ...name.children, constructor),
              "prototype"
            )),

            this.s("array", this.s("attr", name, "prototype"))
          )
        };

        let init_comments = this._comments[init];

        if (init_comments && init_comments.length !== 0) {
          this._comments[constructor] = init_comments;
          this._comments[init] = []
        };

        body.unshift(constructor)
      };

      {
        let class_name;
        let class_parent;
        let ivars;

        try {
          class_name = this._class_name;
          this._class_name = name;
          class_parent = this._class_parent;
          this._class_parent = inheritance;
          ivars = this.ivars;
          this.ivars = null;
          this._rbstack.push(visible);

          if (inheritance) {
            Object.assign(this._rbstack.last, this._namespace.find(inheritance))
          };

          this.parse(this.s("begin", ...body.compact), "statement")
        } finally {
          this.ivars = ivars;
          this._class_name = class_name;
          this._class_parent = class_parent;
          this._namespace.defineProps(this._rbstack.pop());
          if (this._ast.type !== "class_module") this._namespace.leave()
        }
      }
    };

    on_class_hash(name, inheritance, ...body) {
      let extend, init;
      if (this._ast.type !== "class_module") extend = this._namespace.enter(name);

      if (!["class", "class_hash"].includes(this._ast.type) || extend) {
        init = null
      } else {
        if (this._ast.type === "class_hash") {
          this.parse(this._ast.updated(
            "class2",
            [null, ...this._ast.children.slice(1)]
          ))
        } else {
          this.parse(this._ast.updated("class2"))
        };

        if (this._ast.type !== "class_module") this._namespace.leave();
        return
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));

      if (body.length === 1 && body.first.type === "begin") {
        body = body.first.children.slice()
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));
      let visible = this._namespace.getOwnProps();

      body.splice(...[0, body.length].concat(body.map((m) => {
        if (this._ast.type === "class_module" && m.type === "defs" && m.children.first === this.s("self")) {
          m = m.updated("def", m.children.slice(1))
        };

        let node = ["def", "defm", "deff"].includes(m.type) ? m.children.first === "initialize" && !visible.initialize ? (() => {
          init = m;
          return null
        })() : /=/.test(m.children.first) ? (() => {
          let sym = `${(m.children.first ?? "").toString().slice(0, -1) ?? ""}`;

          return this.s("prop", this.s("attr", name, "prototype"), {[sym]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("defm", null, ...m.children.slice(1))
          }})
        })() : !m.is_method() ? (() => {
          visible[m.children[0]] = this.s("self");

          return this.s(
            "prop",
            this.s("attr", name, "prototype"),

            {[m.children.first]: {
              enumerable: this.s("true"),
              configurable: this.s("true"),

              get: this.s(
                "defm",
                null,
                m.children[1],
                m.updated("autoreturn", m.children.slice(2))
              )
            }}
          )
        })() : (() => {
          visible[m.children[0]] = this.s("autobind", this.s("self"));

          return this.s(
            "method",
            this.s("attr", name, "prototype"),
            `${(m.children[0] ?? "").toString().chomp("!").chomp("?") ?? ""}=`,
            this.s("defm", null, ...m.children.slice(1))
          )
        })() : ["defs", "defp"].includes(m.type) && m.children.first === this.s("self") ? /=$/m.test(m.children[1]) ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString().slice(0, -1)]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("def", null, ...m.children.slice(2))
          }}
        ) : !m.is_method() ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString()]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              m.children[2],
              m.updated("autoreturn", m.children.slice(3))
            )
          }}
        ) : this.s("prototype", this.s(
          "send",
          name,
          `${m.children[1] ?? ""}=`,
          this.s("defm", null, ...m.children.slice(2))
        )) : m.type === "send" && m.children.first === null ? m.children[1] === "attr_accessor" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            )
          }})
        }) : m.children[1] === "attr_reader" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "attr_writer" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "include" ? this.s(
          "send",

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),

            this.s("begin", ...m.children.slice(2).map((modname) => {
              this._namespace.defineProps(this._namespace.find(modname));

              return this.s("for", this.s("lvasgn", "$_"), modname, this.s(
                "send",
                this.s("attr", name, "prototype"),
                "[]=",
                this.s("lvar", "$_"),
                this.s("send", modname, "[]", this.s("lvar", "$_"))
              ))
            }))
          ),

          "[]"
        ) : ["private", "protected", "public"].includes(m.children[1]) ? (() => { throw new Error(`class ${m.children[1] ?? ""} is not supported`, this._ast) })() : this.s(
          "send",
          name,
          ...m.children.slice(1)
        ) : m.type === "block" && m.children.first.children.first === null ? this.s(
          "block",
          this.s("send", name, ...m.children.first.children.slice(1)),
          ...m.children.slice(1)
        ) : ["send", "block"].includes(m.type) ? m : m.type === "lvasgn" ? this.s(
          "send",
          name,
          `${m.children[0] ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "cvasgn" ? this.s(
          "send",
          name,
          `_${m.children[0].slice(2) ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "send" && m.children[0].type === "cvar" ? this.s(
          "send",
          this.s("attr", name, `_${m.children[0].children[0].slice(2) ?? ""}`),
          ...m.children.slice(1)
        ) : m.type === "casgn" && m.children[0] === null ? (() => {
          visible[m.children[1]] = name;

          return this.s(
            "send",
            name,
            `${m.children[1] ?? ""}=`,
            ...m.children.slice(2)
          )
        })() : m.type === "alias" ? this.s(
          "send",
          this.s("attr", name, "prototype"),

          `${(m.children[0].children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          ) ?? ""}=`,

          this.s(
            "attr",
            this.s("attr", name, "prototype"),
            (m.children[1].children.first ?? "").toString().replace(/[?!]$/m, "")
          )
        ) : m.type === "class" || m.type === "module" ? (() => {
          let innerclass_name = m.children.first;

          if (innerclass_name.children.first) {
            innerclass_name = innerclass_name.updated(null, [
              this.s("attr", name, innerclass_name.children[0].children.last),
              innerclass_name.children[1]
            ])
          } else {
            innerclass_name = innerclass_name.updated(
              null,
              [name, innerclass_name.children[1]]
            )
          };

          return m.updated(null, [innerclass_name, ...m.children.slice(1)])
        })() : this._ast.type === "class_module" ? m : m.type === "defineProps" ? (() => {
          this._namespace.defineProps(m.children.first);
          Object.assign(visible, m.children.first);
          return null
        })() : (() => { throw new Error(`class ${m.type ?? ""} not supported`, this._ast) })();

        if (node && this._comments[m]) {
          if (Array.isArray(node)) {
            node[0] = m.updated(node.first.type, node.first.children);
            this._comments[node.first] = this._comments[m]
          } else {
            node = m.updated(node.type, node.children);
            this._comments[node] = this._comments[m]
          }
        };

        return node
      })));

      body.flatten;
      this.combine_properties(body);

      if (inheritance && (this._ast.type !== "class_extend" && !extend)) {
        body.unshift(
          this.s("send", name, "prototype=", this.s(
            "send",
            this.s("const", null, "Object"),
            "create",
            this.s("attr", inheritance, "prototype")
          )),

          this.s(
            "send",
            this.s("attr", name, "prototype"),
            "constructor=",
            name
          )
        )
      } else {
        body.splice(0, body.length, ...body.filter(x => x !== null));
        let methods = 0;
        let start = 0;

        for (let node of body) {
          if ((node.type === "method" || node.type === "prop") && node.children[0].type === "attr" && node.children[0].children[1] === "prototype") {
            methods++
          } else if (node.type === "class" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (node.type === "module" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (methods === 0) {
            start++
          } else {
            break
          }
        };

        if (this._ast.type === "class_module" || methods > 1 || body[start]?.type === "prop") {
          let pairs = body.slice(start, start + methods).map((node) => {
            let replacement;

            if (node.type === "method") {
              replacement = node.updated("pair", [
                this.s("str", (node.children[1] ?? "").toString().chomp("=")),
                node.children[2]
              ])
            } else if (node.type === "class" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s("pair", this.s("sym", sym), this.s(
                "class_hash",
                this.s("const", null, sym),
                null,
                node.children.last
              ))
            } else if (node.type === "module" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s(
                "pair",
                this.s("sym", sym),
                this.s("module_hash", this.s("const", null, sym), node.children.last)
              )
            } else {
              replacement = node.children[1].to_a.map((pair) => {
                let [prop, descriptor] = [pair[0], pair[1]];
                return node.updated("pair", [this.s("prop", prop), descriptor])
              })
            };

            if (this._comments[node]) {
              if (Array.isArray(replacement)) {
                this._comments[replacement.first] = this._comments[node]
              } else {
                this._comments[replacement] = this._comments[node]
              }
            };

            return replacement
          });

          if (this._ast.type === "class_module") {
            if (methods === 0) start = 0;

            if (name) {
              body.splice(start, start + methods - start, ...[this.s(
                "casgn",
                ...name.children,
                this.s("hash", ...pairs.flat(Infinity))
              )])
            } else {
              body.splice(
                start,
                start + methods - start,
                ...[this.s("hash", ...pairs.flat(Infinity))]
              )
            }
          } else if (this._ast.type === "class_extend" || extend) {
            body.splice(start, start + methods - start, ...[this.s(
              "assign",
              body[start].children.first,
              this.s("hash", ...pairs.flat(Infinity))
            )])
          } else {
            body.splice(start, start + methods - start, ...[this.s(
              "send",
              name,
              "prototype=",
              this.s("hash", ...pairs.flat(Infinity))
            )])
          }
        } else if ((this._ast.type === "class_extend" || extend) && methods > 1) {
          let pairs = body.slice(start, start + methods).map(node => (
            node.updated("pair", [
              this.s("sym", (node.children[1] ?? "").toString().slice(0, -1)),
              node.children[2]
            ])
          ));

          body.splice(start, start + methods - start, ...[this.s(
            "assign",
            body[start].children.first,
            this.s("hash", ...pairs)
          )])
        }
      };

      if (init) {
        let constructor = init.updated(
          "constructor",
          [name, ...init.children.slice(1)]
        );

        visible.constructor = init.children[1];

        if (this._ast.type === "class_extend" || extend) {
          constructor = this.s(
            "masgn",

            this.s("mlhs", this.s(
              "attr",
              this.s("casgn", ...name.children, constructor),
              "prototype"
            )),

            this.s("array", this.s("attr", name, "prototype"))
          )
        };

        let init_comments = this._comments[init];

        if (init_comments && init_comments.length !== 0) {
          this._comments[constructor] = init_comments;
          this._comments[init] = []
        };

        body.unshift(constructor)
      };

      {
        let class_name;
        let class_parent;
        let ivars;

        try {
          class_name = this._class_name;
          this._class_name = name;
          class_parent = this._class_parent;
          this._class_parent = inheritance;
          ivars = this.ivars;
          this.ivars = null;
          this._rbstack.push(visible);

          if (inheritance) {
            Object.assign(this._rbstack.last, this._namespace.find(inheritance))
          };

          this.parse(this.s("begin", ...body.compact), "statement")
        } finally {
          this.ivars = ivars;
          this._class_name = class_name;
          this._class_parent = class_parent;
          this._namespace.defineProps(this._rbstack.pop());
          if (this._ast.type !== "class_module") this._namespace.leave()
        }
      }
    };

    on_class_extend(name, inheritance, ...body) {
      let extend, init;
      if (this._ast.type !== "class_module") extend = this._namespace.enter(name);

      if (!["class", "class_hash"].includes(this._ast.type) || extend) {
        init = null
      } else {
        if (this._ast.type === "class_hash") {
          this.parse(this._ast.updated(
            "class2",
            [null, ...this._ast.children.slice(1)]
          ))
        } else {
          this.parse(this._ast.updated("class2"))
        };

        if (this._ast.type !== "class_module") this._namespace.leave();
        return
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));

      if (body.length === 1 && body.first.type === "begin") {
        body = body.first.children.slice()
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));
      let visible = this._namespace.getOwnProps();

      body.splice(...[0, body.length].concat(body.map((m) => {
        if (this._ast.type === "class_module" && m.type === "defs" && m.children.first === this.s("self")) {
          m = m.updated("def", m.children.slice(1))
        };

        let node = ["def", "defm", "deff"].includes(m.type) ? m.children.first === "initialize" && !visible.initialize ? (() => {
          init = m;
          return null
        })() : /=/.test(m.children.first) ? (() => {
          let sym = `${(m.children.first ?? "").toString().slice(0, -1) ?? ""}`;

          return this.s("prop", this.s("attr", name, "prototype"), {[sym]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("defm", null, ...m.children.slice(1))
          }})
        })() : !m.is_method() ? (() => {
          visible[m.children[0]] = this.s("self");

          return this.s(
            "prop",
            this.s("attr", name, "prototype"),

            {[m.children.first]: {
              enumerable: this.s("true"),
              configurable: this.s("true"),

              get: this.s(
                "defm",
                null,
                m.children[1],
                m.updated("autoreturn", m.children.slice(2))
              )
            }}
          )
        })() : (() => {
          visible[m.children[0]] = this.s("autobind", this.s("self"));

          return this.s(
            "method",
            this.s("attr", name, "prototype"),
            `${(m.children[0] ?? "").toString().chomp("!").chomp("?") ?? ""}=`,
            this.s("defm", null, ...m.children.slice(1))
          )
        })() : ["defs", "defp"].includes(m.type) && m.children.first === this.s("self") ? /=$/m.test(m.children[1]) ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString().slice(0, -1)]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("def", null, ...m.children.slice(2))
          }}
        ) : !m.is_method() ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString()]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              m.children[2],
              m.updated("autoreturn", m.children.slice(3))
            )
          }}
        ) : this.s("prototype", this.s(
          "send",
          name,
          `${m.children[1] ?? ""}=`,
          this.s("defm", null, ...m.children.slice(2))
        )) : m.type === "send" && m.children.first === null ? m.children[1] === "attr_accessor" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            )
          }})
        }) : m.children[1] === "attr_reader" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "attr_writer" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "include" ? this.s(
          "send",

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),

            this.s("begin", ...m.children.slice(2).map((modname) => {
              this._namespace.defineProps(this._namespace.find(modname));

              return this.s("for", this.s("lvasgn", "$_"), modname, this.s(
                "send",
                this.s("attr", name, "prototype"),
                "[]=",
                this.s("lvar", "$_"),
                this.s("send", modname, "[]", this.s("lvar", "$_"))
              ))
            }))
          ),

          "[]"
        ) : ["private", "protected", "public"].includes(m.children[1]) ? (() => { throw new Error(`class ${m.children[1] ?? ""} is not supported`, this._ast) })() : this.s(
          "send",
          name,
          ...m.children.slice(1)
        ) : m.type === "block" && m.children.first.children.first === null ? this.s(
          "block",
          this.s("send", name, ...m.children.first.children.slice(1)),
          ...m.children.slice(1)
        ) : ["send", "block"].includes(m.type) ? m : m.type === "lvasgn" ? this.s(
          "send",
          name,
          `${m.children[0] ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "cvasgn" ? this.s(
          "send",
          name,
          `_${m.children[0].slice(2) ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "send" && m.children[0].type === "cvar" ? this.s(
          "send",
          this.s("attr", name, `_${m.children[0].children[0].slice(2) ?? ""}`),
          ...m.children.slice(1)
        ) : m.type === "casgn" && m.children[0] === null ? (() => {
          visible[m.children[1]] = name;

          return this.s(
            "send",
            name,
            `${m.children[1] ?? ""}=`,
            ...m.children.slice(2)
          )
        })() : m.type === "alias" ? this.s(
          "send",
          this.s("attr", name, "prototype"),

          `${(m.children[0].children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          ) ?? ""}=`,

          this.s(
            "attr",
            this.s("attr", name, "prototype"),
            (m.children[1].children.first ?? "").toString().replace(/[?!]$/m, "")
          )
        ) : m.type === "class" || m.type === "module" ? (() => {
          let innerclass_name = m.children.first;

          if (innerclass_name.children.first) {
            innerclass_name = innerclass_name.updated(null, [
              this.s("attr", name, innerclass_name.children[0].children.last),
              innerclass_name.children[1]
            ])
          } else {
            innerclass_name = innerclass_name.updated(
              null,
              [name, innerclass_name.children[1]]
            )
          };

          return m.updated(null, [innerclass_name, ...m.children.slice(1)])
        })() : this._ast.type === "class_module" ? m : m.type === "defineProps" ? (() => {
          this._namespace.defineProps(m.children.first);
          Object.assign(visible, m.children.first);
          return null
        })() : (() => { throw new Error(`class ${m.type ?? ""} not supported`, this._ast) })();

        if (node && this._comments[m]) {
          if (Array.isArray(node)) {
            node[0] = m.updated(node.first.type, node.first.children);
            this._comments[node.first] = this._comments[m]
          } else {
            node = m.updated(node.type, node.children);
            this._comments[node] = this._comments[m]
          }
        };

        return node
      })));

      body.flatten;
      this.combine_properties(body);

      if (inheritance && (this._ast.type !== "class_extend" && !extend)) {
        body.unshift(
          this.s("send", name, "prototype=", this.s(
            "send",
            this.s("const", null, "Object"),
            "create",
            this.s("attr", inheritance, "prototype")
          )),

          this.s(
            "send",
            this.s("attr", name, "prototype"),
            "constructor=",
            name
          )
        )
      } else {
        body.splice(0, body.length, ...body.filter(x => x !== null));
        let methods = 0;
        let start = 0;

        for (let node of body) {
          if ((node.type === "method" || node.type === "prop") && node.children[0].type === "attr" && node.children[0].children[1] === "prototype") {
            methods++
          } else if (node.type === "class" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (node.type === "module" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (methods === 0) {
            start++
          } else {
            break
          }
        };

        if (this._ast.type === "class_module" || methods > 1 || body[start]?.type === "prop") {
          let pairs = body.slice(start, start + methods).map((node) => {
            let replacement;

            if (node.type === "method") {
              replacement = node.updated("pair", [
                this.s("str", (node.children[1] ?? "").toString().chomp("=")),
                node.children[2]
              ])
            } else if (node.type === "class" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s("pair", this.s("sym", sym), this.s(
                "class_hash",
                this.s("const", null, sym),
                null,
                node.children.last
              ))
            } else if (node.type === "module" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s(
                "pair",
                this.s("sym", sym),
                this.s("module_hash", this.s("const", null, sym), node.children.last)
              )
            } else {
              replacement = node.children[1].to_a.map((pair) => {
                let [prop, descriptor] = [pair[0], pair[1]];
                return node.updated("pair", [this.s("prop", prop), descriptor])
              })
            };

            if (this._comments[node]) {
              if (Array.isArray(replacement)) {
                this._comments[replacement.first] = this._comments[node]
              } else {
                this._comments[replacement] = this._comments[node]
              }
            };

            return replacement
          });

          if (this._ast.type === "class_module") {
            if (methods === 0) start = 0;

            if (name) {
              body.splice(start, start + methods - start, ...[this.s(
                "casgn",
                ...name.children,
                this.s("hash", ...pairs.flat(Infinity))
              )])
            } else {
              body.splice(
                start,
                start + methods - start,
                ...[this.s("hash", ...pairs.flat(Infinity))]
              )
            }
          } else if (this._ast.type === "class_extend" || extend) {
            body.splice(start, start + methods - start, ...[this.s(
              "assign",
              body[start].children.first,
              this.s("hash", ...pairs.flat(Infinity))
            )])
          } else {
            body.splice(start, start + methods - start, ...[this.s(
              "send",
              name,
              "prototype=",
              this.s("hash", ...pairs.flat(Infinity))
            )])
          }
        } else if ((this._ast.type === "class_extend" || extend) && methods > 1) {
          let pairs = body.slice(start, start + methods).map(node => (
            node.updated("pair", [
              this.s("sym", (node.children[1] ?? "").toString().slice(0, -1)),
              node.children[2]
            ])
          ));

          body.splice(start, start + methods - start, ...[this.s(
            "assign",
            body[start].children.first,
            this.s("hash", ...pairs)
          )])
        }
      };

      if (init) {
        let constructor = init.updated(
          "constructor",
          [name, ...init.children.slice(1)]
        );

        visible.constructor = init.children[1];

        if (this._ast.type === "class_extend" || extend) {
          constructor = this.s(
            "masgn",

            this.s("mlhs", this.s(
              "attr",
              this.s("casgn", ...name.children, constructor),
              "prototype"
            )),

            this.s("array", this.s("attr", name, "prototype"))
          )
        };

        let init_comments = this._comments[init];

        if (init_comments && init_comments.length !== 0) {
          this._comments[constructor] = init_comments;
          this._comments[init] = []
        };

        body.unshift(constructor)
      };

      {
        let class_name;
        let class_parent;
        let ivars;

        try {
          class_name = this._class_name;
          this._class_name = name;
          class_parent = this._class_parent;
          this._class_parent = inheritance;
          ivars = this.ivars;
          this.ivars = null;
          this._rbstack.push(visible);

          if (inheritance) {
            Object.assign(this._rbstack.last, this._namespace.find(inheritance))
          };

          this.parse(this.s("begin", ...body.compact), "statement")
        } finally {
          this.ivars = ivars;
          this._class_name = class_name;
          this._class_parent = class_parent;
          this._namespace.defineProps(this._rbstack.pop());
          if (this._ast.type !== "class_module") this._namespace.leave()
        }
      }
    };

    on_class_module(name, inheritance, ...body) {
      let extend, init;
      if (this._ast.type !== "class_module") extend = this._namespace.enter(name);

      if (!["class", "class_hash"].includes(this._ast.type) || extend) {
        init = null
      } else {
        if (this._ast.type === "class_hash") {
          this.parse(this._ast.updated(
            "class2",
            [null, ...this._ast.children.slice(1)]
          ))
        } else {
          this.parse(this._ast.updated("class2"))
        };

        if (this._ast.type !== "class_module") this._namespace.leave();
        return
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));

      if (body.length === 1 && body.first.type === "begin") {
        body = body.first.children.slice()
      };

      body.splice(0, body.length, ...body.filter(x => x !== null));
      let visible = this._namespace.getOwnProps();

      body.splice(...[0, body.length].concat(body.map((m) => {
        if (this._ast.type === "class_module" && m.type === "defs" && m.children.first === this.s("self")) {
          m = m.updated("def", m.children.slice(1))
        };

        let node = ["def", "defm", "deff"].includes(m.type) ? m.children.first === "initialize" && !visible.initialize ? (() => {
          init = m;
          return null
        })() : /=/.test(m.children.first) ? (() => {
          let sym = `${(m.children.first ?? "").toString().slice(0, -1) ?? ""}`;

          return this.s("prop", this.s("attr", name, "prototype"), {[sym]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("defm", null, ...m.children.slice(1))
          }})
        })() : !m.is_method() ? (() => {
          visible[m.children[0]] = this.s("self");

          return this.s(
            "prop",
            this.s("attr", name, "prototype"),

            {[m.children.first]: {
              enumerable: this.s("true"),
              configurable: this.s("true"),

              get: this.s(
                "defm",
                null,
                m.children[1],
                m.updated("autoreturn", m.children.slice(2))
              )
            }}
          )
        })() : (() => {
          visible[m.children[0]] = this.s("autobind", this.s("self"));

          return this.s(
            "method",
            this.s("attr", name, "prototype"),
            `${(m.children[0] ?? "").toString().chomp("!").chomp("?") ?? ""}=`,
            this.s("defm", null, ...m.children.slice(1))
          )
        })() : ["defs", "defp"].includes(m.type) && m.children.first === this.s("self") ? /=$/m.test(m.children[1]) ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString().slice(0, -1)]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("def", null, ...m.children.slice(2))
          }}
        ) : !m.is_method() ? this.s(
          "prop",
          name,

          {[(m.children[1] ?? "").toString()]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              m.children[2],
              m.updated("autoreturn", m.children.slice(3))
            )
          }}
        ) : this.s("prototype", this.s(
          "send",
          name,
          `${m.children[1] ?? ""}=`,
          this.s("defm", null, ...m.children.slice(2))
        )) : m.type === "send" && m.children.first === null ? m.children[1] === "attr_accessor" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),

            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            )
          }})
        }) : m.children[1] === "attr_reader" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            get: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args"),
              this.s("return", this.s("ivar", `@${$var ?? ""}`))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "attr_writer" ? m.children.slice(2).map((child_sym) => {
          let $var = child_sym.children.first;
          visible[$var] = this.s("self");

          return this.s("prop", this.s("attr", name, "prototype"), {[$var]: {
            set: this.s(
              "block",
              this.s("send", null, "proc"),
              this.s("args", this.s("arg", $var)),
              this.s("ivasgn", `@${$var ?? ""}`, this.s("lvar", $var))
            ),

            enumerable: this.s("true"),
            configurable: this.s("true")
          }})
        }) : m.children[1] === "include" ? this.s(
          "send",

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),

            this.s("begin", ...m.children.slice(2).map((modname) => {
              this._namespace.defineProps(this._namespace.find(modname));

              return this.s("for", this.s("lvasgn", "$_"), modname, this.s(
                "send",
                this.s("attr", name, "prototype"),
                "[]=",
                this.s("lvar", "$_"),
                this.s("send", modname, "[]", this.s("lvar", "$_"))
              ))
            }))
          ),

          "[]"
        ) : ["private", "protected", "public"].includes(m.children[1]) ? (() => { throw new Error(`class ${m.children[1] ?? ""} is not supported`, this._ast) })() : this.s(
          "send",
          name,
          ...m.children.slice(1)
        ) : m.type === "block" && m.children.first.children.first === null ? this.s(
          "block",
          this.s("send", name, ...m.children.first.children.slice(1)),
          ...m.children.slice(1)
        ) : ["send", "block"].includes(m.type) ? m : m.type === "lvasgn" ? this.s(
          "send",
          name,
          `${m.children[0] ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "cvasgn" ? this.s(
          "send",
          name,
          `_${m.children[0].slice(2) ?? ""}=`,
          ...m.children.slice(1)
        ) : m.type === "send" && m.children[0].type === "cvar" ? this.s(
          "send",
          this.s("attr", name, `_${m.children[0].children[0].slice(2) ?? ""}`),
          ...m.children.slice(1)
        ) : m.type === "casgn" && m.children[0] === null ? (() => {
          visible[m.children[1]] = name;

          return this.s(
            "send",
            name,
            `${m.children[1] ?? ""}=`,
            ...m.children.slice(2)
          )
        })() : m.type === "alias" ? this.s(
          "send",
          this.s("attr", name, "prototype"),

          `${(m.children[0].children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          ) ?? ""}=`,

          this.s(
            "attr",
            this.s("attr", name, "prototype"),
            (m.children[1].children.first ?? "").toString().replace(/[?!]$/m, "")
          )
        ) : m.type === "class" || m.type === "module" ? (() => {
          let innerclass_name = m.children.first;

          if (innerclass_name.children.first) {
            innerclass_name = innerclass_name.updated(null, [
              this.s("attr", name, innerclass_name.children[0].children.last),
              innerclass_name.children[1]
            ])
          } else {
            innerclass_name = innerclass_name.updated(
              null,
              [name, innerclass_name.children[1]]
            )
          };

          return m.updated(null, [innerclass_name, ...m.children.slice(1)])
        })() : this._ast.type === "class_module" ? m : m.type === "defineProps" ? (() => {
          this._namespace.defineProps(m.children.first);
          Object.assign(visible, m.children.first);
          return null
        })() : (() => { throw new Error(`class ${m.type ?? ""} not supported`, this._ast) })();

        if (node && this._comments[m]) {
          if (Array.isArray(node)) {
            node[0] = m.updated(node.first.type, node.first.children);
            this._comments[node.first] = this._comments[m]
          } else {
            node = m.updated(node.type, node.children);
            this._comments[node] = this._comments[m]
          }
        };

        return node
      })));

      body.flatten;
      this.combine_properties(body);

      if (inheritance && (this._ast.type !== "class_extend" && !extend)) {
        body.unshift(
          this.s("send", name, "prototype=", this.s(
            "send",
            this.s("const", null, "Object"),
            "create",
            this.s("attr", inheritance, "prototype")
          )),

          this.s(
            "send",
            this.s("attr", name, "prototype"),
            "constructor=",
            name
          )
        )
      } else {
        body.splice(0, body.length, ...body.filter(x => x !== null));
        let methods = 0;
        let start = 0;

        for (let node of body) {
          if ((node.type === "method" || node.type === "prop") && node.children[0].type === "attr" && node.children[0].children[1] === "prototype") {
            methods++
          } else if (node.type === "class" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (node.type === "module" && this._ast.type === "class_module") {
            if (node.children.first.children.first === name) methods++
          } else if (methods === 0) {
            start++
          } else {
            break
          }
        };

        if (this._ast.type === "class_module" || methods > 1 || body[start]?.type === "prop") {
          let pairs = body.slice(start, start + methods).map((node) => {
            let replacement;

            if (node.type === "method") {
              replacement = node.updated("pair", [
                this.s("str", (node.children[1] ?? "").toString().chomp("=")),
                node.children[2]
              ])
            } else if (node.type === "class" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s("pair", this.s("sym", sym), this.s(
                "class_hash",
                this.s("const", null, sym),
                null,
                node.children.last
              ))
            } else if (node.type === "module" && node.children.first.children.first === name) {
              let sym = node.children.first.children.last;

              replacement = this.s(
                "pair",
                this.s("sym", sym),
                this.s("module_hash", this.s("const", null, sym), node.children.last)
              )
            } else {
              replacement = node.children[1].to_a.map((pair) => {
                let [prop, descriptor] = [pair[0], pair[1]];
                return node.updated("pair", [this.s("prop", prop), descriptor])
              })
            };

            if (this._comments[node]) {
              if (Array.isArray(replacement)) {
                this._comments[replacement.first] = this._comments[node]
              } else {
                this._comments[replacement] = this._comments[node]
              }
            };

            return replacement
          });

          if (this._ast.type === "class_module") {
            if (methods === 0) start = 0;

            if (name) {
              body.splice(start, start + methods - start, ...[this.s(
                "casgn",
                ...name.children,
                this.s("hash", ...pairs.flat(Infinity))
              )])
            } else {
              body.splice(
                start,
                start + methods - start,
                ...[this.s("hash", ...pairs.flat(Infinity))]
              )
            }
          } else if (this._ast.type === "class_extend" || extend) {
            body.splice(start, start + methods - start, ...[this.s(
              "assign",
              body[start].children.first,
              this.s("hash", ...pairs.flat(Infinity))
            )])
          } else {
            body.splice(start, start + methods - start, ...[this.s(
              "send",
              name,
              "prototype=",
              this.s("hash", ...pairs.flat(Infinity))
            )])
          }
        } else if ((this._ast.type === "class_extend" || extend) && methods > 1) {
          let pairs = body.slice(start, start + methods).map(node => (
            node.updated("pair", [
              this.s("sym", (node.children[1] ?? "").toString().slice(0, -1)),
              node.children[2]
            ])
          ));

          body.splice(start, start + methods - start, ...[this.s(
            "assign",
            body[start].children.first,
            this.s("hash", ...pairs)
          )])
        }
      };

      if (init) {
        let constructor = init.updated(
          "constructor",
          [name, ...init.children.slice(1)]
        );

        visible.constructor = init.children[1];

        if (this._ast.type === "class_extend" || extend) {
          constructor = this.s(
            "masgn",

            this.s("mlhs", this.s(
              "attr",
              this.s("casgn", ...name.children, constructor),
              "prototype"
            )),

            this.s("array", this.s("attr", name, "prototype"))
          )
        };

        let init_comments = this._comments[init];

        if (init_comments && init_comments.length !== 0) {
          this._comments[constructor] = init_comments;
          this._comments[init] = []
        };

        body.unshift(constructor)
      };

      {
        let class_name;
        let class_parent;
        let ivars;

        try {
          class_name = this._class_name;
          this._class_name = name;
          class_parent = this._class_parent;
          this._class_parent = inheritance;
          ivars = this.ivars;
          this.ivars = null;
          this._rbstack.push(visible);

          if (inheritance) {
            Object.assign(this._rbstack.last, this._namespace.find(inheritance))
          };

          this.parse(this.s("begin", ...body.compact), "statement")
        } finally {
          this.ivars = ivars;
          this._class_name = class_name;
          this._class_parent = class_parent;
          this._namespace.defineProps(this._rbstack.pop());
          if (this._ast.type !== "class_module") this._namespace.leave()
        }
      }
    };

    on_prop(...args) {
      {
        let instance_method;

        try {
          let prop, descriptor;
          instance_method = this._instance_method;
          this._instance_method = this._ast;
          [this._block_this, this._block_depth] = [false, 0];

          if (this._ast.type === "prop") {
            let obj = args[0];
            let props_array = args[1].to_a;

            if (props_array.length === 1) {
              let [prop, descriptor] = props_array[0];
              let descriptor_array = descriptor.to_a;

              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperty",
                obj,
                this.s("sym", prop),

                this.s("hash", ...descriptor_array.map(pair => (
                  this.s("pair", this.s("sym", pair[0]), pair[1])
                )))
              ))
            } else {
              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperties",
                obj,

                this.s("hash", ...props_array.map((pair) => {
                  let [hprop, hdescriptor] = [pair[0], pair[1]];
                  let hdescriptor_array = hdescriptor.to_a;

                  return this.s(
                    "pair",
                    this.s("sym", hprop),

                    this.s("hash", ...hdescriptor_array.map(dpair => (
                      this.s("pair", this.s("sym", dpair[0]), dpair[1])
                    )))
                  )
                }))
              ))
            }
          } else if (this._ast.type === "method") {
            this.parse(this.s("send", ...args))
          } else if (args.first.children.first) {
            this.parse(this.s(
              "send",
              args.first.children.first,
              `${args.first.children[1] ?? ""}=`,
              this.s("block", this.s("send", null, "proc"), ...args.slice(1))
            ))
          } else {
            this.parse(this.s("def", args.first.children[1], ...args.slice(1)))
          }
        } finally {
          this._instance_method = instance_method;
          [this._block_this, this._block_depth] = [null, null]
        }
      }
    };

    on_method(...args) {
      {
        let instance_method;

        try {
          let prop, descriptor;
          instance_method = this._instance_method;
          this._instance_method = this._ast;
          [this._block_this, this._block_depth] = [false, 0];

          if (this._ast.type === "prop") {
            let obj = args[0];
            let props_array = args[1].to_a;

            if (props_array.length === 1) {
              let [prop, descriptor] = props_array[0];
              let descriptor_array = descriptor.to_a;

              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperty",
                obj,
                this.s("sym", prop),

                this.s("hash", ...descriptor_array.map(pair => (
                  this.s("pair", this.s("sym", pair[0]), pair[1])
                )))
              ))
            } else {
              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperties",
                obj,

                this.s("hash", ...props_array.map((pair) => {
                  let [hprop, hdescriptor] = [pair[0], pair[1]];
                  let hdescriptor_array = hdescriptor.to_a;

                  return this.s(
                    "pair",
                    this.s("sym", hprop),

                    this.s("hash", ...hdescriptor_array.map(dpair => (
                      this.s("pair", this.s("sym", dpair[0]), dpair[1])
                    )))
                  )
                }))
              ))
            }
          } else if (this._ast.type === "method") {
            this.parse(this.s("send", ...args))
          } else if (args.first.children.first) {
            this.parse(this.s(
              "send",
              args.first.children.first,
              `${args.first.children[1] ?? ""}=`,
              this.s("block", this.s("send", null, "proc"), ...args.slice(1))
            ))
          } else {
            this.parse(this.s("def", args.first.children[1], ...args.slice(1)))
          }
        } finally {
          this._instance_method = instance_method;
          [this._block_this, this._block_depth] = [null, null]
        }
      }
    };

    on_constructor(...args) {
      {
        let instance_method;

        try {
          let prop, descriptor;
          instance_method = this._instance_method;
          this._instance_method = this._ast;
          [this._block_this, this._block_depth] = [false, 0];

          if (this._ast.type === "prop") {
            let obj = args[0];
            let props_array = args[1].to_a;

            if (props_array.length === 1) {
              let [prop, descriptor] = props_array[0];
              let descriptor_array = descriptor.to_a;

              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperty",
                obj,
                this.s("sym", prop),

                this.s("hash", ...descriptor_array.map(pair => (
                  this.s("pair", this.s("sym", pair[0]), pair[1])
                )))
              ))
            } else {
              this.parse(this.s(
                "send",
                this.s("const", null, "Object"),
                "defineProperties",
                obj,

                this.s("hash", ...props_array.map((pair) => {
                  let [hprop, hdescriptor] = [pair[0], pair[1]];
                  let hdescriptor_array = hdescriptor.to_a;

                  return this.s(
                    "pair",
                    this.s("sym", hprop),

                    this.s("hash", ...hdescriptor_array.map(dpair => (
                      this.s("pair", this.s("sym", dpair[0]), dpair[1])
                    )))
                  )
                }))
              ))
            }
          } else if (this._ast.type === "method") {
            this.parse(this.s("send", ...args))
          } else if (args.first.children.first) {
            this.parse(this.s(
              "send",
              args.first.children.first,
              `${args.first.children[1] ?? ""}=`,
              this.s("block", this.s("send", null, "proc"), ...args.slice(1))
            ))
          } else {
            this.parse(this.s("def", args.first.children[1], ...args.slice(1)))
          }
        } finally {
          this._instance_method = instance_method;
          [this._block_this, this._block_depth] = [null, null]
        }
      }
    };

    on_class2(name, inheritance, ...body) {
      body.splice(0, body.length, ...body.filter(x => x !== null));

      while (body.length === 1 && body.first.type === "begin") {
        body = body.first.children
      };

      body = body.flatMap(m => m?.type === "begin" ? m.children : m).compact;

      if (name === null) {
        let has_include = body.some(m => (
          m.type === "send" && m.children[0] === null && ["include", "extend"].includes(m.children[1])
        ));

        if (has_include) {
          let temp_name = this.s("const", null, "_class");

          return this.parse(this.s(
            "send",

            this.s(
              "block",
              this.s("send", null, "lambda"),
              this.s("args"),

              this.s(
                "begin",

                this.s(
                  "lvasgn",
                  "_class",
                  this._ast.updated("class2", [temp_name, inheritance, ...body])
                ),

                this.s("return", this.s("lvar", "_class"))
              )
            ),

            "[]"
          ))
        }
      };

      let proxied = body.find(node => (
        node.type === "def" && node.children.first === "method_missing"
      ));

      if (!name) {
        this.put("class")
      } else if (name.type === "const" && name.children.first === null) {
        this.put("class ");
        this.parse(name);
        if (proxied) this.put("$")
      } else {
        this.parse(name);
        if (proxied) this.put("$");
        this.put(" = class")
      };

      if (inheritance) {
        this.put(" extends ");
        this.parse(inheritance)
      };

      this.put(" {");

      {
        let class_name;
        let class_parent;

        try {
          let ivars, cvars, walk, references_args, forward;
          class_name = this._class_name;
          this._class_name = name;
          class_parent = this._class_parent;
          this._class_parent = inheritance;
          this._rbstack.push(this._namespace.getOwnProps());

          if (inheritance) {
            Object.assign(this._rbstack.last, this._namespace.find(inheritance))
          };

          let constructor = [];
          let index = 0;
          let constructor_args = new Set;
          let private_methods = new Set;
          let method_visibility = "public";

          for (let m of body) {
            let base_node, prop;

            if (m.type === "send" && m.children.first === null) {
              if (m.children[1] === "private") {
                method_visibility = "private";
                continue
              } else if (m.children[1] === "protected") {
                method_visibility = "protected";
                continue
              } else if (m.children[1] === "public") {
                method_visibility = "public";
                continue
              }
            };

            if (m.type === "def") {
              let prop = m.children.first;

              if (prop === "initialize" && !this._rbstack.last.initialize) {
                constructor = m.children.slice(2);
                let args_node = m.children[1];

                if (args_node?.type === "args") {
                  for (let arg of args_node.children) {
                    switch (arg.type) {
                    case "arg":
                    case "optarg":
                    case "restarg":
                    case "kwarg":
                    case "kwoptarg":
                    case "kwrestarg":
                      if (arg.children.first) constructor_args.add(arg.children.first)
                    }
                  }
                }
              } else if ((prop ?? "").toString().endsWith("=")) {
                base_node = this.s("setter", this.s("self"));

                if (method_visibility === "private") {
                  private_methods.add(prop);
                  let prefix = this.es2022 && !this.underscored_private ? "#" : "_";
                  base_node = this.s("private_method", prefix, base_node)
                };

                this._rbstack.last[(prop ?? "").toString().slice(0, -1)] = base_node
              } else {
                base_node = m.is_method() ? this.s("autobind", this.s("self")) : this.s("self");

                if (method_visibility === "private") {
                  private_methods.add(prop);
                  let prefix = this.es2022 && !this.underscored_private ? "#" : "_";
                  base_node = this.s("private_method", prefix, base_node)
                };

                this._rbstack.last[prop] = base_node;

                if (/[?!]$/m.test((prop ?? "").toString())) {
                  let key = (prop ?? "").toString().replace(/[?!]$/m, "");
                  this._rbstack.last[key] = base_node
                }
              }
            } else if (m.type === "send" && m.children[0] === null && m.children[1] === "async") {
              if (m.children[2].type === "def") {
                prop = m.children[2].children.first;
                base_node = this.s("autobind", this.s("self"));

                if (method_visibility === "private") {
                  private_methods.add(prop);
                  let prefix = this.es2022 && !this.underscored_private ? "#" : "_";
                  base_node = this.s("private_method", prefix, base_node)
                };

                this._rbstack.last[prop] = base_node;

                if (/[?!]$/m.test((prop ?? "").toString())) {
                  let key = (prop ?? "").toString().replace(/[?!]$/m, "");
                  this._rbstack.last[key] = base_node
                }
              }
            }
          };

          if (!this.underscored_private) {
            ivars = new Set;
            cvars = new Set;

            walk = (ast) => {
              if (ast.type === "ivar") ivars.add(ast.children.first);
              if (ast.type === "ivasgn") ivars.add(ast.children.first);
              if (ast.type === "cvar") cvars.add(ast.children.first);
              if (ast.type === "cvasgn") cvars.add(ast.children.first);

              for (let child of ast.children) {
                if (this.ast_node(child)) walk(child)
              };

              if (ast.type === "send" && ast.children.first === null) {
                if (ast.children[1] === "attr_accessor") {
                  return ast.children.slice(2).forEach((child_sym, index2) => (
                    ivars.add(`@${child_sym.children.first ?? ""}`)
                  ))
                } else if (ast.children[1] === "attr_reader") {
                  return ast.children.slice(2).forEach((child_sym, index2) => (
                    ivars.add(`@${child_sym.children.first ?? ""}`)
                  ))
                } else if (ast.children[1] === "attr_writer") {
                  return ast.children.slice(2).forEach((child_sym, index2) => (
                    ivars.add(`@${child_sym.children.first ?? ""}`)
                  ))
                }
              }
            };

            walk(this._ast);

            while (constructor.length === 1 && constructor.first.type === "begin") {
              constructor = constructor.first.children.slice()
            };

            if (cvars.length !== 0) {
              for (let m of body) {
                if (m.type === "cvasgn") delete cvars[m.children.first]
              }
            };

            for (let cvar of [...cvars].sort()) {
              this.put(index === 0 ? this._nl : this._sep);
              index++;
              this.put("static \#$" + (cvar ?? "").toString().slice(2))
            };

            references_args = (node) => {
              if (!this.ast_node(node)) return false;

              if (node.type === "lvar" && constructor_args.has(node.children.first)) {
                return true
              };

              return node.children.some(child => references_args(child))
            };

            while (constructor.length > 0 && constructor.first.type === "ivasgn") {
              if (references_args(constructor.first.children.last)) break;
              this.put(index === 0 ? this._nl : this._sep);
              index++;
              let statement = constructor.shift();
              this.put("#");
              this.put((statement.children.first ?? "").toString().slice(1));
              this.put(" = ");
              this.parse(statement.children.last);
              delete ivars[statement.children.first]
            };

            for (let ivar of [...ivars].sort()) {
              this.put(index === 0 ? this._nl : this._sep);
              index++;
              this.put("#" + (ivar ?? "").toString().slice(1))
            }
          };

          let post = [];
          let skipped = false;
          let visibility = "public";

          for (let m of body) {
            let kind, base_name;
            if (!skipped) this.put(index === 0 ? this._nl : this._sep);
            index++;
            let node_comments = this.comments(m);
            let location = this.output_location;
            skipped = false;

            if (m.type === "send" && m.children[0] === null && m.children[1] === "async") {
              let child = m.children[2];

              if (child.type === "def") {
                m = child.updated("async")
              } else if (child.type === "defs" && child.children[0].type === "self") {
                m = child.updated("asyncs")
              }
            };

            if (["def", "defm", "deff", "async"].includes(m.type)) {
              this._prop = m.children.first;

              if (this._prop === "initialize" && !this._rbstack.last.initialize) {
                this._prop = "constructor";

                if (constructor === [] || constructor === ["super"]) {
                  skipped = true;
                  continue
                };

                m = m.updated(
                  m.type,
                  [this._prop, m.children[1], this.s("begin", ...constructor)]
                )
              } else if (!m.is_method() && !["defm", "deff"].includes(m.type)) {
                this._prop = `get ${this._prop ?? ""}`;

                m = m.updated(
                  m.type,
                  [...m.children.slice(0, 2), this.s("autoreturn", m.children[2])]
                )
              } else if ((this._prop ?? "").toString().endsWith("=")) {
                this._prop = (this._prop ?? "").toString().replace("=", "");
                m = m.updated(m.type, [this._prop, ...m.children.slice(1, 3)]);
                this._prop = `set ${this._prop ?? ""}`
              } else if ((this._prop ?? "").toString().endsWith("!")) {
                this._prop = (this._prop ?? "").toString().replace("!", "");
                m = m.updated(m.type, [this._prop, ...m.children.slice(1, 3)])
              } else if ((this._prop ?? "").toString().endsWith("?")) {
                this._prop = (this._prop ?? "").toString().replace("?", "");
                m = m.updated(m.type, [this._prop, ...m.children.slice(1, 3)])
              };

              if (visibility === "private" && this._prop !== "constructor") {
                let prefix = this.es2022 && !this.underscored_private ? "#" : "_";

                if ((this._prop ?? "").toString().start_with("get ", "set ")) {
                  let [kind, base_name] = (this._prop ?? "").toString().split(" ", 2);
                  this._prop = `${kind ?? ""} ${prefix ?? ""}${base_name ?? ""}`
                } else {
                  this._prop = `${prefix ?? ""}${this._prop ?? ""}`
                }
              };

              try {
                this._instance_method = m;
                this._class_method = null;
                this.parse(m)
              } finally {
                this._instance_method = null
              }
            } else if (["defs", "defp", "asyncs"].includes(m.type) && m.children.first.type === "self") {
              this._prop = `static ${m.children[1] ?? ""}`;

              if (m.type === "defp" || !m.is_method()) {
                this._prop = `static get ${m.children[1] ?? ""}`;

                m = m.updated(
                  m.type,
                  [...m.children.slice(0, 3), this.s("autoreturn", m.children[3])]
                )
              } else if ((this._prop ?? "").toString().endsWith("=")) {
                this._prop = `static set ${(m.children[1] ?? "").toString().replace(
                  "=",
                  ""
                ) ?? ""}`
              } else if ((this._prop ?? "").toString().endsWith("!")) {
                m = m.updated(m.type, [
                  m.children[0],
                  (m.children[1] ?? "").toString().replace("!", ""),
                  ...m.children.slice(2, 4)
                ]);

                this._prop = `static ${m.children[1] ?? ""}`
              } else if ((this._prop ?? "").toString().endsWith("?")) {
                m = m.updated(m.type, [
                  m.children[0],
                  (m.children[1] ?? "").toString().replace("?", ""),
                  ...m.children.slice(2, 4)
                ]);

                this._prop = `static ${m.children[1] ?? ""}`
              };

              if (m.type === "asyncs") {
                this._prop = this._prop.replace("static", "static async")
              };

              m = m.updated("def", m.children.slice(1, 4));

              try {
                this._instance_method = null;
                this._class_method = m;
                this.parse(m)
              } finally {
                this._instance_method = null
              }
            } else if (m.type === "send" && m.children.first === null) {
              let p = this.underscored_private ? "_" : "#";

              if (m.children[1] === "attr_accessor") {
                m.children.slice(2).forEach((child_sym, index2) => {
                  if (index2 !== 0) this.put(this._sep);
                  let $var = child_sym.children.first;
                  this._rbstack.last[$var] = this.s("self");
                  this.put(`get ${$var ?? ""}() {${this._nl ?? ""}return this.${p ?? ""}${$var ?? ""}${this._nl ?? ""}}${this._sep ?? ""}`);
                  this.put(`set ${$var ?? ""}(${$var ?? ""}) {${this._nl ?? ""}this.${p ?? ""}${$var ?? ""} = ${$var ?? ""}${this._nl ?? ""}}`)
                })
              } else if (m.children[1] === "attr_reader") {
                m.children.slice(2).forEach((child_sym, index2) => {
                  if (index2 !== 0) this.put(this._sep);
                  let $var = child_sym.children.first;
                  this._rbstack.last[$var] = this.s("self");
                  this.put(`get ${$var ?? ""}() {${this._nl ?? ""}return this.${p ?? ""}${$var ?? ""}${this._nl ?? ""}}`)
                })
              } else if (m.children[1] === "attr_writer") {
                m.children.slice(2).forEach((child_sym, index2) => {
                  if (index2 !== 0) this.put(this._sep);
                  let $var = child_sym.children.first;
                  this._rbstack.last[$var] = this.s("self");
                  this.put(`set ${$var ?? ""}(${$var ?? ""}) {${this._nl ?? ""}this.${p ?? ""}${$var ?? ""} = ${$var ?? ""}${this._nl ?? ""}}`)
                })
              } else if (m.children[1] === "private") {
                visibility = "private";
                skipped = true
              } else if (m.children[1] === "protected") {
                visibility = "protected";
                skipped = true
              } else if (m.children[1] === "public") {
                visibility = "public";
                skipped = true
              } else {
                if (m.children[1] === "include") {
                  m = m.updated("begin", m.children.slice(2).map((mname) => {
                    this._namespace.defineProps(this._namespace.find(mname));
                    return this.s("assign", this.s("attr", name, "prototype"), mname)
                  }))
                } else if (m.children[1] === "extend") {
                  m = m.updated(
                    "begin",
                    m.children.slice(2).map(mname => this.s("assign", name, mname))
                  )
                };

                skipped = true
              }
            } else if (this.es2022 && m.type === "send" && m.children.first.type === "self" && (m.children[1] ?? "").toString().endsWith("=")) {
              this.put("static ");

              this.parse(m.updated(
                "lvasgn",
                [(m.children[1] ?? "").toString().replace("=", ""), m.children[2]]
              ))
            } else if (m.type === "defineProps") {
              skipped = true;
              this._namespace.defineProps(m.children.first);
              Object.assign(this._rbstack.last, m.children.first)
            } else {
              if (m.type === "cvasgn" && !this.underscored_private) {
                this.put("static \#$");
                this.put((m.children[0] ?? "").toString().slice(2));
                this.put(" = ");
                this.parse(m.children[1])
              } else {
                skipped = true
              };

              if (m.type === "casgn" && m.children[0] === null) {
                this._rbstack.last[m.children[1]] = name;

                if (this.es2022) {
                  this.put("static ");
                  this.put((m.children[1] ?? "").toString());
                  this.put(" = ");
                  this.parse(m.children[2]);
                  skipped = false
                }
              } else if (m.type === "alias") {
                this._rbstack.last[m.children[0]] = name
              }
            };

            if (skipped) {
              if (m.type !== "defineProps" && !(m.type === "send" && m.children.first === null && [
                "private",
                "protected",
                "public"
              ].includes(m.children[1]))) post.push([m, node_comments])
            } else {
              for (let comment of (node_comments ?? []).reverse()) {
                this.insert(location, comment)
              }
            }
          };

          if (!skipped) this.put(this._nl);
          this.put("}");

          for (let [m, m_comments] of post) {
            this.put(this._sep);

            for (let comment of m_comments) {
              this.put(comment)
            };

            if (m.type === "alias") {
              this.parse(name);
              this.put(".prototype.");

              this.put((m.children[0].children[0] ?? "").toString().replace(
                /[?!]$/m,
                ""
              ));

              this.put(" = ");
              this.parse(name);
              this.put(".prototype.");

              this.put((m.children[1].children[0] ?? "").toString().replace(
                /[?!]$/m,
                ""
              ))
            } else if (m.type === "class") {
              let innerclass_name = m.children.first;

              if (innerclass_name.children.first) {
                innerclass_name = innerclass_name.updated(null, [
                  this.s("attr", innerclass_name.children[0], name),
                  innerclass_name.children[1]
                ])
              } else {
                innerclass_name = innerclass_name.updated(
                  null,
                  [name, innerclass_name.children[1]]
                )
              };

              this.parse(m.updated(null, [innerclass_name, ...m.children.slice(1)]))
            } else if (m.type === "send" && (m.children[0] === null || m.children[0].type === "self")) {
              if (m.children[0] === null) {
                this.parse(m.updated(
                  "send",
                  [this._class_name, ...m.children.slice(1)]
                ))
              } else {
                this.parse(m.updated(
                  "send",
                  [this._class_name, ...m.children.slice(1)]
                ))
              }
            } else if (m.type === "block" && m.children.first.children.first === null) {
              this.parse(this.s(
                "block",
                this.s("send", name, ...m.children.first.children.slice(1)),
                ...m.children.slice(1)
              ))
            } else {
              this.parse(m, "statement")
            }
          };

          if (proxied) {
            this.put(this._sep);

            let rename = name.updated(
              null,
              [name.children.first, (name.children.last ?? "").toString() + "$"]
            );

            if (proxied.children[1].children.length === 1) {
              forward = this.s(
                "send",
                this.s("lvar", "obj"),
                "method_missing",
                this.s("lvar", "prop")
              )
            } else {
              forward = this.s(
                "block",
                this.s("send", null, "proc"),
                this.s("args", this.s("restarg", "args")),

                this.s(
                  "send",
                  this.s("lvar", "obj"),
                  "method_missing",
                  this.s("lvar", "prop"),
                  this.s("splat", this.s("lvar", "args"))
                )
              )
            };

            let proxy = this.s("return", this.s(
              "send",
              this.s("const", null, "Proxy"),
              "new",

              this.s(
                "send",
                rename,
                "new",
                this.s("splat", this.s("lvar", "args"))
              ),

              this.s("hash", this.s("pair", this.s("sym", "get"), this.s(
                "block",
                this.s("send", null, "proc"),
                this.s("args", this.s("arg", "obj"), this.s("arg", "prop")),

                this.s(
                  "if",
                  this.s("in?", this.s("lvar", "prop"), this.s("lvar", "obj")),

                  this.s(
                    "return",
                    this.s("send", this.s("lvar", "obj"), "[]", this.s("lvar", "prop"))
                  ),

                  this.s("return", forward)
                )
              )))
            ));

            if (name.children.first === null) {
              proxy = this.s(
                "def",
                name.children.last,
                this.s("args", this.s("restarg", "args")),
                proxy
              )
            } else {
              proxy = this.s(
                "defs",
                ...name.children,
                this.s("args", this.s("restarg", "args")),
                proxy
              )
            };

            this.parse(proxy)
          }
        } finally {
          this._class_name = class_name;
          this._class_parent = class_parent;
          this._namespace.defineProps(this._rbstack.pop())
        }
      }
    };

    on_const(receiver, name) {
      receiver ??= this._rbstack.map(rb => rb[name]).compact.last;

      if (receiver) {
        if (this.ast_node(receiver) && receiver.type === "cbase") {
          this.put("Function(\"return this\")().")
        } else {
          this.parse(receiver);
          this.put(".")
        }
      };

      return name === "Regexp" && receiver === null ? this.put("RegExp") : this.put(name)
    };

    on_cvar($var) {
      let prefix = this.underscored_private ? "_" : "\#$";
      this._class_name ??= null;

      if (this._class_name) {
        this.parse(this._class_name);

        return this.put(($var ?? "").toString().replace(
          "@@",
          `.${prefix ?? ""}`
        ))
      } else if (this._prototype) {
        return this.put(($var ?? "").toString().replace(
          "@@",
          `this.${prefix ?? ""}`
        ))
      } else {
        return this.put(($var ?? "").toString().replace(
          "@@",
          `this.constructor.${prefix ?? ""}`
        ))
      }
    };

    on_cvasgn($var, expression=null) {
      if (this._state === "statement") this.multi_assign_declarations;
      let prefix = this.underscored_private ? "_" : "\#$";

      if (this._class_name) {
        this.parse(this._class_name);
        this.put(($var ?? "").toString().replace("@@", `.${prefix ?? ""}`))
      } else if (this._prototype) {
        this.put(($var ?? "").toString().replace(
          "@@",
          `this.${prefix ?? ""}`
        ))
      } else {
        this.put(($var ?? "").toString().replace(
          "@@",
          `this.constructor.${prefix ?? ""}`
        ))
      };

      if (expression) {
        this.put(" = ");
        return this.parse(expression)
      }
    };

    on_def(name, args, body=null) {
      let has_restarg, restarg, restarg_name, style, nl;
      body ??= this.s("begin");

      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let block_arg_after_rest = null;

      if (args) {
        has_restarg = args.children.some(a => a.type === "restarg");
        let last_arg = args.children.last;

        if (has_restarg && last_arg?.type === "blockarg") {
          block_arg_after_rest = last_arg.children.first;
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";
          args = this.s("args", ...args.children.slice(0, -1));

          let pop_stmt = this.s(
            "lvasgn",
            block_arg_after_rest,
            this.s("send", this.s("lvar", restarg_name), "pop")
          );

          if (body.type === "begin") {
            body = this.s("begin", pop_stmt, ...body.children)
          } else {
            body = this.s("begin", pop_stmt, body)
          }
        }
      };

      if (args) {
        let kwarg_types = ["kwarg", "kwoptarg", "kwrestarg"];
        has_restarg = args.children.some(a => a.type === "restarg");
        let kwargs = args.children.filter(a => kwarg_types.includes(a.type));

        if (has_restarg && kwargs.length !== 0) {
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";

          args = this.s(
            "args",
            ...args.children.filter(a => !(kwarg_types.includes(a.type)))
          );

          let kwarg_names = [];
          let kwarg_defaults = {};

          for (let kw of kwargs) {
            if (kw.type === "kwarg") {
              kwarg_names.push(kw.children.first)
            } else if (kw.type === "kwoptarg") {
              kwarg_names.push(kw.children.first);
              kwarg_defaults[kw.children.first] = kw.children.last
            }
          };

          let opts_var = "$kwargs";

          let opts_init = this.s(
            "lvasgn",
            opts_var,
            this.s("send", this.s("lvar", restarg_name), "at", this.s("int", -1))
          );

          let is_plain_object = this.s(
            "and",

            this.s(
              "and",

              this.s(
                "send",
                this.s("send", null, "typeof", this.s("lvar", opts_var)),
                "===",
                this.s("str", "object")
              ),

              this.s(
                "send",
                this.s("send", this.s("lvar", opts_var), "==", this.s("nil")),
                "!"
              )
            ),

            this.s(
              "send",
              this.s("attr", this.s("lvar", opts_var), "constructor"),
              "===",
              this.s("const", null, "Object")
            )
          );

          let conditional = this.s(
            "if",
            is_plain_object,
            this.s("send", this.s("lvar", restarg_name), "pop"),
            this.s("lvasgn", opts_var, this.s("hash"))
          );

          let pairs = kwarg_names.map(kw_name => (
            kwarg_defaults[kw_name] ? this.s(
              "pair",
              this.s("sym", kw_name),
              kwarg_defaults[kw_name]
            ) : this.s("pair", this.s("sym", kw_name), this.s("lvar", kw_name))
          ));

          let destructure = this.s(
            "lvasgn",

            this.s("hash_pattern", ...kwarg_names.map(n => (
              kwarg_defaults[n] ? this.s(
                "match_var_with_default",
                n,
                kwarg_defaults[n]
              ) : this.s("match_var", n)
            ))),

            this.s("lvar", opts_var)
          );

          let kwarg_stmts = [];
          kwarg_stmts.push(opts_init);
          kwarg_stmts.push(conditional);

          for (let kw_name of kwarg_names) {
            if (kwarg_defaults[kw_name]) {
              kwarg_stmts.push(this.s("lvasgn", kw_name, this.s(
                "nullish",
                this.s("attr", this.s("lvar", opts_var), kw_name),
                kwarg_defaults[kw_name]
              )))
            } else {
              kwarg_stmts.push(this.s(
                "lvasgn",
                kw_name,
                this.s("attr", this.s("lvar", opts_var), kw_name)
              ))
            }
          };

          if (body.type === "begin") {
            body = this.s("begin", ...kwarg_stmts, ...body.children)
          } else if (body) {
            body = this.s("begin", ...kwarg_stmts, body)
          } else {
            body = this.s("begin", ...kwarg_stmts)
          }
        }
      };

      let add_implicit_block = false;

      let walk = (node) => {
        if (node.type === "yield" || (node.type === "send" && node.children[1] === "_implicitBlockYield")) {
          add_implicit_block = true
        };

        for (let child of node.children) {
          if (this.ast_node(child)) walk(child)
        }
      };

      walk(body);

      if (add_implicit_block) {
        let children = args.children.slice();
        children.push(this.s("optarg", "_implicitBlockYield", this.s("nil")));
        args = this.s("args", ...children)
      };

      let vars = {};
      if (!name) Object.assign(vars, this._vars);

      if (args && args.children.length !== 0) {
        for (let arg of args.children) {
          if (arg.type === "shadowarg") {
            delete vars[arg.children.first]
          } else {
            vars[arg.children.first] = true
          }
        }
      };

      if (this._ast.type === "async") this.put("async ");

      if (!name && this._state !== "method" && this._ast.type !== "defm" && this._ast.type !== "deff" && !this._prop) {
        let expr = body;

        while (expr.type === "autoreturn") {
          expr = expr.children.first
        };

        while (expr.type === "begin" && expr.children.length === 1) {
          expr = expr.children.first
        };

        if (expr.type === "return") expr = expr.children.first;

        if (Converter.EXPRESSIONS.includes(expr.type)) {
          if (expr.type === "send" && expr.children[0] === null && expr.children[1] === "raise") {
            style = "statement"
          } else if (expr.type === "send" && expr.children.length === 2 && expr.children.first === null && this._rbstack.last && this._rbstack.last[expr.children[1]]?.type === "autobind") {
            style = "statement"
          } else {
            style = "expression"
          }
        } else if (expr.type === "if" && expr.children[1] && expr.children[2] && Converter.EXPRESSIONS.includes(expr.children[1].type) && Converter.EXPRESSIONS.includes(expr.children[2].type)) {
          style = "expression"
        } else {
          style = "statement"
        };

        if (args.children.length === 1 && args.children.first.type === "arg" && style === "expression") {
          this.parse(args);
          this.put(" => ")
        } else {
          this.put("(");
          this.parse(args);
          this.put(") => ")
        };

        if (style === "expression") {
          if (expr.type === "taglit") {
            this.parse(expr)
          } else if (expr.type === "hash") {
            this.group(expr)
          } else {
            this.wrap("(", ")", () => this.parse(expr))
          }
        } else if (body.type === "begin" && body.children.length === 0) {
          this.put("{}")
        } else {
          this.put(`{${this._nl ?? ""}`);
          this.scope(body, vars);
          this.put(`${this._nl ?? ""}}`)
        };

        return
      };

      if (body !== this.s("begin")) nl = this._nl;

      {
        let next_token;

        try {
          if (this._prop) {
            this.put(this._prop);
            this._prop = null
          } else if (name) {
            this.put(`function ${(name ?? "").toString().replace(/[?!]$/m, "") ?? ""}`)
          } else {
            this.put("function")
          };

          this.put("(");

          if (args !== null) {
            if (args.type === "forward_args") {
              this.parse(args)
            } else {
              this.parse(this.s(
                "args",
                ...args.children.filter(arg => arg.type !== "shadowarg")
              ))
            }
          };

          this.put(`) {${nl ?? ""}`);
          next_token = this._next_token;
          this._next_token = "return";
          if (this._block_depth) this._block_depth++;
          let mark = this.output_location;
          this.scope(body, vars);

          if (this._block_this && this._block_depth === 1) {
            this.insert(mark, `let self = this${this._sep ?? ""}`);
            this._block_this = false
          };

          this.put(`${nl ?? ""}}`)
        } finally {
          this._next_token = next_token;
          if (this._block_depth) this._block_depth--
        }
      }
    };

    on_defm(name, args, body=null) {
      let has_restarg, restarg, restarg_name, style, nl;
      body ??= this.s("begin");

      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let block_arg_after_rest = null;

      if (args) {
        has_restarg = args.children.some(a => a.type === "restarg");
        let last_arg = args.children.last;

        if (has_restarg && last_arg?.type === "blockarg") {
          block_arg_after_rest = last_arg.children.first;
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";
          args = this.s("args", ...args.children.slice(0, -1));

          let pop_stmt = this.s(
            "lvasgn",
            block_arg_after_rest,
            this.s("send", this.s("lvar", restarg_name), "pop")
          );

          if (body.type === "begin") {
            body = this.s("begin", pop_stmt, ...body.children)
          } else {
            body = this.s("begin", pop_stmt, body)
          }
        }
      };

      if (args) {
        let kwarg_types = ["kwarg", "kwoptarg", "kwrestarg"];
        has_restarg = args.children.some(a => a.type === "restarg");
        let kwargs = args.children.filter(a => kwarg_types.includes(a.type));

        if (has_restarg && kwargs.length !== 0) {
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";

          args = this.s(
            "args",
            ...args.children.filter(a => !(kwarg_types.includes(a.type)))
          );

          let kwarg_names = [];
          let kwarg_defaults = {};

          for (let kw of kwargs) {
            if (kw.type === "kwarg") {
              kwarg_names.push(kw.children.first)
            } else if (kw.type === "kwoptarg") {
              kwarg_names.push(kw.children.first);
              kwarg_defaults[kw.children.first] = kw.children.last
            }
          };

          let opts_var = "$kwargs";

          let opts_init = this.s(
            "lvasgn",
            opts_var,
            this.s("send", this.s("lvar", restarg_name), "at", this.s("int", -1))
          );

          let is_plain_object = this.s(
            "and",

            this.s(
              "and",

              this.s(
                "send",
                this.s("send", null, "typeof", this.s("lvar", opts_var)),
                "===",
                this.s("str", "object")
              ),

              this.s(
                "send",
                this.s("send", this.s("lvar", opts_var), "==", this.s("nil")),
                "!"
              )
            ),

            this.s(
              "send",
              this.s("attr", this.s("lvar", opts_var), "constructor"),
              "===",
              this.s("const", null, "Object")
            )
          );

          let conditional = this.s(
            "if",
            is_plain_object,
            this.s("send", this.s("lvar", restarg_name), "pop"),
            this.s("lvasgn", opts_var, this.s("hash"))
          );

          let pairs = kwarg_names.map(kw_name => (
            kwarg_defaults[kw_name] ? this.s(
              "pair",
              this.s("sym", kw_name),
              kwarg_defaults[kw_name]
            ) : this.s("pair", this.s("sym", kw_name), this.s("lvar", kw_name))
          ));

          let destructure = this.s(
            "lvasgn",

            this.s("hash_pattern", ...kwarg_names.map(n => (
              kwarg_defaults[n] ? this.s(
                "match_var_with_default",
                n,
                kwarg_defaults[n]
              ) : this.s("match_var", n)
            ))),

            this.s("lvar", opts_var)
          );

          let kwarg_stmts = [];
          kwarg_stmts.push(opts_init);
          kwarg_stmts.push(conditional);

          for (let kw_name of kwarg_names) {
            if (kwarg_defaults[kw_name]) {
              kwarg_stmts.push(this.s("lvasgn", kw_name, this.s(
                "nullish",
                this.s("attr", this.s("lvar", opts_var), kw_name),
                kwarg_defaults[kw_name]
              )))
            } else {
              kwarg_stmts.push(this.s(
                "lvasgn",
                kw_name,
                this.s("attr", this.s("lvar", opts_var), kw_name)
              ))
            }
          };

          if (body.type === "begin") {
            body = this.s("begin", ...kwarg_stmts, ...body.children)
          } else if (body) {
            body = this.s("begin", ...kwarg_stmts, body)
          } else {
            body = this.s("begin", ...kwarg_stmts)
          }
        }
      };

      let add_implicit_block = false;

      let walk = (node) => {
        if (node.type === "yield" || (node.type === "send" && node.children[1] === "_implicitBlockYield")) {
          add_implicit_block = true
        };

        for (let child of node.children) {
          if (this.ast_node(child)) walk(child)
        }
      };

      walk(body);

      if (add_implicit_block) {
        let children = args.children.slice();
        children.push(this.s("optarg", "_implicitBlockYield", this.s("nil")));
        args = this.s("args", ...children)
      };

      let vars = {};
      if (!name) Object.assign(vars, this._vars);

      if (args && args.children.length !== 0) {
        for (let arg of args.children) {
          if (arg.type === "shadowarg") {
            delete vars[arg.children.first]
          } else {
            vars[arg.children.first] = true
          }
        }
      };

      if (this._ast.type === "async") this.put("async ");

      if (!name && this._state !== "method" && this._ast.type !== "defm" && this._ast.type !== "deff" && !this._prop) {
        let expr = body;

        while (expr.type === "autoreturn") {
          expr = expr.children.first
        };

        while (expr.type === "begin" && expr.children.length === 1) {
          expr = expr.children.first
        };

        if (expr.type === "return") expr = expr.children.first;

        if (Converter.EXPRESSIONS.includes(expr.type)) {
          if (expr.type === "send" && expr.children[0] === null && expr.children[1] === "raise") {
            style = "statement"
          } else if (expr.type === "send" && expr.children.length === 2 && expr.children.first === null && this._rbstack.last && this._rbstack.last[expr.children[1]]?.type === "autobind") {
            style = "statement"
          } else {
            style = "expression"
          }
        } else if (expr.type === "if" && expr.children[1] && expr.children[2] && Converter.EXPRESSIONS.includes(expr.children[1].type) && Converter.EXPRESSIONS.includes(expr.children[2].type)) {
          style = "expression"
        } else {
          style = "statement"
        };

        if (args.children.length === 1 && args.children.first.type === "arg" && style === "expression") {
          this.parse(args);
          this.put(" => ")
        } else {
          this.put("(");
          this.parse(args);
          this.put(") => ")
        };

        if (style === "expression") {
          if (expr.type === "taglit") {
            this.parse(expr)
          } else if (expr.type === "hash") {
            this.group(expr)
          } else {
            this.wrap("(", ")", () => this.parse(expr))
          }
        } else if (body.type === "begin" && body.children.length === 0) {
          this.put("{}")
        } else {
          this.put(`{${this._nl ?? ""}`);
          this.scope(body, vars);
          this.put(`${this._nl ?? ""}}`)
        };

        return
      };

      if (body !== this.s("begin")) nl = this._nl;

      {
        let next_token;

        try {
          if (this._prop) {
            this.put(this._prop);
            this._prop = null
          } else if (name) {
            this.put(`function ${(name ?? "").toString().replace(/[?!]$/m, "") ?? ""}`)
          } else {
            this.put("function")
          };

          this.put("(");

          if (args !== null) {
            if (args.type === "forward_args") {
              this.parse(args)
            } else {
              this.parse(this.s(
                "args",
                ...args.children.filter(arg => arg.type !== "shadowarg")
              ))
            }
          };

          this.put(`) {${nl ?? ""}`);
          next_token = this._next_token;
          this._next_token = "return";
          if (this._block_depth) this._block_depth++;
          let mark = this.output_location;
          this.scope(body, vars);

          if (this._block_this && this._block_depth === 1) {
            this.insert(mark, `let self = this${this._sep ?? ""}`);
            this._block_this = false
          };

          this.put(`${nl ?? ""}}`)
        } finally {
          this._next_token = next_token;
          if (this._block_depth) this._block_depth--
        }
      }
    };

    on_async(name, args, body=null) {
      let has_restarg, restarg, restarg_name, style, nl;
      body ??= this.s("begin");

      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let block_arg_after_rest = null;

      if (args) {
        has_restarg = args.children.some(a => a.type === "restarg");
        let last_arg = args.children.last;

        if (has_restarg && last_arg?.type === "blockarg") {
          block_arg_after_rest = last_arg.children.first;
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";
          args = this.s("args", ...args.children.slice(0, -1));

          let pop_stmt = this.s(
            "lvasgn",
            block_arg_after_rest,
            this.s("send", this.s("lvar", restarg_name), "pop")
          );

          if (body.type === "begin") {
            body = this.s("begin", pop_stmt, ...body.children)
          } else {
            body = this.s("begin", pop_stmt, body)
          }
        }
      };

      if (args) {
        let kwarg_types = ["kwarg", "kwoptarg", "kwrestarg"];
        has_restarg = args.children.some(a => a.type === "restarg");
        let kwargs = args.children.filter(a => kwarg_types.includes(a.type));

        if (has_restarg && kwargs.length !== 0) {
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";

          args = this.s(
            "args",
            ...args.children.filter(a => !(kwarg_types.includes(a.type)))
          );

          let kwarg_names = [];
          let kwarg_defaults = {};

          for (let kw of kwargs) {
            if (kw.type === "kwarg") {
              kwarg_names.push(kw.children.first)
            } else if (kw.type === "kwoptarg") {
              kwarg_names.push(kw.children.first);
              kwarg_defaults[kw.children.first] = kw.children.last
            }
          };

          let opts_var = "$kwargs";

          let opts_init = this.s(
            "lvasgn",
            opts_var,
            this.s("send", this.s("lvar", restarg_name), "at", this.s("int", -1))
          );

          let is_plain_object = this.s(
            "and",

            this.s(
              "and",

              this.s(
                "send",
                this.s("send", null, "typeof", this.s("lvar", opts_var)),
                "===",
                this.s("str", "object")
              ),

              this.s(
                "send",
                this.s("send", this.s("lvar", opts_var), "==", this.s("nil")),
                "!"
              )
            ),

            this.s(
              "send",
              this.s("attr", this.s("lvar", opts_var), "constructor"),
              "===",
              this.s("const", null, "Object")
            )
          );

          let conditional = this.s(
            "if",
            is_plain_object,
            this.s("send", this.s("lvar", restarg_name), "pop"),
            this.s("lvasgn", opts_var, this.s("hash"))
          );

          let pairs = kwarg_names.map(kw_name => (
            kwarg_defaults[kw_name] ? this.s(
              "pair",
              this.s("sym", kw_name),
              kwarg_defaults[kw_name]
            ) : this.s("pair", this.s("sym", kw_name), this.s("lvar", kw_name))
          ));

          let destructure = this.s(
            "lvasgn",

            this.s("hash_pattern", ...kwarg_names.map(n => (
              kwarg_defaults[n] ? this.s(
                "match_var_with_default",
                n,
                kwarg_defaults[n]
              ) : this.s("match_var", n)
            ))),

            this.s("lvar", opts_var)
          );

          let kwarg_stmts = [];
          kwarg_stmts.push(opts_init);
          kwarg_stmts.push(conditional);

          for (let kw_name of kwarg_names) {
            if (kwarg_defaults[kw_name]) {
              kwarg_stmts.push(this.s("lvasgn", kw_name, this.s(
                "nullish",
                this.s("attr", this.s("lvar", opts_var), kw_name),
                kwarg_defaults[kw_name]
              )))
            } else {
              kwarg_stmts.push(this.s(
                "lvasgn",
                kw_name,
                this.s("attr", this.s("lvar", opts_var), kw_name)
              ))
            }
          };

          if (body.type === "begin") {
            body = this.s("begin", ...kwarg_stmts, ...body.children)
          } else if (body) {
            body = this.s("begin", ...kwarg_stmts, body)
          } else {
            body = this.s("begin", ...kwarg_stmts)
          }
        }
      };

      let add_implicit_block = false;

      let walk = (node) => {
        if (node.type === "yield" || (node.type === "send" && node.children[1] === "_implicitBlockYield")) {
          add_implicit_block = true
        };

        for (let child of node.children) {
          if (this.ast_node(child)) walk(child)
        }
      };

      walk(body);

      if (add_implicit_block) {
        let children = args.children.slice();
        children.push(this.s("optarg", "_implicitBlockYield", this.s("nil")));
        args = this.s("args", ...children)
      };

      let vars = {};
      if (!name) Object.assign(vars, this._vars);

      if (args && args.children.length !== 0) {
        for (let arg of args.children) {
          if (arg.type === "shadowarg") {
            delete vars[arg.children.first]
          } else {
            vars[arg.children.first] = true
          }
        }
      };

      if (this._ast.type === "async") this.put("async ");

      if (!name && this._state !== "method" && this._ast.type !== "defm" && this._ast.type !== "deff" && !this._prop) {
        let expr = body;

        while (expr.type === "autoreturn") {
          expr = expr.children.first
        };

        while (expr.type === "begin" && expr.children.length === 1) {
          expr = expr.children.first
        };

        if (expr.type === "return") expr = expr.children.first;

        if (Converter.EXPRESSIONS.includes(expr.type)) {
          if (expr.type === "send" && expr.children[0] === null && expr.children[1] === "raise") {
            style = "statement"
          } else if (expr.type === "send" && expr.children.length === 2 && expr.children.first === null && this._rbstack.last && this._rbstack.last[expr.children[1]]?.type === "autobind") {
            style = "statement"
          } else {
            style = "expression"
          }
        } else if (expr.type === "if" && expr.children[1] && expr.children[2] && Converter.EXPRESSIONS.includes(expr.children[1].type) && Converter.EXPRESSIONS.includes(expr.children[2].type)) {
          style = "expression"
        } else {
          style = "statement"
        };

        if (args.children.length === 1 && args.children.first.type === "arg" && style === "expression") {
          this.parse(args);
          this.put(" => ")
        } else {
          this.put("(");
          this.parse(args);
          this.put(") => ")
        };

        if (style === "expression") {
          if (expr.type === "taglit") {
            this.parse(expr)
          } else if (expr.type === "hash") {
            this.group(expr)
          } else {
            this.wrap("(", ")", () => this.parse(expr))
          }
        } else if (body.type === "begin" && body.children.length === 0) {
          this.put("{}")
        } else {
          this.put(`{${this._nl ?? ""}`);
          this.scope(body, vars);
          this.put(`${this._nl ?? ""}}`)
        };

        return
      };

      if (body !== this.s("begin")) nl = this._nl;

      {
        let next_token;

        try {
          if (this._prop) {
            this.put(this._prop);
            this._prop = null
          } else if (name) {
            this.put(`function ${(name ?? "").toString().replace(/[?!]$/m, "") ?? ""}`)
          } else {
            this.put("function")
          };

          this.put("(");

          if (args !== null) {
            if (args.type === "forward_args") {
              this.parse(args)
            } else {
              this.parse(this.s(
                "args",
                ...args.children.filter(arg => arg.type !== "shadowarg")
              ))
            }
          };

          this.put(`) {${nl ?? ""}`);
          next_token = this._next_token;
          this._next_token = "return";
          if (this._block_depth) this._block_depth++;
          let mark = this.output_location;
          this.scope(body, vars);

          if (this._block_this && this._block_depth === 1) {
            this.insert(mark, `let self = this${this._sep ?? ""}`);
            this._block_this = false
          };

          this.put(`${nl ?? ""}}`)
        } finally {
          this._next_token = next_token;
          if (this._block_depth) this._block_depth--
        }
      }
    };

    on_deff(name, args, body=null) {
      let has_restarg, restarg, restarg_name, style, nl;
      body ??= this.s("begin");

      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let block_arg_after_rest = null;

      if (args) {
        has_restarg = args.children.some(a => a.type === "restarg");
        let last_arg = args.children.last;

        if (has_restarg && last_arg?.type === "blockarg") {
          block_arg_after_rest = last_arg.children.first;
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";
          args = this.s("args", ...args.children.slice(0, -1));

          let pop_stmt = this.s(
            "lvasgn",
            block_arg_after_rest,
            this.s("send", this.s("lvar", restarg_name), "pop")
          );

          if (body.type === "begin") {
            body = this.s("begin", pop_stmt, ...body.children)
          } else {
            body = this.s("begin", pop_stmt, body)
          }
        }
      };

      if (args) {
        let kwarg_types = ["kwarg", "kwoptarg", "kwrestarg"];
        has_restarg = args.children.some(a => a.type === "restarg");
        let kwargs = args.children.filter(a => kwarg_types.includes(a.type));

        if (has_restarg && kwargs.length !== 0) {
          restarg = args.children.find(a => a.type === "restarg");
          restarg_name = restarg.children.first ?? "args";

          args = this.s(
            "args",
            ...args.children.filter(a => !(kwarg_types.includes(a.type)))
          );

          let kwarg_names = [];
          let kwarg_defaults = {};

          for (let kw of kwargs) {
            if (kw.type === "kwarg") {
              kwarg_names.push(kw.children.first)
            } else if (kw.type === "kwoptarg") {
              kwarg_names.push(kw.children.first);
              kwarg_defaults[kw.children.first] = kw.children.last
            }
          };

          let opts_var = "$kwargs";

          let opts_init = this.s(
            "lvasgn",
            opts_var,
            this.s("send", this.s("lvar", restarg_name), "at", this.s("int", -1))
          );

          let is_plain_object = this.s(
            "and",

            this.s(
              "and",

              this.s(
                "send",
                this.s("send", null, "typeof", this.s("lvar", opts_var)),
                "===",
                this.s("str", "object")
              ),

              this.s(
                "send",
                this.s("send", this.s("lvar", opts_var), "==", this.s("nil")),
                "!"
              )
            ),

            this.s(
              "send",
              this.s("attr", this.s("lvar", opts_var), "constructor"),
              "===",
              this.s("const", null, "Object")
            )
          );

          let conditional = this.s(
            "if",
            is_plain_object,
            this.s("send", this.s("lvar", restarg_name), "pop"),
            this.s("lvasgn", opts_var, this.s("hash"))
          );

          let pairs = kwarg_names.map(kw_name => (
            kwarg_defaults[kw_name] ? this.s(
              "pair",
              this.s("sym", kw_name),
              kwarg_defaults[kw_name]
            ) : this.s("pair", this.s("sym", kw_name), this.s("lvar", kw_name))
          ));

          let destructure = this.s(
            "lvasgn",

            this.s("hash_pattern", ...kwarg_names.map(n => (
              kwarg_defaults[n] ? this.s(
                "match_var_with_default",
                n,
                kwarg_defaults[n]
              ) : this.s("match_var", n)
            ))),

            this.s("lvar", opts_var)
          );

          let kwarg_stmts = [];
          kwarg_stmts.push(opts_init);
          kwarg_stmts.push(conditional);

          for (let kw_name of kwarg_names) {
            if (kwarg_defaults[kw_name]) {
              kwarg_stmts.push(this.s("lvasgn", kw_name, this.s(
                "nullish",
                this.s("attr", this.s("lvar", opts_var), kw_name),
                kwarg_defaults[kw_name]
              )))
            } else {
              kwarg_stmts.push(this.s(
                "lvasgn",
                kw_name,
                this.s("attr", this.s("lvar", opts_var), kw_name)
              ))
            }
          };

          if (body.type === "begin") {
            body = this.s("begin", ...kwarg_stmts, ...body.children)
          } else if (body) {
            body = this.s("begin", ...kwarg_stmts, body)
          } else {
            body = this.s("begin", ...kwarg_stmts)
          }
        }
      };

      let add_implicit_block = false;

      let walk = (node) => {
        if (node.type === "yield" || (node.type === "send" && node.children[1] === "_implicitBlockYield")) {
          add_implicit_block = true
        };

        for (let child of node.children) {
          if (this.ast_node(child)) walk(child)
        }
      };

      walk(body);

      if (add_implicit_block) {
        let children = args.children.slice();
        children.push(this.s("optarg", "_implicitBlockYield", this.s("nil")));
        args = this.s("args", ...children)
      };

      let vars = {};
      if (!name) Object.assign(vars, this._vars);

      if (args && args.children.length !== 0) {
        for (let arg of args.children) {
          if (arg.type === "shadowarg") {
            delete vars[arg.children.first]
          } else {
            vars[arg.children.first] = true
          }
        }
      };

      if (this._ast.type === "async") this.put("async ");

      if (!name && this._state !== "method" && this._ast.type !== "defm" && this._ast.type !== "deff" && !this._prop) {
        let expr = body;

        while (expr.type === "autoreturn") {
          expr = expr.children.first
        };

        while (expr.type === "begin" && expr.children.length === 1) {
          expr = expr.children.first
        };

        if (expr.type === "return") expr = expr.children.first;

        if (Converter.EXPRESSIONS.includes(expr.type)) {
          if (expr.type === "send" && expr.children[0] === null && expr.children[1] === "raise") {
            style = "statement"
          } else if (expr.type === "send" && expr.children.length === 2 && expr.children.first === null && this._rbstack.last && this._rbstack.last[expr.children[1]]?.type === "autobind") {
            style = "statement"
          } else {
            style = "expression"
          }
        } else if (expr.type === "if" && expr.children[1] && expr.children[2] && Converter.EXPRESSIONS.includes(expr.children[1].type) && Converter.EXPRESSIONS.includes(expr.children[2].type)) {
          style = "expression"
        } else {
          style = "statement"
        };

        if (args.children.length === 1 && args.children.first.type === "arg" && style === "expression") {
          this.parse(args);
          this.put(" => ")
        } else {
          this.put("(");
          this.parse(args);
          this.put(") => ")
        };

        if (style === "expression") {
          if (expr.type === "taglit") {
            this.parse(expr)
          } else if (expr.type === "hash") {
            this.group(expr)
          } else {
            this.wrap("(", ")", () => this.parse(expr))
          }
        } else if (body.type === "begin" && body.children.length === 0) {
          this.put("{}")
        } else {
          this.put(`{${this._nl ?? ""}`);
          this.scope(body, vars);
          this.put(`${this._nl ?? ""}}`)
        };

        return
      };

      if (body !== this.s("begin")) nl = this._nl;

      {
        let next_token;

        try {
          if (this._prop) {
            this.put(this._prop);
            this._prop = null
          } else if (name) {
            this.put(`function ${(name ?? "").toString().replace(/[?!]$/m, "") ?? ""}`)
          } else {
            this.put("function")
          };

          this.put("(");

          if (args !== null) {
            if (args.type === "forward_args") {
              this.parse(args)
            } else {
              this.parse(this.s(
                "args",
                ...args.children.filter(arg => arg.type !== "shadowarg")
              ))
            }
          };

          this.put(`) {${nl ?? ""}`);
          next_token = this._next_token;
          this._next_token = "return";
          if (this._block_depth) this._block_depth++;
          let mark = this.output_location;
          this.scope(body, vars);

          if (this._block_this && this._block_depth === 1) {
            this.insert(mark, `let self = this${this._sep ?? ""}`);
            this._block_this = false
          };

          this.put(`${nl ?? ""}}`)
        } finally {
          this._next_token = next_token;
          if (this._block_depth) this._block_depth--
        }
      }
    };

    on_optarg(name, value) {
      this.put(this.jsvar(name));
      this.put("=");
      return this.parse(value)
    };

    on_restarg(name=null) {
      this.put("...");
      if (name) return this.put(this.jsvar(name))
    };

    on_defs(target, method, args, body) {
      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let node = this.transform_defs(target, method, args, body);

      if (node.type === "send" && this._ast.type === "asyncs") {
        node = node.updated(
          null,
          [...node.children.slice(0, 2), node.children[2].updated("async")]
        )
      };

      return this.parse(node, "method")
    };

    on_defp(target, method, args, body) {
      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let node = this.transform_defs(target, method, args, body);

      if (node.type === "send" && this._ast.type === "asyncs") {
        node = node.updated(
          null,
          [...node.children.slice(0, 2), node.children[2].updated("async")]
        )
      };

      return this.parse(node, "method")
    };

    on_asyncs(target, method, args, body) {
      if (this._ast.loc && typeof this._ast.loc === "object" && this._ast.loc !== null && "assignment" in this._ast.loc && this._ast.loc.assignment && typeof this._ast.loc === "object" && this._ast.loc !== null && "end" in this._ast.loc && this._ast.loc.end === null) {
        body = this.s("autoreturn", body)
      };

      let node = this.transform_defs(target, method, args, body);

      if (node.type === "send" && this._ast.type === "asyncs") {
        node = node.updated(
          null,
          [...node.children.slice(0, 2), node.children[2].updated("async")]
        )
      };

      return this.parse(node, "method")
    };

    transform_defs(target, method, args, body) {
      let node;

      if (!this._ast.is_method() || this._ast.type === "defp") {
        node = this.s("prop", target, {[(method ?? "").toString()]: {
          enumerable: this.s("true"),
          configurable: this.s("true"),

          get: this.s(
            "block",
            this.s("send", null, "proc"),
            args,
            this.s("autoreturn", body)
          )
        }})
      } else if (/=$/m.test(method)) {
        node = this.s(
          "prop",
          target,

          {[(method ?? "").toString().replace("=", "")]: {
            enumerable: this.s("true"),
            configurable: this.s("true"),
            set: this.s("block", this.s("send", null, "proc"), args, body)
          }}
        )
      } else {
        let clean_method = (method ?? "").toString().replace(/[?!]$/m, "");

        node = this.s(
          "send",
          target,
          `${clean_method ?? ""}=`,
          this.s("def", null, args, body)
        )
      };

      if (this._comments[this._ast]) {
        this._comments[node] = this._comments[this._ast]
      };

      return node
    };

    on_defined_q($var) {
      let op = this._ast.type === "defined?" ? "!==" : "===";
      this.put("typeof ");
      this.parse($var);
      return this.put(` ${op ?? ""} 'undefined'`)
    };

    on_undefined_q($var) {
      let op = this._ast.type === "defined?" ? "!==" : "===";
      this.put("typeof ");
      this.parse($var);
      return this.put(` ${op ?? ""} 'undefined'`)
    };

    on_dstr(...children) {
      if (this._state === "expression" && children.length === 0) {
        this.puts("\"\"");
        return
      };

      let strings = children.filter(child => child.type === "str").map(child => (
        child.children.last
      )).join("");

      let heredoc = strings.length > 40 && strings.match(/\n/g).length > 3;
      this.put("`");

      for (let child of children) {
        if (child.type === "str") {
          let str = JSON.stringify(child.children.first).slice(1, -1).replaceAll(
            "${",
            "$\\{"
          ).replaceAll("`", "\\\\`");

          if (!str.includes("\\\\")) str = str.replaceAll(/\\"/g, "\"");

          if (heredoc) {
            this.put_raw(str.replaceAll("\\n", "\n"))
          } else {
            this.put(str)
          }
        } else if (!(child.type === "begin" && child.children.length === 0)) {
          this.put("${");

          if (this._nullish_to_s) {
            this.parse(this.s("nullish", child, this.s("str", "")))
          } else {
            this.parse(child)
          };

          this.put("}")
        }
      };

      return this.put("`")
    };

    on_dsym(...children) {
      if (this._state === "expression" && children.length === 0) {
        this.puts("\"\"");
        return
      };

      let strings = children.filter(child => child.type === "str").map(child => (
        child.children.last
      )).join("");

      let heredoc = strings.length > 40 && strings.match(/\n/g).length > 3;
      this.put("`");

      for (let child of children) {
        if (child.type === "str") {
          let str = JSON.stringify(child.children.first).slice(1, -1).replaceAll(
            "${",
            "$\\{"
          ).replaceAll("`", "\\\\`");

          if (!str.includes("\\\\")) str = str.replaceAll(/\\"/g, "\"");

          if (heredoc) {
            this.put_raw(str.replaceAll("\\n", "\n"))
          } else {
            this.put(str)
          }
        } else if (!(child.type === "begin" && child.children.length === 0)) {
          this.put("${");

          if (this._nullish_to_s) {
            this.parse(this.s("nullish", child, this.s("str", "")))
          } else {
            this.parse(child)
          };

          this.put("}")
        }
      };

      return this.put("`")
    };

    on_ensure(...children) {
      return this.parse(
        this.s("kwbegin", this.s("ensure", ...children)),
        this._state
      )
    };

    on___FILE__() {
      return this.put((this._ast.type ?? "").toString())
    };

    on___LINE__() {
      return this.put((this._ast.type ?? "").toString())
    };

    on_for($var, expression, block) {
      if (this._jsx && this._ast.type === "for_of") {
        this.parse(this.s(
          "block",
          this.s("send", expression, "map"),
          this.s("args", this.s("arg", $var.children[0])),
          this.s("autoreturn", block)
        ));

        return
      };

      {
        let vars;
        let next_token;

        try {
          vars = {...this._vars};
          next_token = this._next_token;
          this._next_token = "continue";
          this.put("for (let ");
          this.parse($var);

          if (expression && ["irange", "erange"].includes(expression.type)) {
            this.put(" = ");
            this.parse(expression.children.first);
            this.put("; ");
            this.parse($var);

            if (expression.type === "erange") {
              this.put(" < ")
            } else {
              this.put(" <= ")
            };

            this.parse(expression.children.last);
            this.put("; ");
            this.parse($var);
            this.put("++")
          } else if (expression && expression.type === "send" && expression.children[1] === "step" && [
            "irange",
            "erange"
          ].includes(expression.children[0].type)) {
            let range = expression.children[0];
            let step = expression.children[2];
            let step_val = step.type === "int" ? step.children[0] : null;
            this.put(" = ");
            this.parse(range.children.first);
            this.put("; ");
            this.parse($var);

            if (step_val && step_val < 0) {
              if (range.type === "erange") {
                this.put(" > ")
              } else {
                this.put(" >= ")
              }
            } else {
              if (range.type === "erange") {
                this.put(" < ")
              } else {
                this.put(" <= ")
              }
            };

            this.parse(range.children.last);
            this.put("; ");
            this.parse($var);

            if (step_val === 1) {
              this.put("++")
            } else if (step_val === -1) {
              this.put("--")
            } else if (step_val && step_val < 0) {
              this.put(" -= ");
              this.put((-step_val ?? "").toString())
            } else {
              this.put(" += ");
              this.parse(step)
            }
          } else {
            this.put(this._ast.type === "for_of" ? " of " : " in ");
            this.parse(expression)
          };

          this.puts(") {");
          this.redoable(block);
          this.sput("}")
        } finally {
          this._next_token = next_token;
          this._vars = vars
        }
      }
    };

    on_for_of($var, expression, block) {
      if (this._jsx && this._ast.type === "for_of") {
        this.parse(this.s(
          "block",
          this.s("send", expression, "map"),
          this.s("args", this.s("arg", $var.children[0])),
          this.s("autoreturn", block)
        ));

        return
      };

      {
        let vars;
        let next_token;

        try {
          vars = {...this._vars};
          next_token = this._next_token;
          this._next_token = "continue";
          this.put("for (let ");
          this.parse($var);

          if (expression && ["irange", "erange"].includes(expression.type)) {
            this.put(" = ");
            this.parse(expression.children.first);
            this.put("; ");
            this.parse($var);

            if (expression.type === "erange") {
              this.put(" < ")
            } else {
              this.put(" <= ")
            };

            this.parse(expression.children.last);
            this.put("; ");
            this.parse($var);
            this.put("++")
          } else if (expression && expression.type === "send" && expression.children[1] === "step" && [
            "irange",
            "erange"
          ].includes(expression.children[0].type)) {
            let range = expression.children[0];
            let step = expression.children[2];
            let step_val = step.type === "int" ? step.children[0] : null;
            this.put(" = ");
            this.parse(range.children.first);
            this.put("; ");
            this.parse($var);

            if (step_val && step_val < 0) {
              if (range.type === "erange") {
                this.put(" > ")
              } else {
                this.put(" >= ")
              }
            } else {
              if (range.type === "erange") {
                this.put(" < ")
              } else {
                this.put(" <= ")
              }
            };

            this.parse(range.children.last);
            this.put("; ");
            this.parse($var);

            if (step_val === 1) {
              this.put("++")
            } else if (step_val === -1) {
              this.put("--")
            } else if (step_val && step_val < 0) {
              this.put(" -= ");
              this.put((-step_val ?? "").toString())
            } else {
              this.put(" += ");
              this.parse(step)
            }
          } else {
            this.put(this._ast.type === "for_of" ? " of " : " in ");
            this.parse(expression)
          };

          this.puts(") {");
          this.redoable(block);
          this.sput("}")
        } finally {
          this._next_token = next_token;
          this._vars = vars
        }
      }
    };

    on_hash(...pairs) {
      return this._compact(() => {
        let singleton = pairs.length <= 1;

        if (singleton) {
          this.put("{")
        } else {
          this.puts("{")
        };

        let index = 0;

        while (pairs.length > 0) {
          let node = pairs.shift();

          if (index !== 0) {
            if (singleton) {
              this.put(", ")
            } else {
              this.put(`,${this._ws ?? ""}`)
            }
          };

          index++;

          if (node.type === "kwsplat") {
            if (node.children.first.type === "hash") {
              pairs.unshift(...node.children.first.children);
              index = 0
            } else {
              this.put("...");
              this.parse(node.children.first)
            };

            continue
          };

          let node_comments = this._comments[node];

          if (node_comments && node_comments.length !== 0) {
            if (singleton) {
              this.puts("");
              singleton = false
            };

            for (let comment of this.comments(node)) {
              this.put(comment)
            }
          };

          {
            let block_depth;
            let block_hash;

            try {
              let receiver, method;
              [block_depth, block_hash] = [this._block_depth, false];
              let [left, right] = node.children;

              if (typeof right === "object" && right !== null && !Array.isArray(right) || right.type === "block") {
                block_hash = true;
                if (!this._block_depth) this._block_depth = 0
              };

              if (left.type === "prop") {
                if (right.get) {
                  let get_comments = this._comments[right.get];

                  if (get_comments && get_comments.length !== 0) {
                    if (singleton) {
                      this.puts("");
                      singleton = false
                    };

                    for (let comment of this.comments(right.get)) {
                      this.put(comment)
                    }
                  };

                  this._prop = `get ${left.children[0] ?? ""}`;
                  this.parse(right.get);

                  if (right.set) {
                    if (singleton) {
                      this.put(", ")
                    } else {
                      this.put(`,${this._ws ?? ""}`)
                    }
                  }
                };

                if (right.set) {
                  let set_comments = this._comments[right.set];

                  if (set_comments && set_comments.length !== 0) {
                    if (singleton) {
                      this.puts("");
                      singleton = false
                    };

                    for (let comment of this.comments(right.set)) {
                      this.put(comment)
                    }
                  };

                  this._prop = `set ${left.children[0] ?? ""}`;
                  this.parse(right.set)
                }
              } else {
                if (right.type === "hash") {
                  for (let pair of right.children) {
                    let pair_child = pair.children.last;
                    if (!this.ast_node(pair_child)) continue;

                    if (["block", "def", "defm", "async"].includes(pair_child.type)) {
                      if (this._comments[pair_child]) {
                        if (singleton) {
                          this.puts("");
                          singleton = false
                        };

                        for (let comment of this.comments(pair_child)) {
                          this.put(comment)
                        }
                      }
                    }
                  }
                };

                let anonfn = right && right.type === "block";

                if (anonfn) {
                  let [receiver, method] = right.children[0].children;

                  if (receiver) {
                    if (method !== "new" || receiver.children[0] !== null || receiver.children[1] !== "Proc") {
                      anonfn = false
                    }
                  } else if (!["lambda", "proc"].includes(method)) {
                    anonfn = false
                  };

                  if (anonfn && this._class_name) {
                    let walk = (ast) => {
                      if (ast === this.s("self")) {
                        anonfn = false
                      } else if (["ivar", "ivasgn"].includes(ast.type)) {
                        anonfn = false
                      } else if (ast.type === "send" && ast.children.first === null) {
                        if (ast.children.length === 2) method = ast.children.last;
                        if (this._rbstack.some(rb => rb[method]) || method === "this") anonfn = false
                      };

                      for (let child of ast.children) {
                        if (this.ast_node(child)) walk(child)
                      }
                    };

                    walk(right)
                  }
                };

                if (anonfn && /^[a-zA-Z_$][a-zA-Z_$0-9]*$/.test((left.children.first ?? "").toString())) {
                  this._prop = left.children.first;
                  this.parse(right, "method")
                } else if (left.type === "sym" && (right.type === "lvar" || (right.type === "send" && right.children.first === null)) && left.children.last === right.children.last) {
                  this.parse(right)
                } else if (right.type === "defm" && ["sym", "str"].includes(left.type)) {
                  this._prop = (left.children.first ?? "").toString();
                  this.parse(right)
                } else {
                  if (!["str", "sym"].includes(left.type)) {
                    this.put("[");
                    this.parse(left);
                    this.put("]")
                  } else if (/^[a-zA-Z_$][a-zA-Z_$0-9]*$/.test((left.children.first ?? "").toString())) {
                    this.put(left.children.first)
                  } else {
                    this.parse(left)
                  };

                  this.put(": ");
                  this.parse(right)
                }
              }
            } finally {
              if (block_hash) this._block_depth = block_depth
            }
          }
        };

        return singleton ? this.put("}") : this.sput("}")
      })
    };

    on_hide(...nodes) {
      this.capture(() => this.parse_all(...nodes));
      if (this._state === "statement" && this._lines.last === []) this._lines.pop();

      if ((this._lines.last.last ?? "").toString() === this._sep) {
        return this._lines.last.pop()
      }
    };

    parse_condition(condition) {
      let saved_boolean_context = this._boolean_context;
      this._boolean_context = true;

      if (this._truthy === "ruby" && !this.boolean_expression(condition)) {
        this._need_truthy_helpers.push("T");
        this.put("$T(");
        this.parse(condition);
        this.put(")")
      } else {
        this.parse(condition)
      };

      this._boolean_context = saved_boolean_context;
      return this._boolean_context
    };

    on_if(condition, then_block, else_block) {
      if (condition.type === "send" && condition.children[1] === "nil?" && condition.children.slice(2).length === 0) {
        let tested = condition.children[0];

        if (this.es2021 && then_block && !else_block) {
          let asgn = then_block;

          if (asgn.type === "lvasgn" && tested.type === "lvar" && asgn.children[0] === tested.children[0]) {
            return this.parse(this.s(
              "op_asgn",
              this.s("lvasgn", tested.children[0]),
              "??",
              asgn.children[1]
            ))
          } else if (asgn.type === "ivasgn" && tested.type === "ivar" && asgn.children[0] === tested.children[0]) {
            return this.parse(this.s(
              "op_asgn",
              this.s("ivasgn", tested.children[0]),
              "??",
              asgn.children[1]
            ))
          } else if (asgn.type === "cvasgn" && tested.type === "cvar" && asgn.children[0] === tested.children[0]) {
            return this.parse(this.s(
              "op_asgn",
              this.s("cvasgn", tested.children[0]),
              "??",
              asgn.children[1]
            ))
          } else if (asgn.type === "send" && (asgn.children[1] ?? "").toString().endsWith("=") && asgn.children[1] !== "[]=" && tested.type === "send" && asgn.children[0] === tested.children[0] && (asgn.children[1] ?? "").toString().chomp("=") === (tested.children[1] ?? "").toString()) {
            this.parse(tested);
            this.put(" ??= ");
            this.parse(asgn.children[2]);
            return
          } else if (asgn.type === "send" && asgn.children[1] === "[]=" && tested.type === "send" && tested.children[1] === "[]" && asgn.children[0] === tested.children[0] && asgn.children[2] === tested.children[2]) {
            this.parse(tested);
            this.put(" ??= ");
            this.parse(asgn.children[3]);
            return
          }
        };

        if (this.es2020 && then_block && else_block && else_block === tested) {
          this.parse(tested);
          this.put(" ?? ");
          this.parse(then_block);
          return
        }
      };

      if (else_block && !then_block) {
        return this.parse(
          this.s("if", this.s("not", condition), else_block, null),
          this._state
        )
      };

      then_block ??= this.s("nil");

      if (this._state === "statement") {
        {
          let inner;

          try {
            inner = this._inner;
            this._inner = this._ast;

            if (else_block || then_block.type === "begin") {
              this.put("if (");
              this.parse_condition(condition);
              this.puts(") {");
              this.jscope(then_block);
              this.sput("}");

              while (else_block && else_block.type === "if") {
                [condition, then_block, else_block] = else_block.children;

                if (then_block) {
                  this.put(" else if (");
                  this.parse_condition(condition);
                  this.puts(") {");
                  this.jscope(then_block);
                  this.sput("}")
                } else {
                  this.put(" else if (");
                  this.parse_condition(this.s("not", condition));
                  this.puts(") {");
                  this.jscope(else_block);
                  this.sput("}");
                  else_block = null
                }
              };

              if (else_block) {
                this.puts(" else {");
                this.jscope(else_block);
                this.sput("}")
              }
            } else {
              if (["lvasgn", "gvasgn"].includes(then_block.type)) {
                this._vars[then_block.children.first] ??= "pending"
              };

              this.put("if (");
              this.parse_condition(condition);
              this.put(") ");
              this.wrap("{", "}", () => this.jscope(then_block))
            }
          } finally {
            this._inner = inner
          }
        }
      } else {
        else_block ??= this.s("nil");

        if (this._jsx) {
          if (then_block.type === "begin") {
            then_block = this.s("xnode", "", ...then_block.children)
          };

          if (else_block.type === "begin") {
            else_block = this.s("xnode", "", ...else_block.children)
          }
        } else {
          if (then_block.type === "begin") then_block = this.s("kwbegin", then_block);
          if (else_block.type === "begin") else_block = this.s("kwbegin", else_block)
        };

        this.parse_condition(condition);
        this.put(" ? ");
        this.parse(then_block, this._state);
        this.put(" : ");
        return this.parse(else_block, this._state)
      }
    };

    on_in_q(left, right) {
      this.parse(left);
      this.put(" in ");
      return this.parse(right)
    };

    on_instanceof(target, klass) {
      this.parse(target);
      this.put(" instanceof ");
      return this.parse(klass)
    };

    on_import(path, ...args) {
      let default_import, from_kwarg_position;

      if (this.module_type === "cjs") {
        let first_arg = args.first;

        if (this.ast_node(first_arg) && first_arg.type === "attr") {
          return this.parse(
            this.s("casgn", ...first_arg.children, this.s(
              "send",
              null,
              "require",
              this.s("str", Array.from(path).first)
            )),

            "statement"
          )
        } else if (Array.isArray(first_arg) && first_arg.length === 1) {
          let target = first_arg.first;

          if (this.ast_node(target) && target.type === "attr" && target.children.first === null) {
            return this.parse(
              this.s("casgn", ...target.children, this.s(
                "attr",

                this.s(
                  "send",
                  null,
                  "require",
                  this.s("str", Array.from(path).first)
                ),

                target.children.last
              )),

              "statement"
            )
          }
        }
      };

      this.put("import ");

      if (args.length === 0) {
        return this.put(JSON.stringify(path))
      } else {
        default_import = !Array.isArray(args.first) && [
          "const",
          "send",
          "attr",
          "str"
        ].includes(args.first.type);

        if (default_import && args.length > 1) {
          this.parse(args.shift());
          this.put(", ");
          default_import = false
        };

        if (Array.isArray(args.first)) args = args.first;
        if (args.first.type === "array") args = args.first.children;
        if (!default_import) this.put("{ ");

        args.forEach((arg, index) => {
          if (index !== 0) this.put(", ");

          if (arg.type === "str") {
            this.put(arg.children.first)
          } else {
            this.parse(arg)
          }
        });

        if (!default_import) this.put(" }");
        from_kwarg_position = 0;

        if (Array.isArray(path) && typeof path[0] !== "string" && path[0].type === "pair" && path[0].children[0].children[0] === "as") {
          this.put(` as ${path[0].children[1].children.last ?? ""}`);
          from_kwarg_position = 1
        };

        this.put(" from ");

        if (Array.isArray(path) && typeof path[from_kwarg_position] !== "string" && path[from_kwarg_position].type === "pair") {
          return path[from_kwarg_position].children[0].children[0] === "from" ? this.put(JSON.stringify(path[from_kwarg_position].children[1].children[0])) : this.put("\"\"")
        } else {
          return this.put(Array.isArray(path) ? JSON.stringify(path[0]) : JSON.stringify(path))
        }
      }
    };

    on_export(...args) {
      this.put("export ");
      let node = args.first;
      let final_export = false;

      if (typeof node === "object" && node !== null && "type" in node && node.type === "str" && node.children[0] === "*") {
        this.put("* from ");

        if (typeof args[1] === "object" && args[1] !== null && "type" in args[1] && args[1].type === "hash") {
          let from_pair = args[1].children.find(pair => (
            typeof pair.children[0] === "object" && pair.children[0] !== null && "children" in pair.children[0] && pair.children[0].children[0] === "from"
          ));

          if (from_pair) this.put(JSON.stringify(from_pair.children[1].children[0]))
        };

        return
      } else if (node === "default") {
        this.put("default ");
        args.shift()
      } else if (typeof node === "object" && node !== null && "type" in node && node.children[1] === "default") {
        this.put("default ");
        args[0] = node.children[2]
      } else if (typeof node === "object" && node !== null && "type" in node && [
        "lvasgn",
        "casgn"
      ].includes(node.type)) {
        if (node.children[0] === "default") {
          this.put("default ");
          args[0] = node.children[1]
        } else {
          this.put("const ")
        }
      } else if (typeof node !== "object" || node === null || !("type" in node) || node.type !== "module") {
        if (typeof node === "object" && node !== null && "type" in node && node.type === "array" && typeof node.children[0] === "object" && node.children[0] !== null && "type" in node.children[0] && (node.children[0].type === "const" || node.children[0].type === "send" || (node.children[0].type === "hash" && node.children[0].children[0].children[0].children[0] === "default"))) {
          final_export = true;
          this.put("{ ");
          let first = true;

          for (let arg of node.children) {
            if (arg.type === "hash") {
              for (let pair of arg.children) {
                if (!first) this.put(", ");
                first = false;
                let key = pair.children[0].children[0];
                let value = pair.children[1];
                this.parse(value);
                this.put(" as ");
                this.put((key ?? "").toString())
              }
            } else {
              if (!first) this.put(", ");
              first = false;
              this.parse(arg)
            }
          };

          this.put(" }")
        }
      };

      if (!final_export) {
        return args.forEach((arg, index) => {
          if (index !== 0) this.put(", ");
          this.parse(arg)
        })
      }
    };

    on_ivar($var) {
      let node_type;

      if (this.ivars && $var in this.ivars) {
        node_type = typeof Function !== 'undefined' ? "js_hostvalue" : "hostvalue";
        return this.parse(this.s(node_type, this.ivars[$var]))
      } else if (this.underscored_private) {
        return this.parse(this.s(
          "attr",
          this.s("self"),
          ($var ?? "").toString().replace("@", "_")
        ))
      } else {
        return this.parse(this.s(
          "attr",
          this.s("self"),
          ($var ?? "").toString().replace("@", "#")
        ))
      }
    };

    on_js_hostvalue(value) {
      let pairs;

      if (value === null) {
        return this.parse(this.s("nil"))
      } else if (value === true) {
        return this.parse(this.s("true"))
      } else if (value === false) {
        return this.parse(this.s("false"))
      } else if (typeof value === "string") {
        return this.parse(this.s("str", value))
      } else if (typeof value === "number") {
        return Number.isInteger(value) ? this.parse(this.s("int", value)) : this.parse(this.s(
          "float",
          value
        ))
      } else if (typeof value === "symbol") {
        return this.parse(this.s("str", (value ?? "").toString()))
      } else if (Array.isArray(value)) {
        return this.parse(this.s(
          "array",
          ...value.map(v => this.s("js_hostvalue", v))
        ))
      } else if (typeof value === "object") {
        pairs = Object.entries(value).map((entry) => {
          let k = entry[0];
          let v = entry[1];

          return this.s(
            "pair",
            this.s("str", (k ?? "").toString()),
            this.s("js_hostvalue", v)
          )
        });

        return this.parse(this.s("hash", ...pairs))
      } else {
        return this.parse(this.s("str", (value ?? "").toString()))
      }
    };

    on_hostvalue(value) {
      switch (value) {
      case Hash:

        return this.parse(this.s("hash", ...value.map(([key, hvalue]) => {
          switch (key) {
          case String:

            return this.s(
              "pair",
              this.s("str", key),
              this.s("hostvalue", hvalue)
            );

          case Symbol:

            return this.s(
              "pair",
              this.s("sym", key),
              this.s("hostvalue", hvalue)
            );

          default:

            return this.s(
              "pair",
              this.s("hostvalue", key),
              this.s("hostvalue", hvalue)
            )
          }
        })));

      case Array:

        return this.parse(this.s(
          "array",
          ...value.map(hvalue => this.s("hostvalue", hvalue))
        ));

      case String:
        return this.parse(this.s("str", value));

      case Integer:
        return this.parse(this.s("int", value));

      case Float:
        return this.parse(this.s("float", value));

      case true:
        return this.parse(this.s("true"));

      case false:
        return this.parse(this.s("false"));

      case null:
        return this.parse(this.s("nil"));

      case Symbol:
        return this.parse(this.s("sym", value));

      default:

        if (typeof value === "object" && value !== null && "as_json" in value) {
          value = value.as_json
        };

        if (typeof value === "object" && value !== null && "to_hash" in value && typeof value.to_hash === "object" && value.to_hash !== null && !Array.isArray(value.to_hash)) {
          this.parse(this.s("hostvalue", value.to_hash))
        } else if (typeof value === "object" && value !== null && "to_ary" in value && Array.isArray(value.to_ary)) {
          this.parse(this.s("hostvalue", value.to_ary))
        } else if (typeof value === "object" && value !== null && "to_str" in value && typeof value.to_str === "string") {
          this.parse(this.s("str", value.to_str))
        } else if (typeof value === "object" && value !== null && "to_int" in value && typeof value.to_int === "number" && Number.isInteger(value.to_int)) {
          this.parse(this.s("int", value.to_int))
        } else if (typeof value === "object" && value !== null && "to_sym" in value && typeof value.to_sym === "symbol") {
          this.parse(this.s("sym", value))
        } else {
          this.parse(this.s("str", JSON.stringify(value)))
        }
      }
    };

    on_ivasgn($var, expression=null) {
      if (this._state === "statement") this.multi_assign_declarations;

      this.put(`${($var ?? "").toString().replace(
        "@",
        "this." + (this.underscored_private ? "_" : "#")
      ) ?? ""}`);

      if (expression) {
        this.put(" = ");
        return this.parse(expression)
      }
    };

    on_rescue(...statements) {
      return this.parse(
        this.s("kwbegin", this.s("rescue", ...statements)),
        this._state
      )
    };

    on_kwbegin(...children) {
      let $var;
      let block = children.first;

      if (this._state === "expression") {
        this.parse(this.s(
          "send",

          this.s(
            "block",
            this.s("send", null, "proc"),
            this.s("args"),
            this.s("begin", this.s("autoreturn", ...children))
          ),

          "[]"
        ));

        return
      };

      let body = null;
      let recovers = null;
      let otherwise = null;
      let $finally = null;
      let uses_retry = false;
      if (block?.type === "ensure") [block, $finally] = block.children;

      if (block && block.type === "rescue") {
        let $masgn_temp = block.children.slice();
        body = $masgn_temp.shift();
        otherwise = $masgn_temp.pop();
        recovers = $masgn_temp;
        let exception_vars = [];

        for (let r of recovers) {
          let v = r.children[1];
          if (v && !exception_vars.includes(v)) exception_vars.push(v)
        };

        $var = exception_vars.first;

        if (recovers.slice(0, -1).some(recover => !recover.children[0])) {
          throw new Error("additional recovers after catchall", this._ast)
        };

        let has_retry = null;

        has_retry = (node) => {
          if (!this.ast_node(node)) return false;
          if (node.type === "retry") return true;
          return node.children.some(child => has_retry(child))
        };

        uses_retry = recovers.some(recover => has_retry(recover.children.last))
      } else {
        body = block
      };

      if (!recovers && !$finally) {
        this.puts("{");
        this.scope(this.s("begin", ...children));
        this.sput("}");
        return
      };

      let hoisted_any = false;

      if ($finally) {
        let try_vars = [];
        let find_lvasgns = null;

        find_lvasgns = (node) => {
          if (!this.ast_node(node)) return;

          if (node.type === "lvasgn") {
            if (!try_vars.includes(node.children[0])) try_vars.push(node.children[0])
          };

          for (let c of node.children) {
            find_lvasgns(c)
          }
        };

        find_lvasgns(body);
        let finally_vars = [];
        let find_lvars = null;

        find_lvars = (node) => {
          if (!this.ast_node(node)) return;

          if (node.type === "lvar") {
            if (!finally_vars.includes(node.children[0])) {
              finally_vars.push(node.children[0])
            }
          };

          for (let c of node.children) {
            find_lvars(c)
          }
        };

        find_lvars($finally);

        let hoisted = try_vars.filter($var => (
          finally_vars.includes($var) && !this._vars[$var]
        ));

        if (hoisted.length > 0) {
          hoisted_any = true;
          this.puts("{");

          for (let $var of hoisted) {
            this.put(`let ${$var ?? ""}${this._sep ?? ""}`);
            this._vars[$var] = true
          }
        }
      };

      if (uses_retry) this.puts(`while (true) {${this._nl ?? ""}`);
      if (otherwise) this.puts(`let $no_exception = false${this._sep ?? ""}`);
      this.puts("try {");
      this.scope(body);
      if (otherwise) this.puts(`${this._sep ?? ""}$no_exception = true`);
      if (uses_retry) this.puts(`${this._sep ?? ""}break`);
      this.sput("}");

      if (recovers) {
        if (recovers.length === 1 && !recovers.first.children.first) {
          let walk = null;

          walk = (ast) => {
            let result;
            if (!this.ast_node(ast)) return null;
            if (ast.type === "gvar" && ast.children.first === "$!") result = ast;

            for (let child of ast.children) {
              result ||= walk(child)
            };

            return result
          };

          if (!$var && !walk(this._ast)) {
            this.puts(" catch {")
          } else {
            $var ??= this.s("gvar", "$EXCEPTION");
            this.put(" catch (");
            this.parse($var);
            this.puts(") {")
          };

          this.scope(recovers.first.children.last);
          this.sput("}")
        } else {
          let catch_var = $var ?? this.s("gvar", "$EXCEPTION");
          this.put(" catch (");
          this.parse(catch_var);
          this.puts(") {");
          let first = true;

          for (let recover of recovers) {
            let [exceptions, recover_var, recovery] = recover.children;

            if (exceptions) {
              if (!first) this.put("} else ");
              first = false;
              this.put("if (");

              exceptions.children.forEach((exception, index) => {
                if (index !== 0) this.put(" || ");

                if (exception.type === "const" && exception.children[0] === null && exception.children[1] === "String") {
                  this.put("typeof ");
                  this.parse(catch_var);
                  this.put(" == \"string\"")
                } else {
                  this.parse(catch_var);
                  this.put(" instanceof ");
                  this.parse(exception)
                }
              });

              this.puts(") {")
            } else {
              this.puts("} else {")
            };

            if (recover_var && recover_var !== catch_var) {
              this.put("var ");
              this.parse(recover_var);
              this.put(" = ");
              this.parse(catch_var);
              this.puts(this._sep)
            };

            this.scope(recovery);
            this.puts("")
          };

          if (recovers.last.children.first) {
            this.puts("} else {");
            this.put("throw ");
            this.parse(catch_var);
            this.puts("")
          };

          this.puts("}");
          this.put("}")
        }
      };

      if ($finally) {
        this.puts(" finally {");
        this.scope($finally);
        this.sput("}")
      };

      if (otherwise) {
        this.put(`${this._sep ?? ""}if ($no_exception) {${this._nl ?? ""}`);
        this.scope(otherwise);
        this.sput("}")
      };

      if (uses_retry) this.sput("}");
      if (hoisted_any) return this.sput("}")
    };

    on_str(value) {
      return this.put(JSON.stringify(value))
    };

    on_int(value) {
      return this.put(this.number_format(value))
    };

    on_float(value) {
      return this.put(this.number_format(value))
    };

    on_octal(value) {
      return this.put("0" + this.number_format(value.toString(8)))
    };

    on_debugger() {
      return this.put("debugger")
    };

    on_typeof(expr) {
      this.put("typeof ");
      return this.parse(expr)
    };

    number_format(number) {
      if (!this.es2021) return (number ?? "").toString();
      let parts = (number ?? "").toString().split(".");
      parts[0] = parts[0].replaceAll(/(\d)(?=(\d\d\d)+(?!\d))/g, "$1_");
      if (parts[1]) parts[1] = parts[1].replaceAll(/(\d\d\d)(?=\d)/g, "$1_");
      return parts.join(".")
    };

    static COMPARISON_OPS = [
      "<",
      "<=",
      ">",
      ">=",
      "==",
      "!=",
      "===",
      "!==",
      "=~",
      "!~"
    ];

    boolean_expression(node) {
      let method;
      if (!node) return false;

      switch (node.type) {
      case "true":
      case "false":
        return true;

      case "send":
        method = node.children[1];
        if (Converter.COMPARISON_OPS.includes(method)) return true;
        if ((method ?? "").toString().endsWith("?")) return true;
        if (method === "!") return true;
        false;
        break;

      case "and":
      case "or":
      case "not":
        return true;

      case "begin":
        return node.children.length === 1 && this.boolean_expression(node.children.first);

      default:
        return false
      }
    };

    on_and(left, right) {
      let op_index, lgroup, rgroup;
      let type = this._ast.type;

      if (this._truthy === "ruby") {
        if (this._boolean_context) {
          this._need_truthy_helpers.push("T");
          op_index = this.operator_index(type);
          lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
          if (left && left.type === "begin") lgroup = true;
          rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
          if (right.type === "begin") rgroup = true;
          let left_inner = left.type === "begin" && left.children.length === 1 ? left.children.first : left;
          let right_inner = right.type === "begin" && right.children.length === 1 ? right.children.first : right;

          if (["and", "or"].includes(left_inner.type)) {
            if (lgroup) this.put("(");
            this.parse(left);
            if (lgroup) this.put(")")
          } else {
            this.put("$T(");
            if (lgroup) this.put("(");
            this.parse(left);
            if (lgroup) this.put(")");
            this.put(")")
          };

          this.put(type === "and" ? " && " : " || ");

          if (["and", "or"].includes(right_inner.type)) {
            if (rgroup) this.put("(");
            this.parse(right);
            if (rgroup) this.put(")")
          } else {
            this.put("$T(");
            if (rgroup) this.put("(");
            this.parse(right);
            if (rgroup) this.put(")");
            this.put(")")
          };

          return
        };

        this._need_truthy_helpers.push("T");

        if (type === "or") {
          this._need_truthy_helpers.push("ror");
          this.put("$ror(");
          this.parse(left);
          this.put(", () => ");
          this.parse(right);
          this.put(")")
        } else {
          this._need_truthy_helpers.push("rand");
          this.put("$rand(");
          this.parse(left);
          this.put(", () => ");
          this.parse(right);
          this.put(")")
        };

        return
      };

      if (this.es2020 && type === "and") {
        let node = this.rewrite(left, right);

        if (node.type === "csend") {
          return this.parse(right.updated(node.type, node.children))
        } else {
          [left, right] = node.children
        }
      };

      op_index = this.operator_index(type);
      lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
      if (left && left.type === "begin") lgroup = true;
      rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
      if (right.type === "begin") rgroup = true;

      if (["lvasgn", "ivasgn", "cvasgn", "gvasgn", "masgn"].includes(right.type)) {
        rgroup = true
      };

      let use_nullish = (() => {
        switch (this._or) {
        case "logical":
          return false;

        case "nullish":
          return !this.boolean_expression(left) && !this.boolean_expression(right);

        default:
          return !this._boolean_context && !this.boolean_expression(left) && !this.boolean_expression(right) && left.type !== "or"
        }
      })();

      if (type === "or" && !use_nullish && left.type === "or") {
        let saved_or = this._or;
        this._or = "logical";
        if (lgroup) this.put("(");
        this.parse(left);
        if (lgroup) this.put(")");
        this._or = saved_or
      } else {
        if (lgroup) this.put("(");
        this.parse(left);
        if (lgroup) this.put(")")
      };

      this.put(type === "and" ? " && " : (() => {
        return use_nullish ? " ?? " : " || "
      })());

      if (rgroup) this.put("(");
      this.parse(right);
      if (rgroup) return this.put(")")
    };

    on_or(left, right) {
      let op_index, lgroup, rgroup;
      let type = this._ast.type;

      if (this._truthy === "ruby") {
        if (this._boolean_context) {
          this._need_truthy_helpers.push("T");
          op_index = this.operator_index(type);
          lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
          if (left && left.type === "begin") lgroup = true;
          rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
          if (right.type === "begin") rgroup = true;
          let left_inner = left.type === "begin" && left.children.length === 1 ? left.children.first : left;
          let right_inner = right.type === "begin" && right.children.length === 1 ? right.children.first : right;

          if (["and", "or"].includes(left_inner.type)) {
            if (lgroup) this.put("(");
            this.parse(left);
            if (lgroup) this.put(")")
          } else {
            this.put("$T(");
            if (lgroup) this.put("(");
            this.parse(left);
            if (lgroup) this.put(")");
            this.put(")")
          };

          this.put(type === "and" ? " && " : " || ");

          if (["and", "or"].includes(right_inner.type)) {
            if (rgroup) this.put("(");
            this.parse(right);
            if (rgroup) this.put(")")
          } else {
            this.put("$T(");
            if (rgroup) this.put("(");
            this.parse(right);
            if (rgroup) this.put(")");
            this.put(")")
          };

          return
        };

        this._need_truthy_helpers.push("T");

        if (type === "or") {
          this._need_truthy_helpers.push("ror");
          this.put("$ror(");
          this.parse(left);
          this.put(", () => ");
          this.parse(right);
          this.put(")")
        } else {
          this._need_truthy_helpers.push("rand");
          this.put("$rand(");
          this.parse(left);
          this.put(", () => ");
          this.parse(right);
          this.put(")")
        };

        return
      };

      if (this.es2020 && type === "and") {
        let node = this.rewrite(left, right);

        if (node.type === "csend") {
          return this.parse(right.updated(node.type, node.children))
        } else {
          [left, right] = node.children
        }
      };

      op_index = this.operator_index(type);
      lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
      if (left && left.type === "begin") lgroup = true;
      rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
      if (right.type === "begin") rgroup = true;

      if (["lvasgn", "ivasgn", "cvasgn", "gvasgn", "masgn"].includes(right.type)) {
        rgroup = true
      };

      let use_nullish = (() => {
        switch (this._or) {
        case "logical":
          return false;

        case "nullish":
          return !this.boolean_expression(left) && !this.boolean_expression(right);

        default:
          return !this._boolean_context && !this.boolean_expression(left) && !this.boolean_expression(right) && left.type !== "or"
        }
      })();

      if (type === "or" && !use_nullish && left.type === "or") {
        let saved_or = this._or;
        this._or = "logical";
        if (lgroup) this.put("(");
        this.parse(left);
        if (lgroup) this.put(")");
        this._or = saved_or
      } else {
        if (lgroup) this.put("(");
        this.parse(left);
        if (lgroup) this.put(")")
      };

      this.put(type === "and" ? " && " : (() => {
        return use_nullish ? " ?? " : " || "
      })());

      if (rgroup) this.put("(");
      this.parse(right);
      if (rgroup) return this.put(")")
    };

    on_nullish(left, right) {
      if (left === null) {
        this.put("null ?? ");
        this.parse(right);
        return
      };

      let lgroup = Converter.LOGICAL.includes(left.type) || (left.type === "begin" && left.children.length > 1);
      let rgroup = right && (Converter.LOGICAL.includes(right.type) || (right.type === "begin" && right.children.length > 1));
      if (lgroup) this.put("(");
      this.parse(left);
      if (lgroup) this.put(")");
      this.put(" ?? ");
      if (rgroup) this.put("(");
      this.parse(right);
      if (rgroup) return this.put(")")
    };

    on_not(expr) {
      let cmp, group;

      if (expr.type === "send" && Converter.INVERT_OP[expr.children[1]]) {
        return this.parse(this.s(
          "send",
          expr.children[0],
          Converter.INVERT_OP[expr.children[1]],
          expr.children[2]
        ))
      } else if (expr.type === "defined?") {
        return this.parse(this.s("undefined?", ...expr.children))
      } else if (expr.type === "or") {
        return this.parse(this.s(
          "and",
          this.s("not", expr.children[0]),
          this.s("not", expr.children[1])
        ))
      } else if (expr.type === "and") {
        return this.parse(this.s(
          "or",
          this.s("not", expr.children[0]),
          this.s("not", expr.children[1])
        ))
      } else if (expr.type === "send" && expr.children[0] === null && expr.children[1] === "typeof" && expr.children[2]?.type === "send" && Converter.INVERT_OP[expr.children[2].children[1]]) {
        cmp = expr.children[2];

        return this.parse(this.s(
          "send",
          this.s("send", null, "typeof", cmp.children[0]),
          Converter.INVERT_OP[cmp.children[1]],
          cmp.children[2]
        ))
      } else {
        group = Converter.LOGICAL.includes(expr.type) && this.operator_index("not") < this.operator_index(expr.type);
        if (expr && ["begin", "in?"].includes(expr.type)) group = true;
        this.put("!");
        if (group) this.put("(");
        this.parse(expr);
        if (group) return this.put(")")
      }
    };

    rewrite(left, right) {
      if (left && left.type === "and") left = this.rewrite(...left.children);

      if (right.type !== "send" || Converter.OPERATORS.flat(Infinity).includes(right.children[1])) {
        return this.s("and", left, right)
      } else if (this.conditionally_equals(left, right.children.first)) {
        return right.updated("csend", [left, ...right.children.slice(1)])
      } else if (left.type !== "in?" && this.conditionally_equals(
        left.children.last,
        right.children.first
      )) {
        return left.updated(
          "and",

          [left.children.first, left.children.last.updated(
            "csend",
            [left.children.last, ...right.children.slice(1)]
          )]
        )
      } else {
        return this.s("and", left, right)
      }
    };

    conditionally_equals(left, right) {
      if (left === right) {
        return true
      } else if (typeof left !== "object" || left === null || !("type" in left) || !left || !right || left.type !== "csend" || right.type !== "send") {
        return false
      } else {
        return this.conditionally_equals(
          left.children.first,
          right.children.first
        ) && this.conditionally_equals(
          left.children.last,
          right.children.last
        )
      }
    };

    on_masgn(lhs, rhs) {
      let before_splat, splat_var, after_splat, splat_name, temp_var, block, actual_rhs, walk, vars, newvars;

      let has_lvasgn = lhs.children.some(c => (
        c.type === "lvasgn" || c.type === "mlhs" || c.type === "splat"
      ));

      let has_non_lvasgn = lhs.children.some(c => (
        ["ivasgn", "cvasgn", "gvasgn", "send"].includes(c.type)
      ));

      let use_destructuring = !(has_lvasgn && has_non_lvasgn);
      let splat_index = lhs.children.findIndex(c => c.type === "splat");
      let has_middle_splat = splat_index && splat_index >= 0 && splat_index < lhs.children.length - 1;

      if (has_middle_splat && use_destructuring) {
        before_splat = lhs.children.slice(0, splat_index);
        splat_var = lhs.children[splat_index].children.first;
        after_splat = lhs.children.slice(splat_index + 1);
        splat_name = splat_var.type === "lvasgn" ? splat_var.children.first : null;
        temp_var = "$masgn_temp";
        block = [];

        for (let $var of before_splat) {
          let var_name = $var.children.first;
          if (!(var_name in this._vars)) this._vars[var_name] = "masgn"
        };

        for (let $var of after_splat) {
          let var_name = $var.children.first;
          if (!(var_name in this._vars)) this._vars[var_name] = "masgn"
        };

        if (splat_name) {
          if (!(splat_name in this._vars)) this._vars[splat_name] = "masgn"
        };

        actual_rhs = rhs.type === "splat" ? rhs.children.first : rhs;

        block.push(this.s(
          "lvasgn",
          temp_var,
          this.s("send!", actual_rhs, "slice")
        ));

        for (let $var of before_splat) {
          let var_name = $var.children.first;

          block.push(this.s(
            "lvasgn",
            var_name,
            this.s("send", this.s("lvar", temp_var), "shift")
          ))
        };

        for (let $var of after_splat.reverse()) {
          let var_name = $var.children.first;

          block.push(this.s(
            "lvasgn",
            var_name,
            this.s("send", this.s("lvar", temp_var), "pop")
          ))
        };

        if (splat_name) {
          block.push(this.s("lvasgn", splat_name, this.s("lvar", temp_var)))
        };

        return this.parse(this.s("begin", ...block), this._state)
      } else if (use_destructuring) {
        walk = (node) => {
          let results = [];

          for (let $var of node.children) {
            if ($var.type === "lvasgn") {
              results.push($var)
            } else if ($var.type === "mlhs" || $var.type === "splat") {
              results += walk($var)
            }
          };

          return results
        };

        vars = walk(lhs);
        newvars = vars.filter($var => !($var.children[0] in this._vars));

        if (newvars.length > 0) {
          if (vars.length === newvars.length) {
            this.put("let ")
          } else {
            this.put(`let ${newvars.map($var => $var.children.last).join(", ") ?? ""}${this._sep ?? ""}`)
          }
        };

        for (let $var of newvars) {
          this._vars[$var.children.last] ??= this._inner ? "pending" : true
        };

        this.put("[");

        lhs.children.forEach((child, index) => {
          if (index !== 0) this.put(", ");
          this.parse(child)
        });

        this.put("] = ");
        return rhs.type === "splat" ? this.parse(rhs.children.first) : this.parse(rhs)
      } else if (rhs.type === "array") {
        if (lhs.children.length === rhs.children.length) {
          block = [];

          for (let $var of lhs.children) {
            if ($var.type === "lvasgn" && !($var.children[0] in this._vars)) {
              this._vars[$var.children[0]] = "masgn"
            }
          };

          lhs.children.zip(
            rhs.children.zip,
            ($var, val) => block << this.s($var.type, ...$var.children, ...val)
          );

          return this.parse(this.s("begin", ...block), this._state)
        } else {
          return (() => { throw new Error("unmatched assignment", this._ast) })()
        }
      } else {
        block = [];

        for (let $var of lhs.children) {
          if ($var.type === "lvasgn" && !($var.children[0] in this._vars)) {
            this._vars[$var.children[0]] = "masgn"
          }
        };

        lhs.children.forEach(($var, i) => (
          block << this.s(
            $var.type,
            ...$var.children,
            this.s("send", rhs, "[]", this.s("int", i))
          )
        ));

        return this.parse(this.s("begin", ...block), this._state)
      }
    };

    on_match_pattern(value, name) {
      if (name.type === "match_var") {
        return this.parse(
          this._ast.updated("lvasgn", [name.children.first, value]),
          this._state
        )
      } else if (name.type === "hash_pattern" && name.children.every(child => (
        child.type === "match_var"
      ))) {
        this.put("let { ");
        this.put(name.children.map(child => (child.children[0] ?? "").toString()).join(", "));
        this.put(" } = ");
        return this.parse(value)
      } else {
        return (() => { throw new Error("complex match patterns are not supported", this._ast) })()
      }
    };

    on_module(name, ...body) {
      let extend = this._namespace.enter(name);

      if (body.length === 1 && body.first === null) {
        if (this._ast.type === "module" && !extend) {
          this.parse(this._ast.updated(
            "casgn",
            [...name.children, this.s("hash")]
          ))
        } else {
          this.parse(this._ast.updated("hash", []))
        };

        this._namespace.leave();
        return
      };

      while (body.length === 1 && body.first?.type === "begin") {
        body = body.first.children
      };

      if (body.length > 0 && body.every(child => (
        ["def", "module"].includes(child.type) || (child.type === "class" && child.children[1] === null)
      ))) {
        if (extend) {
          this.parse(
            this.s(
              "assign",
              name,
              this._ast.updated("class_module", [null, null, ...body])
            ),

            "statement"
          )
        } else if (this._ast.type === "module_hash") {
          this.parse(this._ast.updated("class_module", [null, null, ...body]))
        } else {
          this.parse(this._ast.updated("class_module", [name, null, ...body]))
        };

        this._namespace.leave();
        return
      };

      let symbols = [];
      let visibility = "public";
      let omit = [];
      body = [...body];

      body.forEach((node, i) => {
        if (node.type === "send" && node.children.first === null) {
          if (["public", "private", "protected"].includes(node.children[1])) {
            if (node.children.length === 2) {
              visibility = node.children[1];
              omit.push(node)
            } else if (node.children[1] === "public") {
              omit.push(node);

              for (let sym of node.children.slice(2)) {
                if (sym.type === "sym") symbols.push(sym.children.first)
              }
            }
          }
        };

        if (visibility !== "public") return;

        if (node.type === "casgn" && node.children.first === null) {
          symbols.push(node.children[1])
        } else if (node.type === "def") {
          let method_name = (node.children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          );

          symbols.push(method_name)
        } else if (node.type === "defs" && node.children.first.type === "self") {
          let method_name = (node.children[1] ?? "").toString().replace(
            /[?!]$/m,
            ""
          );

          symbols.push(method_name);

          body[i] = node.updated(
            "def",
            [node.children[1], ...node.children.slice(2)]
          )
        } else if (node.type === "class" && node.children.first.children.first === null) {
          symbols.push(node.children.first.children.last)
        } else if (node.type === "module") {
          symbols.push(node.children.first.children.last)
        }
      });

      body = body.filter(node => !(omit.includes(node))).concat([this.s(
        "return",

        this.s(
          "hash",
          ...symbols.map(sym => this.s("pair", this.s("sym", sym), this.s("lvar", sym)))
        )
      )]);

      body = this.s(
        "send",

        this.s(
          "block",
          this.s("send", null, "proc"),
          this.s("args"),
          this.s("begin", ...body)
        ),

        "[]"
      );

      if (!name || this._ast.type === "module_hash") {
        this.parse(body)
      } else if (extend) {
        this.parse(this.s("assign", name, body))
      } else if (name.children.first === null) {
        this.parse(
          this.s("casgn", null, name.children.last, body),
          "statement"
        )
      } else {
        this.parse(this.s(
          "send",
          name.children.first,
          `${name.children.last ?? ""}=`,
          body
        ))
      };

      return this._namespace.leave()
    };

    on_module_hash(name, ...body) {
      let extend = this._namespace.enter(name);

      if (body.length === 1 && body.first === null) {
        if (this._ast.type === "module" && !extend) {
          this.parse(this._ast.updated(
            "casgn",
            [...name.children, this.s("hash")]
          ))
        } else {
          this.parse(this._ast.updated("hash", []))
        };

        this._namespace.leave();
        return
      };

      while (body.length === 1 && body.first?.type === "begin") {
        body = body.first.children
      };

      if (body.length > 0 && body.every(child => (
        ["def", "module"].includes(child.type) || (child.type === "class" && child.children[1] === null)
      ))) {
        if (extend) {
          this.parse(
            this.s(
              "assign",
              name,
              this._ast.updated("class_module", [null, null, ...body])
            ),

            "statement"
          )
        } else if (this._ast.type === "module_hash") {
          this.parse(this._ast.updated("class_module", [null, null, ...body]))
        } else {
          this.parse(this._ast.updated("class_module", [name, null, ...body]))
        };

        this._namespace.leave();
        return
      };

      let symbols = [];
      let visibility = "public";
      let omit = [];
      body = [...body];

      body.forEach((node, i) => {
        if (node.type === "send" && node.children.first === null) {
          if (["public", "private", "protected"].includes(node.children[1])) {
            if (node.children.length === 2) {
              visibility = node.children[1];
              omit.push(node)
            } else if (node.children[1] === "public") {
              omit.push(node);

              for (let sym of node.children.slice(2)) {
                if (sym.type === "sym") symbols.push(sym.children.first)
              }
            }
          }
        };

        if (visibility !== "public") return;

        if (node.type === "casgn" && node.children.first === null) {
          symbols.push(node.children[1])
        } else if (node.type === "def") {
          let method_name = (node.children.first ?? "").toString().replace(
            /[?!]$/m,
            ""
          );

          symbols.push(method_name)
        } else if (node.type === "defs" && node.children.first.type === "self") {
          let method_name = (node.children[1] ?? "").toString().replace(
            /[?!]$/m,
            ""
          );

          symbols.push(method_name);

          body[i] = node.updated(
            "def",
            [node.children[1], ...node.children.slice(2)]
          )
        } else if (node.type === "class" && node.children.first.children.first === null) {
          symbols.push(node.children.first.children.last)
        } else if (node.type === "module") {
          symbols.push(node.children.first.children.last)
        }
      });

      body = body.filter(node => !(omit.includes(node))).concat([this.s(
        "return",

        this.s(
          "hash",
          ...symbols.map(sym => this.s("pair", this.s("sym", sym), this.s("lvar", sym)))
        )
      )]);

      body = this.s(
        "send",

        this.s(
          "block",
          this.s("send", null, "proc"),
          this.s("args"),
          this.s("begin", ...body)
        ),

        "[]"
      );

      if (!name || this._ast.type === "module_hash") {
        this.parse(body)
      } else if (extend) {
        this.parse(this.s("assign", name, body))
      } else if (name.children.first === null) {
        this.parse(
          this.s("casgn", null, name.children.last, body),
          "statement"
        )
      } else {
        this.parse(this.s(
          "send",
          name.children.first,
          `${name.children.last ?? ""}=`,
          body
        ))
      };

      return this._namespace.leave()
    };

    on_next(n=null) {
      if (this._next_token === "return") {
        this.put("return");

        if (n) {
          this.put(" ");
          return this.parse(n)
        }
      } else {
        if (n) throw new Error(`next argument ${JSON.stringify(n) ?? ""}`, this._ast);
        return this.put((this._next_token ?? "").toString())
      }
    };

    on_nil() {
      return this.put("null")
    };

    on_nth_ref($var) {
      return this.put(`RegExp.$${$var ?? ""}`)
    };

    on_nullish_or(left, right) {
      let op_index = this.operator_index("or");
      let lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
      if (left && left.type === "begin") lgroup = true;
      let rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
      if (right.type === "begin") rgroup = true;
      if (lgroup) this.put("(");
      this.parse(left);
      if (lgroup) this.put(")");
      this.put(" ?? ");
      if (rgroup) this.put("(");
      this.parse(right);
      if (rgroup) return this.put(")")
    };

    on_nullish_asgn(asgn, value) {
      let vtype = null;
      if (asgn.type === "lvasgn") vtype = "lvar";
      if (asgn.type === "ivasgn") vtype = "ivar";
      if (asgn.type === "cvasgn") vtype = "cvar";

      if (this.es2021) {
        return this.parse(this.s("op_asgn", asgn, "??", value))
      } else if (vtype) {
        return this.parse(this.s(
          asgn.type,
          asgn.children.first,
          this.s("nullish_or", this.s(vtype, asgn.children.first), value)
        ))
      } else if (asgn.type === "send" && asgn.children[1] === "[]") {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          "[]=",
          asgn.children[2],
          this.s("nullish_or", asgn, value)
        ))
      } else {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          `${asgn.children[1] ?? ""}=`,
          this.s("nullish_or", asgn, value)
        ))
      }
    };

    on_logical_or(left, right) {
      let op_index = this.operator_index("or");
      let lgroup = Converter.LOGICAL.includes(left.type) && op_index < this.operator_index(left.type);
      if (left && left.type === "begin") lgroup = true;
      let rgroup = Converter.LOGICAL.includes(right.type) && op_index < this.operator_index(right.type);
      if (right.type === "begin") rgroup = true;
      if (lgroup) this.put("(");
      this.parse(left);
      if (lgroup) this.put(")");
      this.put(" || ");
      if (rgroup) this.put("(");
      this.parse(right);
      if (rgroup) return this.put(")")
    };

    on_logical_asgn(asgn, value) {
      let vtype = null;
      if (asgn.type === "lvasgn") vtype = "lvar";
      if (asgn.type === "ivasgn") vtype = "ivar";
      if (asgn.type === "cvasgn") vtype = "cvar";

      if (this.es2021) {
        return this.parse(this.s("op_asgn", asgn, "||", value))
      } else if (vtype) {
        return this.parse(this.s(
          asgn.type,
          asgn.children.first,
          this.s("logical_or", this.s(vtype, asgn.children.first), value)
        ))
      } else if (asgn.type === "send" && asgn.children[1] === "[]") {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          "[]=",
          asgn.children[2],
          this.s("logical_or", asgn, value)
        ))
      } else {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          `${asgn.children[1] ?? ""}=`,
          this.s("logical_or", asgn, value)
        ))
      }
    };

    on_op_asgn($var, op, value) {
      if ($var.type === "ivasgn") $var = this.s("ivar", $var.children.first);
      if ($var.type === "lvasgn") $var = this.s("lvar", $var.children.first);
      if ($var.type === "cvasgn") $var = this.s("cvar", $var.children.first);

      if ($var.type === "lvar") {
        let name = $var.children.first;
        let receiver = this._rbstack.map(rb => rb[name]).compact.last;
        let is_setter = receiver?.type === "setter" || (receiver?.type === "private_method" && receiver.children[1]?.type === "setter");
        if (is_setter) $var = this.s("attr", null, name)
      };

      if (["+", "-"].includes(op) && value.type === "int" && value.children.length === 1 && (value.children[0] === 1 || value.children[0] === -1)) {
        if (value.children.first === -1) op = op === "+" ? "-" : "+";

        if (this._state === "statement") {
          this.parse($var);
          return this.put(`${op ?? ""}${op ?? ""}`)
        } else {
          this.put(`${op ?? ""}${op ?? ""}`);
          return this.parse($var)
        }
      } else {
        this.parse($var);
        this.put(` ${op ?? ""}= `);
        return this.parse(value)
      }
    };

    on_or_asgn(asgn, value) {
      let op;
      let type = this._ast.type === "and_asgn" ? "and" : "or";
      let vtype = null;
      if (asgn.type === "lvasgn") vtype = "lvar";
      if (asgn.type === "ivasgn") vtype = "ivar";
      if (asgn.type === "cvasgn") vtype = "cvar";

      if (this._truthy === "ruby" && vtype) {
        this._need_truthy_helpers.push("T");
        let helper = type === "or" ? "ror" : "rand";
        this._need_truthy_helpers.push(helper);

        this.parse(this.s(asgn.type, asgn.children.first, this.s(
          "send",
          null,
          `$${helper ?? ""}`,
          this.s(vtype, asgn.children.first),

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),
            value
          )
        )));

        return
      };

      if (this.es2021 && this._truthy !== "ruby") {
        op = type === "and" ? "&&" : (() => {
          return this._or === "logical" ? "||" : "??"
        })();

        return this.parse(this.s("op_asgn", asgn, op, value))
      } else if (vtype) {
        return this.parse(this.s(
          asgn.type,
          asgn.children.first,
          this.s(type, this.s(vtype, asgn.children.first), value)
        ))
      } else if (asgn.type === "send" && asgn.children[1] === "[]") {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          "[]=",
          asgn.children[2],
          this.s(type, asgn, value)
        ))
      } else {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          `${asgn.children[1] ?? ""}=`,
          this.s(type, asgn, value)
        ))
      }
    };

    on_and_asgn(asgn, value) {
      let op;
      let type = this._ast.type === "and_asgn" ? "and" : "or";
      let vtype = null;
      if (asgn.type === "lvasgn") vtype = "lvar";
      if (asgn.type === "ivasgn") vtype = "ivar";
      if (asgn.type === "cvasgn") vtype = "cvar";

      if (this._truthy === "ruby" && vtype) {
        this._need_truthy_helpers.push("T");
        let helper = type === "or" ? "ror" : "rand";
        this._need_truthy_helpers.push(helper);

        this.parse(this.s(asgn.type, asgn.children.first, this.s(
          "send",
          null,
          `$${helper ?? ""}`,
          this.s(vtype, asgn.children.first),

          this.s(
            "block",
            this.s("send", null, "lambda"),
            this.s("args"),
            value
          )
        )));

        return
      };

      if (this.es2021 && this._truthy !== "ruby") {
        op = type === "and" ? "&&" : (() => {
          return this._or === "logical" ? "||" : "??"
        })();

        return this.parse(this.s("op_asgn", asgn, op, value))
      } else if (vtype) {
        return this.parse(this.s(
          asgn.type,
          asgn.children.first,
          this.s(type, this.s(vtype, asgn.children.first), value)
        ))
      } else if (asgn.type === "send" && asgn.children[1] === "[]") {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          "[]=",
          asgn.children[2],
          this.s(type, asgn, value)
        ))
      } else {
        return this.parse(this.s(
          "send",
          asgn.children.first,
          `${asgn.children[1] ?? ""}=`,
          this.s(type, asgn, value)
        ))
      }
    };

    on_prototype(expr) {
      {
        let prototype;

        try {
          [this._block_this, this._block_depth] = [false, 0];
          prototype = this._prototype;
          this._prototype = true;
          let mark = this.output_location;
          this.parse(expr);
          if (this._block_this) this.insert(mark, `let self = this${this._sep ?? ""}`)
        } finally {
          this._prototype = prototype;
          [this._block_this, this._block_depth] = [null, null]
        }
      }
    };

    on_redo() {
      if (!this._redoable || this._next_token !== "continue") {
        throw new Error("redo outside of loop", this._ast)
      };

      return this.put(`redo$ = true${this._sep ?? ""}continue`)
    };

    on_regexp(...args) {
      let str;
      let parts = args;
      let opt = parts.pop();
      let extended = false;
      let opts = opt.children;

      if (opts.includes("x")) {
        opts = opts.filter(o => !(o === "x"));
        extended = true
      };

      if (extended) {
        parts.splice(...[0, parts.length].concat(parts.map((part) => {
          let str;

          if (part.type === "str") {
            str = part.children.first;
            str = str.replaceAll(/ #.*/g, "").replaceAll(/\s/g, "");
            return this.s("str", str)
          } else {
            return part
          }
        })))
      };

      if (parts.first.type === "str" && parts.first.children[0].startsWith("^")) {
        if (opts.includes("m") || opts.includes("m")) {
          if (parts.first.children[0].replaceAll(/\\./g, "").replaceAll(
            /\[.*?\]/g,
            ""
          ).includes(".")) {
            if (!opts.includes("s") && !opts.includes("s")) opts = [...opts, "s"]
          }
        } else {
          opts = [...opts, "m"]
        }
      } else if (parts.last.type === "str" && parts.last.children[0].endsWith("$")) {
        if (opts.includes("m") || opts.includes("m")) {
          if (parts.last.children[0].replaceAll(/\\./g, "").replaceAll(
            /\[.*?\]/g,
            ""
          ).includes(".")) {
            if (!opts.includes("s") && !opts.includes("s")) opts = [...opts, "s"]
          }
        } else {
          opts = [...opts, "m"]
        }
      };

      if (parts.first.type === "str" && parts.first.children[0].startsWith("\\A")) {
        parts = [this.s("str", parts.first.children[0].replace("\\A", "^"))].concat(parts.slice(1))
      };

      if (parts.last.type === "str" && parts.last.children[0].endsWith("\\z")) {
        parts = parts.slice(0, -1).concat([this.s(
          "str",
          parts.last.children[0].replace("\\z", "$")
        )])
      };

      if (parts.every(part => part.type === "str")) {
        str = parts.map(part => part.children.first).join("");

        if (str.count("/") - str.count("\\") <= 3) {
          return this.put(`/${str.replaceAll("\\/", "/").replaceAll("/", "\\/") ?? ""}/` + opts.join(""))
        }
      };

      this.put("new RegExp(");

      if (parts.length === 1) {
        this.parse(parts.first)
      } else {
        this.parse(this.s("dstr", ...parts))
      };

      if (opts.length !== 0) this.put(`, ${JSON.stringify(opts.join("")) ?? ""}`);
      return this.put(")")
    };

    on_retry() {
      return this.put("continue")
    };

    on_return(value=null) {
      if (value) {
        this.put("return ");
        return this.parse(value)
      } else {
        return this.put("return")
      }
    };

    static EXPRESSIONS = [
      "array",
      "float",
      "hash",
      "int",
      "lvar",
      "nil",
      "send",
      "send!",
      "attr",
      "str",
      "sym",
      "dstr",
      "dsym",
      "cvar",
      "ivar",
      "zsuper",
      "super",
      "or",
      "and",
      "block",
      "const",
      "true",
      "false",
      "xnode",
      "taglit",
      "self",
      "op_asgn",
      "and_asgn",
      "or_asgn",
      "taglit",
      "gvar",
      "csend",
      "call",
      "typeof"
    ];

    on_autoreturn(...statements) {
      if (statements.length === 1 && statements.first === null) return;
      let block = statements.slice();

      while (block.length === 1 && block.first && block.first.type === "begin") {
        block = block.first.children.slice()
      };

      if (block.length === 0) return;
      if (!block.last) return;

      if (Converter.EXPRESSIONS.includes(block.last.type)) {
        block.push(this._ast.updated("return", [block.pop()]))
      } else if (block.last.type === "if") {
        let node = block.pop();

        if (node.children[1] && node.children[2] && Converter.EXPRESSIONS.includes(node.children[1].type) && Converter.EXPRESSIONS.includes(node.children[2].type)) {
          node = this.s("return", node)
        } else {
          let conditions = [[
            node.children.first,
            node.children[1] ? this.s("autoreturn", node.children[1]) : null
          ]];

          while (node.children[2] && node.children[2].type === "if") {
            node = node.children[2];

            conditions.unshift([
              node.children.first,
              node.children[1] ? this.s("autoreturn", node.children[1]) : null
            ])
          };

          node = node.children[2] ? this.s("autoreturn", node.children[2]) : null;

          for (let [condition, cstatements] of conditions) {
            node = this.s("if", condition, cstatements, node)
          }
        };

        block.push(node)
      } else if (block.last.type === "case") {
        let node = block.pop();
        let children = node.children.slice();

        for (let i = 1; i < children.length; i++) {
          if (children[i] === null) continue;

          if (children[i].type === "when") {
            let gchildren = children[i].children.slice();

            if (gchildren.length !== 0 && Converter.EXPRESSIONS.includes(gchildren.last.type)) {
              gchildren.push(this.s("return", gchildren.pop()));
              children[i] = children[i].updated(null, gchildren)
            }
          } else if (Converter.EXPRESSIONS.includes(children[i].type)) {
            children[i] = children[i].updated("return", [children[i]])
          }
        };

        block.push(node.updated(null, children))
      } else if (block.last.type === "lvasgn") {
        block.push(this.s(
          "return",
          this.s("lvar", block.last.children.first)
        ))
      } else if (block.last.type === "ivasgn") {
        block.push(this.s(
          "return",
          this.s("ivar", block.last.children.first)
        ))
      } else if (block.last.type === "cvasgn") {
        block.push(this.s(
          "return",
          this.s("cvar", block.last.children.first)
        ))
      };

      return block.length === 1 ? this.parse(block.first, this._state) : this.parse(
        this.s("begin", ...block),
        this._state
      )
    };

    on_self() {
      if (this._block_depth && this._block_depth > 1) {
        this._block_this = true;
        return this.put("self")
      } else {
        return this.put("this")
      }
    };

    on_send(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_sendw(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_send_bang(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_await(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_attr(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_call(receiver, method, ...args) {
      let t2, m2, args2, block, target, group_receiver, group_target, range, start_node, end_node, child0, mod, current, operations, setter_name, opts, new_node, method_name;

      if (args.length === 1 && method === "+") {
        let node = this.collapse_strings(this._ast);
        if (node !== this._ast) return this.parse(node)
      };

      if (receiver && receiver.type === "begin" && ["irange", "erange"].includes(receiver.children.first.type)) {
        if (method === "to_a") {
          return this.range_to_array(receiver.children.first)
        } else {
          throw new Error(`${receiver.children.first.type ?? ""} can only be converted to array currently`, receiver.children.first)
        }
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Class" && args.last.type === "def" && args.last.children.first === null) {
        let parent = args.length > 1 ? args.first : null;

        return this.parse(this.s(
          "class2",
          null,
          parent,
          ...args.last.children.slice(2)
        ))
      };

      if (method === "new" && receiver && receiver.children[0] === null && receiver.children[1] === "Proc") {
        return this.parse(args.first, this._state)
      } else if (!receiver && ["lambda", "proc"].includes(method)) {
        if (method === "lambda" && this._state !== "statement") {
          return this.parse(
            this.s(
              args.first.type,
              ...args.first.children.slice(0, -1),
              this.s("autoreturn", args.first.children.at(-1))
            ),

            this._state
          )
        } else {
          return this.parse(args.first, this._state)
        }
      };

      if (["call", "[]"].includes(method) && receiver && receiver.type === "block") {
        let [t2, m2, ...args2] = receiver.children.first.children;

        if (!t2 && ["lambda", "proc"].includes(m2) && args2.length === 0) {
          this.group(receiver);
          this.put("(");
          this.parse_all(...args, {join: ", "});
          this.put(")");
          return
        } else if (!t2 && m2 === "async" && args2.length === 0) {
          this.put("(");
          this.parse(receiver);
          this.put(")()");
          return
        }
      };

      if (method === "await" && receiver === null && args.length === 2 && args[1].type === "def") {
        args = [this.s("block", args.first, ...args.last.children.slice(1))]
      };

      if (receiver === null && args.length === 1) {
        if (method === "async") {
          if (args.first.type === "def") {
            return this.parse(args.first.updated("async"))
          } else if (args.first.type === "defs") {
            return this.parse(args.first.updated("asyncs"))
          } else if (args.first.type === "send" && args.first.children.first.type === "block" && args.first.children.last === "[]") {
            this.put("(async ");
            this.parse(args.first.children.first, "statement");
            this.put(")()");
            return
          } else if (args.first.type === "block") {
            block = args.first;

            if (block.children[0].children.last === "lambda") {
              return this.parse(block.updated(
                "async",
                [null, block.children[1], this.s("autoreturn", block.children[2])]
              ))
            } else if (block.children[0].children.last === "proc") {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            } else if (block.children[0].children[1] === "new" && block.children[0].children[0] === this.s(
              "const",
              null,
              "Proc"
            )) {
              return this.parse(block.updated(
                "async",
                [null, ...block.children.slice(1)]
              ))
            }
          }
        } else if (method === "await") {
          if (args.first.type === "send") {
            return this.parse(args.first.updated("await"))
          } else if (args.first.type === "block") {
            block = args.first;

            return this.parse(block.updated(
              null,
              [block.children[0].updated("await"), ...block.children.slice(1)]
            ))
          }
        }
      };

      let op_index = this.operator_index(method);
      if (op_index !== -1) target = args.first;
      receiver ||= this._rbstack.map(rb => rb[method]).compact.last || null;
      let autobind = null;
      let private_prefix = null;

      if (receiver?.type === "self") {
        let lookup_key = (method ?? "").toString().endsWith("=") ? (method ?? "").toString().slice(
          0,
          -1
        ) : method;

        let rbstack_entry = this._rbstack.map(rb => rb[lookup_key]).compact.last;

        if (rbstack_entry?.type === "private_method") {
          private_prefix = rbstack_entry.children.first
        }
      };

      if (receiver) {
        if (receiver.type === "autobind") {
          autobind = receiver = receiver.children.first;
          if (!this._autobind) autobind = null
        } else if (receiver.type === "setter") {
          receiver = receiver.children.first
        };

        if (receiver.type === "private_method") {
          private_prefix = receiver.children.first;
          receiver = receiver.children[1];

          if (receiver.type === "autobind") {
            autobind = receiver = receiver.children.first;
            if (!this._autobind) autobind = null
          } else if (receiver.type === "setter") {
            receiver = receiver.children.first
          }
        };

        if (receiver) {
          group_receiver = receiver.type === "send" && op_index < this.operator_index(receiver.children[1])
        };

        group_receiver ||= Converter.GROUP_OPERATORS.includes(receiver.type);
        if (receiver.children[1] === "[]") group_receiver = false;

        if (receiver.type === "int" && !Converter.OPERATORS.flat(Infinity).includes(method)) {
          group_receiver = true
        };

        if (!receiver.is_method() && receiver.children.last === "new") {
          group_receiver = true
        }
      };

      if (target) {
        group_target = target.type === "send" && op_index < this.operator_index(target.children[1]);
        group_target ||= Converter.GROUP_OPERATORS.includes(target.type)
      };

      if (this._ast.type === "await") this.put("await ");

      if (method === "!") {
        return this.parse(this.s("not", receiver))
      } else if (method === "[]") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 1 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          return this.put(`.${args.first.children.first ?? ""}`)
        } else if (args.length === 1 && ["irange", "erange"].includes(args.first.type)) {
          range = args.first;
          let [start_node, end_node] = range.children;
          this.put(".slice(");
          this.parse(start_node);

          if (end_node) {
            if (range.type !== "irange" || end_node.type !== "int" || end_node.children.first !== -1) {
              this.put(", ");

              if (range.type === "irange") {
                if (end_node.type === "int") {
                  this.put((end_node.children.first + 1 ?? "").toString())
                } else {
                  this.parse(end_node);
                  this.put(" + 1")
                }
              } else {
                this.parse(end_node)
              }
            }
          };

          return this.put(")")
        } else {
          this.put("[");
          this.parse_all(...args, {join: ", "});
          return this.put("]")
        }
      } else if (method === "[]=") {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (args.length === 2 && ["str", "sym"].includes(args.first.type) && /^[a-zA-Z]\w*$/m.test((args.first.children.first ?? "").toString())) {
          this.put(`.${args.first.children.first ?? ""} = `)
        } else {
          this.put("[");
          this.parse_all(...args.slice(0, -1), {join: ", "});
          this.put("] = ")
        };

        return this.parse(args.at(-1))
      } else if (["-@", "+@", "~", "~"].includes(method)) {
        child0 = receiver.children[0];

        if (receiver.type === "send" && receiver.children[1] === "+@" && this.ast_node(child0) && [
          "class",
          "module"
        ].includes(child0.type)) {
          if (receiver.children[0].type === "class") {
            return this.parse(receiver.children[0].updated("class_extend"))
          } else {
            mod = receiver.children[0];

            return this.parse(this.s(
              "assign",
              mod.children[0],
              mod.updated(null, [null, ...mod.children.slice(1)])
            ))
          }
        } else {
          this.put((method ?? "").toString()[0]);
          return this.parse(receiver)
        }
      } else if (method === "=~") {
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "!~") {
        this.put("!");
        this.parse(args.first);
        this.put(".test(");
        this.parse(receiver);
        return this.put(")")
      } else if (method === "<<") {
        if (this._state === "statement") {
          current = receiver;
          operations = [args.first];

          while (current.type === "send" && current.children[1] === "<<") {
            operations.unshift(current.children[2]);
            current = current.children[0]
          };

          this.parse(current);
          this.put(".push(");

          operations.forEach((arg, index) => {
            if (index > 0) this.put(", ");
            this.parse(arg)
          });

          return this.put(")")
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(" << ");
          return group_target ? this.group(args.first) : this.parse(args.first)
        }
      } else if (method === "<=>") {
        this.parse(receiver);
        this.put(" < ");
        this.parse(args.first);
        this.put(" ? -1 : ");
        this.parse(receiver);
        this.put(" > ");
        this.parse(args.first);
        return this.put(" ? 1 : 0")
      } else if (Converter.OPERATORS.flat(Infinity).includes(method) && !Converter.LOGICAL.includes(method)) {
        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        if (this._comparison === "identity" && ["==", "!="].includes(method)) {
          this.put(` ${method ?? ""}= `)
        } else {
          this.put(` ${method ?? ""} `)
        };

        return group_target ? this.group(target) : this.parse(target)
      } else if (/=$/m.test(method)) {
        if (this._state === "statement") this.multi_assign_declarations;

        if (group_receiver) {
          this.group(receiver)
        } else {
          this.parse(receiver)
        };

        setter_name = (method ?? "").toString().replace(/=$/m, "");

        if (private_prefix) {
          setter_name = `${private_prefix ?? ""}${setter_name ?? ""}`
        };

        this.put(`${receiver ? "." : null ?? ""}${setter_name ?? ""} = `);

        return this.parse(
          args.first,
          this._state === "method" ? "method" : "expression"
        )
      } else if (method === "new") {
        if (receiver) {
          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "Regexp") {
            receiver = this.s("const", null, "RegExp")
          };

          if (receiver.type === "const" && receiver.children[0] === null && receiver.children[1] === "RegExp") {
            if (args.first.type === "regexp") {
              let opts = "";

              if (args.first.children.last.children.length > 0) {
                opts = args.first.children.last.children.join("")
              };

              if (args.length > 1) opts += args.last.children.last;

              return this.parse(this.s(
                "regexp",
                ...args.first.children.slice(0, -1),
                this.s("regopt", ...opts.split("").map(item => item))
              ))
            } else if (args.first.type === "str") {
              if (args.length === 2 && args[1].type === "str") {
                opts = args[1].children[0]
              } else {
                opts = ""
              };

              return this.parse(this.s(
                "regexp",
                args.first,
                this.s("regopt", ...opts.split("").map(c => c))
              ))
            }
          };

          this.put("new ");

          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          if (this._ast.is_method()) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            return this.put(")")
          }
        } else if (args.length === 1 && args.first.type === "send") {
          new_node = args.first.updated("send", [
            this.s("const", ...args.first.children.slice(0, 2)),
            "new",
            ...args.first.children.slice(2)
          ]);

          return this.parse(new_node, this._state)
        } else if (args.length === 1 && args.first.type === "const") {
          return this.parse(this.s("attr", args.first, "new"), this._state)
        } else if (args.length === 2 && ["send", "const"].includes(args.first.type) && args.last.type === "def" && args.last.children.first === null) {
          return this.parse(
            this.s(
              "send",
              this.s("const", null, args.first.children[1]),
              "new",
              ...args.first.children.slice(2),
              args.last
            ),

            this._state
          )
        } else {
          return (() => { throw new Error("use of JavaScript keyword new", this._ast) })()
        }
      } else if (method === "raise" && receiver === null) {
        if (this._state === "expression") this.put("(() => { ");

        if (args.length === 1) {
          this.put("throw ");
          this.parse(args.first)
        } else {
          this.put("throw new ");
          this.parse(args.first);
          this.put("(");
          this.parse(args[1]);
          this.put(")")
        };

        if (this._state === "expression") return this.put(" })()")
      } else if (method === "typeof" && receiver === null) {
        this.put("typeof ");
        return this.parse(args.first)
      } else if (this._ast.children[1] === "is_a?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "kind_of?" && receiver && args.length === 1) {
        this.put("(");
        this.parse(receiver);
        this.put(" instanceof ");
        this.parse(args.first);
        return this.put(")")
      } else if (this._ast.children[1] === "instance_of?" && receiver && args.length === 1) {
        this.put("(");

        this.parse(this.s(
          "send",
          this.s("attr", receiver, "constructor"),
          "==",
          args.first
        ));

        return this.put(")")
      } else {
        if (method === "bind" && receiver?.type === "send") {
          if (receiver.children.length === 2 && receiver.children.first === null) {
            receiver = receiver.updated("attr")
          }
        };

        method_name = private_prefix ? `${private_prefix ?? ""}${method ?? ""}` : method;

        if (!this._ast.is_method() && !["send!", "call"].includes(this._ast.type)) {
          if (receiver) {
            if (group_receiver) {
              this.group(receiver)
            } else {
              this.parse(receiver)
            };

            this.put(`.${method_name ?? ""}`)
          } else if (this._ast.type === "attr") {
            this.put(method_name)
          } else {
            this.parse(this._ast.updated("lvasgn", [method_name]), this._state)
          }
        } else {
          if (group_receiver) {
            this.group(receiver)
          } else {
            this.parse(receiver)
          };

          this.put(`${receiver && method_name ? "." : null ?? ""}${method_name ?? ""}`);

          if (args.length <= 1) {
            this.put("(");
            this.parse_all(...args, {join: ", "});
            this.put(")")
          } else {
            this._compact(() => {
              this.puts("(");
              this.parse_all(...args, {join: `,${this._ws ?? ""}`});
              return this.sput(")")
            })
          }
        };

        if (autobind && !this._ast.is_method() && this._ast.type !== "attr") {
          if (this._state === "statement") {
            return this.put("()")
          } else {
            this.put(".bind(");
            this.parse(autobind);
            return this.put(")")
          }
        }
      }
    };

    on_csend(receiver, method, ...args) {
      if (["is_a?", "kind_of?", "instance_of?"].includes(method) && args.length === 1) {
        this.parse(receiver);
        this.put(" && ");
        this.parse(this._ast.updated("send"));
        return
      };

      if (/\w[!?]$/m.test(method)) method = (method ?? "").toString().slice(0, -1);
      this.parse(receiver);
      this.put("?.");

      if (method === "[]") {
        this.put("[");
        this.parse_all(...args, {join: ", "});
        return this.put("]")
      } else {
        this.put((method ?? "").toString());
        if (this._ast.is_method()) this.put("(");
        this.parse_all(...args, {join: ", "});
        if (this._ast.is_method()) return this.put(")")
      }
    };

    on_ccall(receiver, method, ...args) {
      if (this.es2020) {
        this.parse(receiver);
        this.put("?.(");
        this.parse_all(...args, {join: ", "});
        return this.put(")")
      } else {
        this.parse(receiver);
        this.put(" && ");
        this.parse(receiver);
        this.put("(");
        this.parse_all(...args, {join: ", "});
        return this.put(")")
      }
    };

    on_splat(expr) {
      this.put("...");
      return this.parse(expr)
    };

    collapse_strings(node) {
      let left = node.children[0];
      if (!left) return node;
      let right = node.children[2];

      if (left.type === "send" && left.children.length === 3 && left.children[1] === "+") {
        left = this.collapse_strings(left)
      };

      if (right.type === "send" && right.children.length === 3 && right.children[1] === "+") {
        right = this.collapse_strings(right)
      };

      if (["dstr", "str"].includes(left.type) && ["dstr", "str"].includes(right.type)) {
        if (left.type === "str" && right.type === "str") {
          return left.updated(
            null,
            [left.children.first + right.children.first]
          )
        } else {
          if (left.type === "str") left = this.s("dstr", left);
          if (right.type === "str") right = this.s("dstr", right);
          return left.updated(null, left.children + right.children)
        }
      };

      if (left === node.children[0] && right === node.children[2]) {
        return node
      } else {
        return node.updated(null, [left, "+", right])
      }
    };

    range_to_array(node) {
      let length, start_value, finish_value, index_var, blank;
      let [start, finish] = node.children;

      if (start.type === "int" && start.children.first === 0) {
        if (finish.type === "int") {
          length = finish.children.first + (node.type === "irange" ? 1 : 0)
        } else {
          length = `${finish.children.last ?? ""}` + (node.type === "irange" ? "+1" : "")
        };

        return this.put(`[...Array(${length ?? ""}).keys()]`)
      } else {
        start_value = start.children.compact.first;
        finish_value = finish.children.compact.first;

        if (start.type === "int" && finish.type === "int") {
          length = finish_value - start_value + (node.type === "irange" ? 1 : 0)
        } else {
          length = `(${finish_value ?? ""}-${start_value ?? ""}` + (node.type === "irange" ? "+1" : "") + ")"
        };

        if ("idx" in this._vars || start_value === "idx" || finish_value === "idx") {
          index_var = "i$"
        } else {
          index_var = "idx"
        };

        if ("_" in this._vars || start_value === "_" || finish_value === "_") {
          blank = "_$"
        } else {
          blank = "_"
        };

        return this.put(`Array.from({length: ${length ?? ""}}, (${blank ?? ""}, ${index_var ?? ""}) => ${index_var ?? ""}+${start_value ?? ""})`)
      }
    };

    on_super(...args) {
      let cleaned_args;
      let method = this._instance_method ?? this._class_method;
      if (!this._class_parent) return;
      if (!method) throw new Error("super outside of a method", this._ast);

      if (this._ast.type === "zsuper") {
        if (method.type === "method") {
          args = method.children[2].children[1].children
        } else if (method.type === "prop") {
          args = null
        } else {
          args = method.children[1].children
        }
      };

      let add_args = true;

      if (this._class_method) {
        this.put("super.");
        this.put(method.children[0]);
        add_args = method.is_method()
      } else if (method.children[0] === "constructor") {
        this.put("super")
      } else {
        this.put("super.");
        this.put(method.children[0]);
        add_args = method.is_method()
      };

      if (add_args) {
        this.put("(");

        cleaned_args = args.map(arg => (
          arg.type === "optarg" ? this.s("arg", arg.children[0]) : arg
        ));

        this.parse(this.s("args", ...cleaned_args));
        return this.put(")")
      }
    };

    on_zsuper(...args) {
      let cleaned_args;
      let method = this._instance_method ?? this._class_method;
      if (!this._class_parent) return;
      if (!method) throw new Error("super outside of a method", this._ast);

      if (this._ast.type === "zsuper") {
        if (method.type === "method") {
          args = method.children[2].children[1].children
        } else if (method.type === "prop") {
          args = null
        } else {
          args = method.children[1].children
        }
      };

      let add_args = true;

      if (this._class_method) {
        this.put("super.");
        this.put(method.children[0]);
        add_args = method.is_method()
      } else if (method.children[0] === "constructor") {
        this.put("super")
      } else {
        this.put("super.");
        this.put(method.children[0]);
        add_args = method.is_method()
      };

      if (add_args) {
        this.put("(");

        cleaned_args = args.map(arg => (
          arg.type === "optarg" ? this.s("arg", arg.children[0]) : arg
        ));

        this.parse(this.s("args", ...cleaned_args));
        return this.put(")")
      }
    };

    on_sym(sym) {
      return this.put(JSON.stringify((sym ?? "").toString()))
    };

    on_taglit(tag, ...children) {
      {
        let save_autobind;

        try {
          save_autobind = this._autobind;
          this._autobind = false;
          this.put(tag.children.first);
          this.parse_all(...children, {join: ""})
        } finally {
          this._autobind = save_autobind
        }
      }
    };

    on_undef(...syms) {
      return syms.forEach((sym, index) => {
        if (index !== 0) this.put(this._sep);

        if (sym.type === "sym") {
          this.put(`delete ${sym.children.last ?? ""}`)
        } else {
          this.put("delete ");
          this.parse(sym)
        }
      })
    };

    on_until(condition, block) {
      return this.parse(this.s(
        "while",
        this.s("send", condition, "!"),
        block
      ))
    };

    on_until_post(condition, block) {
      return this.parse(this.s(
        "while_post",
        this.s("send", condition, "!"),
        block
      ))
    };

    on_lvar($var) {
      if ($var === "$!") {
        return this.put("$EXCEPTION")
      } else if (this._ast.type === "lvar") {
        return this.put(this.jsvar($var))
      } else {
        return this.put($var)
      }
    };

    on_gvar($var) {
      if ($var === "$!") {
        return this.put("$EXCEPTION")
      } else if (this._ast.type === "lvar") {
        return this.put(this.jsvar($var))
      } else {
        return this.put($var)
      }
    };

    on_lvasgn(name, value=null) {
      let receiver, is_setter;

      if (this._ast.type === "lvasgn" && value) {
        if (this._vars[name] !== true && this._vars[name] !== "masgn") {
          receiver = this._rbstack.map(rb => rb[name]).compact.last;
          is_setter = receiver?.type === "setter" || (receiver?.type === "private_method" && receiver.children[1]?.type === "setter");

          if (is_setter) {
            let actual_receiver = receiver.type === "private_method" ? receiver.children[1].children.first : receiver.children.first;

            return this.parse(this.s(
              "attr",
              actual_receiver,
              `${name ?? ""}=`,
              value
            ))
          }
        }
      };

      let state = this._state;

      {
        let $var;

        if (value && value.type === "lvasgn" && this._state === "statement") {
          let undecls = [];
          if (!(name in this._vars)) undecls.push(name);
          let child = value;

          while (child && child.type === "lvasgn") {
            if (!(child.children[0] in this._vars)) undecls.push(child.children[0]);
            child = child.children[1]
          };

          if (undecls.length !== 0) {
            this.put("let ");
            this.put(undecls.map(item => (item ?? "").toString()).join(", ") + this._sep);

            for (let $var of undecls) {
              this._vars[$var] = true
            }
          }
        };

        let hoist = false;
        let is_declared = name in this._vars && this._vars[name] !== "masgn";

        if (state === "statement" && !is_declared) {
          if (this._inner && this._scope !== this._inner) {
            hoist = this.hoist(this._scope, this._inner, name)
          };

          if (!hoist) $var = "let "
        };

        if (value) {
          this.put(`${$var ?? ""}${this.jsvar(name) ?? ""} = `);
          this.parse(value)
        } else {
          this.put(`${$var ?? ""}${this.jsvar(name) ?? ""}`)
        };

        if (!hoist) {
          this._vars[name] ??= true
        } else if (state === "statement") {
          this._vars[name] ??= "pending"
        } else {
          this._vars[name] ??= "implicit"
        }
      }
    };

    on_gvasgn(name, value=null) {
      let receiver, is_setter;

      if (this._ast.type === "lvasgn" && value) {
        if (this._vars[name] !== true && this._vars[name] !== "masgn") {
          receiver = this._rbstack.map(rb => rb[name]).compact.last;
          is_setter = receiver?.type === "setter" || (receiver?.type === "private_method" && receiver.children[1]?.type === "setter");

          if (is_setter) {
            let actual_receiver = receiver.type === "private_method" ? receiver.children[1].children.first : receiver.children.first;

            return this.parse(this.s(
              "attr",
              actual_receiver,
              `${name ?? ""}=`,
              value
            ))
          }
        }
      };

      let state = this._state;

      {
        let $var;

        if (value && value.type === "lvasgn" && this._state === "statement") {
          let undecls = [];
          if (!(name in this._vars)) undecls.push(name);
          let child = value;

          while (child && child.type === "lvasgn") {
            if (!(child.children[0] in this._vars)) undecls.push(child.children[0]);
            child = child.children[1]
          };

          if (undecls.length !== 0) {
            this.put("let ");
            this.put(undecls.map(item => (item ?? "").toString()).join(", ") + this._sep);

            for (let $var of undecls) {
              this._vars[$var] = true
            }
          }
        };

        let hoist = false;
        let is_declared = name in this._vars && this._vars[name] !== "masgn";

        if (state === "statement" && !is_declared) {
          if (this._inner && this._scope !== this._inner) {
            hoist = this.hoist(this._scope, this._inner, name)
          };

          if (!hoist) $var = "let "
        };

        if (value) {
          this.put(`${$var ?? ""}${this.jsvar(name) ?? ""} = `);
          this.parse(value)
        } else {
          this.put(`${$var ?? ""}${this.jsvar(name) ?? ""}`)
        };

        if (!hoist) {
          this._vars[name] ??= true
        } else if (state === "statement") {
          this._vars[name] ??= "pending"
        } else {
          this._vars[name] ??= "implicit"
        }
      }
    };

    hoist(outer, inner, name) {
      for (let $var of outer.children) {
        if ($var === inner) continue;
        if ($var === name && ["lvar", "gvar"].includes(outer.type)) return true;
        if (this.ast_node($var) && this.hoist($var, inner, name)) return true
      };

      return false
    };

    get multi_assign_declarations() {
      let undecls = [];
      let child = this._ast;

      while (true) {
        let subchild;

        if (["send", "casgn"].includes(child.type)) {
          subchild = child.children[2]
        } else {
          subchild = child.children[1]
        };

        if (subchild.type === "send") {
          if (!/=$/m.test(subchild.children[1])) break
        } else if (!["send", "cvasgn", "ivasgn", "gvasgn", "lvasgn"].includes(subchild.type)) {
          break
        };

        child = subchild;

        if (child.type === "lvasgn" && !(child.children[0] in this._vars)) {
          undecls.push(child.children[0])
        }
      };

      if (undecls.length !== 0) {
        this.put("let ");
        return this.put(`${undecls.map(item => (item ?? "").toString()).join(", ") ?? ""}${this._sep ?? ""}`)
      }
    };

    on_while(condition, block) {
      {
        let next_token;

        try {
          next_token = this._next_token;
          this._next_token = "continue";

          while (condition.type === "begin" && condition.children.length === 1) {
            condition = condition.children.first
          };

          if (condition.type === "lvasgn") {
            let $var = condition.children[0];

            if (!this._vars[$var]) {
              this.put(`let ${$var ?? ""}${this._sep ?? ""}`);
              this._vars[$var] = true
            }
          };

          this.put("while (");
          this.parse_condition(condition);
          this.puts(") {");
          this.redoable(block);
          this.sput("}")
        } finally {
          this._next_token = next_token
        }
      }
    };

    on_while_post(condition, block) {
      if (block.type === "kwbegin") block = block.updated("begin");

      {
        let next_token;

        try {
          next_token = this._next_token;
          this._next_token = "continue";
          this.puts("do {");
          this.redoable(block);
          this.sput("} while (");
          this.parse_condition(condition);
          this.put(")")
        } finally {
          this._next_token = next_token
        }
      }
    };

    on_xstr(...children) {
      let str, keys, values, func;

      if (this._binding) {
        str = eval(this.capture(() => this.parse_all(...children)));

        if (typeof Function !== 'undefined') {
          keys = Object.keys(this._binding);
          values = keys.map(k => this._binding[k]);
          func = new Function(...keys, `return eval(${JSON.stringify(str) ?? ""})`);
          return this.puts((func.apply(null, values) ?? "").toString())
        } else {
          return this.puts((this._binding.eval(str) ?? "").toString())
        }
      } else {
        return (() => { throw new SecurityError("Insecure operation, eval without binding option") })()
      }
    };

    on_xnode(nodename, ...args) {
      let attrs = {};
      let children = [];

      for (let arg of args) {
        if (arg.type === "hash") {
          for (let pair of arg.children) {
            let name = pair.children[0].children[0];

            if (typeof Ruby2JS.Filter.React !== 'undefined') {
              if (name === "class") name = "className";
              if (name === "for") name = "htmlFor"
            };

            if (["class", "className"].includes(name) && attrs[name]) {
              if (attrs[name].type === "str" && pair.children[1].type === "str") {
                attrs[name] = this.s(
                  "str",
                  pair.children[1].children[0] + " " + attrs[name].children[0]
                )
              } else {
                attrs[name] = this.s(
                  "send",
                  this.s("send", attrs[name], "+", this.s("str", " ")),
                  "+",
                  pair.children[1]
                )
              }
            } else {
              attrs[name] = pair.children[1]
            }
          }
        } else if (arg.type === "begin") {
          children += arg.children
        } else {
          children.push(arg)
        }
      };

      this.put("<");
      this.put(nodename);

      for (let [name, value] of attrs) {
        this.put(" ");
        this.put(name);
        this.put("=");

        if (value.type === "str") {
          this.parse(value)
        } else {
          this.put("{");
          this.parse(value);
          this.put("}")
        }
      };

      if (children.length === 0) {
        return this.put("/>")
      } else {
        this.put(">");

        if (children.length !== 1 || children.first.type === "xnode") {
          this.put(this._nl)
        };

        children.forEach((child, index) => {
          if (index !== 0) this.put(this._nl);

          if (child.type === "str") {
            this.put(child.children.first)
          } else if (child.type === "xnode") {
            this.parse(child)
          } else {
            {
              let jsx;

              try {
                jsx = this._jsx;
                this._jsx = true;
                this.put("{");
                this.parse(child);
                this.put("}")
              } finally {
                this._jsx = jsx
              }
            }
          }
        });

        if (children.length !== 1 || children.first.type === "xnode") {
          this.put(this._nl)
        };

        this.put("</");
        this.put(nodename);
        return this.put(">")
      }
    };

    on_yield(...args) {
      this.put("_implicitBlockYield");
      this.put("(");
      this.parse_all(...args, {join: ", "});
      return this.put(")")
    };
  };

  Converter._handlers = [];
  ;
  ;
  Converter._handlers.push("arg");
  Converter._handlers.push("blockarg");
  Converter._handlers.push("shadowarg");
  Converter._handlers.push("args");
  Converter._handlers.push("mlhs");
  Converter._handlers.push("forward_args");
  Converter._handlers.push("forwarded_args");
  Converter._handlers.push("array");
  Converter._handlers.push("assign");
  Converter._handlers.push("begin");
  Converter._handlers.push("block");
  Converter._handlers.push("numblock");
  Converter._handlers.push("block_pass");
  Converter._handlers.push("true");
  Converter._handlers.push("false");
  Converter._handlers.push("break");
  Converter._handlers.push("case");
  Converter._handlers.push("casgn");
  Converter._handlers.push("class");
  Converter._handlers.push("class_hash");
  Converter._handlers.push("class_extend");
  Converter._handlers.push("class_module");
  Converter._handlers.push("prop");
  Converter._handlers.push("method");
  Converter._handlers.push("constructor");
  Converter._handlers.push("class2");
  Converter._handlers.push("const");
  Converter._handlers.push("cvar");
  Converter._handlers.push("cvasgn");
  Converter._handlers.push("def");
  Converter._handlers.push("defm");
  Converter._handlers.push("async");
  Converter._handlers.push("deff");
  Converter._handlers.push("optarg");
  Converter._handlers.push("restarg");
  Converter._handlers.push("defs");
  Converter._handlers.push("defp");
  Converter._handlers.push("asyncs");
  Converter._handlers.push("defined?");
  Converter._handlers.push("undefined?");
  Converter._handlers.push("dstr");
  Converter._handlers.push("dsym");
  Converter._handlers.push("ensure");
  Converter._handlers.push("__FILE__");
  Converter._handlers.push("__LINE__");
  Converter._handlers.push("for");
  Converter._handlers.push("for_of");
  Converter._handlers.push("hash");
  Converter._handlers.push("hide");
  Converter._handlers.push("if");
  Converter._handlers.push("in?");
  Converter._handlers.push("instanceof");
  Converter._handlers.push("import");
  Converter._handlers.push("export");
  Converter._handlers.push("ivar");
  Converter._handlers.push("js_hostvalue");
  Converter._handlers.push("hostvalue");
  Converter._handlers.push("ivasgn");
  Converter._handlers.push("rescue");
  Converter._handlers.push("kwbegin");
  Converter._handlers.push("str");
  Converter._handlers.push("int");
  Converter._handlers.push("float");
  Converter._handlers.push("octal");
  Converter._handlers.push("debugger");
  Converter._handlers.push("typeof");
  Converter._handlers.push("and");
  Converter._handlers.push("or");
  Converter._handlers.push("nullish");
  Converter._handlers.push("not");
  Converter._handlers.push("masgn");
  Converter._handlers.push("match_pattern");
  Converter._handlers.push("module");
  Converter._handlers.push("module_hash");
  Converter._handlers.push("next");
  Converter._handlers.push("nil");
  Converter._handlers.push("nth_ref");
  Converter._handlers.push("nullish_or");
  Converter._handlers.push("nullish_asgn");
  Converter._handlers.push("logical_or");
  Converter._handlers.push("logical_asgn");
  Converter._handlers.push("op_asgn");
  Converter._handlers.push("or_asgn");
  Converter._handlers.push("and_asgn");
  Converter._handlers.push("prototype");
  Converter._handlers.push("redo");
  Converter._handlers.push("regexp");
  Converter._handlers.push("retry");
  Converter._handlers.push("return");
  Converter._handlers.push("autoreturn");
  Converter._handlers.push("self");
  Converter._handlers.push("send");
  Converter._handlers.push("sendw");
  Converter._handlers.push("send!");
  Converter._handlers.push("await");
  Converter._handlers.push("attr");
  Converter._handlers.push("call");
  Converter._handlers.push("csend");
  Converter._handlers.push("ccall");
  Converter._handlers.push("splat");
  Converter._handlers.push("super");
  Converter._handlers.push("zsuper");
  Converter._handlers.push("sym");
  Converter._handlers.push("taglit");
  Converter._handlers.push("undef");
  Converter._handlers.push("until");
  Converter._handlers.push("until_post");
  Converter._handlers.push("lvar");
  Converter._handlers.push("gvar");
  Converter._handlers.push("lvasgn");
  Converter._handlers.push("gvasgn");
  Converter._handlers.push("while");
  Converter._handlers.push("while_post");
  Converter._handlers.push("xstr");
  Converter._handlers.push("xnode");
  Converter._handlers.push("yield");

  const Filter = (() => {
    const DEFAULTS = [];

    const SEXP = {
      s(type, ...args) {
        return typeof Parser.AST.Node !== 'undefined' ? new Parser.AST.Node(type, args) : new globalThis.Ruby2JS.Node(type, args)
      },

      S(type, ...args) {
        return this._ast.updated(type, args)
      },

      ast_node(obj) {
        return typeof obj === "object" && obj !== null && "type" in obj && typeof obj === "object" && obj !== null && "children" in obj && typeof obj === "object" && obj !== null && "updated" in obj
      }
    };

    class Processor {
      static BINARY_OPERATORS = [
        "+",
        "-",
        "*",
        "/",
        "%",
        "**",
        "&",
        "|",
        "^",
        "<<",
        ">>",
        "==",
        "===",
        "!=",
        "<",
        ">",
        "<=",
        ">=",
        "<=>",
        "=~"
      ];

      get prepend_list() {
        return this._prepend_list
      };

      set prepend_list(prepend_list) {
        this._prepend_list = prepend_list
      };

      get disable_autoimports() {
        return this._disable_autoimports
      };

      set disable_autoimports(disable_autoimports) {
        this._disable_autoimports = disable_autoimports
      };

      get disable_autoexports() {
        return this._disable_autoexports
      };

      set disable_autoexports(disable_autoexports) {
        this._disable_autoexports = disable_autoexports
      };

      get namespace() {
        return this._namespace
      };

      set namespace(namespace) {
        this._namespace = namespace
      };

      constructor(comments) {
        this._comments = comments;
        this._ast = null;
        this._exclude_methods = [];
        this._prepend_list = []
      };

      ast_node(obj) {
        return typeof obj === "object" && obj !== null && "type" in obj && typeof obj === "object" && obj !== null && "children" in obj && typeof obj === "object" && obj !== null && "updated" in obj
      };

      excluded(method) {
        if (this._included) {
          return !this._included.includes(method)
        } else {
          if (this._exclude_methods.flat(Infinity).includes(method)) return true;
          return this._excluded?.includes(method)
        }
      };

      get include_all() {
        this._included = null;
        this._excluded = [];
        return this._excluded
      };

      include_only(...methods) {
        this._included = methods.flat(Infinity);
        return this._included
      };

      include(...methods) {
        return this._included ? this._included += methods.flat(Infinity) : this._excluded -= methods.flat(Infinity)
      };

      exclude(...methods) {
        return this._included ? this._included -= methods.flat(Infinity) : this._excluded += methods.flat(Infinity)
      };

      set options(options) {
        this._options = options;
        this._included = Filter.included_methods;
        this._excluded = Filter.excluded_methods;
        if (options.include_all) this.include_all;
        if (options.include_only) this.include_only(options.include_only);
        if (options.include) this.include(options.include);
        if (options.exclude) this.exclude(options.exclude);
        let filters = options.filters ?? DEFAULTS;
        return this._modules_enabled = typeof Ruby2JS.Filter.ESM !== 'undefined' && filters.includes(Ruby2JS.Filter.ESM) || (typeof Ruby2JS.Filter.CJS !== 'undefined' && filters.includes(Ruby2JS.Filter.CJS))
      };

      modules_enabled() {
        return this._modules_enabled
      };

      get es2015() {
        return this._options.eslevel >= 2_015
      };

      get es2016() {
        return this._options.eslevel >= 2_016
      };

      get es2017() {
        return this._options.eslevel >= 2_017
      };

      get es2018() {
        return this._options.eslevel >= 2_018
      };

      get es2019() {
        return this._options.eslevel >= 2_019
      };

      get es2020() {
        return this._options.eslevel >= 2_020
      };

      get es2021() {
        return this._options.eslevel >= 2_021
      };

      get es2022() {
        return this._options.eslevel >= 2_022
      };

      get es2023() {
        return this._options.eslevel >= 2_023
      };

      get es2024() {
        return this._options.eslevel >= 2_024
      };

      get es2025() {
        return this._options.eslevel >= 2_025
      };

      process(node) {
        {
          let ast;

          try {
            let replacement;
            if (!this.ast_node(node)) return node;
            ast = this._ast;
            this._ast = node;
            let handler = `on_${node.type ?? ""}`;

            if (typeof this === "object" && this !== null && handler in this) {
              replacement = this[handler](node)
            } else {
              replacement = this.process_children(node)
            };

            return replacement
          } finally {
            this._ast = ast
          }
        }
      };

      process_children(node) {
        if (!this.ast_node(node)) return node;

        let new_children = node.children.map(child => (
          this.ast_node(child) ? this.process(child) : child
        ));

        return new_children !== node.children ? node.updated(
          null,
          new_children
        ) : node
      };

      s(type, ...children) {
        return typeof Parser.AST.Node !== 'undefined' ? new Parser.AST.Node(type, children) : new globalThis.Ruby2JS.Node(type, children)
      };

      process_all(nodes) {
        if (nodes === null) return [];
        return nodes.map(node => this.process(node))
      };

      on_assign(node) {
        return this.process_children(node)
      };

      on_async(node) {
        return this.on_def(node)
      };

      on_asyncs(node) {
        return this.on_defs(node)
      };

      on_attr(node) {
        return this.on_send(node)
      };

      on_autoreturn(node) {
        return this.on_return(node)
      };

      on_await(node) {
        return this.on_send(node)
      };

      on_call(node) {
        return this.on_send(node)
      };

      on_class_extend(node) {
        return this.on_send(node)
      };

      on_class_hash(node) {
        return this.on_class(node)
      };

      on_class_module(node) {
        return this.on_send(node)
      };

      on_constructor(node) {
        return this.on_def(node)
      };

      on_deff(node) {
        return this.on_def(node)
      };

      on_defm(node) {
        return this.on_defs(node)
      };

      on_defp(node) {
        return this.on_defs(node)
      };

      on_for_of(node) {
        return this.on_for(node)
      };

      on_in(node) {
        return this.on_send(node)
      };

      on_instanceof(node) {
        return this.on_send(node)
      };

      on_method(node) {
        return this.on_send(node)
      };

      on_module_hash(node) {
        return this.on_module(node)
      };

      on_nullish_or(node) {
        return this.on_or(node)
      };

      on_nullish_asgn(node) {
        return this.on_or_asgn(node)
      };

      on_logical_or(node) {
        return this.on_or(node)
      };

      on_logical_asgn(node) {
        return this.on_or_asgn(node)
      };

      on_prop(node) {
        return this.on_array(node)
      };

      on_prototype(node) {
        return this.on_begin(node)
      };

      on_send(node) {
        return this.on_send(node)
      };

      on_sendw(node) {
        return this.on_send(node)
      };

      on_undefined(node) {
        return this.on_defined(node)
      };

      on_defineProps(node) {
        return this.process_children(node)
      };

      on_hide(node) {
        return this.on_begin(node)
      };

      on_xnode(node) {
        return this.process_children(node)
      };

      on_export(node) {
        return this.process_children(node)
      };

      on_import(node) {
        return this.process_children(node)
      };

      on_taglit(node) {
        return this.on_pair(node)
      };

      on_nil(node) {
        return node
      };

      on_sym(node) {
        return node
      };

      on_int(node) {
        return node
      };

      on_float(node) {
        return node
      };

      on_str(node) {
        return node
      };

      on_true(node) {
        return node
      };

      on_false(node) {
        return node
      };

      on_self(node) {
        return node
      };

      on_numblock(node) {
        let [call, count, block] = node.children;

        return this.process(this.s(
          "block",
          call,

          this.s("args", ...Array.from({length: count}, (_, $i) => {
            let i = $i + 1;
            return this.s("arg", `_${i ?? ""}`)
          })),

          block
        ))
      };

      on_send(node) {
        node = this.process_children(node);

        if (!this.ast_node(node) || !["send", "csend"].includes(node.type)) {
          return node
        };

        if (node.children.length > 2 && this.ast_node(node.children.last) && node.children.last.type === "block_pass") {
          let block_pass = node.children.last;

          if (this.ast_node(block_pass.children.first) && block_pass.children.first.type === "sym") {
            let method = block_pass.children.first.children.first;
            let call_type = node.type === "csend" ? "csend" : "send";

            if (Processor.BINARY_OPERATORS.includes(method)) {
              return on_block(this.s(
                "block",
                this.s(call_type, ...node.children.slice(0, -1)),
                this.s("args", this.s("arg", "a"), this.s("arg", "b")),

                this.s("return", this.process(this.s(
                  "send",
                  this.s("lvar", "a"),
                  method,
                  this.s("lvar", "b")
                )))
              ))
            } else {
              return on_block(this.s(
                "block",
                this.s(call_type, ...node.children.slice(0, -1)),
                this.s("args", this.s("arg", "item")),

                this.s(
                  "return",
                  this.process(this.s("attr", this.s("lvar", "item"), method))
                )
              ))
            }
          }
        };

        return node
      };

      on_csend(node) {
        return this.on_send(node)
      }
    };

    for (let type of [
      "lvar",
      "ivar",
      "cvar",
      "gvar",
      "const",
      "lvasgn",
      "ivasgn",
      "cvasgn",
      "gvasgn",
      "casgn",
      "block",
      "def",
      "defs",
      "class",
      "module",
      "if",
      "case",
      "when",
      "while",
      "until",
      "for",
      "and",
      "or",
      "not",
      "array",
      "hash",
      "pair",
      "splat",
      "kwsplat",
      "args",
      "arg",
      "optarg",
      "restarg",
      "kwarg",
      "kwoptarg",
      "kwrestarg",
      "blockarg",
      "return",
      "break",
      "next",
      "redo",
      "retry",
      "begin",
      "kwbegin",
      "rescue",
      "resbody",
      "ensure",
      "masgn",
      "mlhs",
      "op_asgn",
      "and_asgn",
      "or_asgn",
      "regexp",
      "regopt",
      "dstr",
      "dsym",
      "xstr",
      "yield",
      "super",
      "zsuper",
      "defined?",
      "alias",
      "undef",
      "irange",
      "erange",
      "sclass",
      "match_pattern",
      "match_var"
    ]) {
      if (!(`on_${type ?? ""}` in Processor.prototype)) {
        Processor.prototype[`on_${type ?? ""}`] = function(node) {
          return this.process_children(node)
        }
      }
    };

    return {DEFAULTS, SEXP, Processor}
  })();

  class Pipeline {
    get ast() {
      return this._ast
    };

    get comments() {
      return this._comments
    };

    get options() {
      return this._options
    };

    get namespace() {
      return this._namespace
    };

    set namespace(namespace) {
      this._namespace = namespace
    };

    constructor(ast, comments, { filters=[], options={} } = {}) {
      this._original_ast = ast;
      this._ast = ast;
      this._comments = comments;
      this._filters = filters;
      this._options = options;
      this._namespace = options.namespace ?? new Namespace;
      this._filter_instance = null
    };

    get run() {
      if (this._filters && this._filters.length !== 0) this.apply_filters;
      this.create_converter;
      this.configure_converter;
      this.execute_converter;
      return this._converter
    };

    get apply_filters() {
      let filter_options = {...this._options, filters: this._filters};
      let filters = [...this._filters];

      for (let filter of filters) {
        if (typeof filter === "object" && filter !== null && "reorder" in filter) {
          filters = filter.reorder(filters)
        }
      };

      let filter_class = Filter.Processor;

      for (let mod of filters.reverse()) {
        filter_class = (() => {
          let _class = class _class extends filter_class {
          };
          Object.assign(_class.prototype, mod);
          return _class
        })()
      };

      this._filter_instance = new filter_class(this._comments);
      this._filter_instance.options = filter_options;
      this._filter_instance.namespace = this._namespace;

      if (this._options.disable_autoimports) {
        this._filter_instance.disable_autoimports = true
      };

      if (this._options.disable_autoexports) {
        this._filter_instance.disable_autoexports = true
      };

      this._ast = this._filter_instance.process(this._ast);
      this.reassociate_comments;
      return this.handle_prepend_list
    };

    get reassociate_comments() {
      let raw_comments = this._comments["_raw"];
      if (!raw_comments || !raw_comments.length !== 0) return;

      try {
        let new_comments = typeof Parser !== 'undefined' && typeof Parser.Source.Comment !== 'undefined' ? Parser.Source.Comment.associate(
          this._ast,
          raw_comments
        ) : typeof Ruby2JS !== 'undefined' && typeof Ruby2JS === "object" && Ruby2JS !== null && "associate_comments" in Ruby2JS ? Ruby2JS.associate_comments(
          this._ast,
          raw_comments
        ) : associateComments(this._ast, raw_comments);

        if (new_comments && new_comments.length !== 0) {
          this._comments.clear;
          Object.assign(this._comments, new_comments);
          this._comments["_raw"] = raw_comments
        }
      } catch ($EXCEPTION) {
        if ($EXCEPTION instanceof NoMethodError) {

        } else {
          throw $EXCEPTION
        }
      }
    };

    get handle_prepend_list() {
      if (!this._filter_instance) return;
      if (this._filter_instance.prepend_list.length === 0) return;
      let prepend = this._filter_instance.prepend_list.uniq;

      prepend = prepend.slice().sort((node_a, node_b) => {
        if ((node_a.type === "import" ? 0 : 1) < (node_b.type === "import" ? 0 : 1)) {
          return -1
        } else if ((node_a.type === "import" ? 0 : 1) > (node_b.type === "import" ? 0 : 1)) {
          return 1
        } else {
          return 0
        }
      });

      if (this._filter_instance.disable_autoimports) {
        prepend = prepend.filter(node => !(node.type === "import"))
      };

      if (prepend.length === 0) return;

      this._ast = typeof Parser !== 'undefined' && typeof Parser.AST.Node !== 'undefined' ? new Parser.AST.Node("begin", [
        ...prepend,
        this._ast
      ]) : new globalThis.Ruby2JS.Node("begin", [...prepend, this._ast]);

      return this._comments[this._ast] = []
    };

    get create_converter() {
      this._converter = new Converter(this._ast, this._comments);
      return this._converter
    };

    get configure_converter() {
      this._converter.namespace = this._namespace;
      this._converter.eslevel = this._options.eslevel ?? 2_020;
      this._converter.strict = this._options.strict || false;
      this._converter.comparison = this._options.comparison ?? "equality";
      this._converter.or = this._options.or ?? "auto";
      this._converter.truthy = this._options.truthy ?? "js";
      this._converter.nullish_to_s = this._options.nullish_to_s || false;
      this._converter.module_type = this._options.module ?? "esm";
      this._converter.underscored_private = (parseInt(this._options.eslevel) < 2_022) || this._options.underscored_private;
      this._converter.binding = this._options.binding;
      this._converter.ivars = this._options.ivars;
      if (this._options.width) this._converter.width = this._options.width;

      if (this._options.source?.includes("\n")) {
        return this._converter.enable_vertical_whitespace
      }
    };

    get execute_converter() {
      return this._converter.convert
    }
  };

  ;

  return {
    Namespace,
    Node,
    SimpleLocation,
    FakeSourceBuffer,
    FakeSourceRange,
    XStrLocation,
    SendLocation,
    DefLocation,
    PrismWalker,
    Token,
    Line,
    Serializer,
    Error,
    Converter,
    Filter,
    Pipeline
  }
})();

setupGlobals(Ruby2JS);
await initPrism();

export function convert(source, options={}) {
  let prism_parse = getPrismParse();
  let parse_result = prism_parse(source);

  if (parse_result.errors && parse_result.errors.length > 0) {
    throw parse_result.errors[0].message
  };

  let walker = new Ruby2JS.PrismWalker(source, options.file);
  let ast = walker.visit(parse_result.value);
  let source_buffer = walker.source_buffer;

  let wrapped_comments = (parse_result.comments ?? []).map(c => (
    new PrismComment(c, source, source_buffer)
  ));

  let comments = associateComments(ast, wrapped_comments);
  let pipeline_options = {...options, source};
  let filters = options.filters ?? [];

  let pipeline = new Ruby2JS.Pipeline(ast, comments, {
    filters,
    options: pipeline_options
  });

  let result = pipeline.run;
  return result.to_s
};

export { Ruby2JS }
