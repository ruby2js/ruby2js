# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Method definition: def foo(args); body; end
    def visit_def_node(node)
      name = node.name
      args = node.parameters ? s(:args, *visit_parameters(node.parameters)) : s(:args)
      body = visit(node.body)

      # Detect endless method: has equal_loc but no end_keyword_loc
      endless = !!(node.equal_loc && node.end_keyword_loc.nil?)

      if node.receiver
        # Singleton method: def self.foo or def obj.foo
        receiver = visit(node.receiver)
        def_node(node, :defs, receiver, name, args, body, endless: endless)
      else
        def_node(node, :def, name, args, body, endless: endless)
      end
    end

    # Class definition: class Foo < Bar; body; end
    def visit_class_node(node)
      # Handle constant path (A::B) or simple constant (A)
      name = visit(node.constant_path)
      superclass = visit(node.superclass)
      body = visit(node.body)

      sl(node, :class, name, superclass, body)
    end

    # Module definition: module Foo; body; end
    def visit_module_node(node)
      name = visit(node.constant_path)
      body = visit(node.body)

      sl(node, :module, name, body)
    end

    # Singleton class: class << self; body; end
    def visit_singleton_class_node(node)
      expression = visit(node.expression)
      body = visit(node.body)

      sl(node, :sclass, expression, body)
    end

    # Alias: alias new_name old_name
    def visit_alias_method_node(node)
      new_name = visit(node.new_name)
      old_name = visit(node.old_name)

      sl(node, :alias, new_name, old_name)
    end

    # Alias global variable: alias $new $old
    def visit_alias_global_variable_node(node)
      new_name = visit(node.new_name)
      old_name = visit(node.old_name)

      sl(node, :alias, new_name, old_name)
    end

    # Undef: undef foo, bar
    def visit_undef_node(node)
      names = visit_all(node.names)
      sl(node, :undef, *names)
    end

    # Defined?: defined?(foo)
    def visit_defined_node(node)
      value = visit(node.value)
      sl(node, :defined?, value)
    end

    # Pre-execution: BEGIN { }
    def visit_pre_execution_node(node)
      body = visit(node.statements)
      sl(node, :preexe, body)
    end

    # Post-execution: END { }
    def visit_post_execution_node(node)
      body = visit(node.statements)
      sl(node, :postexe, body)
    end
  end
end
