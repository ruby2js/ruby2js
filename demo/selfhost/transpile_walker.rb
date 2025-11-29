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

  def visit_call_node(node)
    receiver = visit(node.receiver)
    args = node.arguments ? visit_all(node.arguments.arguments) : []
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

# Output the JavaScript module
puts <<~JS
// Auto-generated from Ruby PrismWalker
// Filter order: return, selfhost, functions

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

// Array.compact polyfill
Array.prototype.compact = function() {
  return this.filter(x => x != null);
};

export { Node, s, PrismWalker };
JS
