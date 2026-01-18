require 'ruby2js'

module Ruby2JS
  module Filter
    module SFC
      include SEXP
      extend SEXP

      # Convert snake_case to camelCase
      def sfc_to_camel_case(str)
        str.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
      end

      # Transform instance variable assignment to framework-appropriate declaration
      # @title = "Hello" becomes:
      #   Astro:  const title = "Hello"
      #   Svelte: let title = "Hello"
      #   Vue:    const title = ref("Hello")
      def on_ivasgn(node)
        return super unless @options[:template]

        var_name = node.children.first.to_s[1..-1]  # strip @
        var_name = sfc_to_camel_case(var_name)  # convert to camelCase

        # For op_asgn like @count += 1, ivasgn only has one child (the name)
        # For regular assignment like @count = 0, it has two children (name and value)
        if node.children.length > 1
          value = process(node.children[1])
        else
          # This is part of an op_asgn - just transform to lvasgn for the target
          return s(:lvasgn, var_name)
        end

        case @options[:template].to_sym
        when :astro
          # const title = value
          s(:casgn, nil, var_name, value)
        when :svelte
          # let title = value (Svelte reactivity uses let)
          s(:lvasgn, var_name, value)
        when :vue
          # const title = ref(value)
          s(:casgn, nil, var_name, s(:send, nil, :ref, value))
        else
          super
        end
      end

      # Transform instance variable reference to local variable
      # @title becomes title
      def on_ivar(node)
        return super unless @options[:template]

        var_name = node.children.first.to_s[1..-1]  # strip @
        var_name = sfc_to_camel_case(var_name)  # convert to camelCase

        case @options[:template].to_sym
        when :vue
          # Vue refs need .value access, but in templates Vue auto-unwraps
          # For script code, we just use the variable name (ref is accessed directly)
          s(:lvar, var_name)
        else
          s(:lvar, var_name)
        end
      end

      # Transform class variable to framework-specific params access
      # @@id becomes:
      #   Astro:  Astro.params.id
      #   Vue:    route.params.id
      #   Svelte: $page.params.id
      def on_cvar(node)
        return super unless @options[:template]

        param_name = node.children.first.to_s[2..-1]  # strip @@
        param_name = sfc_to_camel_case(param_name)  # convert to camelCase

        case @options[:template].to_sym
        when :astro
          # Astro.params.id
          s(:attr, s(:attr, s(:const, nil, :Astro), :params), param_name)
        when :vue
          # route.params.id
          s(:attr, s(:attr, s(:lvar, :route), :params), param_name)
        when :svelte
          # $page.params.id
          s(:attr, s(:attr, s(:gvar, :$page), :params), param_name)
        else
          super
        end
      end
    end

    DEFAULTS.push SFC
  end
end
