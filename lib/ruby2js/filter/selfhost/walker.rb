# frozen_string_literal: true

# Selfhost Walker Filter - Transformations specific to PrismWalker transpilation
#
# This filter handles the API differences between Ruby's Prism gem and the
# JavaScript @ruby/prism package when transpiling the PrismWalker to JS.
#
# ## Prism Ruby vs JavaScript API Differences
#
# The JavaScript @ruby/prism package uses different naming conventions:
#
# 1. **Property names are camelCase** (Ruby: snake_case)
#    - Ruby: `node.opening_loc` → JS: `node.openingLoc`
#    - Ruby: `node.start_offset` → JS: `node.startOffset`
#
# 2. **Reserved words are suffixed with underscore**
#    - Ruby: `node.arguments` → JS: `node.arguments_`
#    (because `arguments` is reserved in JavaScript)
#
# 3. **`unescaped` returns an object in JS**
#    - Ruby: `node.unescaped` returns a String
#    - JS: `node.unescaped` returns `{encoding, validEncoding, value}`
#    - We transform: `node.unescaped` → `node.unescaped.value`
#
# 4. **Visitor method names are camelCase**
#    - Ruby: `visit_program_node` → JS: `visitProgramNode`
#
# ## Other Transformations
#
# - Remove `private`/`protected`/`public` (no-op in JS, and Ruby2JS errors on them)
#
# ## General Transformations (in other filters)
#
# - Functions filter: .freeze, .to_sym, .reject, negative index, 2-arg slice, .empty?
# - Pragma filter: # Pragma: skip for require/def/alias
# - Return filter: autoreturn for method bodies

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Walker
        include SEXP

        # Convert visit_*_node method names to camelCase visit*Node
        # JavaScript Prism.Visitor expects visitProgramNode, visitIntegerNode, etc.
        def on_def(node)
          method_name = node.children[0]

          if method_name.to_s.start_with?('visit_') && method_name.to_s.end_with?('_node')
            # Convert visit_program_node -> visitProgramNode
            camel_name = method_name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
            return process node.updated(nil, [camel_name, *node.children[1..]])
          end

          super
        end

        # Prism Ruby API to JS API PROPERTY name mapping (snake_case -> camelCase)
        # These are accessed as properties without parentheses in JS
        PRISM_PROPERTY_MAP = {
          # Location properties
          :opening_loc => :openingLoc,
          :closing_loc => :closingLoc,
          :message_loc => :messageLoc,
          :name_loc => :nameLoc,
          :operator_loc => :operatorLoc,
          :call_operator_loc => :callOperatorLoc,
          :constant_path => :constantPath,
          :start_offset => :startOffset,
          :end_offset => :endOffset,
          :start_line => :startLine,
          :end_line => :endLine,
          # Node properties
          :left_parenthesis => :leftParenthesis,
          :right_parenthesis => :rightParenthesis,
          :opening => :opening,
          :closing => :closing,
          # Call/write node properties
          :read_name => :readName,
          :write_name => :writeName,
          :binary_operator => :binaryOperator,
          # Reserved word renames in JS
          :arguments => :arguments_,
        }.freeze

        # Prism Ruby API to JS API METHOD name mapping
        # These are methods in JS Prism and need to be called with ()
        PRISM_METHOD_MAP = {
          :safe_navigation? => :isSafeNavigation,
          :exclude_end? => :isExcludeEnd,
        }.freeze

        def on_send(node)
          target, method, *args = node.children

          # Remove private/protected/public (no-op in JS)
          # Ruby2JS core raises an error for these in classes, but walker source uses them
          if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
            return s(:hide)
          end

          # JS Prism locations have {startOffset, length} not {startOffset, endOffset}
          # Transform .end_offset to (.startOffset + .length)
          if method == :end_offset && args.empty? && target
            processed_target = process target
            # Build: target.startOffset + target.length
            start_access = s(:attr, processed_target, :startOffset)
            length_access = s(:attr, processed_target, :length)
            return s(:send, start_access, :+, length_access)
          end

          # Convert Prism Ruby property names to JS camelCase equivalents
          # Note: end_offset is handled specially above (needs calculation in JS Prism)
          # Use :attr for property access without arguments (no parentheses in JS)
          if PRISM_PROPERTY_MAP.key?(method) && method != :end_offset
            js_method = PRISM_PROPERTY_MAP[method]
            if args.empty? && target
              # Property access - use :attr to avoid parentheses
              return process s(:attr, target, js_method)
            else
              return process node.updated(nil, [target, js_method, *args])
            end
          end

          # Convert Prism Ruby method names to JS method names
          # These are methods that need to be called with parentheses in JS
          # e.g., node.safe_navigation? -> node.isSafeNavigation()
          if PRISM_METHOD_MAP.key?(method) && args.empty? && target
            js_method = PRISM_METHOD_MAP[method]
            # Use :call to force parentheses in output (Ruby2JS treats :call as method call)
            return process node.updated(:call, [target, js_method])
          end

          # node.unescaped -> node.unescaped.value (JS Prism returns {encoding, value} object)
          if method == :unescaped && args.empty? && target
            # Process target first, then wrap with .value access
            # Use :attr for property access (no parens) instead of :send (method call)
            processed_target = process target
            unescaped_access = s(:attr, processed_target, :unescaped)
            return s(:attr, unescaped_access, :value)
          end

          super
        end

        # Transform property names in 'in?' checks (from respond_to? -> "prop" in obj)
        # Ruby: node.respond_to?(:message_loc) -> JS functions filter -> :message_loc in node
        # The property name needs to be converted from snake_case to camelCase
        def on_in?(node)
          left, right = node.children

          # Check if left is a symbol that needs camelCase conversion
          if left.type == :sym && PRISM_PROPERTY_MAP.key?(left.children[0])
            js_prop = PRISM_PROPERTY_MAP[left.children[0]]
            return process node.updated(nil, [s(:sym, js_prop), right])
          end

          super
        end
      end

      # Register Walker module
      DEFAULTS.push Walker
    end
  end
end
