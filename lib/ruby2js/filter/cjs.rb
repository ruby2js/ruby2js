require 'ruby2js'

module Ruby2JS
  module Filter
    module CJS
      include SEXP

      def on_send(node)
        return super unless node.children[1] == :export

        if node.children[2].type == :def
          fn = node.children[2]
          node.updated(nil, [
            s(:attr, nil, :exports),
            fn.children[0].to_s + '=',
            s(:block, s(:send, nil, :proc), *process_all(fn.children[1..-1]))
          ])

        elsif node.children[2].type == :lvasgn
          assign = node.children[2]
          node.updated(nil, [
            s(:attr, nil, :exports),
            assign.children[0].to_s + '=',
            *assign.children[1..-1]
          ])

        elsif \
          node.children[2].type == :send and
          node.children[2].children[0..1] == [nil, :async] and
          node.children[2].children[2].type == :def
        then
          fn = node.children[2].children[2]
          node.updated(nil, [
            s(:attr, nil, :exports),
            fn.children[0].to_s + '=',
            s(:send, nil, :async,
              s(:block, s(:send, nil, :proc),
              *process_all(fn.children[1..-1])))
          ])

        elsif \
          node.children[2].type == :send and
          node.children[2].children[0..1] == [nil, :default]
        then
          node = node.children[2]

          node.updated(nil, [
            s(:attr, nil, :module),
            :exports=,
            node.children[2]
          ])

        else
          super
        end
      end

      def on_block(node)
        child = node.children[0]
        unless child.type == :send and child.children[0..1] == [nil, :export]
          return super 
        end

        send = child.children[2]
        unless send.type == :send and send.children[0..1] == [nil, :default]
          return super 
        end

        if send.children[2] == s(:send, nil, :proc)
          node.updated(:send, [
            s(:attr, nil, :module),
            :exports=,
            s(:block, s(:send, nil, :proc),
            *process_all(node.children[1..-1]))
          ])
        elsif send.children[2] == s(:send, nil, :async, s(:send, nil, :proc))
          node.updated(:send, [
            s(:attr, nil, :module),
            :exports=,
            s(:send, nil, :async,
              s(:block, s(:send, nil, :proc),
              *process_all(node.children[1..-1])))
          ])
        else
          super
        end
      end
    end

    DEFAULTS.push CJS
  end
end
