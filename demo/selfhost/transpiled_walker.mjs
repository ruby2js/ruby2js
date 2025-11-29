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

  visitUnlessNode(node) {
    // Parser gem represents unless as: if(condition, else_body, then_body)
    // Note: JS Prism uses camelCase: elseClause
    return this.s(
      "if",
      this.visit(node.predicate),
      this.visit(node.elseClause),
      this.visit(node.statements)
    )
  };

  visitElseNode(node) {
    return this.visit(node.statements)
  };

  visitWhileNode(node) {
    return this.s(
      "while",
      this.visit(node.predicate),
      this.visit(node.statements)
    )
  };

  visitUntilNode(node) {
    return this.s(
      "until",
      this.visit(node.predicate),
      this.visit(node.statements)
    )
  };

  visitCaseNode(node) {
    // Note: JS Prism uses camelCase: elseClause
    return this.s(
      "case",
      this.visit(node.predicate),
      ...this.visit_all(node.conditions),
      this.visit(node.elseClause)
    )
  };

  visitWhenNode(node) {
    return this.s(
      "when",
      ...this.visit_all(node.conditions),
      this.visit(node.statements)
    )
  };

  visitForNode(node) {
    return this.s(
      "for",
      this.visit(node.index),
      this.visit(node.collection),
      this.visit(node.statements)
    )
  };

  visitReturnNode(node) {
    let args;

    if (node.arguments_) {
      args = this.visit_all(node.arguments_.arguments_);

      return args.length == 1 ? this.s("return", args[0]) : this.s(
        "return",
        this.s("array", ...args)
      )
    } else {
      return this.s("return")
    }
  };

  visitBreakNode(node) {
    let args;

    if (node.arguments_) {
      args = this.visit_all(node.arguments_.arguments_);
      return this.s("break", ...args)
    } else {
      return this.s("break")
    }
  };

  visitNextNode(node) {
    let args;

    if (node.arguments_) {
      args = this.visit_all(node.arguments_.arguments_);
      return this.s("next", ...args)
    } else {
      return this.s("next")
    }
  };

  // === Operators ===
  visitAndNode(node) {
    return this.s("and", this.visit(node.left), this.visit(node.right))
  };

  visitOrNode(node) {
    return this.s("or", this.visit(node.left), this.visit(node.right))
  };

  visitRangeNode(node) {
    // JS Prism: detect exclusive range by operator length (... = 3, .. = 2)
    let is_exclusive = node.operatorLoc.length == 3;
    let type = is_exclusive ? "erange" : "irange";
    return this.s(type, this.visit(node.left), this.visit(node.right))
  };

  // === Strings ===
  visitInterpolatedStringNode(node) {
    let parts = node.parts.map(part => (
      part.constructor.name == "StringNode" ? this.s(
        "str",
        part.unescaped.value
      ) : this.visit(part)
    ));

    return this.s("dstr", ...parts)
  };

  visitEmbeddedStatementsNode(node) {
    let body;

    if (node.statements == null) {
      return this.s("begin")
    } else {
      body = node.statements.body;

      return body.length == 1 ? this.visit(body[0]) : this.s(
        "begin",
        ...this.visit_all(body)
      )
    }
  };

  // === Other ===
  visitParenthesesNode(node) {
    // Just visit the body - parentheses are for grouping
    return this.visit(node.body)
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
    // Binary operators that map directly
    this._binaryOps = {
      '+': '+', '-': '-', '*': '*', '/': '/', '%': '%',
      '==': '===', '!=': '!==', '<': '<', '>': '>', '<=': '<=', '>=': '>=',
      '<<': '<<', '>>': '>>', '&': '&', '|': '|', '^': '^',
      '**': '**'
    };

    // Unary operators
    this._unaryOps = {
      '!': '!', '-@': '-', '+@': '+', '~': '~'
    };

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
      'restarg': node => '...' + node.children[0].toString(),

      // Logical operators
      'and': node => '(' + this.convert(node.children[0]) + ' && ' + this.convert(node.children[1]) + ')',
      'or': node => '(' + this.convert(node.children[0]) + ' || ' + this.convert(node.children[1]) + ')',

      // Control flow
      'while': node => this.convertWhile(node),
      'until': node => this.convertUntil(node),
      'for': node => this.convertFor(node),
      'case': node => this.convertCase(node),
      'when': node => this.convertWhen(node),
      'return': node => node.children.length > 0 ? 'return ' + this.convert(node.children[0]) : 'return',
      'break': () => 'break',
      'next': () => 'continue',

      // Ranges
      'irange': node => this.convertRange(node, true),
      'erange': node => this.convertRange(node, false),

      // String interpolation
      'dstr': node => this.convertDstr(node)
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
    const method = methodName.toString();

    // Handle binary operators
    if (this._binaryOps[method] && args.length === 1) {
      return '(' + this.convert(receiver) + ' ' + this._binaryOps[method] + ' ' + this.convert(args[0]) + ')';
    }

    // Handle unary operators
    if (this._unaryOps[method] && args.length === 0 && receiver) {
      return this._unaryOps[method] + this.convert(receiver);
    }

    // Handle puts → console.log
    if (receiver == null && method === 'puts') {
      return 'console.log(' + argsStr + ')';
    }

    // Handle p → console.log (for debugging)
    if (receiver == null && method === 'p') {
      return 'console.log(' + argsStr + ')';
    }

    // Handle array/hash access: a[0]
    if (method === '[]') {
      return this.convert(receiver) + '[' + argsStr + ']';
    }

    // Handle array/hash assignment: a[0] = x
    if (method === '[]=') {
      const [index, value] = args;
      return this.convert(receiver) + '[' + this.convert(index) + '] = ' + this.convert(value);
    }

    if (receiver == null) {
      return method + '(' + argsStr + ')';
    } else {
      return this.convert(receiver) + '.' + method + '(' + argsStr + ')';
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

  convertWhile(node) {
    const [cond, body] = node.children;
    return 'while (' + this.convert(cond) + ') {\\n  ' + (body ? this.convert(body) : '') + '\\n}';
  }

  convertUntil(node) {
    const [cond, body] = node.children;
    return 'while (!(' + this.convert(cond) + ')) {\\n  ' + (body ? this.convert(body) : '') + '\\n}';
  }

  convertFor(node) {
    const [variable, collection, body] = node.children;
    const varName = this.convert(variable);
    return 'for (let ' + varName + ' of ' + this.convert(collection) + ') {\\n  ' + (body ? this.convert(body) : '') + '\\n}';
  }

  convertCase(node) {
    const [predicate, ...rest] = node.children;
    const elseBody = rest.pop(); // last child is else clause
    const whens = rest;

    let result = 'switch (' + this.convert(predicate) + ') {\\n';
    for (const when of whens) {
      result += this.convert(when);
    }
    if (elseBody) {
      result += '  default:\\n    ' + this.convert(elseBody) + ';\\n    break;\\n';
    }
    result += '}';
    return result;
  }

  convertWhen(node) {
    const conditions = node.children.slice(0, -1);
    const body = node.children[node.children.length - 1];
    let result = '';
    for (const cond of conditions) {
      result += '  case ' + this.convert(cond) + ':\\n';
    }
    result += '    ' + (body ? this.convert(body) : '') + ';\\n    break;\\n';
    return result;
  }

  convertRange(node, inclusive) {
    const [left, right] = node.children;
    // For now, generate a simple array comprehension-like helper
    // In real implementation, this would use a range helper function
    const start = this.convert(left);
    const end = this.convert(right);
    if (inclusive) {
      return 'Array.from({length: ' + end + ' - ' + start + ' + 1}, (_, i) => ' + start + ' + i)';
    } else {
      return 'Array.from({length: ' + end + ' - ' + start + '}, (_, i) => ' + start + ' + i)';
    }
  }

  convertDstr(node) {
    // Convert interpolated string to template literal
    const parts = node.children.map(child => {
      if (child.type === 'str') {
        // Escape backticks and ${} in literal parts
        return child.children[0].replace(/`/g, '\\\\`').replace(/\\$/g, '\\\\$');
      } else {
        // Interpolated expression
        return '${' + this.convert(child) + '}';
      }
    });
    return '`' + parts.join('') + '`';
  }
}


// Array.compact polyfill
Array.prototype.compact = function() {
  return this.filter(x => x != null);
};

export { Node, s, PrismWalker, Converter };
