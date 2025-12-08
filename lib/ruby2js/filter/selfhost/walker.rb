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

        # Prism Ruby API to JS API property name mapping (snake_case -> camelCase)
        # Note: Some properties are renamed in JS due to reserved words (arguments -> arguments_)
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
          # Reserved word renames in JS
          :arguments => :arguments_,
        }.freeze

        def on_send(node)
          target, method, *args = node.children

          # Remove private/protected/public (no-op in JS)
          # Ruby2JS core raises an error for these in classes, but walker source uses them
          if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
            return s(:hide)
          end

          # Convert Prism Ruby property names to JS camelCase equivalents
          if PRISM_PROPERTY_MAP.key?(method)
            js_method = PRISM_PROPERTY_MAP[method]
            return process node.updated(nil, [target, js_method, *args])
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
      end

      # Register Walker module
      DEFAULTS.push Walker
    end
  end
end
