require 'ruby2js'

# Ink filter for Ruby2JS
#
# Transforms Ruby component classes into React functional components for Ink
# (React for CLIs). Unlike Phlex which can output strings or React, Ink always
# outputs React.createElement calls since that's what Ink requires.
#
# Architecture:
#   Ruby Ink component → React.createElement calls → Ink terminal UI
#
# Supported features:
# - Ink elements (Box, Text, Newline, Spacer, Static, Transform)
# - Ink ecosystem elements (TextInput, SelectInput, Spinner)
# - Static and dynamic props
# - Nested elements
# - Loops (@items.each { |item| ... })
# - Conditionals (if/unless)
# - Instance variables as destructured parameters
# - Key bindings DSL (keys return: :submit, up: :previous)
#
# Detection:
# - Classes inheriting from Ink::Component
# - Classes with `# @ruby2js ink` pragma (for indirect inheritance)

module Ruby2JS
  module Filter
    module Ink
      include SEXP

      # Core Ink elements (built into ink package)
      INK_ELEMENTS = %i[
        Box Text Newline Spacer Static Transform
      ].freeze

      # Ink ecosystem elements (from ink-* packages)
      INK_ECOSYSTEM_ELEMENTS = %i[
        TextInput SelectInput Spinner Link
      ].freeze

      ALL_ELEMENTS = (INK_ELEMENTS + INK_ECOSYSTEM_ELEMENTS).freeze

      # Key names that map to special key properties in Ink's useInput
      SPECIAL_KEYS = {
        return: 'return',
        enter: 'return',
        up: 'upArrow',
        down: 'downArrow',
        left: 'leftArrow',
        right: 'rightArrow',
        tab: 'tab',
        escape: 'escape',
        backspace: 'backspace',
        delete: 'delete',
        ctrl_c: 'ctrl_c',
        ctrl_d: 'ctrl_d'
      }.freeze

      def initialize(*args)
        @ink_context = false
        @ink_ivars = nil
        @ink_keys = nil
        super
      end

      # Detect Ink component class definition
      def on_class(node)
        name, parent, body = node.children

        if ink_component?(node, parent)
          @ink_context = true
          @ink_ivars = []
          @ink_keys = nil

          # Collect all instance variables used in the class
          collect_ivars(body)

          # Extract keys declaration if present
          extract_keys_declaration(body)

          # Build functional component
          result = build_functional_component(node, name, body)

          @ink_context = false
          @ink_ivars = nil
          @ink_keys = nil
          return result
        end

        super
      end

      # Handle element method calls (Box, Text, etc.)
      def on_send(node)
        return super unless @ink_context

        target, method, *args = node.children

        # Only handle calls with no receiver
        return super unless target.nil?

        # Handle Ink elements (with or without args)
        if ALL_ELEMENTS.include?(method)
          return create_element(method, args, nil, false)
        end

        # Handle keys declaration (keys return: :submit, up: :previous)
        if method == :keys && args.first&.type == :hash
          # Keys are extracted separately, skip here
          return nil
        end

        super
      end

      # Handle element calls with blocks (Box { Text { "hello" } })
      def on_block(node)
        return super unless @ink_context

        send_node, block_args, block_body = node.children
        return super unless send_node.type == :send

        target, method, *args = send_node.children

        # Handle Ink element with block
        if target.nil? && ALL_ELEMENTS.include?(method)
          return create_element(method, args, block_body, true)
        end

        super
      end

      # Handle bare element references (Spinner, Newline, etc.)
      def on_const(node)
        return super unless @ink_context

        parent, name = node.children

        # Only handle top-level constants that are Ink elements
        if parent.nil? && ALL_ELEMENTS.include?(name)
          return create_element(name, [], nil, false)
        end

        super
      end

      # Convert instance variable reads to prop access
      def on_ivar(node)
        return super unless @ink_context

        ivar_name = node.children.first
        prop_name = ivar_name.to_s[1..-1].to_sym  # @title -> title
        s(:lvar, prop_name)
      end

      # Handle conditionals
      def on_if(node)
        return super unless @ink_context

        condition, if_body, else_body = node.children

        processed_condition = process(condition)
        processed_if = if_body ? process(if_body) : nil
        processed_else = else_body ? process(else_body) : nil

        s(:if, processed_condition, processed_if, processed_else)
      end

      private

      # Check if this is an Ink component
      def ink_component?(node, parent)
        # Direct inheritance from Ink::Component
        return true if ink_parent?(parent)

        # Check for pragma: # @ruby2js ink
        has_ink_pragma?(node)
      end

      def ink_parent?(node)
        return false unless node
        return false unless node.type == :const

        parent, name = node.children

        # Ink::Component
        if parent&.type == :const && parent.children[0].nil? && parent.children[1] == :Ink
          return name == :Component
        end

        false
      end

      # Check for # @ruby2js ink pragma
      def has_ink_pragma?(node)
        return false unless @comments

        raw_comments = @comments.get(:_raw)
        raw_comments ||= []
        return false if raw_comments.empty?

        # Get the line number of the node
        line = nil
        if node.respond_to?(:loc) && node.loc
          loc = node.loc
          if loc.respond_to?(:expression) && loc.expression
            line = loc.expression.line
          elsif loc.respond_to?(:line)
            line = loc.line
          end
        end
        return false unless line

        # Check for @ruby2js ink comment on this line
        raw_comments.any? do |comment|
          comment_line = nil
          if comment.respond_to?(:loc) && comment.loc
            cloc = comment.loc
            if cloc.respond_to?(:expression) && cloc.expression
              comment_line = cloc.expression.line
            elsif cloc.respond_to?(:line)
              comment_line = cloc.line
            end
          end

          next false unless comment_line == line

          text = comment.respond_to?(:text) ? comment.text : comment.to_s
          text.match?(/@ruby2js\s+ink/i)
        end
      end

      # Recursively collect all instance variables in the AST
      def collect_ivars(node)
        return unless node.respond_to?(:type)

        if node.type == :ivar
          @ink_ivars << node.children.first
        end

        node.children.each do |child|
          collect_ivars(child) if child.respond_to?(:type)
        end
      end

      # Extract keys declaration from class body
      def extract_keys_declaration(body)
        return unless body

        methods = body.type == :begin ? body.children : [body]

        methods.each do |child|
          next unless child&.type == :send
          target, method, *args = child.children
          next unless target.nil? && method == :keys && args.first&.type == :hash

          @ink_keys = {}
          args.first.children.each do |pair|
            next unless pair.type == :pair
            key_node, handler_node = pair.children

            key = key_node.type == :sym ? key_node.children.first : key_node.children.first.to_sym
            handler = handler_node.type == :sym ? handler_node.children.first : handler_node.children.first

            @ink_keys[key] = handler
          end
        end
      end

      # Build a React functional component from the Ink class
      def build_functional_component(node, name, body)
        # Find the view_template method
        methods = body&.type == :begin ? body.children : [body].compact

        view_template = nil
        other_methods = []

        methods.each do |child|
          next unless child

          if child.type == :def
            method_name = child.children.first
            if [:view_template, :template, :render].include?(method_name)
              view_template = child
            elsif method_name != :initialize
              other_methods << child
            end
          elsif child.type == :send
            # Skip keys declaration
            target, method, *args = child.children
            next if target.nil? && method == :keys
          end
        end

        return super(node) unless view_template

        # Build the function
        func_name = name.children.last

        # Build destructured parameters from collected ivars
        if @ink_ivars && @ink_ivars.length > 0
          kwargs = @ink_ivars.uniq.sort.map do |ivar|
            prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
            s(:kwarg, prop_name)
          end
          func_args = s(:args, *kwargs)
        else
          func_args = s(:args)
        end

        # Process the view_template body
        _, _, template_body = view_template.children
        processed_body = process(template_body)

        # Build the function body
        body_statements = []

        # Add useInput hook if keys are defined
        if @ink_keys && @ink_keys.any?
          body_statements << build_use_input_hook
        end

        # Add handler methods as local functions
        other_methods.each do |method|
          method_name, method_args, method_body = method.children
          processed_method_body = process(method_body)
          body_statements << s(:def, method_name, method_args, processed_method_body)
        end

        # Add the return statement with the rendered content
        body_statements << s(:return, processed_body)

        func_body = body_statements.length == 1 ? body_statements.first : s(:begin, *body_statements)

        s(:def, func_name, func_args, func_body)
      end

      # Build useInput hook call for key bindings
      def build_use_input_hook
        # Build the callback body
        conditions = []

        @ink_keys.each do |key, handler|
          special_key = SPECIAL_KEYS[key]

          if special_key
            # Special key (return, upArrow, etc.)
            if special_key.include?('_')
              # Ctrl combinations: key.ctrl && input === 'c'
              parts = special_key.split('_')
              condition = s(:and,
                s(:send, s(:lvar, :key), parts[0].to_sym),
                s(:send, s(:lvar, :input), :===, s(:str, parts[1]))
              )
            else
              # Simple special key: key.return, key.upArrow, etc.
              condition = s(:send, s(:lvar, :key), special_key.to_sym)
            end
          else
            # Character key: input === 'q'
            condition = s(:send, s(:lvar, :input), :===, s(:str, key.to_s))
          end

          handler_call = s(:send, nil, handler)
          conditions << s(:if, condition, handler_call, nil)
        end

        callback_body = conditions.length == 1 ? conditions.first : s(:begin, *conditions)

        # Build arrow function: (input, key) => { ... }
        callback = s(:block,
          s(:send, nil, :proc),
          s(:args, s(:arg, :input), s(:arg, :key)),
          callback_body
        )

        # useInput(callback)
        s(:send, nil, :useInput, callback)
      end

      # Create a React.createElement call for an Ink element
      # has_block indicates whether this was called with a block (for proper children handling)
      def create_element(tag, args, block_body, has_block = true)
        # Extract props hash if present
        props_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }
        props = process_props(props_node)

        # Process children
        children = []
        if block_body
          children = extract_children(block_body)
        end

        # Build React.createElement(Ink.Box, props, ...children)
        # For Ink elements, we reference them directly (Box, Text, etc.)
        element_ref = s(:const, nil, tag)

        if children.empty?
          s(:send,
            s(:const, nil, :React),
            :createElement,
            element_ref,
            props
          )
        else
          s(:send,
            s(:const, nil, :React),
            :createElement,
            element_ref,
            props,
            *children
          )
        end
      end

      # Process props hash
      def process_props(props_node)
        return s(:nil) unless props_node

        processed_pairs = props_node.children.map do |pair|
          next pair unless pair.type == :pair
          key, value = pair.children
          s(:pair, process(key), process(value))
        end

        s(:hash, *processed_pairs)
      end

      # Extract and process children from a block body
      def extract_children(body)
        return [] unless body

        case body.type
        when :begin
          # Multiple statements - process each
          body.children.map { |child| process(child) }.compact
        when :str
          # Plain string - return as-is (React handles string children)
          [body]
        when :dstr
          # Interpolated string - process but don't wrap
          [process(body)]
        else
          # Single expression
          [process(body)]
        end
      end
    end

    # Note: Don't add to DEFAULTS - this is an opt-in filter
    # DEFAULTS.push Ink
  end
end
