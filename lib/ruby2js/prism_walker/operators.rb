# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Logical and: a && b or a and b
    def visit_and_node(node)
      left = visit(node.left)
      right = visit(node.right)
      sl(node, :and, left, right)
    end

    # Logical or: a || b or a or b
    def visit_or_node(node)
      left = visit(node.left)
      right = visit(node.right)
      sl(node, :or, left, right)
    end

    # Not: !a or not a
    def visit_call_operator_not(node)
      # This is handled by visit_call_node for the ! operator
    end

    # Multiple assignment: a, b = 1, 2
    def visit_multi_write_node(node)
      # Build left-hand side (mlhs)
      targets = []

      node.lefts&.each do |target|
        targets << visit(target)
      end

      if node.rest && !node.rest.is_a?(Prism::ImplicitRestNode)
        targets << visit(node.rest)
      end

      node.rights&.each do |target|
        targets << visit(target)
      end

      lhs = s(:mlhs, *targets)

      # Build right-hand side
      if node.value.is_a?(Prism::ArrayNode) && node.value.elements
        rhs_values = visit_all(node.value.elements)
        if rhs_values.length == 1
          rhs = rhs_values.first
        else
          rhs = s(:array, *rhs_values)
        end
      else
        rhs = visit(node.value)
      end

      sl(node, :masgn, lhs, rhs)
    end

    # Splat in LHS: a, *b = 1, 2, 3
    def visit_splat_node_in_mlhs(node)
      if node.expression
        s(:splat, visit(node.expression))
      else
        s(:splat)
      end
    end

    #
    # Operator assignment nodes (+=, -=, etc.)
    # Prism has many specific node types, Parser uses :op_asgn, :or_asgn, :and_asgn
    #

    # Local variable operator assignment: a += 1
    def visit_local_variable_operator_write_node(node)
      target = s(:lvasgn, node.name)
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Local variable or-assignment: a ||= 1
    def visit_local_variable_or_write_node(node)
      target = s(:lvasgn, node.name)
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Local variable and-assignment: a &&= 1
    def visit_local_variable_and_write_node(node)
      target = s(:lvasgn, node.name)
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Instance variable operator assignment: @a += 1
    def visit_instance_variable_operator_write_node(node)
      target = s(:ivasgn, node.name)
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Instance variable or-assignment: @a ||= 1
    def visit_instance_variable_or_write_node(node)
      target = s(:ivasgn, node.name)
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Instance variable and-assignment: @a &&= 1
    def visit_instance_variable_and_write_node(node)
      target = s(:ivasgn, node.name)
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Class variable operator assignment: @@a += 1
    def visit_class_variable_operator_write_node(node)
      target = s(:cvasgn, node.name)
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Class variable or-assignment: @@a ||= 1
    def visit_class_variable_or_write_node(node)
      target = s(:cvasgn, node.name)
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Class variable and-assignment: @@a &&= 1
    def visit_class_variable_and_write_node(node)
      target = s(:cvasgn, node.name)
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Global variable operator assignment: $a += 1
    def visit_global_variable_operator_write_node(node)
      target = s(:gvasgn, node.name)
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Global variable or-assignment: $a ||= 1
    def visit_global_variable_or_write_node(node)
      target = s(:gvasgn, node.name)
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Global variable and-assignment: $a &&= 1
    def visit_global_variable_and_write_node(node)
      target = s(:gvasgn, node.name)
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Constant operator assignment: A += 1
    def visit_constant_operator_write_node(node)
      target = s(:casgn, nil, node.name)
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Constant or-assignment: A ||= 1
    def visit_constant_or_write_node(node)
      target = s(:casgn, nil, node.name)
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Constant and-assignment: A &&= 1
    def visit_constant_and_write_node(node)
      target = s(:casgn, nil, node.name)
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Constant path operator assignment: A::B += 1
    def visit_constant_path_operator_write_node(node)
      target_path = visit(node.target)
      target = s(:casgn, target_path.children[0], target_path.children[1])
      sl(node, :op_asgn, target, node.binary_operator, visit(node.value))
    end

    # Constant path or-assignment: A::B ||= 1
    def visit_constant_path_or_write_node(node)
      target_path = visit(node.target)
      target = s(:casgn, target_path.children[0], target_path.children[1])
      sl(node, :or_asgn, target, visit(node.value))
    end

    # Constant path and-assignment: A::B &&= 1
    def visit_constant_path_and_write_node(node)
      target_path = visit(node.target)
      target = s(:casgn, target_path.children[0], target_path.children[1])
      sl(node, :and_asgn, target, visit(node.value))
    end

    # Index operator assignment: a[0] += 1
    def visit_index_operator_write_node(node)
      receiver = visit(node.receiver)
      args = visit_all(node.arguments&.arguments || [])
      value = visit(node.value)

      call_args = node.call_operator_loc ? s(:csend, receiver, :[], *args) : s(:send, receiver, :[], *args)
      sl(node, :op_asgn, call_args, node.binary_operator, value)
    end

    # Index or-assignment: a[0] ||= 1
    def visit_index_or_write_node(node)
      receiver = visit(node.receiver)
      args = visit_all(node.arguments&.arguments || [])
      value = visit(node.value)

      call_args = s(:send, receiver, :[], *args)
      sl(node, :or_asgn, call_args, value)
    end

    # Index and-assignment: a[0] &&= 1
    def visit_index_and_write_node(node)
      receiver = visit(node.receiver)
      args = visit_all(node.arguments&.arguments || [])
      value = visit(node.value)

      call_args = s(:send, receiver, :[], *args)
      sl(node, :and_asgn, call_args, value)
    end

    # Call operator assignment: a.b += 1
    def visit_call_operator_write_node(node)
      receiver = visit(node.receiver)
      read_name = node.read_name
      value = visit(node.value)

      call_type = node.safe_navigation? ? :csend : :send
      target = send_with_loc(node, call_type, receiver, read_name)
      sl(node, :op_asgn, target, node.binary_operator, value)
    end

    # Call or-assignment: a.b ||= 1
    def visit_call_or_write_node(node)
      receiver = visit(node.receiver)
      read_name = node.read_name
      value = visit(node.value)

      call_type = node.safe_navigation? ? :csend : :send
      target = send_with_loc(node, call_type, receiver, read_name)
      sl(node, :or_asgn, target, value)
    end

    # Call and-assignment: a.b &&= 1
    def visit_call_and_write_node(node)
      receiver = visit(node.receiver)
      read_name = node.read_name
      value = visit(node.value)

      call_type = node.safe_navigation? ? :csend : :send
      target = send_with_loc(node, call_type, receiver, read_name)
      sl(node, :and_asgn, target, value)
    end

    # Flip flop (very rarely used)
    def visit_flip_flop_node(node)
      left = visit(node.left)
      right = visit(node.right)
      type = node.exclude_end? ? :eflipflop : :iflipflop
      sl(node, type, left, right)
    end
  end
end
