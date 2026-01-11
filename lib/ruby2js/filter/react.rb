# A filter to support React and Preact component development.
#
# Two component styles are supported:
#
#   1. Function components with hooks (modern, recommended):
#      class Foo < React        -> function Foo(props) { ... }
#      class Foo < Preact       -> Uses useState for state management
#
#   2. Class components (for lifecycle methods):
#      class Foo < React::Component  -> class Foo extends React.Component
#      class Foo < Preact::Component -> class Foo extends Preact.Component
#
# Element creation uses JSX syntax or pnode AST nodes:
#   %x{ <div className="container"><p>Hello</p></div> }
#   -> React.createElement("div", {className: "container"},
#        React.createElement("p", null, "Hello"))
#
# Variable mappings:
#   @x   -> state variable (useState hook or this.state.x)
#   @@x  -> this.props.x
#   $x   -> this.refs.x
#   ~x   -> this.refs.x
#   ~(x) -> document.querySelector(x)
#
# Related files:
#   spec/react_spec.rb - specifications
#   spec/hook_spec.rb  - hook-specific tests
#   spec/preact_spec.rb - Preact tests
#
require 'ruby2js'
require 'ruby2js/jsx'
require 'ruby2js/rbx'

module Ruby2JS
  module Filter
    module React
      include SEXP
      extend  SEXP

      REACT_IMPORTS = {
        React: s(:import, ['react'], s(:attr, nil, :React)),
        ReactDOM: s(:import, ['react-dom'], s(:attr, nil, :ReactDOM)),
        Preact: s(:import,
          [s(:pair, s(:sym, :as), s(:const, nil, :Preact)),
            s(:pair, s(:sym, :from), s(:str, "preact"))],
            s(:str, '*')),
        PreactHook: s(:import, ["preact/hooks"], [s(:attr, nil, :useState)])
      }

      # the following command can be used to generate ReactAttrs:
      # 
      #   ruby -r ruby2js/filter/react -e "Ruby2JS::Filter::React.genAttrs"
      #
      def self.genAttrs
        unless RUBY_ENGINE == 'opal'
          require 'nokogiri'
          require 'uri'
          require 'net/http'

          page = 'https://reactjs.org/docs/dom-elements.html'
          uri = URI.parse(page)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          data = http.get(uri.request_uri).body
          doc = Nokogiri::HTML5::Document.parse(data)

          # delete contents of page prior to the list of supported attributes
          attrs = doc.at('a[name=supported-attributes]')
          attrs = attrs.parent while attrs and not attrs.name.start_with? 'h'
          attrs.previous_sibling.remove while attrs and attrs.previous_sibling

          # extract attribute names with uppercase chars from code and format
          attrs = doc.search('div[data-language=text] pre code').map(&:text).join(' ')
          attrs = attrs.split(/\s+/).grep(/[A-Z]/).sort.uniq.join(' ')
          puts "ReactAttrs = %w(#{attrs})".gsub(/(.{1,72})(\s+|\Z)/, "\\1\n")
        end
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

      ReactLifecycle = %w(render componentDidMount shouldComponentUpdate
      getShapshotBeforeUpdate componentDidUpdate componentWillUnmount
      componentDidCatch componentWillReceiveProps)

      ReactAttrMap = Hash[ReactAttrs.map {|name| [name.downcase, name]}]
      ReactAttrMap['for'] = 'htmlFor'

      PreactAttrMap = {
        htmlFor: 'for',
        onDoubleClick: 'onDblClick',
        tabIndex: 'tabindex'
      }

      def initialize(*args)
        @react = nil
        @reactApply = nil
        @reactBlock = nil
        @reactClass = nil
        @reactMethod = nil
        @react_props = []
        @react_methods = []
        @react_filter_functions = false
        @jsx = false
        @rbx_mode = false
        super
      end

      def options=(options)
        super
        @react = true if options[:react]
        @rbx_mode = true if options[:rbx]
        filters = options[:filters] || Filter::DEFAULTS

        if \
          defined? Ruby2JS::Filter::Functions and
          filters.include? Ruby2JS::Filter::Functions
        then
          @react_filter_functions = true
        end

        if \
          defined? Ruby2JS::Filter::JSX and
          filters.include? Ruby2JS::Filter::JSX
        then
          @jsx = true
        end
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

        if inheritance == s(:const, nil, :React) or
          inheritance == s(:const, s(:const, nil, :React), :Component) or
          inheritance == s(:send, s(:const, nil, :React), :Component)

          react = :React
          self.prepend_list << REACT_IMPORTS[:React] if self.modules_enabled?()

        elsif inheritance == s(:const, nil, :Preact) or
          inheritance == s(:const, s(:const, nil, :Preact), :Component) or
          inheritance == s(:send, s(:const, nil, :Preact), :Component)

          react = :Preact
          self.prepend_list << REACT_IMPORTS[:Preact] if self.modules_enabled?()
        else
          return super
        end

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
          react, @react = @react, react
          reactClass, @reactClass = @reactClass, true

          pairs = []

          # collect static properties/functions
          statics = []
          body.select {|child| child.type == :defs}.each do |child|
            pairs << child
          end

          # collect instance methods (including getters and setters)
          @react_props = []
          @react_methods = []
          body.each do |statement|
            if statement.type == :def
              method = statement.children.first
              unless method == :initialize
                if method.to_s.end_with? '='
                  method = method.to_s[0..-2].to_sym
                  @react_props << method unless @react_props.include? method
                elsif statement.is_method?
                  @react_methods << method unless @react_methods.include? method
                else
                  @react_props << method unless @react_props.include? method
                end
              end
            end
          end

          # determine if this class can be emitted as a hook
          hook = (inheritance.children.first == nil)
          hookinit = nil
          useState = []
          body.each_with_index do |statement, index|
            if statement.type == :def
              method = statement.children.first
              if method == :initialize
                children = statement.children[2..-1]
                children.pop unless children.last
                while children.length == 1 and children.first.type == :begin
                  children = children.first.children 
                end
                hookinit = index if children.any? {|child| child.type != :ivasgn}
              elsif method == :render
                nil
              elsif ReactLifecycle.include? method.to_s
                hook = false
              elsif not statement.is_method?
                hook = false
              elsif method.to_s.end_with? '='
                hook = false
              end
            elsif statement.type == :defs
              hook = false
            end
          end

          if hook
            @reactClass = :hook
            @react_props = []
            @react_methods = []

            if hookinit
              body = body.dup
              hookinit = body.delete_at(hookinit)
              pairs.unshift process hookinit.children[2]
            end
          end

          # create a default getInitialState method if there is no such method
          # and there are either references to instance variables or there are
          # methods that need to be bound.
          if \
            not body.any? do |child|
              child.type == :def and
              [:getInitialState, :initialize].include? child.children.first
            end
          then
            @reactIvars = {pre: [], post: [], asgn: [], ref: [], cond: []}
            react_walk(node)

            if hook
              react_walk(hookinit) if hookinit
              useState = [*@reactIvars[:asgn], *@reactIvars[:ref]].uniq
            end

            if not @reactIvars.values().flatten.empty?
              body = [s(:def, :initialize, s(:args)), *body]
            end
          end

          # add a proc/function for each method
          body.select {|child| child.type == :def}.each do |child|
            mname, args, *block = child.children
            @reactMethod = mname

            if @reactClass == :hook
              @reactProps = s(:lvar, :"prop$")
            else
              @reactProps = child.updated(:attr, [s(:self), :props])
            end

            # analyze ivar usage
            @reactIvars = {pre: [], post: [], asgn: [], ref: [], cond: []}
            react_walk(child) unless mname == :initialize
            @reactIvars[:capture] = [*@reactIvars[:pre], *@reactIvars[:post]].uniq
            @reactIvars[:pre] = @reactIvars[:post] = [] if @reactClass == :hook

            if mname == :initialize
              # extract real list of statements
              if block.length == 1
                if not block.first
                  block = []
                elsif block.first.type == :begin
                  block = block.first.children
                end
              end

              # add props argument if there is a reference to a prop
              if args.children.length == 0
                has_cvar = lambda {|list|
                  list.any? {|node|
                    next unless Ruby2JS.ast_node?(node)
                    return true if node.type == :cvar
                    has_cvar.call(node.children)
                  }
                }
                args = s(:args, s(:arg, 'prop$')) if has_cvar[block]
              end

              # peel off the initial set of instance variable assignment stmts
              assigns = []
              block = block.dup
              block.shift if block.first == s(:zsuper)
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
              state = s(:hash, *assigns.map {|anode| s(:pair, s(:str,
                anode.children.first.to_s[1..-1]), anode.children.last)})

              # modify block to build and/or return state
              block.unshift(s(:zsuper), s(:send, s(:self), :state=, state))

            elsif mname == :render and not react_wunderbar_free(block, true)
              if \
                 block.length != 1 or not block.last or
                not %i[send block xstr].include? block.last.type
              then
                if @jsx
                  while block.length == 1 and block.first.type == :begin
                    block = block.first.children.dup
                  end

                  # gather non-element emitting statements in the front
                  prolog = []
                  while not block.empty? and 
                    react_wunderbar_free([block.first]) do
                    prolog << process(block.shift)
                  end

                  # wrap multi-line blocks with an empty element
                  block = [*prolog, s(:return,
                    s(:xnode, '', *process_all(block)))]
                else
                  # wrap multi-line blocks with a React Fragment
                  block = [s(:return,
                    s(:block, s(:send, nil, :"_#{@react}.Fragment"), s(:args), *block))]
                end
              end

            elsif mname == :componentWillReceiveProps
              if args.children.length == 0
                args = s(:args, s(:arg, :"$$props"))
                comments = @comments[child]
                child = child.updated(:def, [mname, args, *block])
                @comments[child] = comments unless comments.nil? || comments.empty?
                @reactProps = s(:lvar, :"$$props")
              else
                @reactProps = s(:lvar, args.children.first.children.last)
              end
            end

            # capture and update ivars as required
            block = react_process_ivars(block)

            # add method to class
            type = (child.is_method? ? :begin : :autoreturn)
            type = :begin if mname == :initialize
            if block.length == 1 and Ruby2JS.ast_node?(block.first)
              type = :begin if block.first.type == :return
            end

            pairs << child.updated(
              ReactLifecycle.include?(mname.to_s) ? :defm : :def,
              [mname, args, process(s(type, *block))]
            )

            # retain comment
            child_comments = @comments[child]
            unless child_comments&.empty?
              @comments[pairs.last] = child_comments
            end
          end

          if hook
            initialize = pairs.find_index {|node| node.type == :def and node.children.first == :initialize} || -1

            hash = {}
            if initialize != -1
              hash = pairs.delete_at(initialize)
              hash = hash.children.last while %i(def begin send).include? hash&.type
              hash = s(:hash) unless hash&.type == :hash
              hash = hash.children.map {|pair|
                [pair.children.first.children.first, pair.children.last]
              }.to_h
            end 

            useState.each do |symbol|
              hash[symbol.to_s[1..-1]] ||= s(:nil)
            end

            hash.entries().sort.reverse.each do |var, value|
              if @react == :Preact 
                hooker = nil
                self.prepend_list << REACT_IMPORTS[:PreactHook] if self.modules_enabled?()
              else
                hooker = s(:const, nil, :React)
              end

              setter = 'set' + var[0].upcase + var[1..-1]
              pairs.unshift(s(:masgn, s(:mlhs, s(:lvasgn, var), 
                s(:lvasgn, setter)), s(:send, hooker, :useState, value)))
            end

            render = pairs.find_index {|node| node.type == :defm and node.children.first == :render} || -1
            if render != -1
              render = pairs.delete_at(render)
              pairs.push s(:autoreturn, render.children.last)
            end

            has_cvar = lambda {|list|
              list.any? {|node|
                next unless Ruby2JS.ast_node?(node)
                return true if node.type == :cvar
                has_cvar.call(node.children)
              }
            }
            args = has_cvar[node.children] ? s(:args, s(:arg, 'prop$')) : s(:args)

            node.updated(:def, [cname.children.last, args, s(:begin, *pairs)])
          else
            # emit a class that extends React.Component
            node.updated(:class, [s(:const, nil, cname.children.last),
              s(:attr, s(:const, nil, @react), :Component), *pairs])
          end
        ensure
          @react = react
          @reactClass = reactClass
          @reactMethod = nil
        end
      end

      def on_send(node)
        # calls to methods (including getters) defined in this class
        if node.children[0]==nil and Symbol === node.children[1]
          if node.is_method?
            if @react_methods.include? node.children[1]
              # calls to methods defined in this class
              return node.updated nil, [s(:self), node.children[1],
                *process_all(node.children[2..-1])]
            end
          else
            if @react_props.include? node.children[1]
              # access to properties defined in this class
              return node.updated nil, [s(:self), node.children[1],
                *process_all(node.children[2..-1])]
            end
          end
        end

        if not @react
          # enable React filtering within React class method calls or
          # React component calls
          if \
            node.children.first == s(:const, nil, :React) or
            node.children.first == s(:const, nil, :Preact) or
            node.children.first == s(:const, nil, :ReactDOM)
          then
            if self.modules_enabled?()
              self.prepend_list << REACT_IMPORTS[node.children.first.children.last]
            end

            begin
              react = @react
              @react = (node.children.first.children.last == :Preact ? :Preact : :React)
              return on_send(node)
            ensure
              @react = react
            end
          end
        end

        return super unless @react

        if \
          (@reactApply and node.children[1] == :createElement and
          node.children[0] == s(:const, nil, :React)) or
          (@reactApply and node.children[1] == :h and
          node.children[0] == s(:const, nil, :Preact))
        then
          # push results of explicit calls to React.createElement
          s(:send, s(:gvar, :$_), :push, s(:send, *node.children[0..1],
            *process_all(node.children[2..-1])))

        elsif \
          @react == :Preact and node.children[1] == :h and node.children[0] == nil
        then
          if @reactApply
            # push results of explicit calls to Preact.h
            s(:send, s(:gvar, :$_), :push, s(:send, s(:const, nil, :Preact), :h,
              *process_all(node.children[2..-1])))
          else
            node.updated(nil, [s(:const, nil, :Preact), :h, *process_all(node.children[2..-1])])
          end

        # Phlex-style: plain(text) - text content
        elsif @jsx_content and node.children[0] == nil and node.children[1] == :plain
          if @reactApply
            s(:send, s(:gvar, :$_), :push, process(node.children[2]))
          else
            process(node.children[2])
          end

        # Phlex-style: fragment - React.Fragment
        elsif @jsx_content and node.children[0] == nil and node.children[1] == :fragment
          if @react == :Preact
            s(:const, nil, :"Preact.Fragment")
          else
            s(:const, nil, :"React.Fragment")
          end

        # Phlex-style: render Component.new(...) - React.createElement(Component, ...)
        elsif @jsx_content and node.children[0] == nil and node.children[1] == :render and
              node.children[2]&.type == :send and node.children[2].children[1] == :new
          component_const = node.children[2].children[0]
          component_args = node.children[2].children[2..-1]

          hash = component_args.find { |arg| arg.type == :hash }
          hash = hash ? process(hash) : s(:nil)

          build_react_element([component_const, hash])

        # Phlex-style: tag("custom-element", ...) - React.createElement("custom-element", ...)
        elsif @jsx_content and node.children[0] == nil and node.children[1] == :tag
          tag_name = node.children[2]
          tag_args = node.children[3..-1] || []

          hash = tag_args.find { |arg| arg.type == :hash }
          hash = hash ? process(hash) : s(:nil)

          build_react_element([tag_name, hash])

        # Phlex-style: HTML element (div, span, etc.) - React.createElement("element", ...)
        elsif @jsx_content and node.children[0] == nil and
              Ruby2JS::JSX_ALL_ELEMENTS.include?(node.children[1])
          tag = node.children[1].to_s
          args = node.children[2..-1] || []

          hash = args.find { |arg| arg.type == :hash }
          if hash
            # process hash and convert class to className
            pairs = hash.children.map do |pair|
              key, value = pair.children
              if key.type == :sym && [:class, 'class'].include?(key.children[0])
                if @react == :Preact
                  s(:pair, s(:sym, :class), value)
                else
                  s(:pair, s(:sym, :className), value)
                end
              else
                pair
              end
            end
            hash = process(s(:hash, *pairs))
          else
            hash = s(:nil)
          end

          build_react_element([s(:str, tag), hash])

        # map method calls involving i/g/c vars to straight calls
        #
        # input:
        #   @x.(a,b,c)
        # output:
        #   @x(a,b,c)
        elsif node.children[1] == :call
          if [:ivar, :gvar, :cvar].include? node.children.first.type
            # Preserve is_method? flag when transforming @x.() to @x()
            new_node = node.updated(:send, [node.children.first, nil,
              *node.children[2..-1]])
            return process(new_node)
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

          rewrite_tilda = proc do |tnode|
            # Example conversion:
            #   before:
            #    (send (send nil :a) :text) :~)
            #   after:
            #    (send (gvar :$a))), :text)
            if tnode.type == :send and tnode.children[0]
              if tnode.children[1] == :~ and tnode.children[0].children[1] == :~
                # consecutive tildes
                if tnode.children[0].children[0].children[1] == :~
                  result = tnode.children[0].children[0].children[0]
                else
                  result = s(:attr, tnode.children[0].children[0], '~')
                end
                s(:attr, s(:attr, process(result), '~'), '~')
              else
                # possible getter/setter
                method = tnode.children[1]
                method = method.to_s.chomp('=') if method =~ /=$/
                rewrite = [rewrite_tilda[tnode.children[0]],
                  method, *tnode.children[2..-1]]
                rewrite[1] = tnode.children[1]
                tnode.updated nil, rewrite
              end
            elsif tnode.children.first == nil and Symbol === tnode.children[1]
              # innermost expression is a scalar
              s(:gvar, "$#{tnode.children[1]}")
            elsif tnode.type == :lvar
              s(:gvar, "$#{tnode.children[0]}")
            elsif tnode.type == :str
              if tnode.children.first =~ /^#[-\w]+$/
                s(:send, s(:attr, nil, :document), :getElementById,
                  s(:str, tnode.children.first[1..-1].gsub('_', '-')))
              elsif tnode.children.first =~ /^(\.[-\w]+)+$/
                s(:send, s(:send, s(:attr, nil, :document),
                  :getElementsByClassName, s(:str,
                  tnode.children.first[1..-1].gsub('.', ' ').gsub('_', '-'))),
                  :[], s(:int, 0))
              elsif tnode.children.first =~ /^[-\w]+$/
                s(:send, s(:send, s(:attr, nil, :document),
                  :getElementsByTagName, s(:str,
                  tnode.children.first.gsub('_', '-'))), :[], s(:int, 0))
              else
                s(:send, s(:attr, nil, :document), :querySelector, tnode)
              end
            else
              s(:send, s(:attr, nil, :document), :querySelector, tnode)
            end
          end

          return process rewrite_tilda[node].children[0]

        elsif \
          node.children[0] and node.children[0].type == :self and
          node.children.length == 2 and
          node.children[1] == :componentWillReceiveProps
        then
          s(:send, *node.children, s(:attr, s(:self), :props))

        else
          super
        end
      end

      # Handle pnode (synthetic AST node for elements)
      # Structure: s(:pnode, tag, attrs_hash, *children)
      def on_pnode(node)
        # pnodes come from Phlex filter - always convert when React filter is present
        # This enables "write once, target both" - same Phlex code, different output
        tag, attrs, *children = node.children

        process_pnode_element(tag, attrs, children)
      end

      # Handle pnode_text (text content in pnode)
      # Structure: s(:pnode_text, content_node)
      def on_pnode_text(node)
        # pnode_text comes from Phlex filter - always handle when React filter is present

        content = node.children.first

        if content.type == :str
          # Static text - return as-is
          if @reactApply
            s(:send, s(:gvar, :$_), :push, content)
          else
            content
          end
        else
          # Dynamic content
          processed = process(content)
          if @reactApply
            s(:send, s(:gvar, :$_), :push, processed)
          else
            processed
          end
        end
      end

      private

      # Process a pnode element and convert to React.createElement
      def process_pnode_element(tag, attrs, children)
        case tag
        when nil
          # Fragment
          process_pnode_fragment(attrs, children)
        when Symbol
          if tag.to_s[0] =~ /[A-Z]/
            # Component (uppercase)
            process_pnode_component(tag, attrs, children)
          else
            # HTML element (lowercase)
            process_pnode_html_element(tag, attrs, children)
          end
        when String
          # Custom element
          process_pnode_custom_element(tag, attrs, children)
        end
      end

      def process_pnode_html_element(tag, attrs, children)
        tag_str = tag.to_s

        # Build params: [tag_string, attrs_hash, ...children]
        params = [s(:str, tag_str)]
        params << process_pnode_attrs(attrs)

        # Process children
        children.each do |child|
          params << process(child)
        end

        # Trim trailing null if no children
        params.pop if params.last == s(:nil) && children.empty?

        build_react_element(params)
      end

      def process_pnode_component(tag, attrs, children)
        # Build params: [ComponentConst, attrs_hash, ...children]
        params = [s(:const, nil, tag)]
        params << process_pnode_attrs(attrs)

        # Process children
        children.each do |child|
          params << process(child)
        end

        # Trim trailing null if no children
        params.pop if params.last == s(:nil) && children.empty?

        build_react_element(params)
      end

      def process_pnode_custom_element(tag, attrs, children)
        # Build params: [tag_string, attrs_hash, ...children]
        params = [s(:str, tag)]
        params << process_pnode_attrs(attrs)

        # Process children
        children.each do |child|
          params << process(child)
        end

        # Trim trailing null if no children
        params.pop if params.last == s(:nil) && children.empty?

        build_react_element(params)
      end

      def process_pnode_fragment(attrs, children)
        # Build params: [React.Fragment, attrs_hash, ...children]
        fragment_const = @react == :Preact ?
          s(:const, nil, :"Preact.Fragment") :
          s(:const, nil, :"React.Fragment")

        params = [fragment_const]
        params << process_pnode_attrs(attrs)

        # Process children
        children.each do |child|
          params << process(child)
        end

        # Trim trailing null if no children
        params.pop if params.last == s(:nil) && children.empty?

        build_react_element(params)
      end

      def process_pnode_attrs(attrs)
        return s(:nil) unless attrs&.type == :hash && attrs.children.any?

        # Normalize attributes: class -> className, for -> htmlFor, etc.
        pairs = attrs.children.map do |pair|
          next pair unless pair.type == :pair

          key_node, value_node = pair.children
          next pair unless key_node.type == :sym

          key = key_node.children.first

          # Attribute normalization for React
          new_key = case key
          when :class then :className
          when :for then :htmlFor
          when :tabindex then :tabIndex
          when :readonly then :readOnly
          when :maxlength then :maxLength
          when :cellpadding then :cellPadding
          when :cellspacing then :cellSpacing
          when :colspan then :colSpan
          when :rowspan then :rowSpan
          when :usemap then :useMap
          when :frameborder then :frameBorder
          when :contenteditable then :contentEditable
          when :autocomplete then :autoComplete
          when :autofocus then :autoFocus
          when :enctype then :encType
          when :formaction then :formAction
          when :novalidate then :noValidate
          when :spellcheck then :spellCheck
          else
            # Convert data_foo to data-foo for data attributes
            if key.to_s.start_with?('data_')
              key.to_s.tr('_', '-').to_sym
            else
              key
            end
          end

          if new_key != key
            s(:pair, s(:sym, new_key), value_node)
          else
            pair
          end
        end

        process(s(:hash, *pairs))
      end

      def build_react_element(params)
        if @jsx
          # Output xnode for JSX serialization
          tag_node, attrs, *children = params

          # Extract tag name as string
          tag_name = case tag_node.type
          when :str
            tag_node.children.first
          when :const
            # Component or Fragment - use the constant name
            tag_node.children.last.to_s
          else
            tag_node.children.first.to_s
          end

          # xnode expects: (tag_string, attrs_hash, *children)
          # attrs should be a hash node, not nil or s(:nil)
          if attrs.nil? || attrs.type == :nil
            attrs = s(:hash)
          end
          element = s(:xnode, tag_name, attrs, *children)
        else
          # Trim trailing nil if no children (matches original behavior)
          params.pop if params.last == s(:nil) && params.length == 2

          if @react == :Preact
            element = s(:send, s(:const, nil, :Preact), :h, *params)
          else
            element = s(:send, s(:const, nil, :React), :createElement, *params)
          end
        end

        if @reactApply
          s(:send, s(:gvar, :$_), :push, element)
        else
          element
        end
      end

      public

      # convert blocks to proc arguments
      def on_block(node)
        if not @react
          # enable React filtering within React class method calls or
          # React component calls
          if \
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
        if \
          (child.children[1] == :createElement and
          child.children[0] == s(:const, nil, :React)) or
          (child.children[1] == :h and
          (child.children[0] == s(:const, nil, :Preact) or
          child.children[0] == nil))
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

          target = child.children[0] || s(:const, nil, :Preact)

          if reactApply
            return child.updated(:send, [s(:gvar, :$_), :push, 
              s(:send, target, child.children[1], *params)])
          else
            return child.updated(:send, [target, child.children[1], *params])
          end
        end

        # traverse through potential "css proxy" style method calls
        test = child.children.first
        while test and test.type == :send and not test.is_method?
          child, test = test, test.children.first
        end

        # Phlex-style block: fragment do ... end
        if @jsx_content and child.children[0] == nil and child.children[1] == :fragment
          if node.children[1].children.empty?
            # Get block body - unwrap :begin node if present
            block_body = node.children[2..-1]
            if block_body.length == 1 && block_body.first&.type == :begin
              block_body = block_body.first.children
            end
            children_ast = block_body.map { |c| process(c) }

            fragment_const = @react == :Preact ?
              s(:const, nil, :"Preact.Fragment") :
              s(:const, nil, :"React.Fragment")

            return build_react_element([fragment_const, s(:nil), *children_ast])
          end

        # Phlex-style block: element do ... end
        elsif @jsx_content and child.children[0] == nil and
              Ruby2JS::JSX_ALL_ELEMENTS.include?(child.children[1])
          if node.children[1].children.empty?
            tag = child.children[1].to_s
            args = child.children[2..-1] || []

            hash = args.find { |arg| arg.type == :hash }
            if hash
              pairs = hash.children.map do |pair|
                key, value = pair.children
                if key.type == :sym && [:class, 'class'].include?(key.children[0])
                  if @react == :Preact
                    s(:pair, s(:sym, :class), value)
                  else
                    s(:pair, s(:sym, :className), value)
                  end
                else
                  pair
                end
              end
              hash = process(s(:hash, *pairs))
            else
              hash = s(:nil)
            end

            # Process children in the block
            block_children = node.children[2..-1]
            children_ast = block_children.map { |c| process(c) }

            return build_react_element([s(:str, tag), hash, *children_ast])
          end

        # Phlex-style block: render Component.new do ... end
        elsif @jsx_content and child.children[0] == nil and child.children[1] == :render and
              child.children[2]&.type == :send and child.children[2].children[1] == :new
          if node.children[1].children.empty?
            component_const = child.children[2].children[0]
            component_args = child.children[2].children[2..-1]

            hash = component_args.find { |arg| arg.type == :hash }
            hash = hash ? process(hash) : s(:nil)

            # Process children in the block
            block_children = node.children[2..-1]
            children_ast = block_children.map { |c| process(c) }

            return build_react_element([component_const, hash, *children_ast])
          end

        # Phlex-style block: tag("custom-element") do ... end
        elsif @jsx_content and child.children[0] == nil and child.children[1] == :tag
          if node.children[1].children.empty?
            tag_name = child.children[2]
            tag_args = child.children[3..-1] || []

            hash = tag_args.find { |arg| arg.type == :hash }
            hash = hash ? process(hash) : s(:nil)

            # Process children in the block
            block_children = node.children[2..-1]
            children_ast = block_children.map { |c| process(c) }

            return build_react_element([tag_name, hash, *children_ast])
          end
        end

        begin
          reactBlock, @reactBlock = @reactBlock, true
          super
        ensure
          @reactBlock = reactBlock
        end
      end

      def on_lvasgn(node)
        return super unless @reactClass
        return super unless @react_props.include? node.children.first
        node.updated(:send, [s(:self), "#{node.children.first}=",
          node.children.last])
      end

      # convert global variables to refs
      def on_gvar(node)
        return super unless @reactClass
        return super if @reactClass == :hook
        s(:attr, s(:attr, s(:self), :refs), node.children.first.to_s[1..-1])
      end

      # convert instance variables to state
      def on_ivar(node)
        return super unless @reactClass

        if @reactClass == :hook
          node.updated(:lvar, [node.children.first.to_s[1..-1]])
        elsif @reactMethod and @reactIvars[:capture].include? node.children.first
          node.updated(:lvar, ["$#{node.children.first[1..-1]}"])
        else
          node.updated(:attr, [s(:attr, s(:self), :state),
            node.children.first.to_s[1..-1]])
        end
      end

      # convert instance variable assignments to setState calls
      def on_ivasgn(node)
        return super unless @react

        if @reactClass == :hook
          var = node.children.first.to_s[1..-1]
          return node.updated(:send, [nil, 'set' + var[0].upcase + var[1..-1],
            process(node.children.last)])
        end

        if @reactMethod and @reactIvars[:capture].include? node.children.first
          ivar = node.children.first.to_s
          if @reactBlock
            return s(:send, s(:self), :setState, s(:hash, s(:pair,
              s(:str, ivar[1..-1]), process(s(:lvasgn, "$#{ivar[1..-1]}",
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
        raise Error.new("setting a React property", node)
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
        if @reactClass == :hook
          var = node.children.first.children.first.to_s[1..-1]
          node.updated(:send, [nil, 'set' + var[0].upcase + var[1..-1],
            s(:send, s(:lvar, var), *node.children[1..-1])])
        elsif @reactMethod and @reactIvars[:capture].include? var
          if @reactBlock
            s(:send, s(:self), :setState, s(:hash, s(:pair,
              s(:str, var[1..-1]), process(s(node.type,
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

      # is this a "wunderbar" style call or createElement?
      def react_element?(node, wunderbar_only=false)
        return false unless node

        forEach = [:forEach]
        forEach << :each if @react_filter_functions

        return true if node.type == :block and
          forEach.include? node.children.first.children.last and 
          react_element?(node.children.last, wunderbar_only)

        unless wunderbar_only
          # explicit call to React.createElement
          return true if node.children[1] == :createElement and
            node.children[0] == s(:const, nil, :React)

          # explicit call to Preact.h
          return true if node.children[1] == :h and
            node.children[0] == s(:const, nil, :Preact)

          # explicit call to h
          return true if node.children[1] == :h and
            node.children[0] == nil
        end

        # wunderbar style call
        node = node.children.first if node.type == :block
        while node.type == :send and node.children.first != nil
          node = node.children.first
        end
        node.type == :send and node.children[1].to_s.start_with? '_'
      end

      # ensure that there are no "wunderbar" or "createElement" calls in
      # a set of statements.
      def react_wunderbar_free(nodes, wunderbar_only=false)
        nodes.each do |node|
          if Ruby2JS.ast_node?(node)
            return false if node.type == :xstr
            return false if react_element?(node, wunderbar_only)

            # recurse
            return false unless react_wunderbar_free(node.children, wunderbar_only)
          end
        end

        # no problems found
        return true
      end

      # analyze ivar usage
      def react_walk(node)
        # ignore hash values which are blocks (most typically, event handlers)
        # as these create their own scopes.
        return if node.type == :pair and node.children[0].type == :sym and
          node.children[1].type == :block
        return if node.type == :defs

        base = @reactIvars[:asgn].dup if [:if, :case].include? node.type

        node.children.each do |child|
          react_walk(child) if Ruby2JS.ast_node?(child)
        end

        child = node.children.first

        case node.type
        when :if, :case
          @reactIvars[:cond].push(*(@reactIvars[:asgn].reject { |x| base.include?(x) }))

        when :ivar
          if @reactIvars[:cond].include? child
            @reactIvars[:post].push(child)
            @reactIvars[:pre].push(child)
          elsif @reactIvars[:asgn].include? child
            @reactIvars[:post].push(child)
            @reactIvars[:pre].push(child) if @reactIvars[:ref].include? child
          end
          @reactIvars[:ref].push(child)

        when :ivasgn
          @reactIvars[:asgn].push(child)

        when :op_asgn, :or_asgn, :and_asgn
          if child.type == :ivasgn
            gchild = child.children.first
            if [*@reactIvars[:ref], *@reactIvars[:cond]].include? gchild
              @reactIvars[:pre].push(gchild)
              @reactIvars[:post].push(gchild)
            end
            @reactIvars[:ref].push(gchild)
            @reactIvars[:asgn].push(gchild)
          end

        when :send
          if \
            child and child.type == :self and node.children.length == 2 and
            node.children[1] == :componentWillReceiveProps
          then
            @reactIvars[:post].push(*@reactIvars[:asgn])
          end
        end
      end

      # Convert hash values of type 'lambda' to 'proc'.  This is because
      # Ruby 'desugars' -> to lambda, and Ruby2JS presumes that lambdas
      # return a value.
      def on_pair(node)
        if \
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
          next unless node.children[i] && node.children[i+1]  # skip nil children
          if \
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
            (@comments[node.children[i+1]].nil? || @comments[node.children[i+1]].empty?)
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
          @reactIvars[:capture] = [*@reactIvars[:pre], *@reactIvars[:post]].uniq
          @reactIvars[:pre] = @reactIvars[:post] = [] if @reactClass == :hook
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
            s(:pair, s(:str, ivar.to_s[1..-1]),
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

      def on_xstr(node)
       loc = node.loc
       return super unless loc
       source = loc.begin.source_buffer.source
       source = source[loc.begin.end_pos...loc.end.begin_pos].strip
       return super unless @reactClass or source.start_with? '<'

       # RBX mode: convert JSX directly to JavaScript, preserving expressions
       if @rbx_mode
         react_name = @react == :Preact ? 'Preact' : 'React'
         js_code = Ruby2JS.rbx2_js(source, react_name: react_name)
         return s(:jsraw, js_code)
       end

       # Standard mode: convert to Ruby AST and process
       source = Ruby2JS.jsx2_rb(source)
       ast =  Ruby2JS.parse(source).first
       # Wrap multiple top-level elements in a fragment
       ast = s(:block, s(:send, nil, :fragment), s(:args), ast) if ast.type == :begin

       begin
         react, @react = @react, @react || :react
         jsx_content, @jsx_content = @jsx_content, true
         process ast
       ensure
         @react = react
         @jsx_content = jsx_content
       end
      end
    end

    DEFAULTS.push React
  end
end
