# frozen_string_literal: true

module Ruby2JS
  # Minimal AST node class compatible with Parser::AST::Node interface.
  # Used by the Prism walker to avoid dependency on parser gem.
  class Node
    attr_reader :type, :children, :location
    alias :loc :location

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

    alias :to_a :children

    # Check if this is a method call (has parentheses or arguments)
    # Uses location-based detection like Parser::AST::Node to check for '(' after selector
    def is_method?
      return false if type == :attr
      return true if type == :call
      return true unless loc

      if loc.respond_to?(:selector)
        return true if children.length > 2
        selector = loc.selector
      elsif type == :defs
        return true if children[1] =~ /[!?]$/
        return true if children[2].children.length > 0
        selector = loc.respond_to?(:name) ? loc.name : nil
      elsif type == :def
        return true if children[0] =~ /[!?]$/
        return true if children[1].children.length > 0
        selector = loc.respond_to?(:name) ? loc.name : nil
      end

      return true unless selector && selector.respond_to?(:source_buffer) && selector.source_buffer
      selector.source_buffer.source[selector.end_pos] == '('
    end

    # For compatibility with code that checks Parser::AST::Node
    def is_a?(klass)
      return true if defined?(::Parser::AST::Node) && klass == ::Parser::AST::Node
      super
    end

    # For compatibility with code that uses === checks
    def self.===(other)
      other.is_a?(Node) || (defined?(::Parser::AST::Node) && other.is_a?(::Parser::AST::Node))
    end

    # For compatibility with kind_of? checks
    alias :kind_of? :is_a?

    # Equality based on type and children
    def ==(other)
      return false unless other.respond_to?(:type) && other.respond_to?(:children)
      type == other.type && children == other.children
    end

    alias :eql? :==

    def hash
      [type, children].hash
    end

    # Pretty print the AST
    def to_sexp(indent = 0)
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

    def inspect
      "#<Ruby2JS::Node #{to_sexp}>"
    end
  end
end
