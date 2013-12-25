require 'parser/current'
require 'ruby2js'

module Ruby2JS
  module Filter
    module AngularRB
      include SEXP

      def self.s(type, *args)
        Parser::AST::Node.new type, args
      end

      Angular = s(:const, nil, :Angular)

      # convert simple assignments, simple method calls, and simple method
      # definitions into a hash when possible; return false otherwise
      def self.hash(pairs)
        if pairs.length == 1 and pairs.first.type == :begin
          pairs = pairs.first.children
        end

        s(:hash, *pairs.map {|pair| 
          if pair.type == :send and pair.children[0] == nil
            s(:pair, s(:sym, pair.children[1]), pair.children[2])
          elsif pair.type == :lvasgn
            s(:pair, s(:sym, pair.children[0]), pair.children[1])
          elsif pair.type == :def
            s(:pair, s(:sym, pair.children[0]), s(:block, s(:send, nil, :proc),
              *pair.children[1..-1]))
          else
            return false
          end
        })
      end

      def initialize(*args)
        @ngApp = nil
        @ngAppUses = []
        @ngClassUses = []
        @ngClassOmit = []
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

        return super unless parent_name == Angular

        @ngApp = s(:lvar, module_name.children[1])
        @ngChildren = node.children[1..-1]
        while @ngChildren.length == 1 and @ngChildren.first and @ngChildren.first.type == :begin
          @ngChildren = @ngChildren.first.children.dup
        end
        @ngAppUses = []

        block = process_all(node.children[1..-1])

        # convert use calls into dependencies
        depends = @ngAppUses.map {|sym| s(:sym, sym)} + extract_uses(block)
        depends = depends.map {|node| node.children.first.to_s}.uniq.
          map {|sym| s(:str, sym)}

        name, @ngApp, @ngChildren = @ngApp, nil, nil

        # construct app
        app = s(:send, s(:lvar, :angular), :module, 
          s(:str, module_name.children[1].to_s), s(:array, *depends.uniq))

        # return a single chained statement when there is only one call
        block.compact!
        if block.length == 0
          return app
        elsif block.length == 1
          call = block.first.children.first
          if block.first.type == :send and call == name
            return block.first.updated nil, [app, *block.first.children[1..-1]]
          elsif block.first.type == :block and call.children.first == name
            call = call.updated nil, [app, *call.children[1..-1]]
            return block.first.updated nil, [call, *block.first.children[1..-1]]
          end
        end

        # replace module with a constant assign followed by the module
        # contents all wrapped in an anonymous function
        s(:send, s(:block, s(:send, nil, :lambda), s(:args),
          s(:begin, s(:casgn, nil, name, app), *block)), :[])
      end

      # input: 
      #   class name {...}
      #
      # output:
      #  app.factory(uses) do
      #    ...
      #  end
      def on_class(node)
        return super unless @ngApp and @ngChildren.include? node
        name = node.children.first
        if name.children.first == nil
          @ngClassUses, @ngClassOmit = [], []
          block = [node.children.last]
          uses = extract_uses(block)
          node = s(:class, name, node.children[1], 
            s(:begin, *process_all(block)))

          @ngClassUses -= @ngClassOmit + [name.children.last]
          args = @ngClassUses.map {|sym| s(:arg, sym)} + uses
          args = args.map {|node| node.children.first.to_sym}.uniq.
            map {|sym| s(:arg, sym)}
          @ngClassUses, @ngClassOmit = [], []

         s(:block, s(:send, @ngApp, :factory,
            s(:sym, name.children.last)), s(:args, *args), 
            s(:begin, node, s(:return, s(:const, nil, name.children.last))))
        else
          super
        end
      end

      # input: 
      #   filter :name { ... }
      #   controller :name { ... }
      #   factory :name { ... }
      #   directive :name { ... }

      def on_block(node)
        ngApp = @ngApp
        call = node.children.first
        target = call.children.first
        if target and target.type == :const and target.children.first == Angular
          @ngApp = s(:send, s(:lvar, :angular), :module, s(:str,
            target.children.last.to_s))
        else
          return super unless @ngApp
        end

        begin
          case call.children[1]
          when :controller
            ng_controller(node)
          when :factory
            ng_factory(node)
          when :filter
            ng_filter(node)
          when :directive
            hash = AngularRB.hash(node.children[2..-1])
            if hash
              node = node.updated nil, [*node.children[0..1], s(:return, hash)]
            end
            ng_controller(node) # reuse template
          else
            super
          end
        ensure
          @ngApp = ngApp
        end
      end

      # input:
      #  controller :name do
      #    ...
      #  end
      #
      def ng_controller(node)
        @ngClassUses, @ngClassOmit = [], []
        target = node.children.first
        target = target.updated(nil, [@ngApp, *target.children[1..-1]])

        block = process_all(node.children[2..-1])

        # convert use calls into args
        @ngClassUses -= @ngClassOmit
        args = node.children[1].children
        args += @ngClassUses.map {|sym| s(:arg, sym)} + extract_uses(block)
        args = args.map {|node| node.children.first.to_sym}.uniq.
          map {|sym| s(:arg, sym)}
        @ngClassUses, @ngClassOmit = [], []

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
      EXPRESSION = [ :and, :array, :attr, :const, :cvar, :defined?, :dstr,
        :dsym, :false, :float, :gvar, :hash, :int, :ivar, :lvar, :nil, :not,
        :or, :regexp, :self, :send, :str, :sym, :true, :undefined?, :xstr ]

      def ng_filter(node)
        @ngClassUses, @ngClassOmit = [], []
        call = node.children.first

        # insert return
        args = process_all(node.children[1].children)
        block = process_all(node.children[2..-1])
        uses = (@ngClassUses - @ngClassOmit).uniq.map {|sym| s(:arg, sym)}
        tail = [block.pop || s(:nil)]
        while tail.length == 1 and tail.first.type == :begin
          tail = tail.first.children.dup
        end
        tail.push s(:return, tail.pop) if EXPRESSION.include? tail.last.type
        block.push (tail.length == 1 ? tail.first : s(:begin, *tail))

        # construct a function returning a function
        inner = s(:block, s(:send, nil, :lambda), s(:args, *args), *block)
        outer = s(:send, @ngApp, :filter, *call.children[2..-1])

        node.updated nil, [outer, s(:args, *uses), s(:return, inner)]
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
        call = call.updated(nil, [@ngApp, *call.children[1..-1]])

        # insert return
        block = process_all(node.children[2..-1])
        tail = [block.pop || s(:nil)]
        while tail.length == 1 and tail.first.type == :begin
          tail = tail.first.children.dup
        end
        tail.push s(:return, tail.pop) unless tail.last.type == :return
        block.push (tail.length == 1 ? tail.first : s(:begin, *tail))

        # extract dependencies
        @ngClassUses.delete call.children[2].children[0]
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
        return super if node.children[0]
        @ngClassOmit << node.children[1]
        return super unless @ngApp and @ngChildren.include? node
        ng_factory s(:block, s(:send, nil, :factory, s(:sym, node.children[1])),
          s(:args), process(node.children[2]))
      end

      def on_gvar(node)
        if @ngClassUses
          @ngClassUses << node.children.first
        end

        super
      end

      BUILTINS = [ :Array, :Boolean, :Date, :Error, :Function, :Infinity, :JSON,
        :Math, :NaN, :Number, :Object, :RegExp, :String ]

      def on_const(node)
        if @ngClassUses and not node.children.first
          unless BUILTINS.include? node.children.last
            @ngClassUses << node.children.last
          end
        end

        super
      end

      def extract_uses(block)
        # find the block
        while block.length == 1 and block.first and block.first.type == :begin
          block.push *block.shift.children
        end

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
