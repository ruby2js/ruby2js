require 'ruby2js'

# Convert Wunderbar syntax to JSX

module Ruby2JS
  module Filter
    module JSX
      include SEXP

      def on_send(node)
        target, method, *args = node.children

        if target == s(:const, nil, :Wunderbar)
          if [:debug, :info, :warn, :error, :fatal].include? method
            method = :error if method == :fatal
            return node.updated(nil, [s(:const, nil, :console), method, *args])
          end
        end

        stack = []
        while target!=nil and target.type==:send and target.children.length==2
          name = method.to_s
          if name.end_with? '!'
            stack << s(:hash, s(:pair, s(:sym, :id), s(:str, name[0..-2])))
          else
            stack << s(:hash, s(:pair, s(:sym, :class), s(:str, name)))
          end
          target, method = target.children
        end

        if target == nil and method.to_s.start_with? "_"
          S(:xnode, method.to_s[1..-1], *stack, *process_all(args))

        elsif method == :createElement and target == s(:const, nil, :React)
          if args.first.type == :str and \
            (args.length == 1 or %i(nil hash).include? args[1].type)
            attrs = (args[1]&.type != :nil && args[1]) || s(:hash)
            S(:xnode, args[0].children.first, attrs, *process_all(args[2..-1]))
          else
            super
          end

        else
          super
        end
      end

      def on_block(node)
        send, args, *block = node.children
        target, method, *_ = send.children
        while target!=nil and target.type==:send and target.children.length==2
          target, method = target.children
        end

        if target == nil and method.to_s.start_with? "_"
          if args.children.empty?
            if method == :_
              # Fragment
              if send.children.length == 2
                process send.updated(:xnode, ['', *process_all(block)])
              else
                process s(:xnode, 'React.Fragment', *send.children[2..-1],
                  *process_all(block))
              end
            else
              # append block as a standalone proc
              process send.updated(nil, [*send.children, *process_all(block)])
            end
          else
            # iterate over Enumerable arguments if there are args present
            send = send.children
            return super if send.length < 3
            process s(:block, s(:send, *send[0..1], *send[3..-1]),
              s(:args), s(:block, s(:send, send[2], :map),
              *node.children[1..-1]))
          end
        else
          super
        end
      end
    end

    DEFAULTS.push JSX
  end
end
