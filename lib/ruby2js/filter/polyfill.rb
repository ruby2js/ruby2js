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
          # Non-mutating: returns new array without null/undefined (matches Ruby's compact)
          # For compact! (mutating), the Functions filter converts it to splice-based code
          define_property_getter(:Array, :compact,
            s(:return,
              s(:send, s(:self), :filter,
                s(:block,
                  s(:send, nil, :lambda),
                  s(:args, s(:arg, :x)),
                  s(:and,
                    s(:send, s(:lvar, :x), :"!==", s(:nil)),
                    s(:send, s(:lvar, :x), :"!==", s(:lvar, :undefined))
                  )
                )
              )
            )
          )

        when :array_uniq
          # Object.defineProperty(Array.prototype, 'uniq', {get() { return [...new Set(this)] }, configurable: true})
          # Non-mutating: returns new array with duplicates removed (matches Ruby's uniq)
          define_property_getter(:Array, :uniq,
            s(:return, s(:array, s(:splat, s(:send, s(:const, nil, :Set), :new, s(:self)))))
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

        when :array_bsearch_index
          # if (!Array.prototype.bsearch_index) { Array.prototype.bsearch_index = function(fn) {...} }
          # Binary search returning index of first element where fn returns true
          define_prototype_method(:Array, :bsearch_index, s(:args, s(:arg, :fn)),
            s(:begin,
              s(:lvasgn, :lo, s(:int, 0)),
              s(:lvasgn, :hi, s(:attr, s(:self), :length)),
              s(:while, s(:send, s(:lvar, :lo), :<, s(:lvar, :hi)),
                s(:begin,
                  s(:lvasgn, :mid, s(:send, s(:const, nil, :Math), :floor,
                    s(:send, s(:send, s(:lvar, :lo), :+, s(:lvar, :hi)), :/, s(:int, 2)))),
                  s(:if,
                    s(:send!, s(:lvar, :fn), nil, s(:send, s(:self), :[], s(:lvar, :mid))),
                    s(:lvasgn, :hi, s(:lvar, :mid)),
                    s(:lvasgn, :lo, s(:send, s(:lvar, :mid), :+, s(:int, 1)))
                  )
                )
              ),
              s(:if,
                s(:send, s(:lvar, :lo), :<, s(:attr, s(:self), :length)),
                s(:return, s(:lvar, :lo)),
                s(:return, s(:nil))
              )
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
              s(:return, s(:send, nil, :String, s(:self)))
            )
          )

        when :string_delete_prefix
          # if (!String.prototype.delete_prefix) { String.prototype.delete_prefix = function(prefix) {...} }
          define_prototype_method(:String, :delete_prefix, s(:args, s(:arg, :prefix)),
            s(:if,
              s(:send, s(:self), :startsWith, s(:lvar, :prefix)),
              s(:return, s(:send, s(:self), :slice, s(:attr, s(:lvar, :prefix), :length))),
              s(:return, s(:send, nil, :String, s(:self)))
            )
          )

        when :string_delete_suffix
          # if (!String.prototype.delete_suffix) { String.prototype.delete_suffix = function(suffix) {...} }
          define_prototype_method(:String, :delete_suffix, s(:args, s(:arg, :suffix)),
            s(:if,
              s(:send, s(:self), :endsWith, s(:lvar, :suffix)),
              s(:return, s(:send, s(:self), :slice, s(:int, 0), s(:send, s(:attr, s(:self), :length), :-, s(:attr, s(:lvar, :suffix), :length)))),
              s(:return, s(:send, nil, :String, s(:self)))
            )
          )

        when :string_count
          # if (!String.prototype.count) { String.prototype.count = function(chars) {...} }
          # Counts occurrences of any character in chars string
          # for (const c of this) { if (chars.includes(c)) count++ }
          define_prototype_method(:String, :count, s(:args, s(:arg, :chars)),
            s(:begin,
              s(:lvasgn, :count, s(:int, 0)),
              s(:for_of, s(:lvasgn, :c), s(:self),
                s(:if,
                  s(:send, s(:lvar, :chars), :includes, s(:lvar, :c)),
                  s(:op_asgn, s(:lvasgn, :count), :+, s(:int, 1)),
                  nil
                )
              ),
              s(:return, s(:lvar, :count))
            )
          )

        when :object_to_a
          # Object.defineProperty(Object.prototype, 'to_a', {get() { return Object.entries(this) }, configurable: true})
          define_property_getter(:Object, :to_a,
            s(:return, s(:send, s(:const, nil, :Object), :entries, s(:self)))
          )

        when :regexp_escape
          # if (!RegExp.escape) { RegExp.escape = function(str) { return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') } }
          s(:if,
            s(:send, s(:attr, s(:const, nil, :RegExp), :escape), :!),
            s(:send, s(:const, nil, :RegExp), :[]=, s(:str, 'escape'),
              s(:deff, nil, s(:args, s(:arg, :str)),
                s(:return,
                  s(:send, s(:lvar, :str), :replace,
                    s(:regexp, s(:str, '[.*+?^${}()|[\\]\\\\]'), s(:regopt, :g)),
                    s(:str, '\\$&')
                  )
                )
              )
            ),
            nil
          )

        when :hash_with_default
          # class $Hash extends Map {
          #   constructor(d, b) { super(); this._d = d; this._b = b; }
          #   get(k) {
          #     const v = super.get(k);
          #     if (v !== undefined || this.has(k)) return v;
          #     if (this._b) return this._b(this, k);
          #     return this._d;
          #   }
          # }
          s(:class,
            s(:const, nil, :$Hash),
            s(:const, nil, :Map),
            s(:begin,
              # constructor(d, b) { super(); this._d = d; this._b = b; }
              s(:def, :initialize, s(:args, s(:arg, :d), s(:arg, :b)),
                s(:begin,
                  s(:super),
                  s(:ivasgn, :@_d, s(:lvar, :d)),
                  s(:ivasgn, :@_b, s(:lvar, :b))
                )
              ),
              # get(k) { ... }
              s(:def, :get, s(:args, s(:arg, :k)),
                s(:begin,
                  # const v = super.get(k);  (super(k) in a get() method becomes super.get(k))
                  s(:lvasgn, :v, s(:super, s(:lvar, :k))),
                  # if (v !== undefined || this.has(k)) return v;
                  s(:if,
                    s(:or,
                      s(:send, s(:lvar, :v), :"!==", s(:lvar, :undefined)),
                      s(:send, s(:self), :has, s(:lvar, :k))
                    ),
                    s(:return, s(:lvar, :v)),
                    nil
                  ),
                  # if (this._b) return this._b(this, k);
                  s(:if,
                    s(:ivar, :@_b),
                    s(:return, s(:send, s(:ivar, :@_b), :call, s(:self), s(:lvar, :k))),
                    nil
                  ),
                  # return this._d;
                  s(:return, s(:ivar, :@_d))
                )
              )
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

          when :uniq
            if args.empty?
              add_polyfill(:array_uniq)
              # Use :attr for property access (no parens) - it's a getter
              return s(:attr, process(target), :uniq)
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

          when :delete_prefix
            if args.length == 1
              add_polyfill(:string_delete_prefix)
              return s(:send!, process(target), :delete_prefix, process(args.first))
            end

          when :delete_suffix
            if args.length == 1
              add_polyfill(:string_delete_suffix)
              return s(:send!, process(target), :delete_suffix, process(args.first))
            end

          when :count
            # String#count(chars) - count occurrences of any char in chars
            if args.length == 1
              add_polyfill(:string_count)
              return s(:send!, process(target), :count, process(args.first))
            end

          when :to_a
            # Hash#to_a / Object#to_a - convert to array of entries
            if args.empty?
              add_polyfill(:object_to_a)
              return s(:attr, process(target), :to_a)
            end

          when :escape
            # Regexp.escape(str) => RegExp.escape(str) with polyfill for pre-ES2025
            if target == s(:const, nil, :Regexp) && args.length == 1
              add_polyfill(:regexp_escape) unless es2025
              return s(:send, s(:const, nil, :RegExp), :escape, process(args.first))
            end

          when :new
            # Hash.new(default) => new $Hash(default)
            # Hash.new => {} (plain object)
            if target == s(:const, nil, :Hash)
              if args.length == 1
                add_polyfill(:hash_with_default)
                return s(:send, s(:const, nil, :$Hash), :new, process(args.first))
              elsif args.empty?
                return s(:hash)
              end
            end
          end
        end

        super
      end

      # Handle .first/.last when already converted to attr by another filter
      # (e.g., selfhost/converter transforms these before polyfill runs)
      def on_attr(node)
        target, method = node.children

        case method
        when :first
          add_polyfill(:array_first)
        when :last
          add_polyfill(:array_last)
        when :compact
          add_polyfill(:array_compact)
        when :uniq
          add_polyfill(:array_uniq)
        end

        super
      end

      # Handle rindex with block and Hash.new with block
      def on_block(node)
        call = node.children.first

        if call.type == :send
          target, method, *args = call.children

          if target && method == :rindex
            add_polyfill(:array_rindex)
            # Process the block but keep as :send! to prevent further transformation
            return node.updated(nil, [
              s(:send!, process(target), :rindex),
              process(node.children[1]),
              process(node.children[2])
            ])
          end

          if target && method == :bsearch_index
            add_polyfill(:array_bsearch_index)
            # Process the block but keep as :send! to prevent further transformation
            return node.updated(nil, [
              s(:send!, process(target), :bsearch_index),
              process(node.children[1]),
              process(node.children[2])
            ])
          end

          # Hash.new { |h, k| ... } => new $Hash(undefined, (h, k) => ...)
          if target == s(:const, nil, :Hash) && method == :new
            add_polyfill(:hash_with_default)
            block_args = node.children[1]
            block_body = node.children[2]
            # Create arrow function from block
            arrow_fn = s(:block,
              s(:send, nil, :lambda),
              process(block_args),
              process(block_body)
            )
            # Pass default value (from args) or undefined, plus the block
            default_val = args.empty? ? s(:lvar, :undefined) : process(args.first)
            return s(:send, s(:const, nil, :$Hash), :new, default_val, arrow_fn)
          end
        end

        super
      end
    end

    DEFAULTS.push Polyfill
  end
end
