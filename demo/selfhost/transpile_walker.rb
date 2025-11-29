#!/usr/bin/env ruby
# frozen_string_literal: true

# Transpile the Ruby PrismWalker to JavaScript for use with @ruby/prism npm package

require_relative '../../lib/ruby2js'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'

# Minimal PrismWalker for proof-of-concept
# (Full walker would need all visitor modules)
WALKER_CODE = <<~'RUBY'
class PrismWalker < Prism::Visitor
  def initialize(source, file = nil)
    @source = source
    @file = file
    super()
  end

  def s(type, *children)
    Node.new(type, children)
  end

  def visit(node)
    return nil if node.nil?
    super
  end

  def visit_all(nodes)
    return [] if nodes.nil?
    nodes.map { |n| visit(n) }.compact
  end

  # === Literals ===

  def visit_integer_node(node)
    s(:int, node.value)
  end

  def visit_float_node(node)
    s(:float, node.value)
  end

  def visit_nil_node(node)
    s(:nil)
  end

  def visit_true_node(node)
    s(:true)
  end

  def visit_false_node(node)
    s(:false)
  end

  # Note: In JS Prism, unescaped returns {encoding, validEncoding, value}
  # We access .value to get the actual string
  def visit_string_node(node)
    s(:str, node.unescaped.value)
  end

  def visit_symbol_node(node)
    s(:sym, node.unescaped.value)
  end

  def visit_self_node(node)
    s(:self)
  end

  # === Variables ===

  def visit_local_variable_read_node(node)
    s(:lvar, node.name)
  end

  def visit_local_variable_write_node(node)
    s(:lvasgn, node.name, visit(node.value))
  end

  def visit_instance_variable_read_node(node)
    s(:ivar, node.name)
  end

  def visit_instance_variable_write_node(node)
    s(:ivasgn, node.name, visit(node.value))
  end

  # === Collections ===

  def visit_array_node(node)
    s(:array, *visit_all(node.elements))
  end

  def visit_hash_node(node)
    s(:hash, *visit_all(node.elements))
  end

  def visit_assoc_node(node)
    s(:pair, visit(node.key), visit(node.value))
  end

  # === Calls ===

  # Note: In JS Prism, arguments is accessed via arguments_ (underscore)
  # and the actual args array is arguments_.arguments_
  def visit_call_node(node)
    receiver = visit(node.receiver)
    args = node.arguments_ ? visit_all(node.arguments_.arguments_) : []
    s(:send, receiver, node.name, *args)
  end

  # === Definitions ===

  def visit_def_node(node)
    args = visit(node.parameters) || s(:args)
    body = visit(node.body)
    s(:def, node.name, args, body)
  end

  def visit_parameters_node(node)
    params = []
    node.requireds.each { |p| params << visit(p) }
    node.optionals.each { |p| params << visit(p) }
    if node.rest
      params << visit(node.rest)
    end
    s(:args, *params)
  end

  def visit_required_parameter_node(node)
    s(:arg, node.name)
  end

  def visit_optional_parameter_node(node)
    s(:optarg, node.name, visit(node.value))
  end

  def visit_rest_parameter_node(node)
    s(:restarg, node.name)
  end

  # === Control Flow ===

  def visit_if_node(node)
    s(:if, visit(node.predicate), visit(node.statements), visit(node.subsequent))
  end

  def visit_unless_node(node)
    # Parser gem represents unless as: if(condition, else_body, then_body)
    # Note: JS Prism uses camelCase: elseClause
    s(:if, visit(node.predicate), visit(node.elseClause), visit(node.statements))
  end

  def visit_else_node(node)
    visit(node.statements)
  end

  def visit_while_node(node)
    s(:while, visit(node.predicate), visit(node.statements))
  end

  def visit_until_node(node)
    s(:until, visit(node.predicate), visit(node.statements))
  end

  def visit_case_node(node)
    # Note: JS Prism uses camelCase: elseClause
    s(:case, visit(node.predicate), *visit_all(node.conditions), visit(node.elseClause))
  end

  def visit_when_node(node)
    s(:when, *visit_all(node.conditions), visit(node.statements))
  end

  def visit_for_node(node)
    s(:for, visit(node.index), visit(node.collection), visit(node.statements))
  end

  def visit_return_node(node)
    if node.arguments_
      args = visit_all(node.arguments_.arguments_)
      args.length == 1 ? s(:return, args.first) : s(:return, s(:array, *args))
    else
      s(:return)
    end
  end

  def visit_break_node(node)
    if node.arguments_
      args = visit_all(node.arguments_.arguments_)
      s(:break, *args)
    else
      s(:break)
    end
  end

  def visit_next_node(node)
    if node.arguments_
      args = visit_all(node.arguments_.arguments_)
      s(:next, *args)
    else
      s(:next)
    end
  end

  # === Operators ===

  def visit_and_node(node)
    s(:and, visit(node.left), visit(node.right))
  end

  def visit_or_node(node)
    s(:or, visit(node.left), visit(node.right))
  end

  def visit_range_node(node)
    # JS Prism: detect exclusive range by operator length (... = 3, .. = 2)
    is_exclusive = node.operatorLoc.length == 3
    type = is_exclusive ? :erange : :irange
    s(type, visit(node.left), visit(node.right))
  end

  # === Strings ===

  def visit_interpolated_string_node(node)
    parts = node.parts.map do |part|
      if part.constructor.name == 'StringNode'
        s(:str, part.unescaped.value)
      else
        visit(part)
      end
    end
    s(:dstr, *parts)
  end

  def visit_embedded_statements_node(node)
    if node.statements.nil?
      s(:begin)
    else
      body = node.statements.body
      if body.length == 1
        visit(body[0])
      else
        s(:begin, *visit_all(body))
      end
    end
  end

  # === Other ===

  def visit_parentheses_node(node)
    # Just visit the body - parentheses are for grouping
    visit(node.body)
  end

  def visit_statements_node(node)
    children = visit_all(node.body)
    children.length == 1 ? children.first : s(:begin, *children)
  end

  def visit_program_node(node)
    visit(node.statements)
  end
end
RUBY

# Transpile with correct filter order
result = Ruby2JS.convert(
  WALKER_CODE,
  filters: [:return, :selfhost, :functions],
  eslevel: 2015
)

# Converter is written directly in JS since it has patterns
# that don't transpile cleanly (method references as handlers)
CONVERTER_JS = <<~'JS'
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
JS

# Output the JavaScript module
puts <<~JS
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

#{result}

#{CONVERTER_JS}

// Array.compact polyfill
Array.prototype.compact = function() {
  return this.filter(x => x != null);
};

export { Node, s, PrismWalker, Converter };
JS
