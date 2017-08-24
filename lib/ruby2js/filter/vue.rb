#
require 'ruby2js'

module Ruby2JS
  module Filter
    module Vue
      include SEXP

      def initialize(*args)
        @vue = nil
        @vue_h = nil
        super
      end

      # Example conversion
      #  before:
      #    (class (const nil :Foo) (const nil :React) nil)
      #  after:
      #    (casgn nil :foo, (send :React :createClass (hash (sym :displayName)
      #       (:str, "Foo"))))
      def on_class(node)
        cname, inheritance, *body = node.children
        return super unless cname.children.first == nil
        return super unless inheritance == s(:const, nil, :Vue)

        # traverse down to actual list of class statements
        if body.length == 1
          if not body.first
            body = []
          elsif body.first.type == :begin
            body = body.first.children
          end
        end

        hash = []

        # convert body into hash
        body.each do |child|

          # named values
          if child.type == :send and child.children.first == nil
            if child.children[1] == :template
              hash << s(:pair, s(:sym, child.children[1]), child.children[2])
            end

          # methods
          elsif child.type == :def
            args = child.children[1]
            args = s(:args, s(:arg, :$h)) if args.children.empty?
            begin
              @vue_h = args.children.first.children.last
              hash << s(:pair, s(:sym, child.children[0]),
                s(:block, s(:send, nil, :lambda),
                  args, process(child.children[2])))
            ensure
              @vue_h = args.children.first.children.last
            end
          end
        end

        camel = cname.children.last.to_s.
          sub(/^[A-Z]/) {|c| c.downcase}.
          gsub(/[A-Z]/) {|c| "-#{c.downcase}"}

        s(:casgn, nil, cname.children.last,
          s(:send, s(:const, nil, :Vue), :component, 
          s(:str, camel), s(:hash, *hash)))
      end

      def on_send(node)
        return super unless @vue_h
        if node.children[0] == nil and node.children[1] =~ /^_\w/
          node.updated :send, [nil, @vue_h, 
            s(:sym, node.children[1].to_s[1..-1]), *node.children[2..-1]]
        else
          super
        end
      end

    end

    DEFAULTS.push Vue
  end
end
