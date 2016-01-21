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
# Conversions provided:
#  *  $x becomes this.refs.x
#  *  @x becomes this.state.x
#  * @@x becomes this.props.x
#  *  ~x becomes this.refs.x
#  * ~(x) becomes document.querySelector(x)
#  * ~"x" becomes document.querySelector("x")
#
require 'ruby2js'

module Ruby2JS
  module Filter
    module React
      include SEXP

      # the following command can be used to generate ReactAttrs:
      # 
      #   ruby -r ruby2js/filter/react -e "Ruby2JS::Filter::React.genAttrs"
      #
      def self.genAttrs
        require 'nokogumbo'
        page = 'https://facebook.github.io/react/docs/tags-and-attributes.html'
        doc = Nokogiri::HTML5.get(page)

        # delete contents of page prior to the list of supported attributes
        attrs = doc.at('a[name=supported-attributes]')
        attrs = attrs.parent while attrs and not attrs.name.start_with? 'h'
        attrs.previous_sibling.remove while attrs and attrs.previous_sibling

        # extract attribute names with uppercase chars from code and format
        attrs = doc.search('code').map(&:text).join(' ')
        attrs = attrs.split(/\s+/).grep(/[A-Z]/).sort.uniq.join(' ')
        puts "ReactAttrs = %w(#{attrs})".gsub(/(.{1,72})(\s+|\Z)/, "\\1\n")
      end

      # list of react attributes that require special processing
      ReactAttrs = %w(acceptCharset accessKey allowFullScreen
      allowTransparency autoCapitalize autoComplete autoCorrect autoFocus
      autoPlay autoSave cellPadding cellSpacing charSet classID className
      clipPath colSpan contentEditable contextMenu crossOrigin
      dangerouslySetInnerHTML dateTime encType fillOpacity fontFamily fontSize
      formAction formEncType formMethod formNoValidate formTarget frameBorder
      gradientTransform gradientUnits hrefLang htmlFor httpEquiv inputMode
      itemID itemProp itemRef itemScope itemType keyParams keyType
      marginHeight marginWidth markerEnd markerMid markerStart maxLength
      mediaGroup noValidate patternContentUnits patternUnits
      preserveAspectRatio radioGroup readOnly rowSpan spellCheck spreadMethod
      srcDoc srcSet stopColor stopOpacity strokeDasharray strokeLinecap
      strokeOpacity strokeWidth tabIndex textAnchor useMap viewBox
      xlinkActuate xlinkArcrole xlinkHref xlinkRole xlinkShow xlinkTitle
      xlinkType xmlBase xmlLang xmlSpace)

      ReactAttrMap = Hash[ReactAttrs.map {|name| [name.downcase, name]}]
      ReactAttrMap['for'] = 'htmlFor'

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
              statics << s(:pair, s(:sym, mname), process(child.updated(:block,
                [s(:send, nil, :proc), args, s(:autoreturn, *block)])))
            elsif
              block.length == 1 and
              Converter::EXPRESSIONS.include? block.first.type
            then
              statics << s(:pair, s(:sym, mname), *block)
            else
              statics << s(:pair, s(:prop, mname), {get: child.updated(
                :block, [s(:send, nil, :proc), args, s(:autoreturn, *block)])})
            end
          end

          # append statics (if any)
          unless statics.empty?
            pairs << s(:pair, s(:sym, :statics), s(:hash, *statics))
          end

          # create a default getInitialState method if there is no such method
          # and there are references to instance variables.
          if
            not body.any? do |child|
              child.type == :def and
              [:getInitialState, :initialize].include? child.children.first
            end
          then
            @reactIvars = {pre: [], post: [], asgn: [], ref: [], cond: []}
            react_walk(node)
            unless @reactIvars.values.flatten.empty?
              body = [s(:def, :getInitialState, s(:args),
                s(:return, s(:hash))), *body]
            end
          end

          # add a proc/function for each method
          body.select {|child| child.type == :def}.each do |child|
            mname, args, *block = child.children
            @reactMethod = mname
            @reactProps = child.updated(:attr, [s(:self), :props])

            # analyze ivar usage
            @reactIvars = {pre: [], post: [], asgn: [], ref: [], cond: []}
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
              if
                block.length != 1 or not block.last or
                not [:send, :block].include? block.last.type
              then
                # wrap multi-line blocks with a 'span' element
                block = [s(:return,
                  s(:block, s(:send, nil, :_span), s(:args), *block))]
              end

            elsif mname == :componentWillReceiveProps
              if args.children.length == 0
                args = s(:args, s(:arg, :"$$props"))
                comments = @comments[child]
                child = child.updated(:def, [mname, args, *block])
                @comments[child] = comments unless comments.empty?
                @reactProps = s(:lvar, :"$$props")
              else
                @reactProps = s(:lvar, args.children.first.children.last)
              end
            end

            # capture and update ivars as required
            block = react_process_ivars(block)

            # add method to class
            type = (child.is_method? ? :begin : :autoreturn)
            if block.length == 1 and Parser::AST::Node === block.first
              type = :begin if block.first.type == :return
            end

            pairs << s(:pair, s(:sym, mname), child.updated(:block,
              [s(:send, nil, :proc), args, process(s(type, *block))]))

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
        node.updated(:casgn, [nil, cname.children.last,
          s(:send, inheritance, :createClass, s(:hash, *pairs))])
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
                while expr.type == :begin and expr.children.length == 1
                  expr = expr.children.first
                end

                if
                  expr.type == :if and expr.children[1] and
                  expr.children[1].type == :str
                then
                  left = expr.children[1]
                  right = expr.children[2] || s(:str, '')
                  right = s(:or, right, s(:str, '')) unless right.type == :str
                  expr = expr.updated(nil, [expr.children[0], left, right])
                elsif expr.type != :str
                  expr = s(:or, expr, s(:str, ''))
                end

                value = s(:send, s(:str, values.join(' ')), :+, expr)
              else
                value = expr
              end
            else
              value = s(:str, values.join(' '))
            end
            pairs.unshift s(:pair, s(:sym, :className), value)
          end

          # support controlled form components
          if %w(input select textarea).include? tag
            # search for the presence of a 'value' attribute
            value = pairs.find_index do |pair|
              ['value', :value].include? pair.children.first.children.first
            end

            # search for the presence of a 'onChange' attribute
            onChange = pairs.find_index do |pair|
              ['onChange', :onChange].include? pair.children.first.children[0]
            end

            if value and pairs[value].children.last.type == :ivar and !onChange
              pairs << s(:pair, s(:sym, :onChange),
                s(:block, s(:send, nil, :proc), s(:args, s(:arg, :event)),
                s(:ivasgn, pairs[value].children.last.children.first,
                s(:attr, s(:attr, s(:lvar, :event), :target), :value))))
            end

            if not value and not onChange and tag == 'input'
              # search for the presence of a 'checked' attribute
              checked = pairs.find_index do |pair|
                ['checked', :checked].include? pair.children.first.children[0]
              end

              if checked and pairs[checked].children.last.type == :ivar
                pairs << s(:pair, s(:sym, :onChange),
                  s(:block, s(:send, nil, :proc), s(:args),
                  s(:ivasgn, pairs[checked].children.last.children.first,
                  s(:send, pairs[checked].children.last, :!))))
              end
            end
          end

          # replace attribute names with case-sensitive javascript properties
          pairs.each_with_index do |pair, index|
            next if pair.type == :kwsplat
            name = pair.children.first.children.first.downcase
            if ReactAttrMap[name] and name.to_s != ReactAttrMap[name]
              pairs[index] = pairs[index].updated(nil, 
                [s(:str, ReactAttrMap[name]), pairs[index].children.last])
            end
          end

          # search for the presence of a 'style' attribute
          style = pairs.find_index do |pair|
            ['style', :style].include? pair.children.first.children.first
          end

          # converts style strings into style hashes
          if style and pairs[style].children[1].type == :str
            hash = []
            pairs[style].children[1].children[0].split(/;\s+/).each do |prop|
              prop.strip!
              next unless prop =~ /^([-a-z]+):\s*(.*)$/
              name, value = $1, $2
              name.gsub!(/-[a-z]/) {|str| str[1].upcase}
              if value =~ /^-?\d+$/
                hash << s(:pair, s(:str, name), s(:int, value.to_i))
              elsif value =~ /^-?\d+$\.\d*/
                hash << s(:pair, s(:str, name), s(:float, value.to_f))
              else
                hash << s(:pair, s(:str, name), s(:str, value))
              end
            end
            pairs[style] = s(:pair, pairs[style].children[0], s(:hash, *hash))
          end

          # construct hash (or nil) from pairs
          if pairs.length == 1 and pairs.first.type == :kwsplat
            hash = pairs.first.children.first
          else
            hash = (pairs.length > 0 ? process(s(:hash, *pairs)) : s(:nil))
          end

          # based on case of tag name, build a HTML tag or React component
          if tag =~ /^[A-Z]/
            params = [s(:const, nil, tag), hash]
          else
            params = [s(:str, tag), hash]
          end

          # handle nested elements
          if block
            # enable hashes to be passed as a variable on block calls
            params[-1] = text if text and params.last == s(:nil)

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
                #     return $_
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
          #   map ~name to this.refs.name
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
            #    (send (gvar :$a))), :text)
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
              s(:gvar, "$#{node.children[1]}")
            elsif node.type == :lvar
              s(:gvar, "$#{node.children[0]}")
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
              react, @react = @react, true
              return on_block(node)
            ensure
              @react = react
            end
          end
        end

        return super unless @react

        # block calls to createElement
        #
        # collect block and apply.  Intermediate representation
        # will look something like the following:
        #
        #   React.createElement(*proc {
        #     var $_ = ['tag', hash]
        #     $_.push(React.createElement(...))
        #     return $_
        #   }())
        #
        # Base Ruby2JS processing will convert the 'splat' to 'apply'
        child = node.children.first
        if 
          child.children[1] == :createElement and
          child.children[0] == s(:const, nil, :React)
        then
          begin
            reactApply, @reactApply = @reactApply, true
            params = [s(:splat, s(:send, s(:block, s(:send, nil, :proc),
              s(:args, s(:shadowarg, :$_)), s(:begin,
              s(:lvasgn, :$_, s(:array, *child.children[2..-1])),
              process(node.children[2]),
              s(:return, s(:lvar, :$_)))), :[]))]
          ensure
            @reactApply = reactApply
          end

          if reactApply
            return child.updated(:send, [s(:gvar, :$_), :push, 
              s(:send, *child.children[0..1], *params)])
          else
            return child.updated(:send, [*child.children[0..1], *params])
          end
        end

        # traverse through potential "css proxy" style method calls
        test = child.children.first
        while test and test.type == :send and not test.is_method?
          child, test = test, test.children.first
        end

        # wunderbar style calls
        if child.children[0] == nil and child.children[1] =~ /^_\w/
          if node.children[1].children.empty?
            # append block as a standalone proc
            block = s(:block, s(:send, nil, :proc), s(:args),
              *node.children[2..-1])
            return on_send node.children.first.updated(:send,
              [*node.children.first.children, block])
          else
            # iterate over Enumerable arguments if there are args present
            send = node.children.first.children
            return super if send.length < 3
            return process s(:block, s(:send, *send[0..1], *send[3..-1]),
              s(:args), s(:block, s(:send, send[2], :forEach),
              *node.children[1..-1]))
          end
        end

        begin
          reactBlock, @reactBlock = @reactBlock, true
          super
        ensure
          @reactBlock = reactBlock
        end
      end

      # convert global variables to refs
      def on_gvar(node)
        return super unless @reactClass
        ref = s(:attr, s(:attr, s(:self), :refs), 
          node.children.first.to_s[1..-1])

        # Handle both refs to custom (user-defined) components as well as
        # refs to built-in DOM components.  See:
        # https://facebook.github.io/react/blog/2015/10/07/react-v0.14.html#dom-node-refs
        s(:if, s(:in?, s(:sym, :getDOMNode), ref), 
          s(:send, ref, :getDOMNode), ref)
      end

      # convert instance variables to state
      def on_ivar(node)
        return super unless @reactClass
        if @reactMethod and @reactIvars[:capture].include? node.children.first
          node.updated(:lvar, ["$#{node.children.first[1..-1]}"])
        else
          node.updated(:attr, [s(:attr, s(:self), :state),
            node.children.first.to_s[1..-1]])
        end
      end

      # convert instance variable assignments to setState calls
      def on_ivasgn(node)
        return super unless @react

        if @reactMethod and @reactIvars[:capture].include? node.children.first
          ivar = node.children.first.to_s
          if @reactBlock
            return s(:send, s(:self), :setState, s(:hash, s(:pair,
              s(:lvar, ivar[1..-1]), process(s(:lvasgn, "$#{ivar[1..-1]}",
              *node.children[1..-1])))))
          else
            return s(:lvasgn, "$#{ivar[1..-1]}",
              *process_all(node.children[1..-1]))
          end
        end

        vars = [node.children.first]

        while node.children.length > 1 and node.children[1].type == :ivasgn
          node = node.children[1]
          vars << node.children.first
        end

        if node.children.length == 2
          if @reactMethod == :initialize
            s(:begin, *vars.map {|var| s(:send, s(:attr, s(:self), :state),
              var.to_s[1..-1] + '=', process(node.children.last))})
          else
            s(:send, s(:self), :setState, s(:hash,
              *vars.map {|var| s(:pair, s(:str, var.to_s[1..-1]),
              process(node.children.last))}))
          end
        end
      end

      # prevent attempts to assign to React properties
      def on_cvasgn(node)
        return super unless @reactMethod
        raise NotImplementedError, "setting a React property"
      end

      # convert instance variables to state: "@x ||= y"
      def on_or_asgn(node)
        return super unless @react
        return super unless node.children.first.type == :ivasgn
        on_op_asgn(node)
      end

      # convert instance variables to state: "@x &&= y"
      def on_and_asgn(node)
        return super unless @react
        return super unless node.children.first.type == :ivasgn
        on_op_asgn(node)
      end

      # convert instance variables to state: "@x += y"
      def on_op_asgn(node)
        return super unless @react
        return super unless node.children.first.type == :ivasgn
        var = node.children.first.children.first
        if @reactMethod and @reactIvars[:capture].include? var
          if @reactBlock
            s(:send, s(:self), :setState, s(:hash, s(:pair,
              s(:lvar, var[1..-1]), process(s(node.type,
              s(:lvasgn, "$#{var[1..-1]}"), *node.children[1..-1])))))
          else
            process s(node.type, s(:lvasgn, "$#{var[1..-1]}"),
              *node.children[1..-1])
          end
        elsif @reactMethod == :initialize
          process s(node.type, s(:attr, s(:attr, s(:self), :state),
            var[1..-1]), *node.children[1..-1])
        elsif node.type == :or_asgn
          process s(:ivasgn, var, s(:or, s(:ivar, var),
            *node.children[1..-1]))
        elsif node.type == :and_asgn
          process s(:ivasgn, var, s(:and, s(:ivar, var),
            *node.children[1..-1]))
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
        # ignore hash values which are blocks (most typically, event handlers)
        # as these create their own scopes.
        return if node.type == :pair and node.children[0].type == :sym and
          node.children[1].type == :block
        return if node.type == :defs

        child = node.children.first

        base = @reactIvars[:asgn].dup if [:if, :case].include? node.type

        node.children.each do |child|
          react_walk(child) if Parser::AST::Node === child
        end

        case node.type
        when :if, :case
          @reactIvars[:cond] += @reactIvars[:asgn] - base

        when :ivar
          if @reactIvars[:cond].include? child
            @reactIvars[:post] << child
            @reactIvars[:pre] << child
          elsif @reactIvars[:asgn].include? child
            @reactIvars[:post] << child
            @reactIvars[:pre] << child if @reactIvars[:ref].include? child
          end
          @reactIvars[:ref] << child

        when :ivasgn
          @reactIvars[:asgn] << child

        when :op_asgn, :or_asgn, :and_asgn
          if child.type == :ivasgn
            gchild = child.children.first
            if (@reactIvars[:ref]+@reactIvars[:cond]).include? gchild
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

      # Convert hash values of type 'lambda' to 'proc'.  This is because
      # Ruby 'desugars' -> to lambda, and Ruby2JS presumes that lambdas
      # return a value.
      def on_pair(node)
        if
          node.children[1].type == :block and
          node.children[1].children[0] == s(:send, nil, :lambda)
        then
          process node.updated(nil, [node.children[0],
            node.children[1].updated(nil, [s(:send, nil, :proc),
              *node.children[1].children[1..-1]])])
        else
          super
        end
      end

      # collapse consecutive setState calls into a single call
      def on_begin(node)
        node = super
        (node.children.length-2).downto(0) do |i|
          if
            node.children[i].type == :send and
            node.children[i].children[0] and
            node.children[i].children[0].type == :self and
            node.children[i].children[1] == :setState and
            node.children[i].children[2].type == :hash and
            node.children[i+1].type == :send and
            node.children[i+1].children[0] and
            node.children[i+1].children[0].type == :self and
            node.children[i+1].children[1] == :setState and
            node.children[i+1].children[2].type == :hash and
            @comments[node.children[i+1]].empty?
          then
            pairs = node.children[i].children[2].children +
                   node.children[i+1].children[2].children
            children = node.children.dup
            children.delete_at(i)
            children[i] = children[i].updated(nil, [
              *children[i].children[0..1],
              children[i].children[2].updated(nil, pairs)])
            node = node.updated(nil, children)
          end
        end
        node
      end

      def on_defs(node)
        return super unless @react

        begin
          reactIvars = @reactIvars
          @reactIvars = {pre: [], post: [], asgn: [], ref: [], cond: []}
          react_walk(node.children.last)
          @reactIvars[:capture] = (@reactIvars[:pre] + @reactIvars[:post]).uniq
          node = super
          block = react_process_ivars([node.children.last.dup])
          node.updated(nil, [*node.children[0..-2], s(:begin, *block)])
        ensure
          @reactIvars = reactIvars
        end
      end

      # common logic for inserting code to manage state (ivars)
      def react_process_ivars(block)
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

        block
      end
    end

    DEFAULTS.push React
  end
end
