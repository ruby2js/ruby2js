// Auto-generated from Ruby PrismWalker
// Filter order: return, selfhost, functions
// Converter written directly in JS

// Node class for AST representation
class Node {
  constructor(type, children, options = {}) {
    this.type = type;
    this.children = children;
    this.location = options.location;
  }
}

// Helper to create nodes
function s(type, ...children) {
  return new Node(type, children);
}

class PrismWalker {
  visit(node) {
    if (!node) return null;
    let method = this[`visit${node.constructor.name}`];
    return method ? method.call(this, node) : null
  };

  constructor(source, file=null) {
    this._source = source;
    this._file = file;

  };

  s(type, ...children) {
    return new Node(type, children)
  };

  visit_all(nodes) {
    if (nodes == null) return [];
    return nodes.map(n => this.visit(n)).filter(x => x != null)
  };

  // === Literals ===
  visitIntegerNode(node) {
    return this.s("int", node.value)
  };

  visitFloatNode(node) {
    return this.s("float", node.value)
  };

  visitNilNode(node) {
    return this.s("nil")
  };

  visitTrueNode(node) {
    return this.s("true")
  };

  visitFalseNode(node) {
    return this.s("false")
  };

  // Note: In JS Prism, unescaped returns {encoding, validEncoding, value}
  // We access .value to get the actual string
  visitStringNode(node) {
    return this.s("str", node.unescaped.value)
  };

  visitSymbolNode(node) {
    return this.s("sym", node.unescaped.value)
  };

  visitSelfNode(node) {
    return this.s("self")
  };

  // === Variables ===
  visitLocalVariableReadNode(node) {
    return this.s("lvar", node.name)
  };

  visitLocalVariableWriteNode(node) {
    return this.s("lvasgn", node.name, this.visit(node.value))
  };

  visitInstanceVariableReadNode(node) {
    return this.s("ivar", node.name)
  };

  visitInstanceVariableWriteNode(node) {
    return this.s("ivasgn", node.name, this.visit(node.value))
  };

  // === Collections ===
  visitArrayNode(node) {
    return this.s("array", ...this.visit_all(node.elements))
  };

  visitHashNode(node) {
    return this.s("hash", ...this.visit_all(node.elements))
  };

  visitAssocNode(node) {
    return this.s("pair", this.visit(node.key), this.visit(node.value))
  };

  // === Calls ===
  // Note: In JS Prism, arguments is accessed via arguments_ (underscore)
  // and the actual args array is arguments_.arguments_
  visitCallNode(node) {
    let receiver = this.visit(node.receiver);
    let args = node.arguments_ ? this.visit_all(node.arguments_.arguments_) : [];
    return this.s("send", receiver, node.name, ...args)
  };

  // === Definitions ===
  visitDefNode(node) {
    let args = this.visit(node.parameters) || this.s("args");
    let body = this.visit(node.body);
    return this.s("def", node.name, args, body)
  };

  visitParametersNode(node) {
    let params = [];

    for (let p of node.requireds) {
      params.push(this.visit(p))
    };

    for (let p of node.optionals) {
      params.push(this.visit(p))
    };

    if (node.rest) params.push(this.visit(node.rest));
    return this.s("args", ...params)
  };

  visitRequiredParameterNode(node) {
    return this.s("arg", node.name)
  };

  visitOptionalParameterNode(node) {
    return this.s("optarg", node.name, this.visit(node.value))
  };

  visitRestParameterNode(node) {
    return this.s("restarg", node.name)
  };

  // === Control Flow ===
  visitIfNode(node) {
    return this.s(
      "if",
      this.visit(node.predicate),
      this.visit(node.statements),
      this.visit(node.subsequent)
    )
  };

  visitStatementsNode(node) {
    let children = this.visit_all(node.body);

    return children.length == 1 ? children[0] : this.s(
      "begin",
      ...children
    )
  };

  visitProgramNode(node) {
    return this.visit(node.statements)
  }
}

class Converter {
  constructor() {
    this._handlers = {
      'int': node => node.children[0].toString(),
      'float': node => node.children[0].toString(),
      'str': node => JSON.stringify(node.children[0]),
      'sym': node => JSON.stringify(node.children[0]),
      'nil': () => 'null',
      'true': () => 'true',
      'false': () => 'false',
      'self': () => 'this',
      'lvar': node => node.children[0].toString(),
      'ivar': node => 'this._' + node.children[0].toString().replace(/^@/, ''),
      'lvasgn': node => 'let ' + node.children[0].toString() + ' = ' + this.convert(node.children[1]),
      'ivasgn': node => 'this._' + node.children[0].toString().replace(/^@/, '') + ' = ' + this.convert(node.children[1]),
      'array': node => '[' + node.children.map(c => this.convert(c)).join(', ') + ']',
      'hash': node => '{' + node.children.map(c => this.convert(c)).join(', ') + '}',
      'pair': node => this.convert(node.children[0]) + ': ' + this.convert(node.children[1]),
      'send': node => this.convertSend(node),
      'def': node => this.convertDef(node),
      'begin': node => node.children.map(c => this.convert(c)).join(';\\n'),
      'if': node => this.convertIf(node),
      'args': node => node.children.map(c => this.convert(c)).join(', '),
      'arg': node => node.children[0].toString(),
      'optarg': node => node.children[0].toString() + '=' + this.convert(node.children[1]),
      'restarg': node => '...' + node.children[0].toString()
    };
  }

  convert(node) {
    if (node == null) return 'null';
    const handler = this._handlers[node.type];
    if (handler) return handler(node);
    return '/* unknown: ' + node.type + ' */';
  }

  convertSend(node) {
    const [receiver, methodName, ...args] = node.children;
    const argsStr = args.map(a => this.convert(a)).join(', ');

    // Handle puts → console.log
    if (receiver == null && methodName === 'puts') {
      return 'console.log(' + argsStr + ')';
    }

    if (receiver == null) {
      return methodName.toString() + '(' + argsStr + ')';
    } else {
      return this.convert(receiver) + '.' + methodName.toString() + '(' + argsStr + ')';
    }
  }

  convertDef(node) {
    const [name, args, body] = node.children;
    const argsStr = this.convert(args);
    const bodyStr = body ? this.convert(body) : '';
    return 'function ' + name.toString() + '(' + argsStr + ') {\\n  return ' + bodyStr + ';\\n}';
  }

  convertIf(node) {
    const [cond, thenBody, elseBody] = node.children;
    let result = 'if (' + this.convert(cond) + ') {\\n  ' + (thenBody ? this.convert(thenBody) : '') + '\\n}';
    if (elseBody) {
      result += ' else {\\n  ' + this.convert(elseBody) + '\\n}';
    }
    return result;
  }
}


// Array.compact polyfill
Array.prototype.compact = function() {
  return this.filter(x => x != null);
};

export { Node, s, PrismWalker, Converter };
