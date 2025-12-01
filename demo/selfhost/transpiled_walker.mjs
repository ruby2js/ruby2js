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
  // Blocks are attached to CallNode via .block property
  visitCallNode(node) {
    let block_params, block_body;
    let receiver = this.visit(node.receiver);
    let args = node.arguments_ ? this.visit_all(node.arguments_.arguments_) : [];
    let call = this.s("send", receiver, node.name, ...args);

    // Check for attached block
    if (node.block) {
      block_params = this.visit(node.block.parameters) || this.s("args");
      block_body = this.visit(node.block.body);
      return this.s("block", call, block_params, block_body)
    } else {
      return call
    }
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

  // === Classes and Modules ===
  visitClassNode(node) {
    // JS Prism uses camelCase: constantPath, superclass
    let name = this.visit(node.constantPath);
    let superclass = this.visit(node.superclass);
    let body = this.visit(node.body);
    return this.s("class", name, superclass, body)
  };

  visitModuleNode(node) {
    let name = this.visit(node.constantPath);
    let body = this.visit(node.body);
    return this.s("module", name, body)
  };

  visitSingletonClassNode(node) {
    // class << self; ... end
    let expr = this.visit(node.expression);
    let body = this.visit(node.body);
    return this.s("sclass", expr, body)
  };

  // Constants
  visitConstantReadNode(node) {
    return this.s("const", null, node.name)
  };

  visitConstantPathNode(node) {
    // Foo::Bar
    let parent = this.visit(node.parent);
    return this.s("const", parent, node.name)
  };

  visitConstantWriteNode(node) {
    return this.s("casgn", null, node.name, this.visit(node.value))
  };

  visitConstantPathWriteNode(node) {
    let target = this.visit(node.target);

    return this.s(
      "casgn",
      target.children[0],
      target.children[1],
      this.visit(node.value)
    )
  };

  // === Blocks ===
  visitBlockNode(node) {
    let call = this.visit(node.call);
    let params = this.visit(node.parameters) || this.s("args");
    let body = this.visit(node.body);
    return this.s("block", call, params, body)
  };

  visitBlockParametersNode(node) {
    let params = [];

    if (node.parameters) {
      for (let p of node.parameters.requireds) {
        params.push(this.visit(p))
      };

      for (let p of node.parameters.optionals) {
        params.push(this.visit(p))
      };

      if (node.parameters.rest) params.push(this.visit(node.parameters.rest))
    };

    return this.s("args", ...params)
  };

  visitLambdaNode(node) {
    let params = this.visit(node.parameters) || this.s("args");
    let body = this.visit(node.body);
    return this.s("block", this.s("send", null, "lambda"), params, body)
  };

  // === Other ===
  visitParenthesesNode(node) {
    // Just visit the body - parentheses are for grouping
    return this.visit(node.body)
  };

  visitSplatNode(node) {
    return this.s("splat", this.visit(node.expression))
  };

  visitKeywordHashNode(node) {
    // Used in method arguments: foo(a: 1, b: 2)
    return this.s("hash", ...this.visit_all(node.elements))
  };

  visitAssocSplatNode(node) {
    // **hash
    return this.s("kwsplat", this.visit(node.value))
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
  };

  // === Exception Handling ===
  visitBeginNode(node) {
    // begin; ...; rescue; ...; ensure; ...; end
    // JS Prism uses camelCase: rescueClause, ensureClause
    let body = this.visit(node.statements);
    let rescue_node = this.visit(node.rescueClause);
    let ensure_node = node.ensureClause ? this.visit(node.ensureClause.statements) : null;

    if (rescue_node) {
      return ensure_node ? this.s(
        "ensure",
        this.s("rescue", body, rescue_node, null),
        ensure_node
      ) : this.s("rescue", body, rescue_node, null)
    } else if (ensure_node) {
      return this.s("ensure", body, ensure_node)
    } else {
      return body
    }
  };

  visitRescueNode(node) {
    // rescue ExceptionClass => var; ...; end
    // JS Prism: reference is the exception variable
    let exceptions = this.visit_all(node.exceptions);
    let exc_var = node.reference ? this.visit(node.reference) : null;
    let body = this.visit(node.statements);
    let subsequent = node.subsequent ? this.visit(node.subsequent) : null;

    // Build the resbody node
    let exc_array = exceptions.length == 0 ? null : this.s(
      "array",
      ...exceptions
    );

    let resbody = this.s("resbody", exc_array, exc_var, body);
    return subsequent ? this.s("begin", resbody, subsequent) : resbody
  };

  // Chain multiple rescue clauses
  visitLocalVariableTargetNode(node) {
    return this.s("lvasgn", node.name)
  };

  // === Regular Expressions ===
  visitRegularExpressionNode(node) {
    // Note: JS Prism uses unescaped.value for the pattern
    // Implicit regex match: if /pattern/
    let pattern = node.unescaped.value;
    let flags = node.flags || 0;

    // Convert Prism flags to string
    let flag_str = "";

    return this.s(
      "regexp",
      this.s("str", pattern),
      this.s("regopt", flag_str)
    )
  };

  visitInterpolatedRegularExpressionNode(node) {
    let parts = node.parts.map(part => (
      part.constructor.name == "StringNode" ? this.s(
        "str",
        part.unescaped.value
      ) : this.visit(part)
    ));

    return this.s("regexp", ...parts, this.s("regopt"))
  };

  visitMatchLastLineNode(node) {
    let pattern = node.unescaped.value;

    return this.s(
      "match_current_line",
      this.s("regexp", this.s("str", pattern), this.s("regopt"))
    )
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
      'begin': node => node.children.map(c => this.convert(c)).join(';\n'),
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
      'dstr': node => this.convertDstr(node),

      // Classes and modules
      'class': node => this.convertClass(node),
      'module': node => this.convertModule(node),
      'sclass': node => this.convertSclass(node),
      'const': node => this.convertConst(node),
      'casgn': node => this.convertCasgn(node),

      // Blocks
      'block': node => this.convertBlock(node),
      'splat': node => '...' + this.convert(node.children[0]),
      'kwsplat': node => '...' + this.convert(node.children[0]),

      // Exception handling
      'rescue': node => this.convertRescue(node),
      'resbody': node => this.convertResbody(node),
      'ensure': node => this.convertEnsure(node),

      // Regular expressions
      'regexp': node => this.convertRegexp(node),
      'regopt': node => ''
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

    // === Ruby method → JavaScript method mappings ===

    // Array methods
    if (method === 'length' || method === 'size' || method === 'count') {
      return this.convert(receiver) + '.length';
    }
    if (method === 'push' || method === 'append') {
      return this.convert(receiver) + '.push(' + argsStr + ')';
    }
    if (method === 'pop') {
      return this.convert(receiver) + '.pop()';
    }
    if (method === 'shift') {
      return this.convert(receiver) + '.shift()';
    }
    if (method === 'unshift' || method === 'prepend') {
      return this.convert(receiver) + '.unshift(' + argsStr + ')';
    }
    if (method === 'first' && args.length === 0) {
      return this.convert(receiver) + '[0]';
    }
    if (method === 'last' && args.length === 0) {
      return this.convert(receiver) + '[' + this.convert(receiver) + '.length - 1]';
    }
    if (method === 'reverse') {
      return this.convert(receiver) + '.slice().reverse()';
    }
    if (method === 'reverse!') {
      return this.convert(receiver) + '.reverse()';
    }
    if (method === 'sort') {
      return this.convert(receiver) + '.slice().sort()';
    }
    if (method === 'sort!') {
      return this.convert(receiver) + '.sort()';
    }
    if (method === 'include?') {
      return this.convert(receiver) + '.includes(' + argsStr + ')';
    }
    if (method === 'join') {
      const sep = args.length > 0 ? argsStr : '""';
      return this.convert(receiver) + '.join(' + sep + ')';
    }
    if (method === 'flatten') {
      return this.convert(receiver) + '.flat(Infinity)';
    }
    if (method === 'compact') {
      return this.convert(receiver) + '.filter(x => x != null)';
    }
    if (method === 'uniq') {
      return '[...new Set(' + this.convert(receiver) + ')]';
    }
    if (method === 'empty?') {
      return '(' + this.convert(receiver) + '.length === 0)';
    }
    if (method === 'any?') {
      return '(' + this.convert(receiver) + '.length > 0)';
    }

    // Enumerable/Array iteration (without blocks - with blocks handled in convertBlock)
    if (method === 'map' || method === 'collect') {
      return this.convert(receiver) + '.map(' + argsStr + ')';
    }
    if (method === 'select' || method === 'filter' || method === 'find_all') {
      return this.convert(receiver) + '.filter(' + argsStr + ')';
    }
    if (method === 'reject') {
      return this.convert(receiver) + '.filter(' + argsStr + ')';
    }
    if (method === 'find' || method === 'detect') {
      return this.convert(receiver) + '.find(' + argsStr + ')';
    }
    if (method === 'reduce' || method === 'inject') {
      return this.convert(receiver) + '.reduce(' + argsStr + ')';
    }
    if (method === 'each') {
      return this.convert(receiver) + '.forEach(' + argsStr + ')';
    }
    if (method === 'each_with_index') {
      return this.convert(receiver) + '.forEach(' + argsStr + ')';
    }
    if (method === 'sum' && args.length === 0) {
      return this.convert(receiver) + '.reduce((a, b) => a + b, 0)';
    }

    // String methods
    if (method === 'to_s') {
      return this.convert(receiver) + '.toString()';
    }
    if (method === 'to_i') {
      return 'parseInt(' + this.convert(receiver) + ', 10)';
    }
    if (method === 'to_f') {
      return 'parseFloat(' + this.convert(receiver) + ')';
    }
    if (method === 'upcase') {
      return this.convert(receiver) + '.toUpperCase()';
    }
    if (method === 'downcase') {
      return this.convert(receiver) + '.toLowerCase()';
    }
    if (method === 'strip') {
      return this.convert(receiver) + '.trim()';
    }
    if (method === 'lstrip') {
      return this.convert(receiver) + '.trimStart()';
    }
    if (method === 'rstrip') {
      return this.convert(receiver) + '.trimEnd()';
    }
    if (method === 'split') {
      return this.convert(receiver) + '.split(' + argsStr + ')';
    }
    if (method === 'chars') {
      return '[...' + this.convert(receiver) + ']';
    }
    if (method === 'start_with?') {
      return this.convert(receiver) + '.startsWith(' + argsStr + ')';
    }
    if (method === 'end_with?') {
      return this.convert(receiver) + '.endsWith(' + argsStr + ')';
    }
    if (method === 'gsub') {
      // gsub(pattern, replacement) → replaceAll or replace with /g
      if (args.length === 2) {
        return this.convert(receiver) + '.replaceAll(' + this.convert(args[0]) + ', ' + this.convert(args[1]) + ')';
      }
    }
    if (method === 'sub') {
      if (args.length === 2) {
        return this.convert(receiver) + '.replace(' + this.convert(args[0]) + ', ' + this.convert(args[1]) + ')';
      }
    }
    if (method === 'index') {
      return this.convert(receiver) + '.indexOf(' + argsStr + ')';
    }
    if (method === 'rindex') {
      return this.convert(receiver) + '.lastIndexOf(' + argsStr + ')';
    }

    // Hash/Object methods
    if (method === 'keys' && args.length === 0) {
      return 'Object.keys(' + this.convert(receiver) + ')';
    }
    if (method === 'values' && args.length === 0) {
      return 'Object.values(' + this.convert(receiver) + ')';
    }
    if (method === 'merge') {
      return '{...' + this.convert(receiver) + ', ...' + argsStr + '}';
    }
    if (method === 'delete') {
      return 'delete ' + this.convert(receiver) + '[' + argsStr + ']';
    }
    if (method === 'key?' || method === 'has_key?') {
      return '(' + argsStr + ' in ' + this.convert(receiver) + ')';
    }

    // Numeric methods
    if (method === 'abs' && args.length === 0) {
      return 'Math.abs(' + this.convert(receiver) + ')';
    }
    if (method === 'round' && args.length === 0) {
      return 'Math.round(' + this.convert(receiver) + ')';
    }
    if (method === 'ceil' && args.length === 0) {
      return 'Math.ceil(' + this.convert(receiver) + ')';
    }
    if (method === 'floor' && args.length === 0) {
      return 'Math.floor(' + this.convert(receiver) + ')';
    }
    if (method === 'times') {
      return 'Array.from({length: ' + this.convert(receiver) + '}, (_, i) => i).forEach(' + argsStr + ')';
    }

    // Object/type methods
    if (method === 'nil?') {
      return '(' + this.convert(receiver) + ' == null)';
    }
    if (method === 'is_a?' || method === 'kind_of?') {
      return '(' + this.convert(receiver) + ' instanceof ' + argsStr + ')';
    }
    if (method === 'respond_to?') {
      return '(typeof ' + this.convert(receiver) + '[' + argsStr + '] === "function")';
    }
    if (method === 'class' && args.length === 0) {
      return this.convert(receiver) + '.constructor';
    }

    // Global functions
    if (receiver == null && method === 'rand') {
      if (args.length === 0) {
        return 'Math.random()';
      } else {
        return 'Math.floor(Math.random() * ' + argsStr + ')';
      }
    }
    if (receiver == null && method === 'print') {
      return 'process.stdout.write(' + argsStr + ')';
    }
    if (receiver == null && method === 'raise') {
      return 'throw new Error(' + argsStr + ')';
    }

    // Constructor: Foo.new(...) → new Foo(...)
    if (method === 'new') {
      return 'new ' + this.convert(receiver) + '(' + argsStr + ')';
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
    return 'function ' + name.toString() + '(' + argsStr + ') {\n  return ' + bodyStr + ';\n}';
  }

  convertIf(node) {
    const [cond, thenBody, elseBody] = node.children;
    let result = 'if (' + this.convert(cond) + ') {\n  ' + (thenBody ? this.convert(thenBody) : '') + '\n}';
    if (elseBody) {
      result += ' else {\n  ' + this.convert(elseBody) + '\n}';
    }
    return result;
  }

  convertWhile(node) {
    const [cond, body] = node.children;
    return 'while (' + this.convert(cond) + ') {\n  ' + (body ? this.convert(body) : '') + '\n}';
  }

  convertUntil(node) {
    const [cond, body] = node.children;
    return 'while (!(' + this.convert(cond) + ')) {\n  ' + (body ? this.convert(body) : '') + '\n}';
  }

  convertFor(node) {
    const [variable, collection, body] = node.children;
    const varName = this.convert(variable);
    return 'for (let ' + varName + ' of ' + this.convert(collection) + ') {\n  ' + (body ? this.convert(body) : '') + '\n}';
  }

  convertCase(node) {
    const [predicate, ...rest] = node.children;
    const elseBody = rest.pop(); // last child is else clause
    const whens = rest;

    let result = 'switch (' + this.convert(predicate) + ') {\n';
    for (const when of whens) {
      result += this.convert(when);
    }
    if (elseBody) {
      result += '  default:\n    ' + this.convert(elseBody) + ';\n    break;\n';
    }
    result += '}';
    return result;
  }

  convertWhen(node) {
    const conditions = node.children.slice(0, -1);
    const body = node.children[node.children.length - 1];
    let result = '';
    for (const cond of conditions) {
      result += '  case ' + this.convert(cond) + ':\n';
    }
    result += '    ' + (body ? this.convert(body) : '') + ';\n    break;\n';
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

  convertConst(node) {
    const [parent, name] = node.children;
    if (parent) {
      return this.convert(parent) + '.' + name.toString();
    }
    return name.toString();
  }

  convertCasgn(node) {
    const [parent, name, value] = node.children;
    const fullName = parent ? this.convert(parent) + '.' + name.toString() : name.toString();
    return 'const ' + fullName + ' = ' + this.convert(value);
  }

  convertClass(node) {
    const [nameNode, superclassNode, body] = node.children;
    const name = this.convert(nameNode);
    const superclass = superclassNode ? this.convert(superclassNode) : null;

    let result = 'class ' + name;
    if (superclass) {
      result += ' extends ' + superclass;
    }
    result += ' {\n';

    // Process body - look for initialize and other methods
    if (body) {
      result += this.convertClassBody(body);
    }

    result += '}';
    return result;
  }

  convertClassBody(body) {
    if (body.type === 'begin') {
      return body.children.map(child => this.convertClassMember(child)).join('\n');
    } else {
      return this.convertClassMember(body);
    }
  }

  convertClassMember(node) {
    if (node.type === 'def') {
      return this.convertMethod(node);
    } else if (node.type === 'send') {
      // Handle attr_accessor, attr_reader, attr_writer
      const [receiver, method, ...args] = node.children;
      if (receiver == null && (method === 'attr_accessor' || method === 'attr_reader' || method === 'attr_writer')) {
        return this.convertAttr(method, args);
      }
    }
    return '  ' + this.convert(node);
  }

  convertMethod(node) {
    const [name, args, body] = node.children;
    const methodName = name.toString();
    const argsStr = this.convert(args);

    // Initialize becomes constructor
    if (methodName === 'initialize') {
      let bodyStr = body ? this.convertMethodBody(body, false) : '';
      return '  constructor(' + argsStr + ') {\n' + bodyStr + '  }';
    }

    // Regular method
    let bodyStr = body ? this.convertMethodBody(body, true) : '';
    return '  ' + methodName + '(' + argsStr + ') {\n' + bodyStr + '  }';
  }

  convertMethodBody(body, addReturn) {
    if (body.type === 'begin') {
      const statements = body.children.map((c, i) => {
        const isLast = i === body.children.length - 1;
        const stmt = this.convert(c);
        if (addReturn && isLast) {
          return '    return ' + stmt + ';';
        }
        return '    ' + stmt + ';';
      });
      return statements.join('\n') + '\n';
    } else {
      const stmt = this.convert(body);
      if (addReturn) {
        return '    return ' + stmt + ';\n';
      }
      return '    ' + stmt + ';\n';
    }
  }

  convertAttr(type, args) {
    const result = [];
    for (const arg of args) {
      const name = arg.children[0].toString();
      if (type === 'attr_reader' || type === 'attr_accessor') {
        result.push('  get ' + name + '() { return this._' + name + '; }');
      }
      if (type === 'attr_writer' || type === 'attr_accessor') {
        result.push('  set ' + name + '(value) { this._' + name + ' = value; }');
      }
    }
    return result.join('\n');
  }

  convertModule(node) {
    const [nameNode, body] = node.children;
    const name = this.convert(nameNode);

    // Convert module to object with methods
    let result = 'const ' + name + ' = {\n';
    if (body) {
      if (body.type === 'begin') {
        const members = body.children.map(child => {
          if (child.type === 'def') {
            const [methodName, args, methodBody] = child.children;
            const argsStr = this.convert(args);
            const bodyStr = methodBody ? this.convert(methodBody) : 'null';
            return '  ' + methodName.toString() + '(' + argsStr + ') { return ' + bodyStr + '; }';
          }
          return '  ' + this.convert(child);
        });
        result += members.join(',\n') + '\n';
      } else if (body.type === 'def') {
        const [methodName, args, methodBody] = body.children;
        const argsStr = this.convert(args);
        const bodyStr = methodBody ? this.convert(methodBody) : 'null';
        result += '  ' + methodName.toString() + '(' + argsStr + ') { return ' + bodyStr + '; }\n';
      }
    }
    result += '}';
    return result;
  }

  convertSclass(node) {
    const [expr, body] = node.children;
    // class << self is for static methods - return as comment for now
    return '/* class << ' + this.convert(expr) + ' */';
  }

  convertBlock(node) {
    const [call, args, body] = node.children;
    const argsStr = this.convert(args);
    const bodyStr = body ? this.convert(body) : 'null';

    // Check if this is a lambda
    if (call.type === 'send' && call.children[1] === 'lambda') {
      return '((' + argsStr + ') => ' + bodyStr + ')';
    }

    // Regular block - convert to method call with arrow function
    const callStr = this.convert(call);
    // Remove trailing () if present, then add arrow function
    const baseCall = callStr.replace(/\\(\\)$/, '');
    return baseCall + '((' + argsStr + ') => ' + bodyStr + ')';
  }

  // === Exception Handling ===

  convertRescue(node) {
    // rescue AST: (rescue body resbody else_body)
    const [body, resbody, elseBody] = node.children;
    const bodyStr = body ? this.convert(body) : '';
    const catchStr = this.convert(resbody);
    let result = 'try {\n  ' + bodyStr + '\n}' + catchStr;
    if (elseBody) {
      // else clause runs if no exception - not directly supported in JS try/catch
      result += '\n// else: ' + this.convert(elseBody);
    }
    return result;
  }

  convertResbody(node) {
    // resbody AST: (resbody exception_array var body)
    const [exceptions, varNode, body] = node.children;
    const bodyStr = body ? this.convert(body) : '';
    let varName = 'e';
    if (varNode && varNode.type === 'lvasgn') {
      varName = varNode.children[0].toString();
    }
    // In JS, we can't easily filter by exception type in catch, so we generate simple catch
    return ' catch (' + varName + ') {\n  ' + bodyStr + '\n}';
  }

  convertEnsure(node) {
    // ensure AST: (ensure body ensure_body)
    const [body, ensureBody] = node.children;
    const bodyStr = body ? this.convert(body) : '';
    const ensureStr = ensureBody ? this.convert(ensureBody) : '';
    // If body is already a try/catch, append finally
    if (bodyStr.startsWith('try {')) {
      return bodyStr + ' finally {\n  ' + ensureStr + '\n}';
    }
    // Otherwise wrap in try/finally
    return 'try {\n  ' + bodyStr + '\n} finally {\n  ' + ensureStr + '\n}';
  }

  convertRegexp(node) {
    // regexp AST: (regexp str_part regopt)
    const parts = node.children.slice(0, -1);
    const opts = node.children[node.children.length - 1];
    const pattern = parts.map(p => {
      if (p.type === 'str') {
        return p.children[0];
      }
      return '${' + this.convert(p) + '}';
    }).join('');
    const flags = opts && opts.children ? opts.children.join('') : '';
    // Escape forward slashes in pattern
    const escaped = pattern.replace(/\\//g, '\\\\/');
    return '/' + escaped + '/' + flags;
  }
}


// Array.compact polyfill
Array.prototype.compact = function() {
  return this.filter(x => x != null);
};

export { Node, s, PrismWalker, Converter };
