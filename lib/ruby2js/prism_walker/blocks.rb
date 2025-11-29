# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Block: foo { |x| x + 1 }
    def visit_block_node(node)
      call = visit(node.call)
      body = visit(node.body)

      if node.parameters.is_a?(Prism::NumberedParametersNode)
        # Numbered parameters: { _1 + _2 }
        sl(node, :numblock, call, node.parameters.maximum, body)
      else
        args = node.parameters ? visit(node.parameters) : s(:args)
        sl(node, :block, call, args, body)
      end
    end

    # Lambda: -> { } or ->(x) { x }
    def visit_lambda_node(node)
      body = visit(node.body)

      # Parser gem produces (:send nil :lambda) for the lambda keyword
      lambda_call = s(:send, nil, :lambda)

      if node.parameters.is_a?(Prism::NumberedParametersNode)
        # Numbered parameters in lambda
        sl(node, :numblock, lambda_call, node.parameters.maximum, body)
      else
        args = node.parameters ? visit(node.parameters) : s(:args)
        sl(node, :block, lambda_call, args, body)
      end
    end

    # Block parameters: |a, b, *rest, &block|
    def visit_block_parameters_node(node)
      params = []

      # Required parameters
      if node.parameters
        params.concat(visit_parameters(node.parameters))
      end

      # Block-local variables (shadow variables): |; a, b|
      if node.locals && !node.locals.empty?
        node.locals.each do |local|
          params << s(:shadowarg, local.name)
        end
      end

      sl(node, :args, *params)
    end

    # Numbered parameters (Ruby 2.7+): _1, _2, etc.
    def visit_numbered_parameters_node(node)
      # This is handled specially in visit_block_node
      # Return count for :numblock
      node.maximum
    end

    # Helper to visit parameter lists (shared between def and block)
    def visit_parameters(params)
      result = []

      # Required parameters
      params.requireds&.each do |param|
        result << visit(param)
      end

      # Optional parameters
      params.optionals&.each do |param|
        result << visit(param)
      end

      # Rest parameter
      if params.rest && !params.rest.is_a?(Prism::ImplicitRestNode)
        result << visit(params.rest)
      end

      # Post-required parameters (after rest)
      params.posts&.each do |param|
        result << visit(param)
      end

      # Keyword parameters
      params.keywords&.each do |param|
        result << visit(param)
      end

      # Keyword rest parameter
      if params.keyword_rest
        result << visit(params.keyword_rest)
      end

      # Block parameter
      if params.block
        result << visit(params.block)
      end

      result
    end

    # Required parameter: def foo(a)
    def visit_required_parameter_node(node)
      sl(node, :arg, node.name)
    end

    # Optional parameter: def foo(a = 1)
    def visit_optional_parameter_node(node)
      sl(node, :optarg, node.name, visit(node.value))
    end

    # Rest parameter: def foo(*args)
    def visit_rest_parameter_node(node)
      if node.name
        sl(node, :restarg, node.name)
      else
        sl(node, :restarg)
      end
    end

    # Keyword parameter: def foo(a:) or def foo(a: 1)
    def visit_required_keyword_parameter_node(node)
      sl(node, :kwarg, node.name)
    end

    def visit_optional_keyword_parameter_node(node)
      sl(node, :kwoptarg, node.name, visit(node.value))
    end

    # Keyword rest parameter: def foo(**opts)
    def visit_keyword_rest_parameter_node(node)
      if node.name
        sl(node, :kwrestarg, node.name)
      else
        sl(node, :kwrestarg)
      end
    end

    # Block parameter: def foo(&block)
    def visit_block_parameter_node(node)
      if node.name
        sl(node, :blockarg, node.name)
      else
        sl(node, :blockarg)
      end
    end

    # Forwarding parameter: def foo(...)
    def visit_forwarding_parameter_node(node)
      sl(node, :forward_args)
    end

    # Implicit rest (for pattern matching)
    def visit_implicit_rest_node(node)
      nil
    end

    # Multi-target node for destructuring: (a, b) = [1, 2]
    def visit_multi_target_node(node)
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

      sl(node, :mlhs, *targets)
    end

    # Destructuring parameter in block: |a, (b, c)|
    def visit_required_destructured_parameter_node(node)
      params = []
      node.parameters.each do |param|
        params << visit(param)
      end
      sl(node, :mlhs, *params)
    end
  end
end
