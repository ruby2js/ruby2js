require 'parser/current'
require 'ruby2js'

module Ruby2JS
  module Filter
    module AngularRB
      include SEXP

      def initialize(*args)
        @ngApp = nil
        @ngAppUses = []
        @ngClassUses = []
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
        @ngAppUses = []

        # find the block
        block = process_all(node.children[1..-1])
        while block.length == 1 and block.first and block.first.type == :begin
          block = block.first.children.dup
        end

        # find use class method calls

        # convert use calls into dependencies
        depends = @ngAppUses.map {|sym| s(:sym, sym)} + extract_uses(block)
        depends = depends.map {|node| node.children.first.to_s}.uniq.
          map {|sym| s(:str, sym)}

        # build constant assignment statement
        casgn = s(:casgn, nil, @ngApp, s(:send, 
                  s(:lvar, :angular), 
                  :module,
                  s(:str, @ngApp.to_s), 
                  s(:array, *depends.uniq)))

        @ngApp = nil

        # replace module with a constant assign followed by the module contents
        node.updated :begin, [casgn, *block.compact]
      end

      # input: 
      #   filter :name { ... }
      #   controller :name { ... }
      #   factory :name { ... }

      def on_block(node)
        return super unless @ngApp
        call = node.children.first
        return super if call.children.first

        case call.children[1]
        when :controller
          ng_controller(node)
        when :factory
          ng_factory(node)
        when :filter
          ng_filter(node)
        else
          super
        end
      end

      # input:
      #  controller :name do
      #    ...
      #  end
      #
      def ng_controller(node)
        target = node.children.first
        target = target.updated(nil, [s(:const, nil, @ngApp), 
          *target.children[1..-1]])

        # find the block
        block = process_all(node.children[2..-1])
        while block.length == 1 and block.first.type == :begin
          block = block.first.children.dup
        end

        # convert use calls into args
        args = node.children[1].children
        args += @ngClassUses.map {|sym| s(:arg, sym)} + extract_uses(block)
        args = args.map {|node| node.children.first.to_sym}.uniq.
          map {|sym| s(:arg, sym)}

        node.updated :block, [target, s(:args, *args), s(:begin, *block)]
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
      def ng_filter(node)
        call = node.children.first

        # insert return
        args = process_all(node.children[1].children)
        block = process_all(node.children[2..-1])
        tail = [block.pop || s(:nil)]
        while tail.length == 1 and tail.first.type == :begin
          tail = tail.first.children.dup
        end
        tail.push s(:return, tail.pop) unless tail.last.type == :return
        block.push (tail.length == 1 ? tail.first : s(:begin, *tail))

        # construct a function returning a function
        inner = s(:block, s(:send, nil, :lambda), s(:args, *args), *block)
        outer = s(:send, s(:lvar, @ngApp), :filter, *call.children[2..-1])

        node.updated nil, [outer, s(:args), s(:return, inner)]
      end

      # input: 
      #   factory :name do |uses|
      #     ...
      #   end
      #
      # output: 
      #   AppName.factory :name, [uses, lambda {|uses| ...}]
      def ng_factory(node)
        call = node.children.first
        call = call.updated(nil, [s(:lvar, @ngApp), *call.children[1..-1]])

        # insert return
        block = process_all(node.children[2..-1])
        tail = [block.pop || s(:nil)]
        while tail.length == 1 and tail.first.type == :begin
          tail = tail.first.children.dup
        end
        tail.push s(:return, tail.pop) unless tail.last.type == :return
        block.push (tail.length == 1 ? tail.first : s(:begin, *tail))

        # extract dependencies
        args = process_all(node.children[1].children)
        args += @ngClassUses.map {|sym| s(:arg, sym)} + extract_uses(block)
        args = args.map {|node| node.children.first.to_sym}.uniq.
          map {|sym| s(:arg, sym)}

        # construct a function
        function = s(:block, s(:send, nil, :lambda), s(:args, *args), *block)
        array = args.map {|arg| s(:str, arg.children.first.to_s)}

        s(:send, *call.children, s(:array, *array, function))
      end

      # input: 
      #   Constant = ...
      #
      # output: 
      #   AppName.factory :name, [uses, lambda {|uses| ...}]
      def on_casgn(node)
        return super unless @ngApp
        return super if node.children[0]
        ng_factory s(:block, s(:send, nil, :factory, s(:sym, node.children[1])),
          s(:args), process(node.children[2]))
      end

      def on_gvar(node)
        if @ngClassUses
          @ngClassUses << node.children.first
        end

        super
      end

      def on_const(node)
        if @ngClassUses
          @ngClassUses << node.children.last if not node.children.first
        end

        super
      end

      def extract_uses(block)
        # find use class method calls
        uses = block.find_all do |node|
          node and node.type == :send and node.children[0..1] == [nil, :use]
        end

        # convert use calls into dependencies
        depends = []
        uses.each do |use|
          use.children[2..-1].each do |node|
            depends << node if [:str, :sym].include? node.type
          end
          block.delete use
        end

        depends
      end
    end

    DEFAULTS.push AngularRB
  end
end
