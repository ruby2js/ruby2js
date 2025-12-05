// Proof-of-concept: JavaScript port of PrismWalker
// This manually translates a few node types to verify the approach works

// Simple AST node class (equivalent to Ruby2JS::Node)
class Node {
  constructor(type, children = [], properties = {}) {
    this.type = type;
    this.children = Object.freeze(children);
    this.location = properties.location || null;
    // Store is_method flag if provided, otherwise null means "use default behavior"
    this._is_method = properties.is_method !== undefined ? properties.is_method : null;
  }

  // Check if this is a method call (has parentheses)
  // Returns true for method calls foo(), false for property access foo
  // Without location info, defaults to true (like Ruby's Node.is_method?)
  is_is_method() {
    if (this.type === 'attr') return false;
    if (this.type === 'call') return true;
    if (this._is_method !== null) return this._is_method;
    // Without location info, default to true
    return true;
  }

  toString() {
    const childStrs = this.children.map(c => {
      if (c instanceof Node) return c.toString();
      if (c === null) return 'null';
      if (typeof c === 'string') return JSON.stringify(c);
      return String(c);
    });
    return `s(:${this.type}${childStrs.length ? ', ' + childStrs.join(', ') : ''})`;
  }
}

// S-expression helper
function s(type, ...children) {
  return new Node(type, children);
}

// Walker class
class PrismWalker {
  constructor(source) {
    this.source = source;
  }

  visit(node) {
    if (node === null || node === undefined) {
      return null;
    }

    const methodName = `visit${node.constructor.name}`;
    if (this[methodName]) {
      return this[methodName](node);
    }

    console.warn(`No handler for ${node.constructor.name}`);
    return null;
  }

  visitAll(nodes) {
    if (!nodes) return [];
    return Array.from(nodes).map(n => this.visit(n));
  }

  // Program node - entry point
  visitProgramNode(node) {
    return this.visit(node.statements);
  }

  // Statements
  visitStatementsNode(node) {
    const stmts = this.visitAll(node.body);
    if (stmts.length === 0) return null;
    if (stmts.length === 1) return stmts[0];
    return s('begin', ...stmts);
  }

  // Literals
  visitIntegerNode(node) {
    return s('int', node.value);
  }

  visitFloatNode(node) {
    return s('float', node.value);
  }

  visitStringNode(node) {
    return s('str', node.unescaped.value);
  }

  visitSymbolNode(node) {
    return s('sym', node.unescaped.value);
  }

  visitNilNode(node) {
    return s('nil');
  }

  visitTrueNode(node) {
    return s('true');
  }

  visitFalseNode(node) {
    return s('false');
  }

  // Variables
  visitLocalVariableReadNode(node) {
    return s('lvar', node.name);
  }

  visitLocalVariableWriteNode(node) {
    return s('lvasgn', node.name, this.visit(node.value));
  }

  visitInstanceVariableReadNode(node) {
    return s('ivar', node.name);
  }

  visitInstanceVariableWriteNode(node) {
    return s('ivasgn', node.name, this.visit(node.value));
  }

  // Arrays and Hashes
  visitArrayNode(node) {
    return s('array', ...this.visitAll(node.elements));
  }

  visitHashNode(node) {
    return s('hash', ...this.visitAll(node.elements));
  }

  visitAssocNode(node) {
    return s('pair', this.visit(node.key), this.visit(node.value));
  }

  // Method calls
  visitCallNode(node) {
    const receiver = this.visit(node.receiver);
    const method = node.name;
    const args = node.arguments_ ? this.visitAll(node.arguments_.arguments_) : [];

    return s('send', receiver, method, ...args);
  }

  // Method definitions
  visitDefNode(node) {
    const name = node.name;
    const args = node.parameters ? this.visit(node.parameters) : s('args');
    const body = node.body ? this.visit(node.body) : null;

    return s('def', name, args, body);
  }

  visitParametersNode(node) {
    const params = [];

    // Required parameters
    if (node.requireds) {
      for (const p of node.requireds) {
        params.push(s('arg', p.name));
      }
    }

    // Optional parameters
    if (node.optionals) {
      for (const p of node.optionals) {
        params.push(s('optarg', p.name, this.visit(p.value)));
      }
    }

    // Rest parameter
    if (node.rest && node.rest.constructor.name === 'RestParameterNode') {
      params.push(s('restarg', node.rest.name));
    }

    return s('args', ...params);
  }

  // Self
  visitSelfNode(node) {
    return s('self');
  }

  // Arguments (wrapper)
  visitArgumentsNode(node) {
    return this.visitAll(node.arguments);
  }
}

// Simple converter - generates JavaScript from AST
class Converter {
  constructor() {
    this.output = [];
    this.indent = 0;
  }

  convert(ast) {
    this.output = [];
    this.process(ast);
    return this.output.join('');
  }

  put(str) {
    this.output.push(str);
  }

  process(node) {
    if (node === null) return;

    const handler = this[`on_${node.type}`];
    if (handler) {
      handler.call(this, node);
    } else {
      this.put(`/* unhandled: ${node.type} */`);
    }
  }

  on_int(node) {
    this.put(String(node.children[0]));
  }

  on_float(node) {
    this.put(String(node.children[0]));
  }

  on_str(node) {
    this.put(JSON.stringify(node.children[0]));
  }

  on_sym(node) {
    this.put(JSON.stringify(node.children[0]));
  }

  on_nil(node) {
    this.put('null');
  }

  on_true(node) {
    this.put('true');
  }

  on_false(node) {
    this.put('false');
  }

  on_lvar(node) {
    this.put(node.children[0]);
  }

  on_lvasgn(node) {
    const [name, value] = node.children;
    this.put(`let ${name} = `);
    this.process(value);
  }

  on_ivar(node) {
    this.put(`this.${node.children[0].replace('@', '_')}`);
  }

  on_ivasgn(node) {
    const [name, value] = node.children;
    this.put(`this.${name.replace('@', '_')} = `);
    this.process(value);
  }

  on_self(node) {
    this.put('this');
  }

  on_array(node) {
    this.put('[');
    node.children.forEach((child, i) => {
      if (i > 0) this.put(', ');
      this.process(child);
    });
    this.put(']');
  }

  on_hash(node) {
    this.put('{');
    node.children.forEach((pair, i) => {
      if (i > 0) this.put(', ');
      this.process(pair);
    });
    this.put('}');
  }

  on_pair(node) {
    const [key, value] = node.children;
    // Use unquoted key if symbol
    if (key.type === 'sym') {
      this.put(key.children[0]);
    } else {
      this.process(key);
    }
    this.put(': ');
    this.process(value);
  }

  on_send(node) {
    const [receiver, method, ...args] = node.children;

    // Special cases
    if (method === 'puts' && receiver === null) {
      this.put('console.log(');
      args.forEach((arg, i) => {
        if (i > 0) this.put(', ');
        this.process(arg);
      });
      this.put(')');
      return;
    }

    // Regular method call
    if (receiver) {
      this.process(receiver);
      this.put('.');
    }
    this.put(method);
    if (args.length > 0 || receiver) {
      this.put('(');
      args.forEach((arg, i) => {
        if (i > 0) this.put(', ');
        this.process(arg);
      });
      this.put(')');
    }
  }

  on_def(node) {
    const [name, args, body] = node.children;
    this.put(`function ${name}(`);
    if (args && args.children) {
      args.children.forEach((arg, i) => {
        if (i > 0) this.put(', ');
        this.put(arg.children[0]); // arg name
      });
    }
    this.put(') {\n');
    if (body) {
      this.put('  return ');
      this.process(body);
      this.put(';\n');
    }
    this.put('}');
  }

  on_begin(node) {
    node.children.forEach((child, i) => {
      if (i > 0) this.put(';\n');
      this.process(child);
    });
  }

  on_args(node) {
    // handled by on_def
  }

  on_arg(node) {
    // handled by on_def
  }
}

// Test it
import { loadPrism } from "@ruby/prism";

const parse = await loadPrism();

const tests = [
  ['42', '42'],
  ['"hello"', '"hello"'],
  ['nil', 'null'],
  ['true', 'true'],
  ['[1, 2, 3]', '[1, 2, 3]'],
  ['{a: 1, b: 2}', '{a: 1, b: 2}'],
  ['foo = 1', 'let foo = 1'],
  ['@foo = 1', 'this._foo = 1'],
  ['puts "hello"', 'console.log("hello")'],
  ['foo.bar(1, 2)', 'foo.bar(1, 2)'],
  ['def greet(name); puts name; end', 'function greet(name) {\n  return console.log(name);\n}'],
];

console.log('Ruby2JS Self-Hosting Proof of Concept\n');
console.log('='.repeat(60));

let passed = 0;
let failed = 0;

for (const [ruby, expected] of tests) {
  const result = parse(ruby);
  const walker = new PrismWalker(ruby);
  const ast = walker.visit(result.value);
  const converter = new Converter();
  const js = converter.convert(ast);

  const ok = js === expected;
  if (ok) passed++; else failed++;

  console.log(`\nRuby:     ${ruby}`);
  console.log(`Expected: ${expected}`);
  console.log(`Got:      ${js}`);
  console.log(`Status:   ${ok ? '✓ PASS' : '✗ FAIL'}`);
}

console.log('\n' + '='.repeat(60));
console.log(`Results: ${passed} passed, ${failed} failed`);

// Export for use as module
export { Node, s, PrismWalker, Converter };
