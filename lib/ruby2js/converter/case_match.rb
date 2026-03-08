module Ruby2JS
  class Converter

    # (case_match
    #   (send nil :x)
    #   (in_pattern
    #     (array_pattern ...)
    #     nil
    #     (...))
    #   nil)

    handle :case_match do |expr, *rest|
      if @state == :expression
        parse s(:kwbegin, @ast), @state
        return
      end

      begin
        inner, @inner = @inner, @ast

        branches = rest
        else_body = branches.pop unless branches.last&.type == :in_pattern

        # Assign predicate to temp variable to avoid re-evaluation
        case_var = gensym(:$case)
        put "let #{case_var} = "; parse expr; put @sep

        branches.each_with_index do |branch, index|
          pattern, guard, body = branch.children

          # Prism wraps guard in an :if node inside the pattern
          if pattern.type == :if
            guard = pattern.children[0]
            pattern = pattern.children[1]
          end

          put(index == 0 ? 'if (' : ' else if (')
          emit_pattern_condition(pattern, case_var)
          puts ') {'

          emit_pattern_bindings(pattern, case_var)

          if guard
            # Guard may reference variables bound by the pattern,
            # so it must be checked after bindings are emitted
            put 'if ('
            parse guard
            puts ') {'
            parse body, :statement
            sput '}'
          else
            parse body, :statement
          end

          sput '}'
        end

        if else_body
          puts ' else {'
          parse else_body, :statement
          sput '}'
        end
      ensure
        @inner = inner
      end
    end

    # x in pattern (returns boolean)
    handle :match_pattern_p do |expr, pattern|
      case_var = gensym(:$case)
      put "(() => { let #{case_var} = "
      parse expr
      put "; return "
      emit_pattern_condition(pattern, case_var)
      put " })()"
    end

    private

    # Generate a unique symbol name for temporaries
    def gensym(prefix)
      @gensym_counter ||= 0
      @gensym_counter += 1
      "#{prefix}#{@gensym_counter}"
    end

    # Map Ruby constant names to JavaScript type checks
    TYPE_CHECKS = {
      Integer:  ->(v) { "typeof #{v} === \"number\" && Number.isInteger(#{v})" },
      Float:    ->(v) { "typeof #{v} === \"number\"" },
      Numeric:  ->(v) { "typeof #{v} === \"number\"" },
      String:   ->(v) { "typeof #{v} === \"string\"" },
      Symbol:   ->(v) { "typeof #{v} === \"symbol\"" },
      Array:    ->(v) { "Array.isArray(#{v})" },
      Hash:     ->(v) { "typeof #{v} === \"object\" && #{v} !== null && !Array.isArray(#{v})" },
      Regexp:   ->(v) { "#{v} instanceof RegExp" },
      NilClass: ->(v) { "#{v} === null || #{v} === undefined" },
      TrueClass: ->(v) { "#{v} === true" },
      FalseClass: ->(v) { "#{v} === false" },
    }

    # Emit the condition check for a pattern against a target variable
    def emit_pattern_condition(pattern, target)
      case pattern.type
      when :match_var, :lvasgn
        # Always matches — captures a variable
        put 'true'

      when :pin
        # ^variable — test equality against pinned value
        put "#{target} === "
        parse pattern.children[0]

      when :match_as
        # Type => var — emit inner pattern condition
        inner_pattern = pattern.children[0]
        emit_pattern_condition(inner_pattern, target)

      when :match_alt
        # pattern1 | pattern2
        put '('
        emit_pattern_condition(pattern.children[0], target)
        put ' || '
        emit_pattern_condition(pattern.children[1], target)
        put ')'

      when :const
        # Type check (Integer, String, etc.)
        const_name = pattern.children[1]
        check = TYPE_CHECKS[const_name]
        if check
          put check.call(target)
        else
          put "#{target} instanceof "
          parse pattern
        end

      when :array_pattern
        emit_array_pattern_condition(pattern, target)

      when :hash_pattern
        emit_hash_pattern_condition(pattern, target)

      when :find_pattern
        emit_find_pattern_condition(pattern, target)

      when :if
        # Guard clause — condition wraps the actual pattern
        # The guard is children[0], the pattern is children[1]
        emit_pattern_condition(pattern.children[1], target)
        put ' && ('
        parse pattern.children[0]
        put ')'

      when :nil
        put "#{target} == null"

      when :true, :false
        put "#{target} === "
        parse pattern

      when :int, :float, :str, :sym, :rational, :complex
        put "#{target} === "
        parse pattern

      when :irange
        put "#{target} >= "
        parse pattern.children[0]
        put " && #{target} <= "
        parse pattern.children[1]

      when :erange
        put "#{target} >= "
        parse pattern.children[0]
        put " && #{target} < "
        parse pattern.children[1]

      when :regexp
        parse pattern
        put ".test(#{target})"

      when :lambda, :send
        # Proc/lambda patterns use === which calls the proc
        parse pattern
        put "(#{target})"

      else
        # Fallback: use strict equality
        put "#{target} === "
        parse pattern
      end
    end

    # Emit variable bindings for a pattern
    def emit_pattern_bindings(pattern, target)
      case pattern.type
      when :match_var, :lvasgn
        name = pattern.children[0]
        @vars[name] = true
        put "let #{name} = #{target}#{@sep}" unless name == :_

      when :match_as
        inner_pattern = pattern.children[0]
        var_node = pattern.children[1]
        # Emit bindings from inner pattern first
        emit_pattern_bindings(inner_pattern, target)
        # Then bind the variable
        if var_node.type == :match_var || var_node.type == :lvasgn
          name = var_node.children[0]
          @vars[name] = true
          put "let #{name} = #{target}#{@sep}" unless name == :_
        end

      when :array_pattern
        emit_array_pattern_bindings(pattern, target)

      when :hash_pattern
        emit_hash_pattern_bindings(pattern, target)

      when :if
        # Guard — emit bindings for the inner pattern
        emit_pattern_bindings(pattern.children[1], target)

      when :match_alt, :pin, :const, :nil, :true, :false,
           :int, :float, :str, :sym, :irange, :erange, :regexp
        # No bindings for these patterns
      end
    end

    # Array pattern: [a, b, *rest, c]
    def emit_array_pattern_condition(pattern, target)
      elements = pattern.children
      has_splat = elements.any? { |e| e.type == :splat || e.type == :match_rest }
      non_splat = elements.reject { |e| e.type == :splat || e.type == :match_rest }

      put "Array.isArray(#{target})"

      if has_splat
        put " && #{target}.length >= #{non_splat.length}"
      else
        put " && #{target}.length === #{elements.length}"
      end

      splat_index = elements.index { |e| e.type == :splat || e.type == :match_rest }
      after_splat = splat_index ? elements.length - splat_index - 1 : 0

      elements.each_with_index do |element, i|
        next if element.type == :splat || element.type == :match_rest
        next if element.type == :match_var || element.type == :lvasgn

        if splat_index && i > splat_index
          # Elements after splat use negative offset from end
          offset = elements.length - i
          element_target = "#{target}[#{target}.length - #{offset}]"
        else
          element_target = "#{target}[#{i}]"
        end

        put ' && '
        emit_pattern_condition(element, element_target)
      end
    end

    def emit_array_pattern_bindings(pattern, target)
      elements = pattern.children
      splat_index = elements.index { |e| e.type == :splat || e.type == :match_rest }
      after_splat = splat_index ? elements.length - splat_index - 1 : 0

      elements.each_with_index do |element, i|
        if element.type == :splat || element.type == :match_rest
          # Splat binding: rest = target.slice(i, target.length - after_count)
          inner = element.children[0]
          if inner
            var_node = inner.type == :lvasgn ? inner : inner
            name = var_node.children[0]
            if name && name != :_
              @vars[name] = true
              if after_splat > 0
                put "let #{name} = #{target}.slice(#{i}, #{target}.length - #{after_splat})#{@sep}"
              else
                put "let #{name} = #{target}.slice(#{i})#{@sep}"
              end
            end
          end
        else
          if splat_index && i > splat_index
            offset = elements.length - i
            element_target = "#{target}[#{target}.length - #{offset}]"
          else
            element_target = "#{target}[#{i}]"
          end

          emit_pattern_bindings(element, element_target)
        end
      end
    end

    # Hash pattern: {name:, age: Integer => a}
    def emit_hash_pattern_condition(pattern, target)
      put "typeof #{target} === \"object\" && #{target} !== null"

      pattern.children.each do |element|
        if element.type == :pair
          key = element.children[0].children[0]  # sym node -> name
          put " && \"#{key}\" in #{target}"

          value_pattern = element.children[1]
          unless value_pattern.type == :match_var
            put ' && '
            emit_pattern_condition(value_pattern, "#{target}.#{key}")
          end
        elsif element.type == :match_var
          # Implicit {name:} — key is the variable name
          key = element.children[0]
          put " && \"#{key}\" in #{target}"
        elsif element.type == :kwnilarg
          # **nil — no additional keys allowed
          # Check that target has no keys beyond those listed
          other_keys = pattern.children
            .select { |e| e.type == :pair || e.type == :match_var }
            .map { |e| e.type == :pair ? e.children[0].children[0] : e.children[0] }
          put " && Object.keys(#{target}).length === #{other_keys.length}"
        end
      end
    end

    def emit_hash_pattern_bindings(pattern, target)
      pattern.children.each do |element|
        if element.type == :pair
          key = element.children[0].children[0]
          value_pattern = element.children[1]
          emit_pattern_bindings(value_pattern, "#{target}.#{key}")
        elsif element.type == :match_var
          key = element.children[0]
          @vars[key] = true
          put "let #{key} = #{target}.#{key}#{@sep}"
        end
      end
    end

    # Find pattern: [*, needle, *]
    def emit_find_pattern_condition(pattern, target)
      elements = pattern.children
      # Find patterns have the form: splat, ...needles..., splat
      needles = elements.reject { |e| e.type == :splat || e.type == :match_rest }

      put "Array.isArray(#{target})"

      if needles.length == 1 && [:int, :float, :str, :sym].include?(needles[0].type)
        # Simple literal: use includes
        put " && #{target}.includes("
        parse needles[0]
        put ')'
      else
        # General case: use some()
        needle = needles[0]
        find_var = gensym(:$find)
        put " && #{target}.some(#{find_var} => "
        emit_pattern_condition(needle, find_var)
        put ')'
      end
    end
  end
end
