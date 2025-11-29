# frozen_string_literal: true

# selfhost filter - transforms Ruby2JS internals for JavaScript execution
#
# This filter handles patterns specific to Ruby2JS's own codebase:
# - s(:type, ...) → s('type', ...) - symbol to string for AST node types
# - node.type == :str → node.type === 'str' - symbol comparisons
# - handle :type do ... end → handler registration
# - class Foo < Prism::Visitor → class with self-dispatch visit() method
#
# This is NOT a general-purpose filter. It's specifically designed
# for transpiling Ruby2JS itself to JavaScript.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      include SEXP

      # Track if we're inside a Prism::Visitor subclass
      def initialize(*args)
        super
        @prism_visitor_class = false
      end

      # Transform Prism::Visitor subclass
      # - Remove inheritance
      # - Add self-dispatch visit() method
      # - Remove user-defined visit method (we generate our own)
      def on_class(node)
        name, superclass, body = node.children

        # Check for < Prism::Visitor
        if superclass&.type == :const &&
           superclass.children[0]&.type == :const &&
           superclass.children[0].children[1] == :Prism &&
           superclass.children[1] == :Visitor

          @prism_visitor_class = true

          # Filter out user-defined visit method before processing
          # (we generate our own self-dispatch visit method)
          if body&.type == :begin
            filtered_children = body.children.reject do |child|
              child&.type == :def && child.children[0] == :visit
            end
            body = s(:begin, *filtered_children)
          elsif body&.type == :def && body.children[0] == :visit
            body = nil
          end

          # Process body
          processed_body = process(body)

          # Create self-dispatch visit method for JS:
          # visit(node) {
          #   if (!node) return null;
          #   const method = this[`visit${node.constructor.name}`];
          #   return method ? method.call(this, node) : null;
          # }
          #
          # We use :attr for property access (not method calls) to get:
          #   node.constructor.name  (not node.constructor().name())
          visit_method = s(:def, :visit, s(:args, s(:arg, :node)),
            s(:begin,
              # if (!node) return null;
              s(:if, s(:send, s(:lvar, :node), :!),
                s(:return, s(:nil)), nil),
              # const method = this[`visit${node.constructor.name}`];
              s(:lvasgn, :method,
                s(:send, s(:self), :[],
                  s(:dstr,
                    s(:str, 'visit'),
                    s(:begin, s(:attr, s(:attr, s(:lvar, :node), :constructor), :name))))),
              # return method ? method.call(this, node) : null;
              s(:return,
                s(:if, s(:lvar, :method),
                  s(:send, s(:lvar, :method), :call, s(:self), s(:lvar, :node)),
                  s(:nil)))))

          # Add visit method to body
          if processed_body&.type == :begin
            new_body = s(:begin, visit_method, *processed_body.children)
          elsif processed_body
            new_body = s(:begin, visit_method, processed_body)
          else
            new_body = visit_method
          end

          @prism_visitor_class = false

          # Return class without superclass
          return s(:class, name, nil, new_body)
        end

        super
      end

      # Convert visit_*_node method names to camelCase (visitIntegerNode)
      # to match @ruby/prism constructor names
      def on_def(node)
        method_name, args, body = node.children

        # Check for visit_*_node pattern
        if method_name.to_s.start_with?('visit_') && method_name.to_s.end_with?('_node')
          # Convert snake_case to camelCase: visit_integer_node → visitIntegerNode
          camel_name = method_name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
          return s(:def, camel_name, process(args), process(body))
        end

        super
      end

      # Remove super() calls inside Prism::Visitor subclasses
      # (since there's no superclass in the generated JS)
      def on_super(node)
        return nil if @prism_visitor_class
        super
      end

      def on_zsuper(node)
        return nil if @prism_visitor_class
        super
      end

      # Also handle singleton methods (def self.foo)
      def on_defs(node)
        target, method_name, args, body = node.children

        if method_name.to_s.start_with?('visit_') && method_name.to_s.end_with?('_node')
          camel_name = method_name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
          return s(:defs, process(target), camel_name, process(args), process(body))
        end

        super
      end

      # Convert symbols to strings in s() calls
      # s(:send, ...) → s('send', ...)
      def on_send(node)
        target, method, *args = node.children

        # Handle s(:type, ...) calls - convert symbol to string
        if target.nil? && method == :s && args.first&.type == :sym
          sym_node = args.first
          str_node = s(:str, sym_node.children.first.to_s)
          return process s(:send, nil, :s, str_node, *process_all(args[1..]))
        end

        # Handle sl(:type, ...) calls - same pattern
        if target.nil? && method == :sl && args.length >= 2 && args[1]&.type == :sym
          # sl(node, :type, ...) → sl(node, 'type', ...)
          first_arg = process(args[0])
          sym_node = args[1]
          str_node = s(:str, sym_node.children.first.to_s)
          return process s(:send, nil, :sl, first_arg, str_node, *process_all(args[2..]))
        end

        # Handle node.type == :sym comparisons
        # node.type == :str → node.type === 'str'
        if method == :== && args.length == 1 && args.first&.type == :sym
          if target&.type == :send && target.children[1] == :type
            sym = args.first.children.first
            return s(:send, process(target), :===, s(:str, sym.to_s))
          end
        end

        # Handle %i(...).include?(node.type) patterns
        # %i(send csend).include?(node.type) → ['send', 'csend'].includes(node.type)
        if method == :include? && target&.type == :array
          # Check if target is an array of symbols
          if target.children.all? { |c| c.type == :sym }
            str_array = s(:array, *target.children.map { |c| s(:str, c.children.first.to_s) })
            return s(:send, str_array, :includes, *process_all(args))
          end
        end

        super
      end

      # Convert handle :type do ... end to handler registration
      # handle :send do |target, method, *args| ... end
      # → this.handle('send', function(target, method, ...args) { ... })
      def on_block(node)
        call, block_args, body = node.children

        if call.type == :send && call.children[0].nil? && call.children[1] == :handle
          types = call.children[2..]

          # Convert symbols to strings
          type_strs = types.map do |t|
            if t.type == :sym
              s(:str, t.children.first.to_s)
            else
              process(t)
            end
          end

          # Process block args
          processed_args = process(block_args)
          processed_body = process(body)

          # Generate: types.forEach(type => this.handle(type, (args) => body))
          if type_strs.length == 1
            return s(:send, s(:self), :handle, type_strs.first,
                     s(:block, s(:send, nil, :proc), processed_args, processed_body))
          else
            # Multiple types: handle('type1', handler); handle('type2', handler)
            handler = s(:block, s(:send, nil, :proc), processed_args, processed_body)
            return s(:begin, *type_strs.map { |t| s(:send, s(:self), :handle, t, handler) })
          end
        end

        super
      end

      # Convert case node.type; when :str patterns
      def on_case(node)
        expr, *whens, else_body = node.children

        # Check if this is a case on node.type
        if expr&.type == :send && expr.children[1] == :type
          new_whens = whens.map do |when_node|
            conditions, body = when_node.children[0...-1], when_node.children.last

            # Convert symbol conditions to strings
            new_conditions = conditions.map do |cond|
              if cond.type == :sym
                s(:str, cond.children.first.to_s)
              else
                process(cond)
              end
            end

            s(:when, *new_conditions, process(body))
          end

          return s(:case, process(expr), *new_whens, else_body ? process(else_body) : nil)
        end

        super
      end
    end

    DEFAULTS.push Selfhost
  end
end

