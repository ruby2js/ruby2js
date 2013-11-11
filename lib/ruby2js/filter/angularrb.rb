require 'parser/current'
require 'ruby2js'

module Ruby2JS
  module Filter
    module AngularRB
      def initialize(*args)
        @ngApp = nil
        super
      end

      # input: 
      #   module Angular::AppName
      #     ...
      #   end
      #
      # output: 
      #   AppName = angular.module("AppName", [])
      #   ...

      def on_module(node)
        module_name = node.children[0]
        parent_name = module_name.children[0]

        return super unless parent_name and parent_name.type == :const
        return super unless parent_name.children == [nil, :Angular]

        @ngApp = module_name.children[1]

        # build constant assignment statement
        casgn = s(:casgn, nil, @ngApp, s(:send, 
                  s(:lvar, :angular), 
                  :module,
                  s(:str, @ngApp.to_s), 
                  s(:array)))

        # process remaining children
        children = process_all(node.children[1..-1])

        @ngApp = nil

        # replace module with a constant assign followed by the module contents
        node.updated :begin, [casgn, *children]
      end

      # input: 
      #   class Name < Angular::Controller
      #     inject :$service
      #     ...
      #   end
      #
      # output: 
      #   AppName.controller :Name do |$service|
      #     ...
      #   end

      def on_class(node)
        return super unless @ngApp
        return super unless node.children.length == 3
        return super unless node.children.last.type == :begin
        name = node.children.first
        return super unless name.type == :const and name.children.first == nil
        block = process_all(node.children.last.children)

        # find inject class method calls
        injects = block.find_all do |node|
          node.type == :send and node.children[0..1] == [nil, :inject]
        end

        # convert inject calls into args
        args = []
        injects.each do |inject|
          pending = []
          inject.children[2..-1].each do |child|
            break unless child.type == :sym
            pending << s(:arg, *child.children)
          end
          args += pending
          block.delete inject
        end

        # build Appname.controller call statement
        call = s(:send,
                 s(:const, nil, @ngApp),
                 :controller,
                 s(:sym, name.children.last))

        # replace class with a block
        node.updated :block, [call, s(:args, *args), s(:begin, *block)]
      end

      private

      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end

    end

  end

end
