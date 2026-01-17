require 'ruby2js'

module Ruby2JS
  module Filter
    module SFC
      include SEXP
      extend SEXP

      # Transform instance variable assignment to framework-appropriate declaration
      # @title = "Hello" becomes:
      #   Astro:  const title = "Hello"
      #   Svelte: let title = "Hello"
      #   Vue:    const title = ref("Hello")
      def on_ivasgn(node)
        return super unless @options[:template]

        var_name = node.children.first.to_s[1..-1].to_sym  # strip @
        value = node.children.last ? process(node.children.last) : nil

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

        var_name = node.children.first.to_s[1..-1].to_sym  # strip @

        case @options[:template].to_sym
        when :vue
          # Vue refs need .value access, but in templates Vue auto-unwraps
          # For script code, we just use the variable name (ref is accessed directly)
          s(:lvar, var_name)
        else
          s(:lvar, var_name)
        end
      end
    end

    DEFAULTS.push SFC
  end
end
