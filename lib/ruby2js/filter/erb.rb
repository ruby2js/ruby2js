require 'ruby2js'

module Ruby2JS
  module Filter
    module Erb
      include SEXP

      # Track instance variables found during AST traversal
      def initialize(*args)
        # Note: super must be called first for JS class compatibility
        super
        # Note: use Array instead of Set for JS compatibility (Set doesn't have push)
        @erb_ivars = []
        @erb_locals = []      # Undefined local variables (used but not assigned)
        @erb_lvar_assigns = [] # Local variable assignments
        @erb_bufvar = nil
      end

      # Main entry point - detect ERB/HERB output patterns and transform
      def on_begin(node)
        # Check if this looks like ERB/HERB output:
        # - First statement assigns to _erbout or _buf
        # - Last statement returns the buffer
        children = node.children
        return super unless children.length >= 2

        first = children.first

        # Detect buffer variable assignment
        bufvar = nil
        if first.type == :lvasgn
          name = first.children.first
          if [:_erbout, :_buf].include?(name)
            bufvar = name
          end
        end

        return super unless bufvar
        @erb_bufvar = bufvar

        # Collect all instance variables and undefined locals used in the template
        # Note: use Array instead of Set for JS compatibility
        @erb_ivars = []
        @erb_locals = []
        @erb_lvar_assigns = []
        collect_vars(node)

        # Transform the body, converting ivars to property access on 'data' param
        transformed_children = children.map { |child| process(child) }

        # Build the function body with autoreturn for the last expression
        body = s(:autoreturn, *transformed_children)

        # Create parameter for the function - destructure ivars and undefined locals
        # Combine ivars (converted to names) and undefined locals
        all_params = []

        # Add ivars (strip @ prefix)
        @erb_ivars.uniq.sort.each do |ivar|
          prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
          all_params << prop_name
        end

        # Add undefined locals (used but not assigned in template)
        undefined_locals.uniq.sort.each do |local|
          all_params << local unless all_params.include?(local)
        end

        if all_params.empty?
          args = s(:args)
        else
          kwargs = all_params.map { |name| s(:kwarg, name) }
          args = s(:args, *kwargs)
        end

        # Subclasses can add imports via erb_prepend_imports hook
        erb_prepend_imports

        # Wrap in arrow function or regular function
        s(:def, :render, args, body)
      end

      # Hook for subclasses to add imports - override in rails/helpers
      def erb_prepend_imports
        # Base implementation does nothing
      end

      # Convert instance variable reads to local variable reads
      def on_ivar(node)
        return super unless @erb_bufvar  # Only transform when in ERB mode
        ivar_name = node.children.first
        prop_name = ivar_name.to_s[1..-1].to_sym  # @title -> title
        s(:lvar, prop_name)
      end

      # Handle buffer initialization: _erbout = +''; or _buf = ::String.new
      def on_lvasgn(node)
        name, value = node.children
        return super unless @erb_bufvar && [:_erbout, :_buf].include?(name)

        # Convert to simple empty string assignment: let _erbout = ""
        s(:lvasgn, name, s(:str, ""))
      end

      # Handle buffer concatenation: _erbout.<< "str" or _erbout.<<(expr)
      # Also handle _buf.append= for block expressions from Ruby2JS::Erubi
      def on_send(node)
        target, method, *args = node.children

        # Check if this is buffer concatenation via << or append=
        if @erb_bufvar && target&.type == :lvar &&
           target.children.first == @erb_bufvar &&
           (method == :<< || method == :append=)

          arg = args.first

          # Handle block attached to append= (e.g., form_for do |f| ... end)
          # Subclasses can handle specific block helpers
          if arg&.type == :block && method == :append=
            result = process_erb_block_append(arg)
            return result if result
          end

          # Skip nil args (shouldn't happen after above handling)
          return nil if arg.nil? && method == :append=

          # Handle .freeze calls - strip them
          if arg&.type == :send && arg.children[1] == :freeze
            arg = arg.children[0]
          end

          # Handle .to_s calls
          if arg&.type == :send && arg.children[1] == :to_s
            inner = arg.children[0]
            # Remove unnecessary parens from ((expr))
            while inner&.type == :begin && inner.children.length == 1
              inner = inner.children.first
            end
            arg = process(inner)
            # Skip String() wrapper if already a string literal
            unless arg&.type == :str
              arg = s(:send, nil, :String, arg)
            end
          else
            arg = process(arg) if arg
          end

          # Convert to += concatenation
          return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, arg)
        end

        # Strip .freeze calls
        if method == :freeze && args.empty? && target
          return process(target)
        end

        # Strip .to_s calls on buffer (final return)
        if method == :to_s && args.empty? && target&.type == :lvar &&
           target.children.first == @erb_bufvar
          return process(target)
        end

        # Handle html_safe - just return the receiver (no-op in JavaScript)
        # "string".html_safe -> "string"
        if method == :html_safe && args.empty? && target
          return process(target)
        end

        # Handle raw() helper - returns the argument as-is (no-op in JavaScript)
        # raw(html) -> html
        if method == :raw && target.nil? && args.length == 1
          return process(args.first)
        end

        super
      end

      # Hook for subclasses to handle block helpers (form_for, etc.)
      # Returns nil if not handled, or processed AST if handled
      def process_erb_block_append(block_node)
        nil  # Base implementation doesn't handle any block helpers
      end

      # Handle block expressions - subclasses can override for specific helpers
      def on_block(node)
        return super unless @erb_bufvar

        send_node = node.children[0]
        block_args = node.children[1]
        block_body = node.children[2]

        # Check if this is _buf.append= with a block helper call
        if send_node.type == :send
          target, method, helper_call = send_node.children

          if target&.type == :lvar && target.children.first == @erb_bufvar &&
             method == :append= && helper_call&.type == :send

            result = process_erb_block_helper(helper_call, block_args, block_body)
            return result if result
          end
        end

        super
      end

      # Hook for subclasses to handle block helpers
      def process_erb_block_helper(helper_call, block_args, block_body)
        nil  # Base implementation doesn't handle any block helpers
      end

      # Convert final buffer reference to return statement
      def on_lvar(node)
        name = node.children.first
        return super unless @erb_bufvar && name == @erb_bufvar

        # Check if this is the final expression (return value)
        # For now just return the variable as-is, the function will implicitly return it
        super
      end

      # Accessor for subclasses
      def erb_bufvar
        @erb_bufvar
      end

      private

      # Recursively collect all instance variables and undefined locals in the AST
      def collect_vars(node)
        return unless ast_node?(node)

        # Note: avoid case/when for JS compatibility (variable declarations in case blocks
        # cause TDZ errors). Use if/elsif instead.
        if node.type == :ivar
          # Instance variable: @article
          @erb_ivars.push(node.children.first)
        elsif node.type == :lvasgn
          # Local variable assignment: article = ...
          name = node.children.first
          @erb_lvar_assigns.push(name) unless @erb_lvar_assigns.include?(name)
        elsif node.type == :lvar
          # Local variable read: article
          name = node.children.first
          # Skip the buffer variable itself
          unless name == @erb_bufvar
            @erb_locals.push(name) unless @erb_locals.include?(name)
          end
        elsif node.type == :send && node.children.first.nil?
          # Method call with no receiver: article.something or just article
          # In ERB partials, these are often locals passed from the parent
          name = node.children[1]
          # Only track if it looks like a local variable (lowercase, no args beyond the method chain)
          # Skip common Rails helpers and keywords
          # Note: use string skip list for JS compatibility (symbols become strings in JS)
          skip_names = %w[render link_to form_with form_for form_tag
                          pluralize truncate content_for notice raw
                          String Array Hash Integer Float]
          name_str = name.to_s
          # Skip path helpers (e.g., new_article_path, articles_path)
          # Note: use combined condition for JS compatibility (no 'next' in if/elsif)
          if name_str =~ /\A[a-z_][a-z0-9_]*\z/ && !skip_names.include?(name_str) && !name_str.end_with?('_path')
            @erb_locals.push(name) unless @erb_locals.include?(name)
          end
        elsif [:args, :arg, :kwarg, :blockarg].include?(node.type)
          # Block/method arguments define local variables
          node.children.each do |child|
            # Note: check for string (JS) or symbol (Ruby) for dual compatibility
            if child.respond_to?(:to_s) && !ast_node?(child)
              @erb_lvar_assigns.push(child) unless @erb_lvar_assigns.include?(child)
            elsif ast_node?(child) && [:arg, :kwarg, :blockarg].include?(child.type)
              arg_name = child.children.first
              @erb_lvar_assigns.push(arg_name) unless @erb_lvar_assigns.include?(arg_name)
            end
          end
        end

        node.children.each do |child|
          collect_vars(child) if ast_node?(child)
        end
      end

      # Helper to get only undefined locals (called after collect_vars completes)
      def undefined_locals
        @erb_locals.select { |local| !@erb_lvar_assigns.include?(local) }
      end
    end

    DEFAULTS.push Erb
  end
end
