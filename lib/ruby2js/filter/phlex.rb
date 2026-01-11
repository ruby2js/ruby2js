require 'ruby2js'

# Phlex filter for Ruby2JS
#
# Transforms Phlex component classes into JavaScript render functions.
# Elements are converted to pnodes which the converter renders as template literals.
#
# Architecture:
#   Phlex Ruby (div { }) → pnode → converter → template literal strings
#   If React filter is present: pnode → React filter → React.createElement
#
# This enables "write once, target both":
#   Ruby2JS.convert(source, filters: [:phlex])           → Phlex JS
#   Ruby2JS.convert(source, filters: [:phlex, :react])   → React JS
#
# Supported features:
# - HTML5 elements (void and standard)
# - Static and dynamic attributes
# - Nested elements
# - Loops (@items.each { |item| ... })
# - Conditionals (if/unless)
# - Instance variables as destructured parameters
# - Component composition (render Component.new)
# - Custom elements (tag("my-widget"))
# - Fragments (fragment { })
# - Special methods: plain, unsafe_raw, whitespace, comment, doctype
#
# Detection:
# - Classes inheriting from Phlex::HTML or Phlex::SVG
# - Classes with `# @ruby2js phlex` pragma (for indirect inheritance)

module Ruby2JS
  module Filter
    module Phlex
      include SEXP

      # HTML5 void elements (self-closing)
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ].freeze

      # Standard HTML5 elements
      HTML_ELEMENTS = %i[
        a abbr address article aside audio b bdi bdo blockquote body button
        canvas caption cite code colgroup data datalist dd del details dfn
        dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3
        h4 h5 h6 head header hgroup html i iframe ins kbd label legend li
        main map mark menu meter nav noscript object ol optgroup option
        output p picture pre progress q rp rt ruby s samp script section
        select slot small span strong style sub summary sup table tbody td
        template textarea tfoot th thead time title tr u ul var video
      ].freeze

      ALL_ELEMENTS = (VOID_ELEMENTS + HTML_ELEMENTS).freeze

      # Phlex special methods
      PHLEX_METHODS = %i[
        plain unsafe_raw whitespace comment doctype
      ].freeze

      def initialize(*args)
        @phlex_context = false
        @phlex_buffer = nil
        @phlex_ivars = nil
        @phlex_react_mode = false
        @phlex_lit_mode = false
        @phlex_astro_mode = false
        @phlex_vue_mode = false
        super
      end

      def options=(options)
        super
        # Detect framework filters for "write once, target both"
        filters = options[:filters] || Filter::DEFAULTS
        if defined?(Ruby2JS::Filter::React) && filters.include?(Ruby2JS::Filter::React)
          @phlex_react_mode = true
        end
        if defined?(Ruby2JS::Filter::Lit) && filters.include?(Ruby2JS::Filter::Lit)
          @phlex_lit_mode = true
        end
        if defined?(Ruby2JS::Filter::Astro) && filters.include?(Ruby2JS::Filter::Astro)
          @phlex_astro_mode = true
        end
        if defined?(Ruby2JS::Filter::Vue) && filters.include?(Ruby2JS::Filter::Vue)
          @phlex_vue_mode = true
        end
      end

      # Check if we're in a framework mode (React, Lit, Astro, or Vue)
      def phlex_framework_mode?
        @phlex_react_mode || @phlex_lit_mode || @phlex_astro_mode || @phlex_vue_mode
      end

      # Detect Phlex component class definition
      def on_class(node)
        name, parent, body = node.children

        # Check if this should be treated as a Phlex component
        if phlex_component?(node, parent)
          @phlex_context = true
          @phlex_ivars = []

          # Collect all instance variables used in the class
          collect_ivars(body)

          # When JSX filter is present, emit a function component instead of a class
          if @jsx
            result = build_function_component(node, name, body)
            @phlex_context = false
            @phlex_ivars = nil
            return result
          end

          result = super
          @phlex_context = false
          @phlex_ivars = nil
          return result
        end

        super
      end

      # Build a function component from a Phlex class
      def build_function_component(node, name, body)
        # Find and process the view_template/template method
        methods = body&.type == :begin ? body.children : [body].compact

        render_method = nil
        methods.each do |child|
          next unless child&.type == :def
          method_name = child.children.first
          if [:view_template, :template].include?(method_name)
            render_method = process(child)
            break
          end
        end

        return super(node) unless render_method

        # Extract the render method's args and body
        _, render_args, render_body = render_method.children

        # Create a function definition with the class name
        func_name = name.children.last
        s(:def, func_name, render_args, render_body)
      end

      # Handle method definitions within Phlex context
      def on_def(node)
        return super unless @phlex_context

        method_name, args, body = node.children

        # Transform view_template or template method to render
        if [:view_template, :template].include?(method_name)
          @phlex_buffer = :_phlex_out

          # Build destructured parameters from collected ivars
          if @phlex_ivars && @phlex_ivars.length > 0
            kwargs = @phlex_ivars.uniq.sort.map do |ivar|
              prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
              s(:kwarg, prop_name)
            end
            render_args = s(:args, *kwargs)
          else
            render_args = s(:args)
          end

          # Transform the body
          transformed_body = process(body)

          if phlex_framework_mode?
            # Framework mode (React/Lit): return pnodes directly (no buffer pattern)
            # The transformed_body contains pnodes wrapped in buffer ops - extract them
            new_body = build_framework_render_body(transformed_body)
          else
            # Buffer mode: wrap in buffer initialization and return
            init = s(:lvasgn, @phlex_buffer, s(:str, ''))
            ret = s(:return, s(:lvar, @phlex_buffer))

            new_body = if transformed_body
              s(:begin, init, transformed_body, ret)
            else
              s(:begin, init, ret)
            end
          end

          result = s(:def, :render, render_args, new_body)
          @phlex_buffer = nil
          return result
        end

        # Skip initialize method (ivars become render params instead)
        if method_name == :initialize
          return nil
        end

        super
      end

      # Convert instance variable reads to local variable reads
      def on_ivar(node)
        return super unless @phlex_buffer

        ivar_name = node.children.first
        prop_name = ivar_name.to_s[1..-1].to_sym  # @title -> title
        s(:lvar, prop_name)
      end

      # Handle element method calls
      def on_send(node)
        return super unless @phlex_buffer

        target, method, *args = node.children

        # Only handle calls with no receiver (element methods)
        return super unless target.nil?

        if ALL_ELEMENTS.include?(method)
          return create_element_pnode(method, args, nil)
        end

        if PHLEX_METHODS.include?(method)
          return process_phlex_method(method, args)
        end

        # Handle render Component.new(...) for component composition
        if method == :render && args.first&.type == :send
          component_call = args.first
          if component_call.children[1] == :new
            return create_component_pnode(component_call, nil)
          end
        end

        # Handle tag("custom-element", ...) for custom elements
        if method == :tag && args.first&.type == :str
          tag_name = args.first.children.first
          tag_args = args[1..-1]
          return create_custom_element_pnode(tag_name, tag_args, nil)
        end

        # Handle fragment (produces no output itself when called without block)
        if method == :fragment
          return nil
        end

        super
      end

      # Handle element calls with blocks (including loops)
      def on_block(node)
        return super unless @phlex_buffer

        send_node, block_args, block_body = node.children

        return super unless send_node.type == :send

        target, method, *args = send_node.children

        # Handle element with block (div { ... })
        if target.nil? && ALL_ELEMENTS.include?(method)
          return create_element_pnode(method, args, block_body)
        end

        # Handle render Component.new do ... end
        if target.nil? && method == :render && args.first&.type == :send
          component_call = args.first
          if component_call.children[1] == :new
            return create_component_pnode(component_call, block_body)
          end
        end

        # Handle tag("custom-element") do ... end
        if target.nil? && method == :tag && args.first&.type == :str
          tag_name = args.first.children.first
          tag_args = args[1..-1]
          return create_custom_element_pnode(tag_name, tag_args, block_body)
        end

        # Handle fragment do ... end
        if target.nil? && method == :fragment
          return create_fragment_pnode(block_body)
        end

        # For loops (.each, .map, etc.), let other filters handle the conversion
        # but ensure the body is processed for Phlex elements
        super
      end

      # Handle conditionals
      def on_if(node)
        return super unless @phlex_buffer

        # Process normally - Ruby2JS handles if/unless conversion
        # We just need to make sure the body is processed for elements
        condition, if_body, else_body = node.children

        processed_condition = process(condition)
        processed_if = if_body ? process(if_body) : nil
        processed_else = else_body ? process(else_body) : nil

        s(:if, processed_condition, processed_if, processed_else)
      end

      private

      def phlex_component?(node, parent)
        # Direct inheritance from Phlex::HTML or Phlex::SVG
        return true if self.phlex_parent?(parent)

        # Check for conventional Phlex directories
        return true if self.phlex_path?

        # Check for pragma: # Pragma: phlex
        self.has_phlex_pragma?(node)
      end

      # Check if file is in a conventional Phlex directory
      def phlex_path?
        file = @options[:file]
        return false unless file

        # app/components/*.rb - always Phlex
        return true if file.start_with?('app/components/') ||
          file.include?('/app/components/')

        # app/views/*.rb - Phlex (traditional views are .html.erb)
        return true if file.end_with?('.rb') &&
          (file.start_with?('app/views/') || file.include?('/app/views/'))

        false
      end

      # Check if a node has a Pragma: phlex comment on the same line
      def has_phlex_pragma?(node)
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

        # Check for Pragma: phlex comment on this line
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
          text.match?(/Pragma:\s*phlex/i)
        end
      end

      def phlex_parent?(node)
        return false unless node
        return false unless node.type == :const

        parent, name = node.children

        # Explicit: Phlex::HTML or Phlex::SVG
        if parent&.type == :const && parent.children[0].nil? && parent.children[1] == :Phlex
          return [:HTML, :SVG].include?(name)
        end

        # Convention: Top-level class ending in Component or View
        if parent.nil?
          name_str = name.to_s
          return true if name_str.end_with?('Component') || name_str.end_with?('View')
        end

        false
      end

      # Recursively collect all instance variables in the AST
      def collect_ivars(node)
        return unless node.respond_to?(:type)

        if node.type == :ivar
          @phlex_ivars << node.children.first
        end

        node.children.each do |child|
          collect_ivars(child) if child.respond_to?(:type)
        end
      end

      # Build render body for framework mode (React/Lit)
      def build_framework_render_body(transformed_body)
        return s(:return, s(:nil)) unless transformed_body

        # In framework mode, transformed_body contains raw pnodes (not buffer ops)
        pnodes = collect_pnodes(transformed_body)

        if pnodes.empty?
          s(:return, s(:nil))
        elsif pnodes.length == 1
          # Single element - process and return
          s(:return, process(pnodes.first))
        else
          # Multiple elements - wrap in fragment, then process
          fragment = s(:pnode, nil, s(:hash), *pnodes)
          s(:return, process(fragment))
        end
      end

      # Collect pnodes from transformed body (React mode - no buffer ops)
      def collect_pnodes(node)
        return [] unless node

        case node.type
        when :begin
          # Multiple statements - collect from each
          node.children.flat_map { |child| collect_pnodes(child) }
        when :pnode
          # Direct pnode
          [node]
        when :if
          # Conditional - keep as-is (React filter handles conditionals)
          [node]
        else
          # Other node types - keep as-is
          [node]
        end
      end

      # Create a pnode for an HTML element
      def create_element_pnode(tag, args, block_body)
        # Extract attributes hash if present
        attrs_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }
        attrs = process_attrs(attrs_node)

        # Process children
        children = []
        if block_body
          children = extract_children(block_body)
        end

        # Create pnode
        pnode = s(:pnode, tag, attrs, *children)

        if phlex_framework_mode?
          # Framework mode (React/Lit): return pnode directly (will be processed later)
          pnode
        else
          # Buffer mode: process and wrap in buffer operation
          processed = process(pnode)
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, processed)
        end
      end

      # Create a pnode for a component
      def create_component_pnode(component_call, block_body)
        component_const = component_call.children[0]
        component_name = component_const.children[1]
        component_args = component_call.children[2..-1] || []

        # Extract props hash
        props_hash = component_args.find { |a| a.respond_to?(:type) && a.type == :hash }
        attrs = process_attrs(props_hash)

        # Process children
        children = []
        if block_body
          children = extract_children(block_body)
        end

        # Create pnode with uppercase symbol for component
        pnode = s(:pnode, component_name, attrs, *children)

        if phlex_framework_mode?
          # Framework mode (React/Lit): return pnode directly
          pnode
        else
          # Buffer mode: process and wrap in buffer operation
          processed = process(pnode)
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, processed)
        end
      end

      # Create a pnode for a custom element
      def create_custom_element_pnode(tag_name, args, block_body)
        # Extract attrs hash
        attrs_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }
        attrs = process_attrs(attrs_node)

        # Process children
        children = []
        if block_body
          children = extract_children(block_body)
        end

        # Create pnode with string tag for custom element
        pnode = s(:pnode, tag_name, attrs, *children)

        if phlex_framework_mode?
          # Framework mode (React/Lit): return pnode directly
          pnode
        else
          # Buffer mode: process and wrap in buffer operation
          processed = process(pnode)
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, processed)
        end
      end

      # Create a pnode for a fragment
      def create_fragment_pnode(block_body)
        return nil unless block_body

        children = extract_children(block_body)
        return nil if children.empty?

        # Create fragment pnode (nil tag)
        pnode = s(:pnode, nil, s(:hash), *children)

        if phlex_framework_mode?
          # Framework mode (React/Lit): return pnode directly
          pnode
        else
          # Buffer mode: process and wrap in buffer operation
          processed = process(pnode)
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, processed)
        end
      end

      # Process attributes hash, converting ivars to lvars
      def process_attrs(attrs_node)
        return s(:hash) unless attrs_node&.type == :hash

        pairs = attrs_node.children.map do |pair|
          next pair unless pair.type == :pair

          key_node, value_node = pair.children

          # Process the value (converts ivars to lvars)
          processed_value = process(value_node)

          s(:pair, key_node, processed_value)
        end

        s(:hash, *pairs.compact)
      end

      # Extract children from block body and convert to pnode children
      def extract_children(node)
        return [] unless node

        children = []

        case node.type
        when :begin
          node.children.each do |child|
            extracted = extract_child_node(child)
            # Use push(*array) instead of concat for JS compatibility
            # (JS concat returns new array, Ruby concat mutates)
            children.push(*extracted) if extracted
          end
        else
          extracted = extract_child_node(node)
          children.push(*extracted) if extracted
        end

        children
      end

      # Convert a single node to pnode child(ren)
      def extract_child_node(node)
        return nil unless node

        case node.type
        when :str
          # String literal → pnode_text
          [s(:pnode_text, node)]
        when :dstr
          # Interpolated string → pnode_text with processed dstr
          [s(:pnode_text, process(node))]
        when :ivar
          # Instance variable → pnode_text with local var
          prop_name = node.children.first.to_s[1..-1].to_sym
          [s(:pnode_text, s(:lvar, prop_name))]
        when :lvar
          # Local variable → pnode_text
          [s(:pnode_text, node)]
        when :send
          target, method, *args = node.children
          if target.nil? && ALL_ELEMENTS.include?(method)
            # Nested element without block → nested pnode
            attrs_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }
            attrs = process_attrs(attrs_node)
            [s(:pnode, method, attrs)]
          elsif target.nil? && PHLEX_METHODS.include?(method)
            # Phlex method → process and wrap
            result = process_phlex_method(method, args)
            result ? [result] : []
          elsif target.nil? && method == :render
            # Component render → will be handled when block is processed
            [process(node)]
          else
            # Other expression → pnode_text with processed value
            [s(:pnode_text, process(node))]
          end
        when :block
          # Could be nested element with block or a loop
          send_node = node.children[0]
          if send_node.type == :send
            # Use direct indexing to avoid duplicate let declarations in JS
            block_target = send_node.children[0]
            block_method = send_node.children[1]
            block_args = send_node.children[2..-1]
            if block_target.nil? && ALL_ELEMENTS.include?(block_method)
              # Nested element with block → nested pnode with children
              block_body = node.children[2]
              attrs_node = block_args.find { |a| a.respond_to?(:type) && a.type == :hash }
              attrs = process_attrs(attrs_node)
              nested_children = extract_children(block_body)
              [s(:pnode, block_method, attrs, *nested_children)]
            elsif block_target.nil? && block_method == :fragment
              # Fragment → children only (no wrapper)
              block_body = node.children[2]
              extract_children(block_body)
            else
              # Other block (loop, etc.) → process normally
              [process(node)]
            end
          else
            [process(node)]
          end
        when :if
          # Conditional → process normally (will contain buffer operations)
          [process(node)]
        else
          # Other node types → process and add as expression
          [process(node)]
        end
      end

      def process_phlex_method(method, args)
        case method
        when :plain
          # plain "text" or plain variable → pnode_text
          arg = args.first
          if arg
            processed = process(arg)
            s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
              s(:send, nil, :String, processed))
          end
        when :unsafe_raw
          # unsafe_raw "html" → add directly without String()
          arg = args.first
          if arg
            s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, process(arg))
          end
        when :whitespace
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, s(:str, ' '))
        when :comment
          arg = args.first
          if arg
            if arg.type == :str
              text = arg.children.first
              s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
                s(:str, "<!-- #{text} -->"))
            else
              s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
                s(:dstr,
                  s(:str, '<!-- '),
                  s(:begin, process(arg)),
                  s(:str, ' -->')))
            end
          end
        when :doctype
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:str, '<!DOCTYPE html>'))
        end
      end
    end

    DEFAULTS.push Phlex
  end
end
