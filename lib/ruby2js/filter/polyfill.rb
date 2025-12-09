require 'ruby2js'

module Ruby2JS
  module Filter
    module Polyfill
      include SEXP

      # Ensure polyfill runs before functions filter so that
      # the polyfill methods can be transformed by functions
      def self.reorder(filters)
        if defined?(Ruby2JS::Filter::Functions) &&
           filters.include?(Ruby2JS::Filter::Functions)
          filters = filters.dup
          polyfill = filters.delete(Ruby2JS::Filter::Polyfill)
          filters.insert(filters.index(Ruby2JS::Filter::Functions), polyfill)
        end
        filters
      end

      def initialize(comments)
        super
        @polyfills_added = Set.new
      end

      # Build AST for: Object.defineProperty(Array.prototype, 'name', {get() {...}, configurable: true})
      def define_property_getter(prototype, name, body)
        s(:send,
          s(:const, nil, :Object),
          :defineProperty,
          s(:attr, s(:const, nil, prototype), :prototype),
          s(:str, name.to_s),
          s(:hash,
            s(:pair, s(:sym, :get), s(:defm, nil, s(:args), body)),
            s(:pair, s(:sym, :configurable), s(:true))
          )
        )
      end

      # Build AST for: if (!Prototype.prototype.name) { Prototype.prototype.name = function(...) {...} }
      def define_prototype_method(prototype, name, args, body)
        proto_attr = s(:attr, s(:const, nil, prototype), :prototype)
        s(:if,
          s(:send, s(:attr, proto_attr, name), :!),
          s(:send, proto_attr, :[]=, s(:str, name.to_s),
            s(:deff, nil, args, body)
          ),
          nil
        )
      end

      # Generate polyfill AST nodes
      def polyfill_ast(name)
        case name
        when :array_first
          # Object.defineProperty(Array.prototype, 'first', {get() { return this[0] }, configurable: true})
          define_property_getter(:Array, :first,
            s(:return, s(:send, s(:self), :[], s(:int, 0)))
          )

        when :array_last
          # Object.defineProperty(Array.prototype, 'last', {get() { return this.at(-1) }, configurable: true})
          define_property_getter(:Array, :last,
            s(:return, s(:send, s(:self), :at, s(:int, -1)))
          )

        when :array_compact
          # Object.defineProperty(Array.prototype, 'compact', {get() {...}, configurable: true})
          # Loops backwards removing null/undefined, returns this
          # Using while loop: let i = this.length - 1; while (i >= 0) { ...; i-- }
          define_property_getter(:Array, :compact,
            s(:begin,
              s(:lvasgn, :i, s(:send, s(:attr, s(:self), :length), :-, s(:int, 1))),
              s(:while, s(:send, s(:lvar, :i), :>=, s(:int, 0)),
                s(:begin,
                  s(:if,
                    s(:or,
                      s(:send, s(:send, s(:self), :[], s(:lvar, :i)), :===, s(:nil)),
                      s(:send, s(:send, s(:self), :[], s(:lvar, :i)), :===, s(:lvar, :undefined))
                    ),
                    s(:send, s(:self), :splice, s(:lvar, :i), s(:int, 1)),
                    nil
                  ),
                  s(:op_asgn, s(:lvasgn, :i), :-, s(:int, 1))
                )
              ),
              s(:return, s(:self))
            )
          )

        when :array_rindex
          # if (!Array.prototype.rindex) { Array.prototype.rindex = function(fn) {...} }
          # Using while loop: let i = this.length - 1; while (i >= 0) { ...; i-- }
          define_prototype_method(:Array, :rindex, s(:args, s(:arg, :fn)),
            s(:begin,
              s(:lvasgn, :i, s(:send, s(:attr, s(:self), :length), :-, s(:int, 1))),
              s(:while, s(:send, s(:lvar, :i), :>=, s(:int, 0)),
                s(:begin,
                  s(:if,
                    s(:send!, s(:lvar, :fn), nil, s(:send, s(:self), :[], s(:lvar, :i))),
                    s(:return, s(:lvar, :i)),
                    nil
                  ),
                  s(:op_asgn, s(:lvasgn, :i), :-, s(:int, 1))
                )
              ),
              s(:return, s(:nil))
            )
          )

        when :array_insert
          # if (!Array.prototype.insert) { Array.prototype.insert = function(index, ...items) {...} }
          define_prototype_method(:Array, :insert, s(:args, s(:arg, :index), s(:restarg, :items)),
            s(:begin,
              s(:send, s(:self), :splice, s(:lvar, :index), s(:int, 0), s(:splat, s(:lvar, :items))),
              s(:return, s(:self))
            )
          )

        when :array_delete_at
          # if (!Array.prototype.delete_at) { Array.prototype.delete_at = function(index) {...} }
          define_prototype_method(:Array, :delete_at, s(:args, s(:arg, :index)),
            s(:begin,
              s(:if,
                s(:send, s(:lvar, :index), :<, s(:int, 0)),
                s(:lvasgn, :index, s(:send, s(:attr, s(:self), :length), :+, s(:lvar, :index))),
                nil
              ),
              s(:if,
                s(:or,
                  s(:send, s(:lvar, :index), :<, s(:int, 0)),
                  s(:send, s(:lvar, :index), :>=, s(:attr, s(:self), :length))
                ),
                s(:return, s(:lvar, :undefined)),
                nil
              ),
              s(:return, s(:send, s(:send, s(:self), :splice, s(:lvar, :index), s(:int, 1)), :[], s(:int, 0)))
            )
          )

        when :string_chomp
          # if (!String.prototype.chomp) { String.prototype.chomp = function(suffix) {...} }
          define_prototype_method(:String, :chomp, s(:args, s(:arg, :suffix)),
            s(:begin,
              s(:if,
                s(:send, s(:lvar, :suffix), :===, s(:lvar, :undefined)),
                s(:return, s(:send, s(:self), :replace, s(:regexp, s(:str, '\\r?\\n$'), s(:regopt)), s(:str, ''))),
                nil
              ),
              s(:if,
                s(:send, s(:self), :endsWith, s(:lvar, :suffix)),
                s(:return, s(:send, s(:self), :slice, s(:int, 0), s(:send, s(:attr, s(:self), :length), :-, s(:attr, s(:lvar, :suffix), :length)))),
                nil
              ),
              s(:return, s(:send, s(:const, nil, :String), :call, s(:self)))
            )
          )
        end
      end

      # Helper to add a polyfill only once
      def add_polyfill(name)
        return if @polyfills_added.include?(name)
        @polyfills_added << name
        prepend_list << polyfill_ast(name)
      end

      def on_send(node)
        target, method, *args = node.children

        # Only process calls with a receiver
        if target
          case method
          when :first
            if args.empty?
              add_polyfill(:array_first)
              # Use :attr for property access (no parens) - it's a getter
              return s(:attr, process(target), :first)
            end

          when :last
            if args.empty?
              add_polyfill(:array_last)
              # Use :attr for property access (no parens) - it's a getter
              return s(:attr, process(target), :last)
            end

          when :rindex
            if args.empty?
              # rindex with block (block handled separately)
              add_polyfill(:array_rindex)
              return s(:send!, process(target), :rindex)
            end

          when :compact
            if args.empty?
              add_polyfill(:array_compact)
              # Use :attr for property access (no parens) - it's a getter
              return s(:attr, process(target), :compact)
            end

          when :insert
            add_polyfill(:array_insert)
            return s(:send!, process(target), :insert, *args.map { |a| process(a) })

          when :delete_at
            if args.length == 1
              add_polyfill(:array_delete_at)
              return s(:send!, process(target), :delete_at, process(args.first))
            end

          when :chomp
            if args.length <= 1
              add_polyfill(:string_chomp)
              return s(:send!, process(target), :chomp, *args.map { |a| process(a) })
            end
          end
        end

        super
      end

      # Handle rindex with block
      def on_block(node)
        call = node.children.first

        if call.type == :send
          target, method = call.children
          if target && method == :rindex
            add_polyfill(:array_rindex)
            # Process the block but keep as :send! to prevent further transformation
            return node.updated(nil, [
              s(:send!, process(target), :rindex),
              process(node.children[1]),
              process(node.children[2])
            ])
          end
        end

        super
      end
    end

    DEFAULTS.push Polyfill
  end
end
