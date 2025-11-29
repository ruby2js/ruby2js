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
