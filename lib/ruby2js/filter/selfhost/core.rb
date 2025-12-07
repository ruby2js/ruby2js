# frozen_string_literal: true

# Selfhost Core Filter - Universal transformations for self-hosting
#
# This filter handles transformations needed by ALL selfhost targets:
# - s(:sym, ...) → s('str', ...) - symbol to string for AST node types
# - node.type == :sym → node.type === 'str' - type comparisons
# - %i[...].include?(x) → ['...'].includes(x) - symbol arrays
# - Reserved word renaming (var → var_)
# - Remove private/protected/public (no-op in JS)
#
# Target-specific transformations are in separate filters:
# - selfhost/walker.rb - Prism::Visitor patterns
# - selfhost/converter.rb - handle :type do...end patterns
# - selfhost/spec.rb - minitest → JS test framework

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Core
        include SEXP

        # JavaScript reserved words that need renaming
        # Note: The core converter uses jsvar() with $ prefix for output,
        # but filters operate at AST level before that, so we use _ suffix
        JS_RESERVED_WORDS = %i[
          break case catch class const continue debugger default delete do else
          enum export extends false finally for function if import in instanceof
          new null return super switch this throw true try typeof var void while
          with yield let static implements interface package private protected public
        ].freeze

        def initialize(*args)
          super
          @selfhost_spec = false
        end

        def options=(options)
          super
          @selfhost_spec = options[:selfhost_spec]
        end

        # Rename reserved words: var → var_, class → class_, etc.
        def rename_var(name)
          return name unless name.is_a?(Symbol)
          JS_RESERVED_WORDS.include?(name) ? :"#{name}_" : name
        end

        # Handle local variable assignments - rename reserved words
        def on_lvasgn(node)
          name, value = node.children
          renamed = rename_var(name)
          if renamed != name
            node.updated(nil, [renamed, value ? process(value) : nil])
          else
            super
          end
        end

        # Handle local variable references - rename reserved words
        def on_lvar(node)
          name = node.children.first
          renamed = rename_var(name)
          renamed != name ? node.updated(nil, [renamed]) : super
        end

        # Handle argument names - rename reserved words
        def on_arg(node)
          name = node.children.first
          renamed = rename_var(name)
          renamed != name ? node.updated(nil, [renamed]) : super
        end

        def on_optarg(node)
          name, default = node.children
          renamed = rename_var(name)
          if renamed != name
            node.updated(nil, [renamed, process(default)])
          else
            super
          end
        end

        def on_kwarg(node)
          name = node.children.first
          renamed = rename_var(name)
          renamed != name ? node.updated(nil, [renamed]) : super
        end

        def on_kwoptarg(node)
          name, default = node.children
          renamed = rename_var(name)
          if renamed != name
            node.updated(nil, [renamed, process(default)])
          else
            super
          end
        end

        # Handle s(:type, ...) → s('type', ...) - symbol to string for AST construction
        def on_send(node)
          target, method, *args = node.children

          # s(:sym, ...) → s('str', ...)
          if target.nil? && method == :s && args.first&.type == :sym
            sym_node = args.first
            str_node = s(:str, sym_node.children.first.to_s)
            return process s(:send, nil, :s, str_node, *args[1..])
          end

          # node.type == :sym → node.type === 'str'
          if method == :== && args.length == 1 && args.first&.type == :sym
            if target&.type == :send && target.children[1] == :type
              sym = args.first.children.first
              return s(:send, process(target), :===, s(:str, sym.to_s))
            end
          end

          # %i[...].include?(x) where array is symbols → ['...'].includes(x)
          if method == :include? && target&.type == :array
            if target.children.all? { |c| c&.type == :sym }
              str_array = s(:array, *target.children.map { |c| s(:str, c.children.first.to_s) })
              return s(:send, str_array, :includes, *process_all(args))
            end
          end

          # Remove private/protected/public (no-op in JS)
          if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
            return s(:hide)
          end

          # Spec mode: remove gem() calls
          if @selfhost_spec && target.nil? && method == :gem
            return s(:hide)
          end

          # Spec mode: _(...) wrapper → just the inner expression
          if @selfhost_spec && target.nil? && method == :_ && args.length == 1
            return process(args.first)
          end

          super
        end
      end

      # Register the Core module - it's always loaded with selfhost
      DEFAULTS.push Core
    end
  end
end
