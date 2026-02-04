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
          parse @ast.updated(:casgn, [*name.children, s(:hash)])
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

      symbols = []
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
          end
        end

        next unless visibility == :public

        if node.type == :casgn and node.children.first == nil
          symbols << node.children[1]
        elsif node.type == :def
          # Strip ? and ! from method names (they're stripped in def transpilation)
          method_name = node.children.first.to_s.sub(/[?!]$/, '').to_sym
          symbols << method_name
        elsif node.type == :defs and node.children.first.type == :self
          # Convert singleton method (def self.X) to regular function
          # In IIFE context, this.X = ... fails because this is undefined
          method_name = node.children[1].to_s.sub(/[?!]$/, '').to_sym
          symbols << method_name
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
          method_name = node.children[1].to_s.sub(/[?!]$/, '').to_sym
          symbols << method_name
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
            info[1] = info[1].updated(nil, [nil, *info[1].children[1..-1]])
          end
          info[2] = info[2].updated(nil, [nil, *info[2].children[1..-1]])
        end
      end

      regular_pairs = symbols.map {|sym| s(:pair, s(:sym, sym), s(:lvar, sym))}
      prop_pairs = accessor_list.map do |info|
        pair = {}
        pair[:get] = info[1] if info[1]
        pair[:set] = info[2]
        s(:pair, s(:prop, info[0]), pair)
      end

      body = body.reject {|node| omit.include? node}.concat([s(:return, s(:hash,
        *regular_pairs, *prop_pairs))])

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

      @namespace.leave()
    end
  end
end
