# Support for HAML template compilation to JavaScript render functions.
#
# Transforms compiled HAML template output into JavaScript render functions.
# Similar to the ERB filter, converts instance variables to destructured
# parameters.
#
# Example HAML:
#   %h1= @title
#   %p= @content
#
# Compiles to Ruby (HAML 6+):
#   _buf = ''.dup
#   _buf << "<h1>".freeze
#   _haml_compiler1 = (@title; ; )
#   _buf << ((::Haml::Util.escape_html(_haml_compiler1)).to_s)
#   _buf << "</h1>\n<p>".freeze
#   ...
#   _buf
#
# This filter transforms it to JavaScript:
#   function render({ title, content }) {
#     let _buf = "";
#     _buf += "<h1>";
#     _buf += String(title);
#     _buf += "</h1>\n<p>";
#     ...
#     return _buf
#   }

require 'ruby2js'

module Ruby2JS
  module Filter
    module Haml
      include SEXP

      def initialize(*args)
        @haml_ivars = Set.new
        @haml_bufvar = nil
        super
      end

      # Main entry point - detect HAML output patterns and transform
      def on_begin(node)
        children = node.children
        return super unless children.length >= 2

        first = children.first
        bufvar = nil

        # Detect HAML buffer initialization: _buf = ''.dup or _buf = ::String.new
        if first.type == :lvasgn
          name = first.children.first
          value = first.children[1]

          if name == :_buf
            if value&.type == :send
              # ''.dup pattern
              if value.children[0]&.type == :str &&
                 value.children[0].children[0] == '' &&
                 value.children[1] == :dup
                bufvar = :_buf
              # ::String.new pattern
              elsif value.children[1] == :new &&
                    value.children[0] == s(:const, s(:cbase), :String)
                bufvar = :_buf
              end
            end
          end
        end

        return super unless bufvar
        @haml_bufvar = bufvar

        # Collect all instance variables used in the template
        @haml_ivars = Set.new
        collect_ivars(node)

        # Transform the body
        transformed_children = children.map { |child| process(child) }

        # Build the function body with autoreturn
        body = s(:autoreturn, *transformed_children)

        # Create destructuring parameters for instance variables
        if @haml_ivars.empty?
          args = s(:args)
        else
          # Use splat to array for JS Set compatibility (Set#to_a doesn't exist in JS)
          kwargs = [*@haml_ivars].sort.map do |ivar|
            prop_name = ivar.to_s[1..-1].to_sym
            s(:kwarg, prop_name)
          end
          args = s(:args, *kwargs)
        end

        s(:def, :render, args, body)
      end

      # Convert instance variable reads to local variable reads
      def on_ivar(node)
        return super unless @haml_bufvar
        ivar_name = node.children.first
        prop_name = ivar_name.to_s[1..-1].to_sym
        s(:lvar, prop_name)
      end

      # Handle buffer initialization
      def on_lvasgn(node)
        name, value = node.children
        return super unless @haml_bufvar && name == :_buf

        # Convert to simple empty string assignment
        s(:lvasgn, :_buf, s(:str, ""))
      end

      # Handle buffer concatenation and HAML-specific patterns
      def on_send(node)
        target, method, *args = node.children

        # Handle buffer concatenation: _buf << "str" or _buf.<<(expr)
        if @haml_bufvar && target&.type == :lvar &&
           target.children.first == @haml_bufvar && method == :<<

          arg = args.first
          return nil unless arg

          # Unwrap all HAML-specific wrappers in a loop
          changed = true
          while changed
            changed = false

            # Handle .freeze calls
            if arg.type == :send && arg.children[1] == :freeze && arg.children[2..-1].empty?
              arg = arg.children[0]
              changed = true
            end

            # Handle .to_s calls
            if arg.type == :send && arg.children[1] == :to_s && arg.children[2..-1].empty?
              arg = arg.children[0]
              changed = true
            end

            # Remove parens wrapper (begin node with single child)
            while arg&.type == :begin && arg.children.length == 1
              arg = arg.children.first
              changed = true
            end

            # Handle ::Haml::Util.escape_html() wrapper
            if arg.type == :send && arg.children[1] == :escape_html &&
               arg.children[0] == s(:const, s(:const, s(:cbase), :Haml), :Util)
              arg = arg.children[2]
              changed = true
            end
          end

          # Process the final argument
          arg = process(arg) if arg

          # Skip nil args
          return nil unless arg

          # Wrap non-strings in String()
          unless arg.type == :str
            arg = s(:send, nil, :String, arg)
          end

          # Convert to += concatenation
          return s(:op_asgn, s(:lvasgn, @haml_bufvar), :+, arg)
        end

        # Strip .freeze calls
        if method == :freeze && args.empty? && target
          return process(target)
        end

        # Strip .to_s calls on buffer (final return)
        if method == :to_s && args.empty? && target&.type == :lvar &&
           target.children.first == @haml_bufvar
          return process(target)
        end

        # Handle HAML temp variable assignments with multiple statements
        # _haml_compiler1 = (@title; ; ) -> just @title
        super
      end

      # Handle final buffer reference
      def on_lvar(node)
        name = node.children.first
        return super unless @haml_bufvar && name == @haml_bufvar
        super
      end

      private

      # Recursively collect all instance variables in the AST
      def collect_ivars(node)
        return unless Ruby2JS.ast_node?(node)

        if node.type == :ivar
          @haml_ivars << node.children.first
        end

        node.children.each do |child|
          collect_ivars(child) if Ruby2JS.ast_node?(child)
        end
      end
    end

    DEFAULTS.push Haml
  end
end
