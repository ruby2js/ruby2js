require 'ruby2js'

module Ruby2JS
  module Filter
    module CamelCase
      include SEXP

      WHITELIST = %w{
        attr_accessor
      }

      def camelCase(symbol)
        symbol.to_s.gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}
      end

      def on_send(node)
        if node.children[0] == nil and WHITELIST.include? node.children[1].to_s
          super
        elsif node.children[1] =~ /_.*\w[=!?]?$/
          super S(:send , node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          super
        end
      end

      def on_def(node)
        if node.children[0] =~ /_.*\w$/
          super S(:def , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_optarg(node)
        if node.children[0] =~ /_.*\w$/
          super S(:optarg , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_lvar(node)
        if node.children[0] =~ /_.*\w$/
          super S(:lvar , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_arg(node)
        if node.children[0] =~ /_.*\w$/
          super S(:arg , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_lvasgn(node)
        if node.children[0] =~ /_.*\w$/
          super S(:lvasgn , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_sym(node)
        if node.children[0] =~ /_.*\w$/
          super S(:sym , camelCase(node.children[0]), *node.children[1..-1])
        else
          super
        end
      end

      def on_defs(node)
        if node.children[1] =~ /_.*\w$/
          super S(:defs , node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          super
        end
      end
    end

    DEFAULTS.push CamelCase
  end
end
