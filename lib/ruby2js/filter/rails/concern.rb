require 'ruby2js'
require_relative 'active_record'

module Ruby2JS
  module Filter
    module Rails
      module Concern
        include SEXP

        # Bare sends that should NOT get self. prefix in concerns.
        # These are globals, constructors, or framework references.
        CONCERN_SELF_EXCEPTIONS = %i[
          require require_relative puts print p pp raise fail
          Array Hash String Integer Float
          lambda proc loop
        ].freeze

        # ActiveRecord instance methods that are always method calls, never
        # property accesses. For csend (safe navigation) nodes with these
        # methods, we strip source location so the converter emits ().
        AR_MUTATION_METHODS = %i[
          destroy destroy! save save! delete reload reload! touch
          increment! decrement!
        ].freeze

        def initialize(*args)
          super
          @rails_concern = nil
        end

        def on_module(node)
          return super if @rails_concern

          name = node.children.first
          body = node.children[1..-1]

          # Flatten begin wrapper
          while body.length == 1 && body.first&.type == :begin
            body = body.first.children
          end

          # Detect: is there an `extend ActiveSupport::Concern`?
          has_concern = body.any? { |n| concern_extend?(n) }
          return super unless has_concern

          @rails_concern = true
          @concern_enum_bangs = {}

          # Transform body
          new_body = transform_concern_body(body)

          # Force the IIFE path in the module converter by adding a public marker.
          # This ensures concerns use underscored_private (@x -> this._x) instead of
          # ES2022 private fields (#x) which are invalid in object literals.
          # The module converter omits bare public markers from output.
          # Also mark as concern so module converter makes zero-arg methods getters.
          unless new_body.empty?
            new_body.unshift(s(:send, nil, :public))
            new_body.unshift(s(:send, nil, :__concern__))
          end

          # Rebuild module with cleaned body
          if new_body.empty?
            new_body_node = nil
          elsif new_body.length == 1
            new_body_node = new_body.first
          else
            new_body_node = s(:begin, *new_body)
          end

          result = node.updated(nil, [name, new_body_node])

          # Record concern metadata for cross-file filter context
          if @options[:metadata]
            concern_name = name.children.last.to_s
            meta = @options[:metadata]
            meta['concerns'] = {} unless meta['concerns']

            # Collect method names from transformed body
            method_names = []
            new_body.each do |n|
              if n.respond_to?(:type) && n.type == :def
                method_names.push(n.children[0].to_s)
              end
            end

            meta['concerns'][concern_name] = { 'methods' => method_names }
          end

          @rails_concern = nil
          super(result)
        end

        private

        # Detect: s(:send, nil, :extend, s(:const, s(:const, nil, :ActiveSupport), :Concern))
        def concern_extend?(node)
          return false unless node.respond_to?(:type)
          node.type == :send &&
            node.children[0].nil? &&
            node.children[1] == :extend &&
            node.children[2]&.type == :const &&
            node.children[2].children[1] == :Concern &&
            node.children[2].children[0]&.type == :const &&
            node.children[2].children[0].children[1] == :ActiveSupport
        end

        def transform_concern_body(body)
          result = []
          host_names = []  # Names from included do block (associations, scopes)
          @has_one_names = []  # Track has_one association names for loaded-flag checks

          body.each do |node|
            next unless node.respond_to?(:type)

            case node.type
            when :send
              if node.children[0].nil?
                case node.children[1]
                when :extend
                  # Strip extend ActiveSupport::Concern (and any other extend)
                  next if concern_extend?(node)
                  result << node

                when :attr_accessor
                  # Transform to getter + setter def pairs
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, attr, s(:args),
                      s(:ivar, :"@#{attr}"))
                    result << s(:def, :"#{attr}=", s(:args, s(:arg, :val)),
                      s(:ivasgn, :"@#{attr}", s(:lvar, :val)))
                  end

                when :attr_reader
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, attr, s(:args),
                      s(:ivar, :"@#{attr}"))
                  end

                when :attr_writer
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, :"#{attr}=", s(:args, s(:arg, :val)),
                      s(:ivasgn, :"@#{attr}", s(:lvar, :val)))
                  end

                when :alias_method
                  new_name = node.children[2].children.first
                  old_name = node.children[3].children.first

                  # Strip if names differ only by ?/! suffix
                  new_base = new_name.to_s.sub(/[?!]$/, '')
                  old_base = old_name.to_s.sub(/[?!]$/, '')
                  unless new_base == old_base
                    result << s(:def, new_name, s(:args),
                      s(:send, nil, old_name))
                  end

                when :delegate
                  # Strip delegate calls
                  next

                when :private, :public, :protected
                  # Keep visibility markers (bare ones with no args)
                  if node.children.length == 2
                    result << node
                  end
                  # Skip visibility with specific method names (e.g., private :foo)

                when :include
                  # Strip include calls in concerns — framework modules
                  # (e.g., ActionView::Helpers::TagHelper) don't exist in JS.
                  # The including class handles its own includes.
                  next

                else
                  # Keep other send nodes
                  result << node
                end
              else
                result << node
              end

            when :block
              # Strip included do...end and class_methods do...end
              if node.children[0].type == :send &&
                 node.children[0].children[0].nil? &&
                 [:included, :class_methods].include?(node.children[0].children[1])
                # Extract association/scope names before stripping
                extract_included_names(node, host_names)
                next
              end
              result << node

            when :def, :defs
              # Keep method definitions
              result << node

            else
              # Keep everything else (begin, class, module, etc.)
              result << node
            end
          end

          # Rewrite bare method calls in concern methods to use self. prefix.
          # In Ruby, any s(:send, nil, :name) is an implicit self call. In JS
          # concerns (IIFEs), these must be explicit this. so they resolve on
          # the host model prototype after mixing.
          result.map! do |n|
            if n.respond_to?(:type) && (n.type == :def || n.type == :defs)
              rewrite_concern_sends(n)
            else
              n
            end
          end

          result
        end

        # Extract association and scope names from the included do...end block
        def extract_included_names(block_node, names)
          block_body = block_node.children[2]
          return unless block_body

          children = block_body.type == :begin ? block_body.children : [block_body]
          children.each do |child|
            next unless child.respond_to?(:type) && child.type == :send
            method = child.children[1]
            case method
            when :has_many, :has_one, :belongs_to
              # First arg is association name symbol
              if child.children[2]&.type == :sym
                assoc_name = child.children[2].children[0]
                names << assoc_name
                @has_one_names.push(assoc_name) if method == :has_one
              end
            when :scope
              # First arg is scope name symbol
              if child.children[2]&.type == :sym
                names << child.children[2].children[0]
              end
            when :enum
              # enum :status, ... — extract the attribute name and values
              if child.children[2]&.type == :sym
                enum_field = child.children[2].children[0]
                names << enum_field
                # Extract enum value names for bang method inlining
                @concern_enum_bangs ||= {}
                extract_concern_enum_values(child, enum_field)
              end
            end
          end
        end

        # Extract enum value names from an enum declaration for bang method inlining.
        # enum :status, %w[drafted published].index_by(&:itself)
        # enum :status, { drafted: "drafted", published: "published" }
        def extract_concern_enum_values(enum_node, field)
          # Try to find value names from the third arg (after :enum, :field)
          values_node = enum_node.children[3]
          return unless values_node

          value_names = []
          if values_node.type == :hash
            # { drafted: "drafted", published: "published" }
            values_node.children.each do |pair|
              next unless pair.type == :pair
              key = pair.children[0]
              val = pair.children[1]
              name = key.type == :sym ? key.children[0].to_s : key.children[0].to_s
              value_names.push([name, field, val])
            end
          elsif values_node.type == :send && values_node.children[1] == :index_by
            # %w[drafted published].index_by(&:itself) — extract from array
            arr = values_node.children[0]
            if arr.type == :array
              arr.children.each do |el|
                name = el.type == :str ? el.children[0] : el.children[0].to_s
                value_names.push([name, field, s(:str, name)])
              end
            end
          end

          value_names.each do |name, fld, val|
            @concern_enum_bangs[:"#{name}!"] = { field: fld, value: val }
          end
        end

        # Rewrite bare sends in a def node to use self. prefix
        def rewrite_concern_sends(node)
          # Collect local variable names (params + assignments) to avoid rewriting
          locals = collect_locals(node)

          # Rewrite the method body (children[2] for def, children[3] for defs)
          if node.type == :def
            name, args, body = node.children
            return node unless body
            method_name = name.to_s.sub(/[?!=]$/, '')
            new_body = rewrite_node(body, locals, method_name)
            node.updated(nil, [name, args, new_body])
          elsif node.type == :defs
            target, name, args, body = node.children
            return node unless body
            method_name = name.to_s.sub(/[?!=]$/, '')
            new_body = rewrite_node(body, locals, method_name)
            node.updated(nil, [target, name, args, new_body])
          else
            node
          end
        end

        # Collect local variable names from a def node
        def collect_locals(node)
          locals = []

          # Add parameter names
          args_node = node.type == :def ? node.children[1] : node.children[2]
          if args_node
            args_node.children.each do |arg|
              next unless arg.respond_to?(:children)
              case arg.type
              when :arg, :optarg, :kwarg, :kwoptarg, :restarg, :kwrestarg, :blockarg
                locals << arg.children[0] if arg.children[0]
              end
            end
          end

          # Walk body to find local variable assignments
          body = node.type == :def ? node.children[2] : node.children[3]
          collect_lvasgn(body, locals) if body

          locals
        end

        # Recursively find lvasgn nodes to track local variables
        def collect_lvasgn(node, locals)
          return unless node.respond_to?(:type)

          if node.type == :lvasgn
            locals << node.children[0]
          end

          node.children.each do |child|
            collect_lvasgn(child, locals) if child.respond_to?(:type)
          end
        end

        # Recursively rewrite bare sends to use self. prefix.
        # In concerns, ALL s(:send, nil, :name) are implicit self calls
        # that must become this.name for prototype mixing to work.
        def rewrite_node(node, locals, method_name = nil)
          return node unless node.respond_to?(:type)

          # Handle super/zsuper in concern methods.
          # In Rails, super on an attribute method returns the raw DB value.
          # In concerns (IIFEs), there's no class hierarchy for super to call.
          # Rewrite to this.attributes["method_name"] for raw attribute access.
          if method_name && (node.type == :zsuper || node.type == :super)
            return s(:send,
              s(:attr, s(:self), :attributes),
              :[],
              s(:send, s(:str, method_name), :to_s))
          end

          # Handle .present? / .blank? / .nil? on bare sends (association checks).
          # closure.present? → check if association is loaded and non-null
          # Must intercept before the functions filter converts .present? to ?.length > 0.
          if node.type == :send && [:present?, :blank?, :nil?].include?(node.children[1])
            receiver = node.children[0]
            if receiver&.respond_to?(:type) && receiver.type == :send && receiver.children[0].nil?
              method = receiver.children[1]
              unless locals.include?(method) || CONCERN_SELF_EXCEPTIONS.include?(method)
                # has_one associations use a loaded flag because the getter returns
                # a HasOneReference proxy (truthy object) when not loaded.
                # present? → this._X_loaded && this._X != null
                # blank?/nil? → !this._X_loaded || this._X == null
                if @has_one_names&.include?(method)
                  loaded_flag = :"_#{method}_loaded"
                  cache_name = :"_#{method}"
                  if node.children[1] == :present?
                    return s(:and,
                      s(:attr, s(:self), loaded_flag),
                      s(:send, s(:attr, s(:self), cache_name), :!=, s(:nil)))
                  else
                    return s(:or,
                      s(:send, s(:attr, s(:self), loaded_flag), :!),
                      s(:send, s(:attr, s(:self), cache_name), :==, s(:nil)))
                  end
                else
                  self_send = receiver.updated(nil, [s(:self), method])
                  op = (node.children[1] == :present?) ? :!= : :==
                  return node.updated(nil, [self_send, op, s(:nil)])
                end
              end
            end
          end

          # Match: s(:send, nil, :name, *args) — bare method call
          if node.type == :send && node.children[0].nil?
            method = node.children[1]

            # Inline enum bang methods: published! → this.update({status: "published"})
            if @concern_enum_bangs && @concern_enum_bangs[method]
              info = @concern_enum_bangs[method]
              return s(:send, s(:self), :update,
                s(:hash, s(:pair, s(:sym, info[:field]), info[:value])))
            end

            # Skip local variables and known exceptions
            unless locals.include?(method) || CONCERN_SELF_EXCEPTIONS.include?(method)
              new_children = [s(:self), method, *node.children[2..-1].map { |c|
                rewrite_node(c, locals, method_name)
              }]
              # For bang methods (!), use s() to create a fresh node
              # without source location. This forces the converter to emit ()
              # for method calls. Without this, the preserved location from
              # Ruby source (which has no parens) causes property access.
              # Predicate methods (?) are NOT forced — they become getters
              # (enum predicates, concern predicates) so property access is correct.
              method_str = method.to_s
              if method_str.end_with?('!')
                return s(:send, *new_children)
              end
              return node.updated(nil, new_children)
            end
          end

          # Handle csend (safe navigation) with known AR mutation methods.
          # Ruby's &. is always a method call, but the converter checks
          # source location for () to decide parens. Nodes rewritten by
          # this filter preserve original location (no parens in Ruby source),
          # so is_method? returns false → property access. Fix: create a
          # fresh node via s() (no location) for known mutation methods.
          if node.type == :csend
            csend_method = node.children[1]
            new_children = node.children.map { |child|
              child.respond_to?(:type) ? rewrite_node(child, locals, method_name) : child
            }
            if AR_MUTATION_METHODS.include?(csend_method)
              return s(:csend, *new_children)
            else
              return node.updated(nil, new_children)
            end
          end

          # Handle transaction blocks: make callback async and await each
          # statement so that AR operations (destroy, create, etc.) complete
          # in order. Without this, the callback is sync and async operations
          # inside are fire-and-forget promises.
          if node.type == :block
            send_child = node.children[0]
            if send_child&.respond_to?(:type) && send_child.type == :send
              if send_child.children[1] == :transaction
                return rewrite_transaction_block(node, locals, method_name)
              end
            end
          end

          # Recurse into children (but track new locals from block args)
          new_children = node.children.map do |child|
            if child.respond_to?(:type)
              # Block args introduce new locals
              if node.type == :block && child.type == :args
                child.children.each do |arg|
                  locals = locals.dup
                  locals << arg.children[0] if arg.respond_to?(:children) && arg.children[0]
                end
                child
              else
                rewrite_node(child, locals, method_name)
              end
            else
              child
            end
          end

          node.updated(nil, new_children)
        end
        # Rewrite a transaction do...end block to use async callback with awaits.
        # Input AST:  s(:block, s(:send, nil, :transaction), s(:args), body)
        # Output AST: s(:send, nil, :await,
        #               s(:send, s(:self), :transaction,
        #                 s(:block, s(:send, nil, :async), s(:args),
        #                   s(:begin, s(:send, nil, :await, stmt1), ...))))
        def rewrite_transaction_block(node, locals, method_name)
          _send_node, args_node, body = node.children

          # Rewrite and await-wrap each statement in the body
          if body
            statements = body.type == :begin ? body.children : [body]
            new_statements = statements.map do |stmt|
              rewritten = rewrite_node(stmt, locals, method_name)
              wrap_with_await(rewritten)
            end

            new_body = if new_statements.length == 1
              new_statements.first
            else
              s(:begin, *new_statements)
            end
          end

          # await this.transaction(async () => { ...awaited body... })
          s(:send, nil, :await,
            s(:send, s(:self), :transaction,
              s(:block,
                s(:send, nil, :async),
                args_node || s(:args),
                new_body)))
        end

        # Wrap a statement with await. For assignments and setters,
        # put await on the RHS to avoid invalid JS like
        # await(let x = expr) or (await this.x) = expr.
        def wrap_with_await(node)
          return node unless node.respond_to?(:type)

          case node.type
          when :lvasgn
            # let x = value → let x = await value
            name, value = node.children
            s(:lvasgn, name, s(:send, nil, :await, value))
          when :ivasgn
            # @x = value → this._x = await value
            name, value = node.children
            s(:ivasgn, name, s(:send, nil, :await, value))
          when :send
            target, method, *args = node.children
            if method && method.to_s.end_with?('=') && target && args.length == 1
              # this.attr = value → this.attr = await value
              s(:send, target, method, s(:send, nil, :await, args[0]))
            else
              s(:send, nil, :await, node)
            end
          else
            s(:send, nil, :await, node)
          end
        end
      end
    end

    DEFAULTS.push Rails::Concern
  end
end
