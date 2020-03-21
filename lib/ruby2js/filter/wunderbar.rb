require 'ruby2js'

module Ruby2JS
  module Filter
    module Wunderbar
      include SEXP

      def on_send(node)
        target, method, *attrs = node.children

        stack = []
        while target != nil and target.type == :send and target.children.length == 2
          name = method.to_s
          if name.end_with? '!'
            stack << s(:hash, s(:pair, s(:sym, :id), s(:str, name[0..-2])))
          else
            stack << s(:hash, s(:pair, s(:sym, :class), s(:str, name)))
          end
          target, method = target.children
        end

        if target == nil and method.to_s.start_with? "_"
          s(:xnode, *method.to_s[1..-1], *stack, *attrs)
        else
          super
        end
      end

      def on_block(node)
        send, args, *block = node.children
        target, method, *attrs = send.children
        while target != nil and target.type == :send and target.children.length == 2
          target, method = target.children
        end

        if target == nil and method.to_s.start_with? "_"
          process send.updated(nil, [*send.children, *process_all(block)])
        else
          super
        end
      end
    end

    DEFAULTS.push Wunderbar
  end
end
