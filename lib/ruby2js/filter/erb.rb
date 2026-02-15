require 'ruby2js'

module Ruby2JS
  module Filter
    module Erb
      include SEXP

      # Track instance variables found during AST traversal
      def initialize(*args)
        # Note: super must be called first for JS class compatibility
        super
        @erb_ivars = Set.new
        @erb_locals = Set.new      # Undefined local variables (used but not assigned)
        @erb_lvar_assigns = Set.new # Local variable assignments
        @erb_bufvar = nil
        @erb_needs_async = false   # Track if render function needs to be async
      end

      # Check if layout mode is enabled (options are set after initialize)
      def erb_layout_mode?
        @options && @options[:layout]
      end

      # Handle `def render` wrapping from ERB compiler output
      def on_def(node)
        method_name = node.children[0]
        def_args = node.children[1]
        def_body = node.children[2]

        # Only handle def render with no args whose body starts with buffer assignment
        return super unless method_name == :render
        return super unless def_args.children.empty?

        # The body should be a begin node wrapping the buffer statements
        return super unless def_body
        if def_body.type == :begin
          children = def_body.children
        else
          children = [def_body]
        end
        return super unless children.length >= 2

        first = children.first
        bufvar = nil
        if first.type == :lvasgn
          name = first.children.first
          if [:_erbout, :_buf].include?(name)
            bufvar = name
          end
        end

        return super unless bufvar

        process_erb_body(children, bufvar)
      end

      # Main entry point - detect ERB/HERB output patterns and transform
      # (kept for backward compatibility with hand-crafted ERB strings in tests)
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

        process_erb_body(children, bufvar)
      end

      # Handle yield in ERB mode
      # yield -> content (layout mode)
      # yield(:section) -> context.contentFor.section || ""
      def on_yield(node)
        return super unless @erb_bufvar

        args = node.children

        if args.empty?
          # yield -> content
          return s(:lvar, :content)
        end

        # yield(:section) -> context.contentFor.section || ""
        section = args.first
        if section.type == :sym
          section_name = section.children.first
          return s(:or,
            s(:attr,
              s(:attr, s(:lvar, :context), :contentFor),
              section_name),
            s(:str, ""))
        end

        super
      end

      # Hook for subclasses to indicate async is needed
      # Override in rails/helpers when async operations are detected
      def erb_needs_async?
        false
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

      # Convert instance variable assignments to local variable assignments
      # @scores = value -> scores = value
      def on_ivasgn(node)
        return super unless @erb_bufvar  # Only transform when in ERB mode
        ivar_name, value = node.children
        prop_name = ivar_name.to_s[1..-1].to_sym  # @scores -> scores
        s(:lvasgn, prop_name, process(value))
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

            # Check if inner expression needs special processing (e.g., turbo_stream.prepend)
            # before the normal String() wrapping
            if inner&.type == :send
              result = process_erb_send_append(inner)
              return result if result
            end

            arg = process(inner)
            # Skip String() wrapper if already a string literal or template literal
            unless arg&.type == :str || arg&.type == :dstr
              arg = s(:send, nil, :String, arg)
            end
          else
            # Handle non-block sends that need special processing
            if arg&.type == :send && method == :append=
              result = process_erb_send_append(arg)
              return result if result
            end
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
        # Delegate to filter chain (e.g., Rails::Helpers) via super
        defined?(super) ? super : nil
      end

      # Hook for subclasses to handle send expressions that produce buffer operations
      # (e.g., turbo_stream.prepend "photos", @photo)
      # Return processed AST or nil to fall through to default handling
      def process_erb_send_append(send_node)
        defined?(super) ? super : nil
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
        return super if defined?(super)
        nil
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

      # Mark that async is needed (for subclasses to call)
      def erb_mark_async!
        @erb_needs_async = true
      end

      private

      # Shared logic for processing ERB body from both on_begin and on_def
      def process_erb_body(children, bufvar)
        @erb_bufvar = bufvar

        # Step 1: Collect instance variables BEFORE transformation
        # (they get converted from @foo to foo by on_ivar)
        @erb_ivars = Set.new
        children.each { |child| collect_ivars(child) }

        # Step 2: Transform the body (this triggers all filters including helpers)
        transformed_children = children.map { |child| process(child) }

        # Step 2.5: Collapse consecutive buffer appends into single dstr
        transformed_children = collapse_buf_appends(transformed_children, bufvar)

        # Step 3: Let subclasses add imports via erb_prepend_imports hook
        # (must happen before we check imported names)
        erb_prepend_imports

        # Step 4: Collect undefined locals from TRANSFORMED AST
        # This runs after helper filters have processed their methods
        @erb_locals = Set.new
        @erb_lvar_assigns = Set.new
        transformed_body = s(:begin, *transformed_children)
        collect_locals(transformed_body)

        # Step 5: Get names that were imported (these are defined, not undefined locals)
        imported_names = collect_imported_names

        # Build the function body with autoreturn for the last expression
        body = s(:autoreturn, *transformed_children)

        # Layout mode: generate function layout(context, content) signature
        # yield becomes content, yield :section becomes context.contentFor.section
        if erb_layout_mode?()
          args = s(:args, s(:arg, :context), s(:arg, :content))
          return s(:def, :layout, args, body)
        end

        # Create parameter for the function - destructure ivars and undefined locals
        # Combine ivars (converted to names) and undefined locals
        all_params = []

        # Add ivars (strip @ prefix)
        [*@erb_ivars].sort.each do |ivar|
          prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
          all_params << prop_name
        end

        # Add undefined locals (used but not assigned and not imported)
        undefined_locals.each do |local|
          next if all_params.include?(local)
          next if imported_names.include?(local)
          all_params << local
        end

        # Allow subclasses to prepend extra kwargs (e.g., $context)
        # All args are now kwargs in a single destructured object
        extra_kwargs = erb_render_extra_args

        # Build unified kwargs list - extra first, then params
        all_kwargs = []

        # Add extra kwargs (e.g., $context)
        extra_kwargs.each do |kwarg|
          all_kwargs << kwarg
        end

        # Add params as kwargs (excluding any that are in extra)
        extra_kwarg_names = extra_kwargs.map { |kwarg| kwarg.children.first }
        all_params.each do |name|
          next if extra_kwarg_names.include?(name)
          all_kwargs << s(:kwarg, name)
        end

        if all_kwargs.empty?
          args = s(:args)
        else
          args = s(:args, *all_kwargs)
        end

        # Wrap in arrow function or regular function
        # Use async if any async operations were detected (e.g., association access)
        if @erb_needs_async || self.erb_needs_async?()
          s(:async, :render, args, body)
        else
          s(:def, :render, args, body)
        end
      end

      # Collect instance variables from the original AST (before transformation)
      def collect_ivars(node)
        return unless ast_node?(node)

        if node.type == :ivar
          @erb_ivars << node.children.first
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
          @erb_lvar_assigns << name
        elsif node.type == :lvar
          # Local variable read: article
          name = node.children.first
          # Skip the buffer variable itself
          unless name == @erb_bufvar
            @erb_locals << name
          end
        elsif node.type == :send && node.children.first.nil? && node.children.length == 2
          # Bare method call with no receiver and no arguments: likely a local variable reference
          # In ERB, article.title has article as s(:send, nil, :article) with 2 children
          # Calls like render(x) have 3+ children and should not be treated as locals
          name = node.children[1]
          name_str = name.to_s
          # Only track lowercase names that look like variables (not constants or keywords)
          if name_str =~ /\A[a-z_][a-z0-9_]*\z/
            @erb_locals << name
          end
        elsif [:args, :arg, :kwarg, :blockarg].include?(node.type)
          # Block/method arguments define local variables
          node.children.each do |child|
            # Note: check for string (JS) or symbol (Ruby) for dual compatibility
            if child.respond_to?(:to_s) && !ast_node?(child)
              @erb_lvar_assigns << child
            elsif ast_node?(child) && [:arg, :kwarg, :blockarg].include?(child.type)
              arg_name = child.children.first
              @erb_lvar_assigns << arg_name
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

      # Check if a node contains only buffer appends (safe to inline)
      # Returns true for op_asgn on bufvar, or begin blocks where all children are buf_only?
      def buf_only?(node, bufvar)
        return false unless ast_node?(node)

        if node.type == :op_asgn &&
           ast_node?(node.children[0]) &&
           node.children[0].type == :lvasgn &&
           node.children[0].children[0] == bufvar &&
           node.children[1] == :+
          return true
        end

        if node.type == :begin
          result = true
          node.children.each do |child|
            result = false unless buf_only?(child, bufvar)
          end
          return result
        end

        false
      end

      # Extract dstr parts from a buf-only node
      # Returns an array of :str and :begin nodes suitable for embedding in a :dstr
      def buf_to_dstr_parts(node, bufvar)
        parts = []

        if node.type == :op_asgn
          value = node.children[2]
          if value.type == :str
            parts << value
          elsif value.type == :dstr
            value.children.each { |c| parts.push(c) }
          else
            # Strip String() wrapper — template literal interpolation coerces
            if value.type == :send && value.children[0].nil? &&
               value.children[1] == :String && value.children.length == 3
              parts << s(:begin, value.children[2])
            else
              parts << s(:begin, value)
            end
          end
        elsif node.type == :begin
          node.children.each do |child|
            buf_to_dstr_parts(child, bufvar).each { |p| parts.push(p) }
          end
        end

        parts
      end

      # Check if a node is an inlineable :if (both branches are buf_only?)
      def inlineable_if?(node, bufvar)
        return false unless ast_node?(node) && node.type == :if
        cond = node.children[0]
        then_branch = node.children[1]
        else_branch = node.children[2]

        # Then branch must exist and be buf_only
        return false unless then_branch && buf_only?(then_branch, bufvar)

        # Else branch: either nil (if-without-else) or buf_only
        if else_branch
          buf_only?(else_branch, bufvar)
        else
          true
        end
      end

      # Check if a node is an inlineable .each block (body is buf_only?)
      def inlineable_each?(node, bufvar)
        return false unless ast_node?(node) && node.type == :for
        # :for nodes are [var, collection, body]
        body = node.children[2]
        body && buf_only?(body, bufvar)
      end

      # Check if a node can participate in a buf-append run
      def buf_append?(node, bufvar)
        return false unless ast_node?(node)

        # Direct buffer append
        if node.type == :op_asgn &&
           ast_node?(node.children[0]) &&
           node.children[0].type == :lvasgn &&
           node.children[0].children[0] == bufvar &&
           node.children[1] == :+
          return true
        end

        # Inlineable if/else or .each
        return true if inlineable_if?(node, bufvar)
        return true if inlineable_each?(node, bufvar)

        false
      end

      # Build dstr parts from a run element (op_asgn, inlineable if, or inlineable for)
      def run_to_dstr_parts(node, bufvar)
        if node.type == :op_asgn
          buf_to_dstr_parts(node, bufvar)
        elsif node.type == :if
          inline_if_to_dstr_part(node, bufvar)
        elsif node.type == :for
          inline_each_to_dstr_part(node, bufvar)
        else
          []
        end
      end

      # Convert an inlineable :if to a dstr part (ternary expression)
      def inline_if_to_dstr_part(node, bufvar)
        cond = node.children[0]
        then_branch = node.children[1]
        else_branch = node.children[2]

        then_parts = buf_to_dstr_parts(then_branch, bufvar)
        then_value = parts_to_value(then_parts)

        if else_branch
          else_parts = buf_to_dstr_parts(else_branch, bufvar)
          else_value = parts_to_value(else_parts)
        else
          else_value = s(:str, "")
        end

        [s(:begin, s(:if, cond, then_value, else_value))]
      end

      # Convert an inlineable :for to a dstr part (.map().join(""))
      def inline_each_to_dstr_part(node, bufvar)
        lvar = node.children[0]   # loop variable
        collection = node.children[1]  # collection
        body = node.children[2]   # loop body

        body_parts = buf_to_dstr_parts(body, bufvar)
        body_value = parts_to_value(body_parts)

        # Build: collection.map(lvar => body_value).join("")
        map_block = s(:block,
          s(:send, collection, :map),
          s(:args, s(:arg, lvar.children[0])),
          body_value)
        join_call = s(:send, map_block, :join, s(:str, ""))

        [s(:begin, join_call)]
      end

      # Convert dstr parts array to a single value (:str, :dstr, or unwrapped expression)
      def parts_to_value(parts)
        if parts.length == 1 && parts[0].type == :str
          parts[0]
        elsif parts.length == 1 && parts[0].type == :begin
          # Single expression — unwrap the :begin to avoid IIFE generation
          parts[0].children[0]
        else
          s(:dstr, *parts)
        end
      end

      # Recursively apply collapse_buf_appends to children of non-inlineable control flow
      def recursive_collapse(node, bufvar)
        return node unless ast_node?(node)

        if node.type == :if
          cond = node.children[0]
          then_branch = node.children[1]
          else_branch = node.children[2]

          then_branch = recursive_collapse_body(then_branch, bufvar) if then_branch
          else_branch = recursive_collapse_body(else_branch, bufvar) if else_branch

          s(:if, cond, then_branch, else_branch)
        elsif node.type == :for
          lvar = node.children[0]
          collection = node.children[1]
          body = node.children[2]

          body = recursive_collapse_body(body, bufvar) if body

          s(:for, lvar, collection, body)
        elsif node.type == :begin
          new_children = collapse_buf_appends([*node.children], bufvar)
          s(:begin, *new_children)
        else
          node
        end
      end

      # Collapse buf appends within a branch body (begin or single node)
      def recursive_collapse_body(node, bufvar)
        return node unless ast_node?(node)

        if node.type == :begin
          new_children = collapse_buf_appends([*node.children], bufvar)
          s(:begin, *new_children)
        else
          # Single statement — wrap in array, collapse, unwrap
          collapsed = collapse_buf_appends([node], bufvar)
          if collapsed.length == 1
            collapsed[0]
          else
            s(:begin, *collapsed)
          end
        end
      end

      # Collapse consecutive _buf += statements into a single dstr
      # Also inlines simple if/else as ternary and .each as .map().join("")
      def collapse_buf_appends(children, bufvar)
        result = []
        i = 0
        while i < children.length
          child = children[i]

          if buf_append?(child, bufvar)
            # Collect consecutive buffer appends (including inlineable control flow)
            run_start = i
            i += 1
            while i < children.length
              if buf_append?(children[i], bufvar)
                i += 1
              else
                break
              end
            end

            run = children[run_start...i]
            if run.length > 1
              # Build dstr parts from the run
              dstr_parts = []
              run.each do |node|
                run_to_dstr_parts(node, bufvar).each { |p| dstr_parts.push(p) }
              end

              # If all parts are :str, merge into a single :str
              all_str = true
              dstr_parts.each { |p| all_str = false unless ast_node?(p) && p.type == :str }
              if all_str
                merged = ""
                dstr_parts.each { |p| merged = merged + p.children[0] }
                result << s(:op_asgn, s(:lvasgn, bufvar), :+, s(:str, merged))
              else
                result << s(:op_asgn, s(:lvasgn, bufvar), :+, s(:dstr, *dstr_parts))
              end
            else
              # Single element — if it's inlineable control flow that's alone,
              # don't inline it (no benefit), but do recursively collapse its body
              if child.type == :if || child.type == :for
                result << recursive_collapse(child, bufvar)
              else
                result << child
              end
            end
          elsif child.type == :if || child.type == :for || child.type == :begin
            # Non-inlineable control flow — recursively collapse within
            result << recursive_collapse(child, bufvar)
            i += 1
          else
            result << child
            i += 1
          end
        end
        result
      end

      # Helper to get only undefined locals (used but not assigned)
      def undefined_locals
        @erb_locals.select { |local| !@erb_lvar_assigns.include?(local) }.sort
      end
    end

    DEFAULTS.push Erb
  end
end
