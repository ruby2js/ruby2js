require 'ruby2js'

# Note care is taken to run all the filters first before camelCasing.
# This ensures that Ruby methods like each_pair can be mapped to
# JavaScript before camelcasing.

module Ruby2JS
  module Filter
    module CamelCase
      include SEXP

      ALLOWLIST = %w{
        attr_accessor
        attr_reader
        attr_writer
        method_missing
        is_a?
        kind_of?
        instance_of?
      }

      CAPS_EXCEPTIONS = {
        "innerHtml" => "innerHTML",
        "innerHtml=" => "innerHTML=",
        "outerHtml" => "outerHTML",
        "outerHtml=" => "outerHTML=",
        "encodeUri" => "encodeURI",
        "encodeUriComponent" => "encodeURIComponent",
        "decodeUri" => "decodeURI",
        "decodeUriComponent" => "decodeURIComponent"
      }

      def camelCase(symbol)
        return symbol if ALLOWLIST.include?(symbol.to_s)

        should_symbolize = symbol.is_a?(Symbol)
        symbol = symbol
                  .to_s
                  .gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}
                  .gsub(/^(.*)$/) {|match| CAPS_EXCEPTIONS[match] || match }
        should_symbolize ? symbol.to_sym : symbol
      end

      def on_send(node)
        node = super
        return node unless [:send, :csend, :attr].include? node.type

        if node.children[0] == nil and ALLOWLIST.include? node.children[1].to_s
          node
        elsif node.children[0] && [:ivar, :cvar].include?(node.children[0].type)
          S(node.type, s(node.children[0].type, camelCase(node.children[0].children[0])),
            camelCase(node.children[1]), *node.children[2..-1])
        elsif node.children[1] =~ /_.*\w[=!?]?$/
          S(node.type, node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          node
        end
      end
      
      def on_csend(node)
        on_send(node)
      end

      def on_attr(node)
        on_send(node)
      end

      def handle_generic_node(node, node_type)
        return node if node.type != node_type

        if node.children[0].to_s =~ /_.*[?!\w]$/ and !ALLOWLIST.include?(node.children[0].to_s)
          S(node_type , camelCase(node.children[0]), *node.children[1..-1])
        else
          node
        end
      end

      def on_def(node)
        handle_generic_node(super, :def)
      end

      def on_optarg(node)
        handle_generic_node(super, :optarg)
      end

      def on_kwoptarg(node)
        handle_generic_node(super, :kwoptarg)
      end

      def on_lvar(node)
        handle_generic_node(super, :lvar)
      end

      def on_ivar(node)
        handle_generic_node(super, :ivar)
      end

      def on_cvar(node)
        handle_generic_node(super, :cvar)
      end

      def on_arg(node)
        handle_generic_node(super, :arg)
      end

      def on_kwarg(node)
        handle_generic_node(super, :kwarg)
      end

      def on_lvasgn(node)
        handle_generic_node(super, :lvasgn)
      end

      def on_ivasgn(node)
        handle_generic_node(super, :ivasgn)
      end

      def on_cvasgn(node)
        handle_generic_node(super, :cvasgn)
      end

      def on_match_pattern(node)
        handle_generic_node(super, :match_pattern)
      end

      def on_match_var(node)
        handle_generic_node(super, :match_var)
      end

      def on_sym(node)
        handle_generic_node(super, :sym)
      end

      def on_defs(node)
        node = super
        return node if node.type != :defs

        if node.children[1] =~ /_.*[?!\w]$/
          S(:defs , node.children[0],
            camelCase(node.children[1]), *node.children[2..-1])
        else
          node
        end
      end
    end

    DEFAULTS.push CamelCase
  end
end
