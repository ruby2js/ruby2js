require 'ruby2js'

module Ruby2JS
  module Filter
    module CamelCase
      include SEXP

      WHITELIST = %w{
        attr_accessor
      }

      def camelCase(symbol)
        symbol.to_s.gsub(/_[a-z]/) {|match| match[1].upcase}
      end

      def on_send(node)
        if node.children[0] == nil and WHITELIST.include? node.children[1].to_s
          super
        elsif node.children[1] =~ /_.*\w$/
          super s((node.is_method? ? :send : :attr) , node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          super
        end
      end

      def on_def(node)
        if node.children[0] =~ /_.*\w$/
          super s(:def , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_optarg(node)
        if node.children[0] =~ /_.*\w$/
          super s(:optarg , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_lvar(node)
        if node.children[0] =~ /_.*\w$/
          super s(:lvar , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_arg(node)
        if node.children[0] =~ /_.*\w$/
          super s(:arg , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_lvasgn(node)
        if node.children[0] =~ /_.*\w$/
          super s(:lvasgn , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_sym(node)
        if node.children[0] =~ /_.*\w$/
          super s(:sym , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_defs(node)
        if node.children[1] =~ /_.*\w$/
          super s(:defs , node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          super
        end
      end
    end

    DEFAULTS.push CamelCase
  end
end
