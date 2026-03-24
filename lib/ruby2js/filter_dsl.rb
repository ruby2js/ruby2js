require 'ruby2js'

module Ruby2JS
  class FilterDSL
    include Filter::SEXP

    attr_reader :filter_name, :rewrites, :handlers

    def initialize(name)
      @filter_name = name
      @rewrites = []
      @handlers = {}
    end

    # Layer 1: Declarative rewrite
    # Pattern and replacement are Ruby expression strings.
    # Placeholders _1, _2, etc. match any subtree.
    def rewrite(pattern_str, to:)
      pattern_ast = Ruby2JS.parse(pattern_str).first
      replacement_ast = Ruby2JS.parse(to).first
      placeholders = extract_placeholders(pattern_ast)
      @rewrites << {
        pattern: pattern_ast,
        replacement: replacement_ast,
        placeholders: placeholders
      }
    end

    # Layer 2+: Custom handler blocks
    def on_send(&block)
      @handlers[:send] = block
    end

    def on_class(&block)
      @handlers[:class] ||= []
      @handlers[:class] << block
    end

    def on_block(&block)
      @handlers[:block] = block
    end

    # Generate a Ruby2JS::Filter module from this DSL definition
    def to_filter
      dsl = self
      mod = Module.new do
        include Ruby2JS::Filter::SEXP

        define_method(:on_send) do |node|
          # Try each rewrite rule before other filters
          dsl.rewrites.each do |rule|
            bindings = {}
            if FilterDSL.match_pattern(node, rule[:pattern], bindings)
              return FilterDSL.apply_replacement(rule[:replacement], bindings)
            end
          end

          # Try custom handler before other filters
          if dsl.handlers[:send]
            result = dsl.handlers[:send].call(node)
            return result if result
          end

          super(node)
        end

        if dsl.handlers[:class]
          class_handlers = dsl.handlers[:class]
          define_method(:on_class) do |node|
            # Run app handlers before other filters
            class_handlers.each do |handler|
              result = handler.call(node)
              node = result if result
            end
            super(node)
          end
        end

        if dsl.handlers[:block]
          define_method(:on_block) do |node|
            result = dsl.handlers[:block].call(node)
            node = result if result
            super(node)
          end
        end
      end

      # Register in the Filter namespace
      Ruby2JS::Filter.const_set(dsl.filter_name, mod)
      mod
    end

    # Match an AST node against a pattern, collecting placeholder bindings.
    # Returns true if matched, false otherwise.
    def self.match_pattern(node, pattern, bindings)
      # Placeholder: _1, _2, etc. (parsed as bare method call: send nil :_1)
      if pattern.respond_to?(:type) && pattern.type == :send &&
         pattern.children[0].nil? && pattern.children[1].to_s =~ /\A_(\d+)\z/
        bindings[pattern.children[1]] = node
        return true
      end

      # Both must be AST nodes
      return node == pattern unless pattern.respond_to?(:type) && node.respond_to?(:type)

      # Types must match
      return false unless node.type == pattern.type

      # Children count must match
      return false unless node.children.length == pattern.children.length

      # Recursively match each child
      node.children.zip(pattern.children).all? do |n_child, p_child|
        if p_child.respond_to?(:type)
          match_pattern(n_child, p_child, bindings)
        else
          n_child == p_child
        end
      end
    end

    # Substitute placeholder bindings into a replacement template
    def self.apply_replacement(replacement, bindings)
      return replacement unless replacement.respond_to?(:type)

      # Check if this node is a placeholder reference
      if replacement.type == :send && replacement.children[0].nil? &&
         replacement.children[1].to_s =~ /\A_(\d+)\z/
        bound = bindings[replacement.children[1]]
        return bound if bound
      end

      # Recursively apply to children
      new_children = replacement.children.map do |child|
        if child.respond_to?(:type)
          apply_replacement(child, bindings)
        else
          child
        end
      end

      replacement.updated(nil, new_children)
    end

    private

    # Find all placeholder symbols in a pattern AST
    def extract_placeholders(node)
      result = []
      return result unless node.respond_to?(:type)

      if node.type == :send && node.children[0].nil? &&
         node.children[1].to_s =~ /\A_(\d+)\z/
        result << node.children[1]
      end

      node.children.each do |child|
        result += extract_placeholders(child) if child.respond_to?(:type)
      end

      result
    end
  end

  # Top-level DSL entry point
  def self.filter(name, &block)
    dsl = FilterDSL.new(name)
    dsl.instance_eval(&block)
    dsl.to_filter
  end
end
