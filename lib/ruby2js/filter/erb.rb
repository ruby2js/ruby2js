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

        # Step 1: Collect instance variables BEFORE transformation
        # (they get converted from @foo to foo by on_ivar)
        @erb_ivars = []
        collect_ivars(node)

        # Step 2: Transform the body (this triggers all filters including helpers)
        transformed_children = children.map { |child| process(child) }

        # Step 3: Let subclasses add imports via erb_prepend_imports hook
        # (must happen before we check imported names)
        erb_prepend_imports

        # Step 4: Collect undefined locals from TRANSFORMED AST
        # This runs after helper filters have processed their methods
        @erb_locals = []
        @erb_lvar_assigns = []
        transformed_body = s(:begin, *transformed_children)
        collect_locals(transformed_body)

        # Step 5: Get names that were imported (these are defined, not undefined locals)
        imported_names = collect_imported_names

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

        # Add undefined locals (used but not assigned and not imported)
        undefined_locals.each do |local|
          next if all_params.include?(local)
          next if imported_names.include?(local)
          all_params << local
        end

        # Allow subclasses to prepend extra args (e.g., $context)
        extra = erb_render_extra_args

        if all_params.empty?
          kwargs = []
        else
          kwargs = all_params.map { |name| s(:kwarg, name) }
        end
        if extra.empty? && kwargs.empty?
          args = s(:args)
        elsif extra.empty?
          args = s(:args, *kwargs)
        elsif kwargs.empty?
          args = s(:args, *extra)
        else
          args = s(:args, *extra, *kwargs)
        end

        # Wrap in arrow function or regular function
        s(:def, :render, args, body)
      end

      # Hook for subclasses to add imports - override in rails/helpers
      def erb_prepend_imports
        # Base implementation does nothing
      end

      # Hook for subclasses to add extra render args - override in rails/helpers
      def erb_render_extra_args
        # Base implementation returns no extra args
        []
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

      # Collect instance variables from the original AST (before transformation)
      def collect_ivars(node)
        return unless ast_node?(node)

        if node.type == :ivar
          @erb_ivars.push(node.children.first)
        end

        node.children.each do |child|
          collect_ivars(child) if ast_node?(child)
        end
      end

      # Collect local variable usage and assignments from transformed AST
      # This runs AFTER helper filters have processed, so helper calls are already
      # transformed and won't appear as undefined locals
      def collect_locals(node)
        return unless ast_node?(node)

        # Note: avoid case/when for JS compatibility (variable declarations in case blocks
        # cause TDZ errors). Use if/elsif instead.
        if node.type == :lvasgn
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
          # Method call with no receiver: could be a local variable reference
          # In ERB, article.title has article as s(:send, nil, :article)
          name = node.children[1]
          name_str = name.to_s
          # Only track lowercase names that look like variables (not constants or keywords)
          if name_str =~ /\A[a-z_][a-z0-9_]*\z/
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
          collect_locals(child) if ast_node?(child)
        end
      end

      # Extract imported names from prepend_list
      # These are names that helper filters have imported, so they're defined
      def collect_imported_names
        names = []
        list = self.prepend_list
        return names unless list

        list.each do |node|
          next unless ast_node?(node) && node.type == :import

          # Import node structures:
          # 1. Named: s(:import, path, s(:const, nil, :name))
          # 2. Named array: s(:import, path, [s(:const, nil, :name1), ...])
          # 3. Namespace: s(:import, [s(:pair, :as, s(:const, nil, :name)), s(:pair, :from, path)], '*')
          first_child = node.children[0]
          second_child = node.children[1]

          # Handle namespace imports: import * as name from "..."
          # Structure: s(:import, [as_pair, from_pair], '*')
          if first_child.is_a?(Array)
            first_child.each do |pair|
              next unless ast_node?(pair) && pair.type == :pair
              key = pair.children[0]
              value = pair.children[1]
              if ast_node?(key) && key.type == :sym && key.children[0] == :as
                if ast_node?(value) && value.type == :const
                  names << value.children[1]
                end
              end
            end
          # Handle named imports: s(:import, path, names)
          elsif ast_node?(second_child)
            if second_child.type == :const
              names << second_child.children[1]
            elsif second_child.type == :array
              second_child.children.each do |child|
                names << child.children[1] if ast_node?(child) && child.type == :const
              end
            end
          elsif second_child.is_a?(Array)
            second_child.each do |child|
              names << child.children[1] if ast_node?(child) && child.type == :const
            end
          end
        end

        names
      end

      # Helper to get only undefined locals (used but not assigned)
      def undefined_locals
        @erb_locals.select { |local| !@erb_lvar_assigns.include?(local) }.uniq.sort
      end
    end

    DEFAULTS.push Erb
  end
end
