require 'parser/current'
require 'ruby2js'

module Ruby2JS
  module Filter
    module AngularRB
      include SEXP

      def initialize(*args)
        @ngApp = nil
        super
      end

      # input: 
      #   module Angular::AppName
      #     use :Dependency
      #     ...
      #   end
      #
      # output: 
      #   AppName = angular.module("AppName", ["Dependency"])
      #   ...

      def on_module(node)
        module_name = node.children[0]
        parent_name = module_name.children[0]

        return super unless parent_name and parent_name.type == :const
        return super unless parent_name.children == [nil, :Angular]

        @ngApp = module_name.children[1]

        # find the block
        block = process_all(node.children[1..-1])
        while block.length == 1 and block.first and block.first.type == :begin
          block = block.first.children.dup
        end

        # find use class method calls
        uses = block.find_all do |node|
          node and node.type == :send and node.children[0..1] == [nil, :use]
        end

        # convert use calls into dependencies
        depends = []
        uses.each do |use|
          pending = []
          use.children[2..-1].each do |node|
            break unless [:str, :sym].include? node.type
            pending << node
          end
          depends += pending
          block.delete use
        end

        # build constant assignment statement
        casgn = s(:casgn, nil, @ngApp, s(:send, 
                  s(:lvar, :angular), 
                  :module,
                  s(:str, @ngApp.to_s), 
                  s(:array, *depends)))

        @ngApp = nil

        # replace module with a constant assign followed by the module contents
        node.updated :begin, [casgn, *block]
      end

      # input: 
      #   class Name < Angular::Controller
      #     use :$service
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

        # (const nil :Name)
        name = node.children.first
        return super unless name.type == :const and name.children.first == nil

        # (const (const nil :Angular) :Controller)
        parent = node.children[1]
        return super unless parent and parent.children.length == 2
        return super unless parent.children[0]
        return super unless parent.children[0].type == :const
        return super unless parent.children[0].children == [nil, :Angular]
        return super unless [:Controller].include? parent.children[1]

        # find the block
        block = process_all(node.children[2..-1])
        while block.length == 1 and block.first.type == :begin
          block = block.first.children.dup
        end

        # find use class method calls
        uses = block.find_all do |node|
          node.type == :send and node.children[0..1] == [nil, :use]
        end

        # convert use calls into args
        args = []
        uses.each do |use|
          pending = []
          use.children[2..-1].each do |node|
            break unless [:str, :sym].include? node.type
            pending << s(:arg, *node.children)
          end
          args += pending
          block.delete use
        end

        # build Appname.controller call statement
        call = s(:send,
                 s(:const, nil, @ngApp),
                 :controller,
                 s(:sym, name.children.last))

        # replace class with a block
        node.updated :block, [call, s(:args, *args), s(:begin, *block)]
      end

      # input: 
      #   filter :name do |input|
      #     ...
      #   end
      #
      # output: 
      #   AppName.filter :name do
      #     return lambda {|input| return ... }
      #   end
      def on_block(node)
        return super unless @ngApp

        call = node.children.first
        return super unless call.children[0..1] == [nil, :filter]

        # insert return
        children = process_all(node.children[1..-1])
        block = [children.pop || s(:nil)]
        while block.length == 1 and block.first.type == :begin
          block = block.first.children.dup
        end
        block.push s(:return, block.pop) unless block.last.type == :return
        children.push (block.length == 1 ? block.first : s(:begin, *block))

        # construct a function returning a function
        inner = s(:block, s(:send, nil, :lambda), *children)
        outer = s(:send, s(:lvar, @ngApp), :filter, *call.children[2..-1])

        node.updated nil, [outer, s(:args), s(:return, inner)]
      end
    end

    DEFAULTS.push AngularRB
  end
end
