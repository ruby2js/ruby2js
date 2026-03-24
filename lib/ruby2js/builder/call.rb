module Ruby2JS
  module Builder
    class Call
      include Filter::SEXP
      extend Filter::SEXP

      attr_reader :node

      # Low-level constructor: wraps a pre-built AST node
      def initialize(node)
        @node = node
      end

      # Factory: method call on a receiver
      def self.on(receiver, method, *args)
        new(s(:send, receiver, method, *args))
      end

      # Factory: method call on self
      def self.self(method, *args)
        new(s(:send, s(:self), method, *args))
      end

      # Factory: bare function call (no receiver)
      def self.bare(method, *args)
        new(s(:send, nil, method, *args))
      end

      # Factory: property access (no parens)
      def self.attr(receiver, name)
        new(s(:attr, receiver, name))
      end

      # Factory: property access on self (no parens)
      def self.self_attr(name)
        new(s(:attr, s(:self), name))
      end

      # Chain a method call on the result
      def chain(method, *args)
        Call.new(s(:send, @node, method, *args))
      end

      # Chain a property access (no parens)
      def prop(name)
        Call.new(s(:attr, @node, name))
      end

      # Wrap in await
      def await
        Call.new(s(:send, nil, :await, @node))
      end

      # Extract the AST node
      def to_node
        @node
      end

      # Allow builders to be used directly as AST node children
      def type
        @node.type
      end

      def children
        @node.children
      end

      def updated(*args)
        @node.updated(*args)
      end
    end
  end
end
