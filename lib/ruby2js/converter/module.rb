module Ruby2JS
  class Converter

    # (module
    #   (const nil :A)
    #   (...)
    #
    #   Note: modules_hash is an anonymous modules as a value in a hash; the
    #         name has already been output so should be ignored other than
    #         in determining the namespace.

    handle :module, :module_hash do |name, *body|
      extend = @namespace.enter(name)

      if body.length == 1 && body.first == nil
        if @ast.type == :module and not extend
          parse @ast.updated(:casgn, [*name.children, s(:hash)]), :statement
        else
          parse @ast.updated(:hash, [])
        end

        @namespace.leave()
        return
      end

      while body.length == 1 and body.first&.type == :begin
        body = body.first.children
      end

      if body.length > 0 and body.all? {|child|
        %i[def module].include? child.type or
        (child.type == :class and child.children[1] == nil)}

        if extend
          parse s(:assign, name, @ast.updated(:class_module, 
            [nil, nil, *body])), :statement
        elsif @ast.type == :module_hash
          parse @ast.updated(:class_module, [nil, nil, *body])
        else
          parse @ast.updated(:class_module, [name, nil, *body])
        end

        @namespace.leave()
        return
      end

      # Force underscored_private for module IIFEs since IIFEs can't use
      # ES2022 private fields (#foo syntax) - same as class_extend in class.rb
      saved_underscored_private = @underscored_private
      @underscored_private = true

      symbols = []
      predicate_symbols = []  # Track methods originally named with ? suffix
      is_concern = false  # Set by __concern__ marker from rails/concern filter
      visibility = :public
      omit = []
      body = [*body]  # Copy array so we can modify defs nodes (works in Ruby and JS)

      body.each_with_index do |node, i|
        if node.type == :send and node.children.first == nil
          if [:public, :private, :protected].include? node.children[1]
            if node.children.length == 2
              visibility = node.children[1]
              omit << node
            elsif node.children[1] == :public
              omit << node
              node.children[2..-1].each do |sym|
                symbols << sym.children.first if sym.type == :sym
              end
            end
          elsif node.children[1] == :__concern__
            is_concern = true
            omit << node
          end
        end

        next unless visibility == :public

        if node.type == :casgn and node.children.first == nil
          symbols << node.children[1]
        elsif node.type == :def
          # Strip ? and ! from method names (they're stripped in def transpilation)
          original_name = node.children.first.to_s
          method_name = original_name.sub(/[?!]$/, '').to_sym
          symbols << method_name
          # In concerns, zero-arg methods become getters (get x() { return x.call(this) })
          # so property-style access (card.closed, card.color) works after mixing.
          # ?-suffix methods always become getters regardless of concern status.
          args = node.children[1]
          has_no_args = !args || args.children.empty?
          predicate_symbols << method_name if original_name.end_with?('?') || (is_concern && has_no_args)
        elsif node.type == :defs and node.children.first.type == :self
          # Convert singleton method (def self.X) to regular function
          # In IIFE context, this.X = ... fails because this is undefined
          original_name = node.children[1].to_s
          method_name = original_name.sub(/[?!]$/, '').to_sym
          symbols << method_name
          args = node.children[2]
          has_no_args = !args || args.children.empty?
          predicate_symbols << method_name if original_name.end_with?('?') || (is_concern && has_no_args)
          # Transform defs to def for IIFE-safe output
          new_node = node.updated(:def, [node.children[1], *node.children[2..-1]])
          # Transfer comments from original defs node to new def node
          # Use location-based lookup since object identity may differ in selfhost
          node_comments = nil
          node_loc = node.loc&.expression
          if node_loc
            if @comments.respond_to?(:forEach)
              # JS selfhost: iterate Map to find by location
              @comments.forEach do |value, key|
                next if node_comments  # Already found
                next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
                key_loc = key.loc&.expression
                if key_loc && key_loc.begin_pos == node_loc.begin_pos
                  node_comments = value
                  @comments.set(key, [])
                end
              end
            else
              # Ruby: iterate Hash to find by location
              @comments.each do |key, value|
                next if node_comments  # Already found
                next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
                key_loc = key.loc&.expression
                if key_loc && key_loc.begin_pos == node_loc.begin_pos
                  node_comments = value
                  @comments[key] = []
                  break
                end
              end
            end
          end
          if node_comments && (node_comments.is_a?(Array) ? node_comments.any? : node_comments)
            @comments.set(new_node, node_comments)
          end
          body[i] = new_node
        elsif node.type == :asyncs and node.children.first.type == :self
          # Convert async singleton method (async def self.X) to regular async function
          # In IIFE context, this.X = ... fails because this is undefined
          original_name = node.children[1].to_s
          method_name = original_name.sub(/[?!]$/, '').to_sym
          symbols << method_name
          predicate_symbols << method_name if original_name.end_with?('?')
          # Transform asyncs to async for IIFE-safe output
          body[i] = node.updated(:async, [node.children[1], *node.children[2..-1]])
        elsif node.type == :class and node.children.first.children.first == nil
          symbols << node.children.first.children.last
        elsif node.type == :module
          symbols << node.children.first.children.last
        end
      end

      # Detect getter/setter pairs for object literal accessor syntax.
      # Uses arrays (not hashes) to avoid iteration issues in selfhost JS.
      # accessor_list: [[base_sym, getter_node_or_nil, setter_node], ...]
      accessor_list = []
      body.each do |node|
        next unless node.respond_to?(:type) && node.type == :def
        name_str = node.children.first.to_s
        if name_str.end_with?('=')
          base = name_str.chomp('=').to_sym
          getter = body.find { |n| n.respond_to?(:type) && n.type == :def && n.children.first == base }
          accessor_list.push [base, getter, node]
        end
      end

      unless accessor_list.empty?
        accessor_nodes = accessor_list.flat_map { |info| [info[1], info[2]].compact }
        body = body.reject { |node| accessor_nodes.include?(node) }

        # Build list of symbol names to exclude (both getter and setter names).
        # Use reject+include? instead of Array#delete for JS compatibility.
        excluded_syms = []
        accessor_list.each do |info|
          excluded_syms.push info[0]
          excluded_syms.push :"#{info[0]}="
        end
        symbols = symbols.reject { |sym| excluded_syms.include?(sym) }
        predicate_symbols = predicate_symbols.reject { |sym| excluded_syms.include?(sym) }

        # Ensure closure variables used by getter/setter are declared in IIFE
        # scope.  When @@logo is only used inside methods (no top-level
        # @@logo = nil), the IIFE has no `let logo` declaration.  Add one
        # so the setter can assign to the closure variable rather than
        # creating a new local with `let`.
        accessor_list.each do |info|
          base = info[0]
          already_declared = body.any? { |n|
            n.respond_to?(:type) && n.type == :lvasgn && n.children[0] == base
          }
          body.unshift s(:lvasgn, base) unless already_declared
        end

        # Make getter/setter def nodes anonymous (name=nil) so the def
        # converter inherits @vars from the IIFE scope. This ensures
        # assignments to closure variables (from @@cvar -> cvar conversion)
        # don't produce spurious `let` declarations. The hash converter's
        # @prop mechanism provides the output name (get/set).
        accessor_list.each do |info|
          if info[1]
            # Wrap getter body in autoreturn for proper return statement
            getter_args = info[1].children[1]
            getter_body = s(:autoreturn, *info[1].children[2..-1])
            info[1] = info[1].updated(nil, [nil, getter_args, getter_body])
          end
          info[2] = info[2].updated(nil, [nil, *info[2].children[1..-1]])
        end
      end

      # Wrap predicate function bodies in autoreturn so the inner function
      # returns its last expression (the getter calls fn.call(this)).
      unless predicate_symbols.empty?
        body.each_with_index do |node, i|
          next unless node.respond_to?(:type) && node.type == :def
          fn_name = node.children[0].to_s.sub(/[?!]$/, '').to_sym
          next unless predicate_symbols.include?(fn_name)
          fn_body = node.children[2]
          next unless fn_body
          body[i] = node.updated(nil, [node.children[0], node.children[1],
            s(:autoreturn, fn_body)])
        end
      end

      # Split regular symbols from predicate (formerly ?) symbols.
      # Predicates become getters that call the inner function with this,
      # so card.closed evaluates the predicate instead of returning the function.
      regular_syms = symbols.reject { |sym| predicate_symbols.include?(sym) }
      regular_pairs = regular_syms.map {|sym| s(:pair, s(:sym, sym), s(:lvar, sym))}

      # Predicate symbols: get closed() { return closed.call(this) }
      pred_pairs = predicate_symbols.map do |sym|
        getter = s(:def, nil, s(:args),
          s(:autoreturn, s(:send, s(:lvar, sym), :call, s(:self))))
        s(:pair, s(:prop, sym), { get: getter })
      end

      prop_pairs = accessor_list.map do |info|
        pair = {}
        pair[:get] = info[1] if info[1]
        pair[:set] = info[2]
        s(:pair, s(:prop, info[0]), pair)
      end

      body = body.reject {|node| omit.include? node}.concat([s(:return, s(:hash,
        *regular_pairs, *pred_pairs, *prop_pairs))])

      body = s(:send, s(:block, s(:send, nil, :proc), s(:args),
        s(:begin, *body)), :[])
      if not name or @ast.type == :module_hash
        # module_hash is used when module appears as hash value - don't emit const declaration
        parse body
      elsif extend
        parse s(:assign, name, body)
      elsif name.children.first == nil
        # Use casgn for const declaration (consistent with class_module)
        parse s(:casgn, nil, name.children.last, body), :statement
      else
        parse s(:send, name.children.first, "#{name.children.last}=", body)
      end

      @underscored_private = saved_underscored_private
      @namespace.leave()
    end
  end
end
