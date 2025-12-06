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
  # Blocks are attached to CallNode via .block property
  def visit_call_node(node)
    receiver = visit(node.receiver)
    args = node.arguments_ ? visit_all(node.arguments_.arguments_) : []

    # Detect if this is a method call with parentheses
    # Prism JS binding uses camelCase: openingLoc for the opening parenthesis location
    is_method = !!node.openingLoc
    # Create node with is_method option
    call = Node.new(:send, [receiver, node.name, *args], { is_method: is_method })

    # Check for attached block
    if node.block
      block_params = visit(node.block.parameters) || s(:args)
      block_body = visit(node.block.body)
      s(:block, call, block_params, block_body)
    else
      call
    end
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
    if node.block
      params << visit(node.block)
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

  def visit_block_parameter_node(node)
    s(:blockarg, node.name)
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

  def visit_local_variable_operator_write_node(node)
    s(:op_asgn, s(:lvasgn, node.name), node.binaryOperator, visit(node.value))
  end

  def visit_instance_variable_operator_write_node(node)
    s(:op_asgn, s(:ivasgn, node.name), node.binaryOperator, visit(node.value))
  end

  def visit_class_variable_operator_write_node(node)
    s(:op_asgn, s(:cvasgn, node.name), node.binaryOperator, visit(node.value))
  end

  def visit_global_variable_operator_write_node(node)
    s(:op_asgn, s(:gvasgn, node.name), node.binaryOperator, visit(node.value))
  end

  def visit_local_variable_or_write_node(node)
    s(:or_asgn, s(:lvasgn, node.name), visit(node.value))
  end

  def visit_local_variable_and_write_node(node)
    s(:and_asgn, s(:lvasgn, node.name), visit(node.value))
  end

  def visit_instance_variable_or_write_node(node)
    s(:or_asgn, s(:ivasgn, node.name), visit(node.value))
  end

  def visit_instance_variable_and_write_node(node)
    s(:and_asgn, s(:ivasgn, node.name), visit(node.value))
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

  # === Classes and Modules ===

  def visit_class_node(node)
    # JS Prism uses camelCase: constantPath, superclass
    name = visit(node.constantPath)
    superclass = visit(node.superclass)
    body = visit(node.body)
    s(:class, name, superclass, body)
  end

  def visit_module_node(node)
    name = visit(node.constantPath)
    body = visit(node.body)
    s(:module, name, body)
  end

  def visit_singleton_class_node(node)
    # class << self; ... end
    expr = visit(node.expression)
    body = visit(node.body)
    s(:sclass, expr, body)
  end

  # Constants
  def visit_constant_read_node(node)
    s(:const, nil, node.name)
  end

  def visit_constant_path_node(node)
    # Foo::Bar
    parent = visit(node.parent)
    s(:const, parent, node.name)
  end

  def visit_constant_write_node(node)
    s(:casgn, nil, node.name, visit(node.value))
  end

  def visit_constant_path_write_node(node)
    target = visit(node.target)
    s(:casgn, target.children[0], target.children[1], visit(node.value))
  end

  # === Blocks ===

  def visit_block_node(node)
    call = visit(node.call)
    params = visit(node.parameters) || s(:args)
    body = visit(node.body)
    s(:block, call, params, body)
  end

  def visit_block_parameters_node(node)
    params = []
    if node.parameters
      node.parameters.requireds.each { |p| params << visit(p) }
      node.parameters.optionals.each { |p| params << visit(p) }
      if node.parameters.rest
        params << visit(node.parameters.rest)
      end
    end
    s(:args, *params)
  end

  def visit_lambda_node(node)
    params = visit(node.parameters) || s(:args)
    body = visit(node.body)
    s(:block, s(:send, nil, :lambda), params, body)
  end

  # === Other ===

  def visit_parentheses_node(node)
    # Wrap in :begin to match Ruby parser behavior
    # This is important for preserving semantics in cases like `not (a or b)`
    # where the :begin prevents DeMorgan transformation
    body = visit(node.body)
    body ? s(:begin, body) : nil
  end

  def visit_splat_node(node)
    s(:splat, visit(node.expression))
  end

  def visit_keyword_hash_node(node)
    # Used in method arguments: foo(a: 1, b: 2)
    s(:hash, *visit_all(node.elements))
  end

  def visit_assoc_splat_node(node)
    # **hash
    s(:kwsplat, visit(node.value))
  end

  def visit_statements_node(node)
    children = visit_all(node.body)
    children.length == 1 ? children.first : s(:begin, *children)
  end

  def visit_program_node(node)
    visit(node.statements)
  end

  # === Exception Handling ===

  def visit_begin_node(node)
    # begin; ...; rescue; ...; ensure; ...; end
    # JS Prism uses camelCase: rescueClause, ensureClause
    body = visit(node.statements)
    rescue_node = visit(node.rescueClause)
    ensure_node = node.ensureClause ? visit(node.ensureClause.statements) : nil

    if rescue_node
      if ensure_node
        s(:ensure, s(:rescue, body, rescue_node, nil), ensure_node)
      else
        s(:rescue, body, rescue_node, nil)
      end
    else
      if ensure_node
        s(:ensure, body, ensure_node)
      else
        body
      end
    end
  end

  def visit_rescue_node(node)
    # rescue ExceptionClass => var; ...; end
    # JS Prism: reference is the exception variable
    exceptions = visit_all(node.exceptions)
    exc_var = node.reference ? visit(node.reference) : nil
    body = visit(node.statements)
    subsequent = node.subsequent ? visit(node.subsequent) : nil

    # Build the resbody node
    exc_array = exceptions.empty? ? nil : s(:array, *exceptions)
    resbody = s(:resbody, exc_array, exc_var, body)

    if subsequent
      # Chain multiple rescue clauses
      s(:begin, resbody, subsequent)
    else
      resbody
    end
  end

  def visit_local_variable_target_node(node)
    s(:lvasgn, node.name)
  end

  # === Regular Expressions ===

  def visit_regular_expression_node(node)
    # Note: JS Prism uses unescaped.value for the pattern
    pattern = node.unescaped.value
    flags = node.flags || 0
    # Convert Prism flags to string
    flag_str = ""
    s(:regexp, s(:str, pattern), s(:regopt, flag_str))
  end

  def visit_interpolated_regular_expression_node(node)
    parts = node.parts.map do |part|
      if part.constructor.name == 'StringNode'
        s(:str, part.unescaped.value)
      else
        visit(part)
      end
    end
    s(:regexp, *parts, s(:regopt))
  end

  def visit_match_last_line_node(node)
    # Implicit regex match: if /pattern/
    pattern = node.unescaped.value
    s(:match_current_line, s(:regexp, s(:str, pattern), s(:regopt)))
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
    // Store is_method flag for call nodes (true if has parentheses)
    if (options.is_method !== undefined) {
      this.is_method = options.is_method;
    }
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
