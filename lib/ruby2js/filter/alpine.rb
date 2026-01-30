# Support for Alpine.js reactive components.
#
# Converts Ruby DSL for Alpine.js components:
#   Alpine.data :counter do
#     def initialize
#       @count = 0
#     end
#
#     def increment
#       @count += 1
#     end
#   end
#
# To JavaScript:
#   Alpine.data('counter', () => ({
#     count: 0,
#     increment() { this.count++ }
#   }))
#
# Magic properties use underscore prefix: _el, _refs, _dispatch, etc.
# These are converted to this.$el, this.$refs, this.$dispatch, etc.
#
# Works with alpinejs.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Alpine
      include SEXP
      extend SEXP

      # Alpine magic properties - underscore prefix maps to $ prefix
      # _el -> this.$el, _refs -> this.$refs, etc.
      ALPINE_MAGIC = Set.new(%i[
        _el
        _refs
        _store
        _watch
        _dispatch
        _nextTick
        _root
        _data
        _id
      ])

      def initialize(*args)
        super
        @alpine_component = false
        @alpine_ivars = Set.new
      end

      def on_block(node)
        call = node.children.first
        return super unless call.type == :send

        target, method, *args = call.children

        # Alpine.data :name do ... end
        if target == s(:const, nil, :Alpine) && method == :data &&
           args.length == 1 && args.first.type == :sym

          component_name = args.first.children.first
          block_body = node.children[2]

          # Add import if ESM is enabled
          if self.modules_enabled?
            self.prepend_list << s(:import,
              ['alpinejs'],
              s(:const, nil, :Alpine))
          end

          # Collect instance variables and methods from the block
          @alpine_ivars = Set.new
          @alpine_component = true

          # Extract methods and init code from the block body
          methods = []
          init_code = []

          if block_body
            nodes = block_body.type == :begin ? block_body.children : [block_body]

            nodes.each do |child|
              if child.type == :def
                method_name = child.children[0]
                method_args = child.children[1]
                method_body = child.children[2]

                if method_name == :initialize
                  # Extract instance variable assignments from initialize
                  if method_body
                    init_nodes = method_body.type == :begin ? method_body.children : [method_body]
                    init_nodes.each do |init_node|
                      if init_node.type == :ivasgn
                        ivar_name = init_node.children[0].to_s[1..-1]
                        @alpine_ivars << ivar_name
                        init_code << s(:pair, s(:sym, ivar_name.to_sym), process(init_node.children[1]))
                      end
                    end
                  end
                else
                  # Regular method - convert to object method
                  processed_body = method_body ? process(method_body) : nil
                  methods << s(:pair, s(:sym, method_name),
                    s(:block, s(:send, nil, :proc), method_args, processed_body))
                end
              elsif child.type == :ivasgn
                # Top-level instance variable assignment
                ivar_name = child.children[0].to_s[1..-1]
                @alpine_ivars << ivar_name
                init_code << s(:pair, s(:sym, ivar_name.to_sym), process(child.children[1]))
              end
            end
          end

          @alpine_component = false

          # Build the component object
          pairs = init_code + methods

          # Generate: Alpine.data('name', () => ({ ... }))
          s(:send, s(:const, nil, :Alpine), :data,
            s(:str, component_name.to_s),
            s(:block, s(:send, nil, :proc), s(:args),
              s(:hash, *pairs)))
        else
          super
        end
      end

      def on_ivar(node)
        return super unless @alpine_component

        ivar_name = node.children.first.to_s[1..-1]
        @alpine_ivars << ivar_name
        s(:attr, s(:self), ivar_name.to_sym)
      end

      def on_ivasgn(node)
        return super unless @alpine_component

        ivar_name = node.children[0].to_s[1..-1]
        @alpine_ivars << ivar_name
        value = node.children[1]

        if value
          s(:send, s(:self), "#{ivar_name}=".to_sym, process(value))
        else
          # No value means this is part of an op_asgn, let super handle it
          super
        end
      end

      def on_op_asgn(node)
        return super unless @alpine_component

        target, op, value = node.children

        if target.type == :ivasgn
          ivar_name = target.children[0].to_s[1..-1]
          @alpine_ivars << ivar_name

          # @count += 1 -> this.count += 1
          s(:op_asgn,
            s(:send, s(:self), ivar_name.to_sym),
            op,
            process(value))
        else
          super
        end
      end

      def on_send(node)
        return super unless @alpine_component

        target, method, *args = node.children

        # Convert Alpine magic properties (_el -> this.$el, etc.)
        if target.nil? && ALPINE_MAGIC.include?(method) # Pragma: set
          js_method = ('$' + method.to_s[1..-1]).to_sym
          if args.empty?
            s(:attr, s(:self), js_method)
          else
            s(:send, s(:self), js_method, *process_all(args))
          end
        else
          super
        end
      end
    end

    DEFAULTS.push Alpine
  end
end
