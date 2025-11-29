# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Local variable read: foo
    def visit_local_variable_read_node(node)
      sl(node, :lvar, node.name)
    end

    # Local variable write: foo = 1
    def visit_local_variable_write_node(node)
      sl(node, :lvasgn, node.name, visit(node.value))
    end

    # Local variable target (for multiple assignment): a, b = 1, 2
    def visit_local_variable_target_node(node)
      sl(node, :lvasgn, node.name)
    end

    # Instance variable read: @foo
    def visit_instance_variable_read_node(node)
      sl(node, :ivar, node.name)
    end

    # Instance variable write: @foo = 1
    def visit_instance_variable_write_node(node)
      sl(node, :ivasgn, node.name, visit(node.value))
    end

    # Instance variable target (for multiple assignment)
    def visit_instance_variable_target_node(node)
      sl(node, :ivasgn, node.name)
    end

    # Class variable read: @@foo
    def visit_class_variable_read_node(node)
      sl(node, :cvar, node.name)
    end

    # Class variable write: @@foo = 1
    def visit_class_variable_write_node(node)
      sl(node, :cvasgn, node.name, visit(node.value))
    end

    # Class variable target (for multiple assignment)
    def visit_class_variable_target_node(node)
      sl(node, :cvasgn, node.name)
    end

    # Global variable read: $foo
    def visit_global_variable_read_node(node)
      sl(node, :gvar, node.name)
    end

    # Global variable write: $foo = 1
    def visit_global_variable_write_node(node)
      sl(node, :gvasgn, node.name, visit(node.value))
    end

    # Global variable target (for multiple assignment)
    def visit_global_variable_target_node(node)
      sl(node, :gvasgn, node.name)
    end

    # Constant read: FOO
    def visit_constant_read_node(node)
      sl(node, :const, nil, node.name)
    end

    # Constant write: FOO = 1
    def visit_constant_write_node(node)
      sl(node, :casgn, nil, node.name, visit(node.value))
    end

    # Constant target (for multiple assignment)
    def visit_constant_target_node(node)
      sl(node, :casgn, nil, node.name)
    end

    # Constant path: A::B::C
    def visit_constant_path_node(node)
      parent = node.parent ? visit(node.parent) : s(:cbase)
      sl(node, :const, parent, node.name)
    end

    # Constant path write: A::B = 1
    def visit_constant_path_write_node(node)
      target = visit(node.target)
      # target is s(:const, parent, name), we need s(:casgn, parent, name, value)
      sl(node, :casgn, target.children[0], target.children[1], visit(node.value))
    end

    # Constant path target (for multiple assignment)
    def visit_constant_path_target_node(node)
      parent = node.parent ? visit(node.parent) : s(:cbase)
      sl(node, :casgn, parent, node.name)
    end

    # Back reference: $& $` $' $+
    def visit_back_reference_read_node(node)
      sl(node, :back_ref, node.name)
    end

    # Numbered reference: $1, $2, etc.
    def visit_numbered_reference_read_node(node)
      sl(node, :nth_ref, node.number)
    end

    # It (Ruby 3.4+ anonymous block parameter)
    def visit_it_local_variable_read_node(node)
      sl(node, :lvar, :it)
    end
  end
end
