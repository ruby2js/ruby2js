# A filter to support usage of React.  Overview of translations provided:
#   * classes that inherit from React are converted to React.createClass
#     calls.
#   * Wunderbar style element definitions are converted to
#     React.createElement calls.
#
# Related files:
#   spec/react_spec.rb contains a specification
#   demo/react-tutorial.rb contains a working sample
#
# Experimental conversions provided:
#  *  $x becomes this.refs.x
#  *  @x becomes this.state.x
#  * @@x becomes this.props.x
#  *  ~x becomes this.refs.x.getDOMNode()
#  * ~"x" becomes document.querySelector("x")
#
require 'ruby2js'

module Ruby2JS
  module Filter
    module React
      include SEXP

      def options=(options)
        super
        @react = true if options[:react]
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
        return super unless inheritance == s(:const, nil, :React)

        # traverse down to actual list of class statements
        if body.length == 1 
          if not body.first
            body = []
          elsif body.first.type == :begin
            body = body.first.children 
          end
        end

        # abort conversion unless all body statements are method definitions
        return super unless body.all? do |child| 
          child.type == :def or
          (child.type == :defs and child.children.first == s(:self))
        end

        begin
          react, @react = @react, true
          reactClass, @reactClass = @reactClass, true

          # automatically capture the displayName for the class
          pairs = [s(:pair, s(:sym, :displayName), 
            s(:str, cname.children.last.to_s))]

          # collect static properties/functions
          statics = []
          body.select {|child| child.type == :defs}.each do |child|
            parent, mname, args, *block = child.children
            if child.is_method?
              statics << s(:pair, s(:sym, mname), 
                s(:block, s(:send, nil, :proc), args, s(:autoreturn, *block)))
            elsif 
              block.length == 1 and 
              Converter::EXPRESSIONS.include? block.first.type
            then
              statics << s(:pair, s(:sym, mname), *block)
            else
              statics << s(:pair, s(:prop, mname), {get: 
                s(:block, s(:send, nil, :proc), args, s(:autoreturn, *block))})
            end
          end

          # append statics (if any)
          unless statics.empty?
            pairs << s(:pair, s(:sym, :statics), s(:hash, *statics))
          end

          # add a proc/function for each method
          body.select {|child| child.type == :def}.each do |child|
            mname, args, *block = child.children
            @reactMethod = mname
            @reactProps = s(:attr, s(:self), :props)

            # analyze ivar usage
            @reactIvars = {pre: [], post: [], asgn: [], ref: []}
            react_walk(child) unless mname == :initialize
            @reactIvars[:capture] = 
              (@reactIvars[:pre] + @reactIvars[:post]).uniq

            if mname == :initialize
              mname = :getInitialState

              # extract real list of statements
              if block.length == 1
                if not block.first
                  block = []
                elsif block.first.type == :begin
                  block = block.first.children
                end
              end

              # peel off the initial set of instance variable assignment stmts
              assigns = []
              block = block.dup
              while not block.empty? and block.first.type == :ivasgn
                node = block.shift
                vars = [node.children.first]
                while node.children[1].type == :ivasgn
                  node = node.children[1]
                  vars << node.children.first
                end
                vars.each do |var|
                  assigns << s(:ivasgn, var, node.children.last)
                end
              end

              # build a hash for state
              state = s(:hash, *assigns.map {|node| s(:pair, s(:str,
                node.children.first.to_s[1..-1]), node.children.last)})

              # modify block to build and/or return state
              if block.empty?
                block = [s(:return, state)]
              else
                block.unshift(s(:send, s(:self), :state=, state))
                block.push(s(:return, s(:attr, s(:self), :state)))
              end

            elsif mname == :render
              if block.length!=1 or not block.last or block.last.type==:begin
                # wrap multi-line blocks with a 'span' element
                block = [s(:return, 
                  s(:block, s(:send, nil, :_span), s(:args), *block))]
              end

            elsif mname == :componentWillReceiveProps
              if args.children.length == 0
                args = s(:args, s(:arg, :"$$props"))
                child = s(:def, mname, args, *block)
                @reactProps = s(:lvar, :"$$props")
              else
                @reactProps = s(:lvar, args.children.first.children.last)
              end
            end

            # drill down if necessary to find the block
            while block.length==1 and block.first and block.first.type==:begin
              block = block.first.children.dup
            end

            # capture ivars that are both set and referenced
            @reactIvars[:pre].uniq.sort.reverse.each do |ivar|
              block.unshift(s(:lvasgn, "$#{ivar.to_s[1..-1]}", 
                s(:attr, s(:attr, s(:self), :state), ivar.to_s[1..-1])))
            end

            # update ivars that are set and later referenced
            unless @reactIvars[:post].empty?
              updates = @reactIvars[:post].uniq.sort.reverse.map do |ivar|
                s(:pair, s(:lvar, ivar.to_s[1..-1]), 
                  s(:lvar, "$#{ivar.to_s[1..-1]}"))
              end
              update = s(:send, s(:self), :setState, s(:hash, *updates))

              if block.last.type == :return
                block.insert(block.length-1, update)
              else
                block.push(update)
              end
            end

            # add method to class
            pairs << child.updated(:pair, [s(:sym, mname), s(:block,
              s(:send, nil, :proc), args,
              process(s((child.is_method? ? :begin : :autoreturn),
              *block)))])

            # retain comment
            unless @comments[child].empty?
              @comments[pairs.last] = @comments[child]
            end
          end
        ensure
          @react = react
          @reactClass = reactClass
          @reactMethod = nil
        end

        # emit a createClass statement
        s(:casgn, nil, cname.children.last, 
          s(:send, inheritance, :createClass, s(:hash, *pairs)))
      end

      def on_send(node)
        if not @react
          # enable React filtering within React class method calls or
          # React component calls
          if 
            node.children.first == s(:const, nil, :React)
          then
            begin
              react, @react = @react, true
              return on_send(node)
            ensure
              @react = react
            end
          end
        end

        return super unless @react

        if node.children[0] == nil and node.children[1] == :_
          # text nodes
          if @reactApply
            # if apply is set, emit code that pushes text
            s(:send, s(:gvar, :$_), :push, process(node.children[2]))
          else
            # simple/normal case: simply return the text
            process(node.children[2])
          end

        elsif 
          @reactApply and node.children[1] == :createElement and
          node.children[0] == s(:const, nil, :React)
        then
          # push results of explicit calls to React.createElement
          s(:send, s(:gvar, :$_), :push, s(:send, *node.children[0..1],
            *process_all(node.children[2..-1])))

        elsif node.children[0] == nil and node.children[1] =~ /^_\w/
          # map method calls starting with an underscore to React calls
          # to create an element.  
          #
          # input:
          #   _a 'name', href: 'link'
          # output:
          #  React.createElement("a", {href: "link"}, "name")
          #
          tag = node.children[1].to_s[1..-1]
          pairs = []
          text = block = nil
          node.children[2..-1].each do |child|
            if child.type == :hash
              # convert _ to - in attribute names
              pairs += child.children.map do |pair|
                key, value = pair.children
                if key.type == :sym
                  s(:pair, s(:str, key.children[0].to_s.gsub('_', '-')), value)
                else
                  pair
                end
              end

            elsif child.type == :block
              # :block arguments are inserted by on_block logic below
              block = child

            else
              # everything else added as text
              text = child
            end
          end

          # extract all class names
          classes = pairs.find_all do |pair|
            key = pair.children.first.children.first
            [:class, 'class', :className, 'className'].include? key
          end

          # combine all classes into a single value (or expression)
          if classes.length > 0
            expr = nil
            values = classes.map do |pair|
              if [:sym, :str].include? pair.children.last.type
                pair.children.last.children.first.to_s
              else
                expr = pair.children.last
                ''
              end
            end
            pairs -= classes
            if expr
              if values.length > 1
                value = s(:send, s(:str, values.join(' ')), :+, 
                  s(:or, expr, s(:str, '')))
              else
                value = s(:or, expr, s(:str, ''))
              end
            else
              value = s(:str, values.join(' '))
            end
            pairs.unshift s(:pair, s(:sym, :className), value)
          end

          # search for the presence of a 'for' attribute
          htmlFor = pairs.find_index do |pair|
            ['for', :for].include? pair.children.first.children.first
          end

          # replace 'for' attribute (if any) with 'htmlFor'
          if htmlFor
            pairs[htmlFor] = s(:pair, s(:sym, :htmlFor),
              pairs[htmlFor].children.last)
          end

          # construct hash (or nil) from pairs
          hash = (pairs.length > 0 ? process(s(:hash, *pairs)) : s(:nil))

          # based on case of tag name, build a HTML tag or React component
          if tag =~ /^[A-Z]/
            params = [s(:const, nil, tag), hash]
          else
            params = [s(:str, tag), hash]
          end

          # handle nested elements
          if block

            # traverse down to actual list of nested statements
            args = block.children[2..-1]
            if args.length == 1 
              if not args.first
                args = []
              elsif args.first.type == :begin
                args = args.first.children 
              end
            end

            # check for normal case: only elements and text
            simple = args.all? do |arg|
              # explicit call to React.createElement
              next true if arg.children[1] == :createElement and
                arg.children[0] == s(:const, nil, :React)

              # wunderbar style call
              arg = arg.children.first if arg.type == :block
              while arg.type == :send and arg.children.first != nil
                arg = arg.children.first
              end
              arg.type == :send and arg.children[1] =~ /^_/
            end

            begin
              if simple
                # in the normal case, process each argument
                reactApply, @reactApply = @reactApply, false
                params += args.map {|arg| process(arg)}
              else
                reactApply, @reactApply = @reactApply, true

                # collect children and apply.  Intermediate representation
                # will look something like the following:
                #
                #   React.createElement(*proc {
                #     var $_ = ['tag', hash]
                #     $_.push(React.createElement(...))
                #   }())
                #
                # Base Ruby2JS processing will convert the 'splat' to 'apply'
                params = [s(:splat, s(:send, s(:block, s(:send, nil, :proc), 
                  s(:args, s(:shadowarg, :$_)), s(:begin, 
                  s(:lvasgn, :$_, s(:array, *params)),
                  *args.map {|arg| process arg},
                  s(:return, s(:lvar, :$_)))), :[]))]
              end
            ensure
              @reactApply = reactApply
            end

          elsif text
            # add text
            params << process(text)
          end

          # trim trailing null if no text or children
          params.pop if params.last == s(:nil)

          # construct element using params
          element = node.updated(:send, [s(:const, nil, :React), 
            :createElement, *params])

          if @reactApply
            # if apply is set, emit code that pushes result
            s(:send, s(:gvar, :$_), :push, element)
          else
            # simple/normal case: simply return the element
            element
          end

        elsif node.children[0]==s(:send, nil, :_) and node.children[1]==:[]
          if @reactApply
            # if apply is set, emit code that pushes results
            s(:send, s(:gvar, :$_), :push, *process_all(node.children[2..-1]))
          elsif node.children.length == 3
            process(node.children[2])
          else
            # simple/normal case: simply return the element
            s(:splat, s(:array, *process_all(node.children[2..-1])))
          end

        # map method calls involving i/g/c vars to straight calls
        #
        # input:
        #   @x.(a,b,c)
        # output:
        #   @x(a,b,c)
        elsif node.children[1] == :call
          if [:ivar, :gvar, :cvar].include? node.children.first.type
            return process(s(:send, node.children.first, nil,
              *node.children[2..-1]))
          else
            return super
          end

        elsif node.children[1] == :~
          # Locate a DOM Node
          #   map ~(expression) to document.querySelector(expression)
          #   map ~name to this.refs.name.getDOMNode()
          #   map ~"a b" to document.querySelector("a b")
          #   map ~"#a" to document.getElementById("a")
          #   map ~"a" to document.getElementsByTagName("a")[0]
          #   map ~".a.b" to document.getElementsByClassName("a b")[0]
          #   map ~~expression to ~~expression
          #   map ~~~expression to ~expression

          if node.children[0] and node.children[0].type == :op_asgn
            asgn = node.children[0]
            if asgn.children[0] and asgn.children[0].type == :send
              inner = asgn.children[0]
              return on_send s(:send, s(:send, inner.children[0],
                (inner.children[1].to_s+'=').to_sym,
                s(:send, s(:send, s(:send, inner.children[0], '~'),
                *inner.children[1..-1]), *asgn.children[1..-1])), '~')
            else
              return on_send asgn.updated nil, [s(:send, asgn.children[0], '~'),
                *asgn.children[1..-1]]
            end
          end

          rewrite_tilda = proc do |node|
            # Example conversion:
            #   before:
            #    (send (send nil :a) :text) :~)
            #   after:
            #    (send (send (gvar :$a), :getDOMNode)), :text)
            if node.type == :send and node.children[0]
              if node.children[1] == :~ and node.children[0].children[1] == :~
                # consecutive tildes
                if node.children[0].children[0].children[1] == :~
                  result = node.children[0].children[0].children[0]
                else
                  result = s(:attr, node.children[0].children[0], '~')
                end
                s(:attr, s(:attr, process(result), '~'), '~')
              else
                # possible getter/setter
                method = node.children[1]
                method = method.to_s.chomp('=') if method =~ /=$/
                rewrite = [rewrite_tilda[node.children[0]], 
                  method, *node.children[2..-1]]
                rewrite[1] = node.children[1]
                node.updated nil, rewrite
              end
            elsif node.children.first == nil and Symbol === node.children[1]
              # innermost expression is a scalar
              s(:send, s(:gvar, "$#{node.children[1]}"), :getDOMNode)
            elsif node.type == :lvar
              s(:send, s(:gvar, "$#{node.children[0]}"), :getDOMNode)
            elsif node.type == :str
              if node.children.first =~ /^#[-\w]+$/
                s(:send, s(:attr, nil, :document), :getElementById, 
                  s(:str, node.children.first[1..-1].gsub('_', '-')))
              elsif node.children.first =~ /^(\.[-\w]+)+$/
                s(:send, s(:send, s(:attr, nil, :document), 
                  :getElementsByClassName, s(:str, 
                  node.children.first[1..-1].gsub('.', ' ').gsub('_', '-'))),
                  :[], s(:int, 0))
              elsif node.children.first =~ /^[-\w]+$/
                s(:send, s(:send, s(:attr, nil, :document), 
                  :getElementsByTagName, s(:str, 
                  node.children.first.gsub('_', '-'))), :[], s(:int, 0))
              else
                s(:send, s(:attr, nil, :document), :querySelector, node)
              end
            else
              s(:send, s(:attr, nil, :document), :querySelector, node)
            end
          end

          return process rewrite_tilda[node].children[0]

        elsif node.children[0] and node.children[0].type == :send
          # determine if markaby style class and id names are being used
          child = node
          test = child.children.first
          while test and test.type == :send and not test.is_method?
            child, test = test, test.children.first
          end

          if child.children[0] == nil and child.children[1] =~ /^_\w/
            # capture the arguments provided on the current node
            children = node.children[2..-1]

            # convert method calls to id and class values
            while node != child
              if node.children[1] !~ /!$/
                # convert method name to hash {className: name} pair
                pair = s(:pair, s(:sym, :className), 
                  s(:str, node.children[1].to_s.gsub('_','-')))
              else
                # convert method name to hash {id: name} pair
                pair = s(:pair, s(:sym, :id), 
                  s(:str, node.children[1].to_s[0..-2].gsub('_','-')))
              end

              # if a hash argument is already passed, merge in id value
              hash = children.find_index {|node| node.type == :hash}
              if hash
                children[hash] = s(:hash, pair, *children[hash].children)
              else
                children.unshift s(:hash, pair)
              end

              # advance to next node
              node = node.children.first
            end

            # collapse series of method calls into a single call
            return process(node.updated(nil, [*node.children[0..1], *children]))
          else
            super
          end

        elsif 
          node.children[0] and node.children[0].type == :self and
          node.children.length == 2 and
          node.children[1] == :componentWillReceiveProps
        then
          s(:send, *node.children, s(:attr, s(:self), :props))

        else
          super
        end
      end

      # convert blocks to proc arguments
      def on_block(node)
        if not @react
          # enable React filtering within React class method calls or
          # React component calls
          if 
            node.children.first == s(:const, nil, :React)
          then
            begin
              reacth @react = @react, true
              return on_block(node)
            ensure
              @react = react
            end
          end
        end

        return super unless @react

        # traverse through potential "css proxy" style method calls
        child = node.children.first
        test = child.children.first
        while test and test.type == :send and not test.is_method?
          child, test = test, test.children.first
        end

        # iterate over Enumerable arguments if (a) node is a createElement
        # type of call, and (b) there are args present
        if
          child.children[0] == nil and child.children[1] =~ /^_/ and
          not node.children[1].children.empty?
        then
          send = node.children.first.children
          return super if send.length < 3
          return process s(:block, s(:send, *send[0..1], *send[3..-1]),
            s(:args), s(:block, s(:send, send[2], :forEach),
            *node.children[1..-1]))
        end

        # append block as a standalone proc to wunderbar style method call
        if child.children[0] == nil and child.children[1] =~ /^_\w/
          block = s(:block, s(:send, nil, :proc), s(:args),
            *node.children[2..-1])
          return on_send node.children.first.updated(:send, 
            [*node.children.first.children, block])
        end

        super
      end

      # convert global variables to refs
      def on_gvar(node)
        return super unless @reactClass
        s(:attr, s(:attr, s(:self), :refs), node.children.first.to_s[1..-1])
      end

      # convert instance variables to state
      def on_ivar(node)
        return super unless @reactClass
        if @reactMethod and @reactIvars[:capture].include? node.children.first
          s(:lvar, "$#{node.children.first[1..-1]}")
        else
          s(:attr, s(:attr, s(:self), :state), node.children.first.to_s[1..-1])
        end
      end

      # convert instance variable assignments to setState calls
      def on_ivasgn(node)
        return super unless @react

        if @reactMethod and @reactIvars[:capture].include? node.children.first
          return s(:lvasgn, "$#{node.children.first[1..-1]}",
            *process_all(node.children[1..-1]))
        end

        vars = [node.children.first]

        while node.children.length > 1 and node.children[1].type == :ivasgn
          node = node.children[1]
          vars << node.children.first
        end

        if @reactMethod == :initialize
          s(:begin, *vars.map {|var| s(:send, s(:attr, s(:self), :state),
            var.to_s[1..-1] + '=', process(node.children.last))})
        else
          s(:send, s(:self), :setState, s(:hash, 
            *vars.map {|var| s(:pair, s(:str, var.to_s[1..-1]),
            process(node.children.last))}))
        end
      end

      # prevent attempts to assign to React properties
      def on_cvasgn(node)
        return super unless @reactMethod
        raise NotImplementedError, "setting a React property"
      end

      # convert class variables to props
      def on_op_asgn(node)
        return super unless @react
        return super unless node.children.first.type == :ivasgn
        var = node.children.first.children.first
        if @reactMethod and @reactIvars[:capture].include? var
          process s(:op_asgn, s(:lvasgn, "$#{var[1..-1]}"),
            *node.children[1..-1])
        elsif @reactMethod == :initialize
          process s(:op_asgn, s(:attr, s(:attr, s(:self), :state),
            var[1..-1]), *node.children[1..-1])
        else
          process s(:ivasgn, var, s(:send, s(:ivar, var), 
            *node.children[1..-1]))
        end
      end

      # convert class variables to props
      def on_cvar(node)
        return super unless @reactMethod
        s(:attr, @reactProps, node.children.first.to_s[2..-1])
      end

      # analyze ivar usage
      def react_walk(node)
        child = node.children.first

        node.children.each do |child|
          react_walk(child) if Parser::AST::Node === child
        end

        case node.type
        when :ivar
          if @reactIvars[:asgn].include? child
            @reactIvars[:post] << child
            @reactIvars[:pre] << child if @reactIvars[:ref].include? child
          end
          @reactIvars[:ref] << child
          
        when :ivasgn
          @reactIvars[:asgn] << child

        when :op_asgn 
          if child.type == :ivasgn
            gchild = child.children.first
            if @reactIvars[:ref].include? gchild
              @reactIvars[:pre] << gchild 
              @reactIvars[:post] << gchild 
            end
            @reactIvars[:ref] << gchild
            @reactIvars[:asgn] << gchild
          end

        when :send 
          if 
            child and child.type == :self and node.children.length == 2 and
            node.children[1] == :componentWillReceiveProps
          then
            @reactIvars[:post] += @reactIvars[:asgn]
          end
        end
      end
    end

    DEFAULTS.push React
  end
end
