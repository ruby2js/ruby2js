require 'ruby2js'

module Ruby2JS
  module Filter
    module Node
      include SEXP

      def initialize(*args)
        @node_prefix = nil
        super
      end

      def process(node)
        return super if @node_prefix
        @node_prefix = []
        result = super

        return s(:begin, *@node_prefix.uniq, super)
      end

      def on_send(node)
        target, method, *args = node.children

        if target == nil
          if target == nil and method == :__dir__
            S(:attr, nil, :__dirname)
          else
            super
          end

        elsif 
          [:File, :IO].include? target.children.last and
          target.type == :const and target.children.first == nil
        then
          if method == :read and args.length == 1
            @node_prefix << s(:casgn, nil, :fs, 
              s(:send, nil, :require, s(:str, "fs")))
            s(:send, s(:attr, nil, :fs), :readFileSync, *process_all(args),
              s(:str, 'utf8'))
          elsif method == :write and args.length == 2
            @node_prefix << s(:casgn, nil, :fs, 
              s(:send, nil, :require, s(:str, "fs")))
            S(:send, s(:attr, nil, :fs), :writeFileSync, *process_all(args))
          else
            super
          end

        elsif 
          target.type == :const and target.children.first == nil and
          target.children.last == :Dir
        then
          if method == :chdir and args.length == 1
            S(:send, s(:attr, nil, :process), :chdir, *process_all(args))
          elsif method == :pwd and args.length == 0
            s(:send, s(:attr, nil, :process), :cwd)
          else
            super
          end

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        target, method, *args = call.children

        if 
          method == :chdir and args.length == 1 and
          target.children.last == :Dir and
          target.type == :const and target.children.first == nil
        then
          s(:begin,
            s(:gvasgn, :$oldwd, s(:send, s(:attr, nil, :process), :cwd)),
            s(:kwbegin, s(:ensure, 
              s(:begin, process(call), process(node.children.last)),
              s(:send, s(:attr, nil, :process), :chdir, s(:gvar, :$oldwd)))))
        else
          super
        end
      end

      def on_const(node)
        if node.children == [nil, :ARGV]
          @node_prefix << s(:lvasgn, :ARGV, s(:send, s(:attr, 
            s(:attr, nil, :process), :argv), :slice, s(:int, 1)))
        end

        super
      end

      def on___FILE__(node)
        s(:attr, nil, :__filename)
      end
    end

    DEFAULTS.push Node
  end
end
