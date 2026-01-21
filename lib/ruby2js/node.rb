# frozen_string_literal: true

module Ruby2JS
  # Minimal AST node class compatible with Parser::AST::Node interface.
  # Used by the Prism walker to avoid dependency on parser gem.
  class Node
    attr_reader :type, :children, :location

    # Alias for location - defined as method for JS getter aliasing compatibility
    def loc
      @location
    end

    def initialize(type, children = [], properties = {})
      @type = type.to_sym
      @children = children.freeze
      @location = properties[:location]
      freeze
    end

    def updated(type = nil, children = nil, properties = nil)
      new_props = { location: @location }
      new_props.merge!(properties) if properties
      Node.new(
        type || @type,
        children || @children,
        new_props
      )
    end

    # Return children array (for compatibility with code expecting to_a method)
    def to_a
      @children
    end

    # Check if this is a method call (has parentheses or arguments)
    # Uses location-based detection like Parser::AST::Node to check for '(' after selector
    def is_method?
      return false if @type == :attr
      return false if @type == :await_attr  # await on property access (no parens)
      return true if @type == :call
      return true unless @location

      if @location.respond_to?(:selector)
        return true if @children.length > 2
        selector = @location.selector
      elsif @type == :defs
        return true if @children[1] =~ /[!?]$/
        return true if @children[2].children.length > 0
        selector = @location.respond_to?(:name) ? @location.name : nil
      elsif @type == :def
        return true if @children[0] =~ /[!?]$/
        return true if @children[1].children.length > 0
        selector = @location.respond_to?(:name) ? @location.name : nil
      end

      return true unless selector && selector.respond_to?(:source_buffer) && selector.source_buffer
      # Use byte-based check since Prism gives byte offsets
      # 0x28 is ASCII for '(' - works with both byte and char indexing for ASCII
      source = selector.source_buffer.source
      source.getbyte(selector.end_pos) == 0x28
    end

    # For compatibility with code that checks Parser::AST::Node
    def is_a?(klass) # Pragma: skip
      return true if defined?(::Parser::AST::Node) && klass == ::Parser::AST::Node
      super
    end

    # For compatibility with code that uses === checks
    def self.===(other) # Pragma: skip
      other.is_a?(Node) || (defined?(::Parser::AST::Node) && other.is_a?(::Parser::AST::Node))
    end

    # For compatibility with kind_of? checks
    alias :kind_of? :is_a? # Pragma: skip

    # Deep equality check - transpiles to JavaScript for selfhost
    # Used by conditionally_equals in logical.rb
    def equals(other)
      return false unless other.respond_to?(:type) && other.respond_to?(:children)
      return false unless type == other.type
      return false unless children.length == other.children.length
      children.each_with_index do |child, i|
        other_child = other.children[i]
        if child.respond_to?(:equals)
          return false unless child.equals(other_child)
        else
          return false unless child == other_child
        end
      end
      true
    end

    # Equality based on type and children
    def ==(other) # Pragma: skip
      return false unless other.respond_to?(:type) && other.respond_to?(:children)
      type == other.type && children == other.children
    end

    alias :eql? :== # Pragma: skip

    def hash # Pragma: skip
      [type, children].hash
    end

    # Pretty print the AST
    def to_sexp(indent = 0) # Pragma: skip
      prefix = "  " * indent
      if children.empty?
        "#{prefix}(#{type})"
      elsif children.all? { |c| !c.respond_to?(:type) || !c.respond_to?(:children) }
        "#{prefix}(#{type} #{children.map(&:inspect).join(' ')})"
      else
        result = "#{prefix}(#{type}"
        children.each do |child|
          if child.respond_to?(:to_sexp)
            result += "\n#{child.to_sexp(indent + 1)}"
          else
            result += "\n#{prefix}  #{child.inspect}"
          end
        end
        result + ")"
      end
    end

    def inspect # Pragma: skip
      "#<Ruby2JS::Node #{to_sexp}>"
    end
  end
end
