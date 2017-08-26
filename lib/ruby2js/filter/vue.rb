
require 'ruby2js'

module Ruby2JS
  module Filter
    module Vue
      include SEXP

      def initialize(*args)
        @vue = nil
        @vue_h = nil
        @vue_self = nil
        super
      end

      # Example conversion
      #  before:
      #    (class (const nil :Foo) (const nil :Vue) nil)
      #  after:
      #    (casgn nil :Foo, (send nil, :Vue, :component, (:str, "foo"), 
      #      s(:hash)))
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
        body.each do |statement|

          # named values
          if statement.type == :send and statement.children.first == nil
            if statement.children[1] == :template
              hash << s(:pair, s(:sym, statement.children[1]), 
                statement.children[2])
            end

          # methods
          elsif statement.type == :def
            begin
              @vue_self = s(:attr, s(:self), :$data)
              method, args, block = statement.children
              if method == :render
                args = s(:args, s(:arg, :$h)) if args.children.empty?
                @vue_h = args.children.first.children.last
              elsif method == :initialize
                method = :data

                if block == nil
                  block = s(:begin)
                elsif block.type != :begin
                  block = s(:begin, block)
                end

                # convert to a hash
                if block.children.all? {|child| child.type == :ivasgn}
                  # simple case: all statements are ivar assignments
                  pairs = block.children.map do |child|
                    s(:pair, s(:sym, child.children[0].to_s[1..-1]),
                     process(child.children[1]))
                  end

                  block = s(:return, s(:hash, *pairs))
                else
                  # general case: build up a hash incrementally
                  block = s(:begin, s(:gvasgn, :$_, s(:hash)), block,
                    s(:return, s(:gvar, :$_)))
                  @vue_self = s(:gvar, :$_)
                end
              end

              # return hash
              hash << s(:pair, s(:sym, method),
                s(:block, s(:send, nil, :lambda), args, process(block)))
            ensure
              @vue_h = nil
              @vue_self = nil
            end
          end
        end

        # convert class name to camel case
        camel = cname.children.last.to_s.gsub(/[^\w]/, '-').
          sub(/^[A-Z]/) {|c| c.downcase}.
          gsub(/[A-Z]/) {|c| "-#{c.downcase}"}

        # build component
        s(:casgn, nil, cname.children.last,
          s(:send, s(:const, nil, :Vue), :component, 
          s(:str, camel), s(:hash, *hash)))
      end

      # expand 'wunderbar' like method calls
      def on_send(node)
        return super unless @vue_h
        if node.children[0] == nil and node.children[1] =~ /^_\w/
          hash = Hash.new {|h, k| h[k] = {}}
          args = []

          node.children[2..-1].each do |attr|
            if attr.type == :hash
              # attributes
              # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
              node.children[-1].children.each do |pair|
                name = pair.children[0].children[0].to_s
                if name =~ /^domProps([A-Z])(.*)/
                  hash[:domProps]["#{$1.downcase}#$2"] = pair.children[1]
                elsif name =~ /^(nativeOn|on)([A-Z])(.*)/
                  hash[$1]["#{$2.downcase}#$3"] = pair.children[1]
                elsif name == 'class' and pair.children[1].type == :hash
                  hash[:class] = pair.children[1]
                elsif name == 'style' and pair.children[1].type == :hash
                  hash[:style] = pair.children[1]
                elsif %w(key ref refInFor slot).include? name
                  hash[name] = pair.children[1]
                else
                  hash[:attrs][name] = pair.children[1]
                end
              end
            else
              # text or child elements
              args << node.children[2]
            end
          end

          # put attributes up front
          unless hash.empty?
            pairs = hash.to_a.map do |k1, v1| 
              s(:pair, s(:str, k1.to_s), 
                if Parser::AST::Node === v1
                  v1
                else
                  s(:hash, *v1.map {|k2, v2| s(:pair, s(:str, k2.to_s), v2)})
                end
              )
            end
            args.unshift s(:hash, *pairs)
          end

          # emit $h (createElement) call
          node.updated :send, [nil, @vue_h, 
            s(:str, node.children[1].to_s[1..-1]), *process_all(args)]
        else
          super
        end
      end

      # expand @ to @vue_self.
      def on_ivar(node)
        return super unless @vue_self
        s(:attr, @vue_self, node.children[0].to_s[1..-1])
      end

      # expand @= to @vue_self.=
      def on_ivasgn(node)
        return super unless @vue_self
        s(:send, @vue_self, "#{node.children[0].to_s[1..-1]}=", 
          process(node.children[1]))
      end
    end

    DEFAULTS.push Vue
  end
end
