# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Method call: foo.bar(1, 2) or foo.bar or bar(1, 2) or bar
    def visit_call_node(node)
      receiver = visit(node.receiver)
      method_name = node.name

      # Get arguments
      args = []
      if node.arguments
        args = visit_all(node.arguments.arguments)
      end

      # Handle block argument
      if node.block.is_a?(Prism::BlockArgumentNode)
        args << visit(node.block)
      end

      # Choose :send or :csend based on safe navigation
      type = node.safe_navigation? ? :csend : :send

      # Use send_node to create node with location for is_method? detection
      result = send_node(node, type, receiver, method_name, *args)

      # If there's a block (not a block argument), wrap in :block
      if node.block.is_a?(Prism::BlockNode)
        block_args = node.block.parameters ? visit(node.block.parameters) : s(:args)
        block_body = visit(node.block.body)

        # Check for numbered parameters
        if node.block.parameters.is_a?(Prism::NumberedParametersNode)
          sl(node, :numblock, result, node.block.parameters.maximum, block_body)
        else
          sl(node, :block, result, block_args, block_body)
        end
      else
        result
      end
    end

    # Block argument: &block
    def visit_block_argument_node(node)
      if node.expression
        sl(node, :block_pass, visit(node.expression))
      else
        # Anonymous block argument: &
        sl(node, :block_pass)
      end
    end

    # Note: visit_index_operator_write_node is defined in operators.rb
    # with proper safe navigation (csend) handling

    # Super with arguments: super(1, 2)
    def visit_super_node(node)
      if node.arguments
        args = visit_all(node.arguments.arguments)
        result = sl(node, :super, *args)
      else
        # super with no arguments but with parentheses
        result = sl(node, :super)
      end

      # Handle block
      if node.block.is_a?(Prism::BlockNode)
        block_args = node.block.parameters ? visit(node.block.parameters) : s(:args)
        block_body = visit(node.block.body)
        sl(node, :block, result, block_args, block_body)
      else
        result
      end
    end

    # Super without parentheses: super (forwards all arguments)
    def visit_forwarding_super_node(node)
      sl(node, :zsuper)
    end

    # Yield: yield 1, 2
    def visit_yield_node(node)
      if node.arguments
        args = visit_all(node.arguments.arguments)
        sl(node, :yield, *args)
      else
        sl(node, :yield)
      end
    end

    # Forwarding arguments: def foo(...); bar(...); end
    def visit_forwarding_arguments_node(node)
      sl(node, :forwarded_args)
    end
  end
end
