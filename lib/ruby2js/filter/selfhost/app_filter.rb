# Selfhost App Filter - Transpiles config/ruby2js_filter.rb to JavaScript
#
# Transforms a filter written with the Ruby2JS filter DSL into a JavaScript
# filter class compatible with the selfhost runtime.
#
# Input (Ruby DSL):
#   filter :Writebook do
#     rewrite 'RQRCode::QRCode.new(_1).as_svg(_2)', to: '"<svg></svg>"'
#   end
#
# Output (JavaScript):
#   import { Filter, SEXP, s, registerFilter } from 'ruby2js';
#   class Writebook extends Filter.Processor {
#     on_send(node) {
#       // expanded pattern matching code
#     }
#   }
#   registerFilter("Writebook", Writebook.prototype);
#   export default Writebook;
#
# This filter is NOT added to DEFAULTS - it's loaded explicitly when
# transpiling app-specific filter files.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module AppFilter
        include SEXP

        def initialize(*args)
          super
          @app_filter_name = nil
          @app_filter_rewrites = []
          @app_filter_handlers = {}
        end

        # Detect filter(:Name) { ... } block and transform
        def on_block(node)
          send_node = node.children[0]
          block_args = node.children[1]
          block_body = node.children[2]

          # Match: filter(:Name) { ... }
          if send_node.type == :send && send_node.children[0].nil? &&
             send_node.children[1] == :filter && send_node.children[2]&.type == :sym
            @app_filter_name = send_node.children[2].children[0].to_s

            # Parse the block body for rewrites and handlers
            statements = block_body&.type == :begin ? block_body.children : [block_body].compact
            parse_dsl_body(statements)

            # Generate the output
            return generate_filter_output
          end

          super
        end

        private

        # Parse DSL statements: rewrite(...), on_send { }, etc.
        def parse_dsl_body(statements)
          statements.each do |stmt|
            next unless stmt

            if stmt.type == :send && stmt.children[0].nil? && stmt.children[1] == :rewrite
              parse_rewrite(stmt)
            elsif stmt.type == :block
              parse_handler_block(stmt)
            end
          end
        end

        # Parse: rewrite 'pattern', to: 'replacement'
        def parse_rewrite(node)
          args = node.children[2..]
          pattern_str = nil
          replacement_str = nil

          args.each do |arg|
            if arg.type == :str
              pattern_str = arg.children[0]
            elsif arg.type == :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]
                if key.type == :sym && key.children[0] == :to && value.type == :str
                  replacement_str = value.children[0]
                end
              end
            end
          end

          if pattern_str && replacement_str
            pattern_ast = Ruby2JS.parse(pattern_str).first
            replacement_ast = Ruby2JS.parse(replacement_str).first
            placeholders = collect_placeholders(pattern_ast)
            @app_filter_rewrites << {
              pattern: pattern_ast,
              replacement: replacement_ast,
              placeholders: placeholders
            }
          end
        end

        # Parse: on_send do |node| ... end
        def parse_handler_block(node)
          send_node = node.children[0]
          if send_node.type == :send && send_node.children[0].nil?
            handler_name = send_node.children[1]
            if [:on_send, :on_class, :on_block].include?(handler_name)
              @app_filter_handlers[handler_name] = {
                args: node.children[1],
                body: node.children[2]
              }
            end
          end
        end

        # Generate the complete filter output
        def generate_filter_output
          output = []

          # Import from ruby2js
          output << s(:import, 'ruby2js',
            [s(:const, nil, :Filter),
             s(:const, nil, :SEXP),
             s(:const, nil, :s),
             s(:const, nil, :registerFilter)])

          # Build class body
          class_body = []

          # Generate on_send method from rewrites + handler
          on_send = generate_on_send
          class_body << on_send if on_send

          # Generate on_class method from handler
          if @app_filter_handlers[:on_class]
            handler = @app_filter_handlers[:on_class]
            class_body << s(:def, :on_class,
              handler[:args],
              handler[:body])
          end

          # Generate on_block method from handler (the AST node type, not the DSL block)
          if @app_filter_handlers[:on_block]
            handler = @app_filter_handlers[:on_block]
            class_body << s(:def, :on_block,
              handler[:args],
              handler[:body])
          end

          # Build class
          filter_sym = @app_filter_name.to_sym
          filter_class = s(:class,
            s(:const, nil, filter_sym),
            s(:const, s(:const, nil, :Filter), :Processor),
            s(:begin, *class_body))
          output << filter_class

          # Copy SEXP to prototype
          output << s(:send, s(:const, nil, :Object), :defineProperties,
            s(:attr, s(:const, nil, filter_sym), :prototype),
            s(:send, s(:const, nil, :Object), :getOwnPropertyDescriptors,
              s(:const, nil, :SEXP)))

          # Register filter
          output << s(:send, nil, :registerFilter,
            s(:str, @app_filter_name),
            s(:attr, s(:const, nil, filter_sym), :prototype))

          # Export
          output << s(:export, :default, s(:const, nil, filter_sym))

          s(:begin, *output)
        end

        # Generate on_send method from rewrite rules and custom handler
        def generate_on_send
          return nil if @app_filter_rewrites.empty? && !@app_filter_handlers[:on_send]

          body_stmts = []

          # Destructure node
          body_stmts << s(:lvasgn, :target_method_args,
            s(:attr, s(:lvar, :node), :children))

          # Generate pattern match for each rewrite rule
          @app_filter_rewrites.each do |rule|
            condition = generate_match_condition(rule[:pattern], s(:lvar, :node))
            replacement = generate_replacement(rule[:replacement], rule[:pattern], s(:lvar, :node))
            body_stmts << s(:if, condition, s(:return, replacement), nil)
          end

          # Add custom handler body if present
          if @app_filter_handlers[:on_send]
            handler = @app_filter_handlers[:on_send]
            # Inline the handler body (it receives node as parameter)
            body_stmts << handler[:body]
          end

          # Fall through to super: this._parent.on_send.call(this, node)
          body_stmts << s(:return,
            s(:send,
              s(:attr, s(:attr, s(:self), :_parent), :on_send),
              :call, s(:self), s(:lvar, :node)))

          s(:def, :on_send,
            s(:args, s(:arg, :node)),
            s(:begin, *body_stmts))
        end

        # Generate a condition expression that matches a pattern against a node
        def generate_match_condition(pattern, target)
          if pattern.type == :send && pattern.children[0].nil? &&
             pattern.children[1].to_s =~ /\A_(\d+)\z/
            # Placeholder — always matches
            return s(:true)
          end

          conditions = []

          # Check type
          if pattern.respond_to?(:type)
            conditions << s(:send,
              s(:attr, target, :type),
              :===,
              s(:str, pattern.type.to_s))
          end

          # Check children
          pattern.children.each_with_index do |child, i|
            child_access = s(:send, s(:attr, target, :children), :[], s(:int, i))

            if child.nil?
              conditions << s(:send, child_access, :==, s(:nil))
            elsif child.is_a?(Symbol)
              conditions << s(:send, child_access, :===, s(:str, child.to_s))
            elsif child.respond_to?(:type)
              # Skip placeholders
              if child.type == :send && child.children[0].nil? &&
                 child.children[1].to_s =~ /\A_(\d+)\z/
                next
              end
              # Recurse for nested nodes
              conditions << generate_match_condition(child, child_access)
            else
              conditions << s(:send, child_access, :===, s(:str, child.to_s))
            end
          end

          # Also check children length
          conditions << s(:send,
            s(:attr, s(:attr, target, :children), :length),
            :===,
            s(:int, pattern.children.length))

          # Combine with &&
          conditions.reduce { |acc, cond| s(:and, acc, cond) }
        end

        # Generate a replacement expression, extracting placeholder bindings
        def generate_replacement(replacement, pattern, target)
          if replacement.type == :send && replacement.children[0].nil? &&
             replacement.children[1].to_s =~ /\A_(\d+)\z/
            placeholder = replacement.children[1]
            # Find where this placeholder is in the pattern and generate accessor
            return find_placeholder_access(pattern, placeholder, target)
          end

          # For non-placeholder replacements, check if any children reference placeholders
          has_placeholders = replacement_has_placeholders?(replacement)

          unless has_placeholders
            # Static replacement — return the AST directly as an s() call
            return ast_to_s_call(replacement)
          end

          # Dynamic replacement — build s() call with placeholder substitutions
          ast_to_s_call_with_bindings(replacement, pattern, target)
        end

        def replacement_has_placeholders?(node)
          return false unless node.respond_to?(:type)
          if node.type == :send && node.children[0].nil? &&
             node.children[1].to_s =~ /\A_(\d+)\z/
            return true
          end
          node.children.any? { |c| replacement_has_placeholders?(c) }
        end

        # Convert a static AST node to an s() constructor call
        def ast_to_s_call(node)
          return s(:nil) if node.nil?
          return s(:str, node.to_s) if node.is_a?(Symbol)

          unless node.respond_to?(:type)
            if node.is_a?(Integer)
              return s(:int, node)
            end
            return s(:str, node.to_s)
          end

          args = node.children.map { |c| ast_to_s_call(c) }
          s(:send, nil, :s, s(:str, node.type.to_s), *args)
        end

        # Convert AST to s() call, substituting placeholders with extracted values
        def ast_to_s_call_with_bindings(node, pattern, target)
          return s(:nil) if node.nil?
          return s(:str, node.to_s) if node.is_a?(Symbol)

          unless node.respond_to?(:type)
            if node.is_a?(Integer)
              return s(:int, node)
            end
            return s(:str, node.to_s)
          end

          # Check if this node is a placeholder
          if node.type == :send && node.children[0].nil? &&
             node.children[1].to_s =~ /\A_(\d+)\z/
            placeholder = node.children[1]
            return find_placeholder_access(pattern, placeholder, target)
          end

          args = node.children.map { |c| ast_to_s_call_with_bindings(c, pattern, target) }
          s(:send, nil, :s, s(:str, node.type.to_s), *args)
        end

        # Find the access path to a placeholder in the pattern tree
        def find_placeholder_access(pattern, placeholder, target, path = [])
          return nil unless pattern.respond_to?(:type)

          if pattern.type == :send && pattern.children[0].nil? &&
             pattern.children[1] == placeholder
            # Build accessor chain: target.children[i].children[j]...
            return build_accessor(target, path)
          end

          pattern.children.each_with_index do |child, i|
            next unless child.respond_to?(:type)
            result = find_placeholder_access(child, placeholder, target, path + [i])
            return result if result
          end

          nil
        end

        # Build a chain of .children[i] accessors
        def build_accessor(target, path)
          result = target
          path.each do |i|
            result = s(:send, s(:attr, result, :children), :[], s(:int, i))
          end
          result
        end

        # Collect placeholder symbols from a pattern AST
        def collect_placeholders(node)
          result = []
          return result unless node.respond_to?(:type)

          if node.type == :send && node.children[0].nil? &&
             node.children[1].to_s =~ /\A_(\d+)\z/
            result << node.children[1]
          end

          node.children.each do |child|
            result += collect_placeholders(child) if child.respond_to?(:type)
          end

          result
        end
      end
    end
  end
end
