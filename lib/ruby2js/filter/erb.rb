require 'ruby2js'

module Ruby2JS
  module Filter
    module Erb
      include SEXP

      # Track instance variables found during AST traversal
      def initialize(*args)
        @erb_ivars = Set.new
        @erb_bufvar = nil
        @erb_block_var = nil  # Track current block variable (e.g., 'f' in form_for)
        super
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

        # Collect all instance variables used in the template
        @erb_ivars = Set.new
        collect_ivars(node)

        # Transform the body, converting ivars to property access on 'data' param
        transformed_children = children.map { |child| process(child) }

        # Build the function body with autoreturn for the last expression
        body = s(:autoreturn, *transformed_children)

        # Create parameter for the function - destructure ivars from object
        if @erb_ivars.empty?
          args = s(:args)
        else
          # Create destructuring pattern: { title, content }
          kwargs = @erb_ivars.to_a.sort.map do |ivar|
            prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
            s(:kwarg, prop_name)
          end
          args = s(:args, *kwargs)
        end

        # Wrap in arrow function or regular function
        s(:def, :render, args, body)
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
          # This is handled in on_block, so just return nil here to skip
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
            # Convert to string using template literal or String()
            arg = s(:send, nil, :String, arg)
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

        super
      end

      # Handle block expressions like form_for, which produce:
      # _buf.append= form_for @user do |f| ... end
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

            helper_name = helper_call.children[1]

            # Handle form_for and similar block helpers
            if helper_name == :form_for
              return process_form_for(helper_call, block_args, block_body)
            end

            # Generic block helper - just process the body
            # This handles link_to with blocks, content_tag, etc.
            return process_block_helper(helper_name, helper_call, block_args, block_body)
          end
        end

        super
      end

      # Convert final buffer reference to return statement
      def on_lvar(node)
        name = node.children.first
        return super unless @erb_bufvar && name == @erb_bufvar

        # Check if this is the final expression (return value)
        # For now just return the variable as-is, the function will implicitly return it
        super
      end

      private

      # Process form_for block into JavaScript
      # Generates a form tag and processes the block body with a form builder
      def process_form_for(helper_call, block_args, block_body)
        # Extract the model from form_for @model
        model_node = helper_call.children[2]
        model_name = model_node.children.first.to_s.delete_prefix('@') if model_node&.type == :ivar

        # Get the block parameter name (usually 'f')
        block_param = block_args.children.first&.children&.first

        # Track the block variable so we can handle f.text_field, etc.
        old_block_var = @erb_block_var
        @erb_block_var = block_param

        # Build the form output
        statements = []

        # Add opening form tag
        form_attrs = model_name ? " data-model=\"#{model_name}\"" : ""
        statements << s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                       s(:str, "<form#{form_attrs}>"))

        # Process block body
        if block_body
          if block_body.type == :begin
            block_body.children.each do |child|
              processed = process(child)
              statements << processed if processed
            end
          else
            processed = process(block_body)
            statements << processed if processed
          end
        end

        # Add closing form tag
        statements << s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                       s(:str, "</form>"))

        @erb_block_var = old_block_var

        # Return a begin node with all statements
        s(:begin, *statements.compact)
      end

      # Process generic block helpers
      def process_block_helper(helper_name, helper_call, block_args, block_body)
        # Get the block parameter if any
        block_param = block_args.children.first&.children&.first

        old_block_var = @erb_block_var
        @erb_block_var = block_param

        statements = []

        # Process block body
        if block_body
          if block_body.type == :begin
            block_body.children.each do |child|
              processed = process(child)
              statements << processed if processed
            end
          else
            processed = process(block_body)
            statements << processed if processed
          end
        end

        @erb_block_var = old_block_var

        return nil if statements.empty?
        statements.length == 1 ? statements.first : s(:begin, *statements.compact)
      end

      # Recursively collect all instance variables in the AST
      def collect_ivars(node)
        return unless Ruby2JS.ast_node?(node)

        if node.type == :ivar
          @erb_ivars << node.children.first
        end

        node.children.each do |child|
          collect_ivars(child) if Ruby2JS.ast_node?(child)
        end
      end
    end

    DEFAULTS.push Erb
  end
end
