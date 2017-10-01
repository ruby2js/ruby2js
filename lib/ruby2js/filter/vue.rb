require 'ruby2js'

module Ruby2JS
  module Filter
    module Vue
      include SEXP

      VUE_METHODS = [
        :delete, :destroy, :emit, :forceUpdate, :mount, :nextTick, :off, :on,
        :once, :set, :watch
      ]

      VUE_LIFECYCLE = [
        :data, :render, :beforeCreate, :created, :beforeMount, :mounted,
        :beforeUpdate, :updated, :beforeDestroy, :destroyed
      ]

      VUE_PROPERTIES = [
        :$data, :$props, :$el, :$options, :$parent, :$root, :$children,
        :$slots, :$scopedSlots, :$refs, :$isServer, :$attrs, :$listeners
      ]

      def initialize(*args)
        @vue_class = nil
        @vue_h = nil
        @vue_self = nil
        @vue_apply = nil
        @vue_inventory = Hash.new {|h, k| h[k] = []}
        @vue_methods = []
        @vue_props = []
        @vue_reactive = []
        super
      end

      def options=(options)
        super
        @vue_h ||= options[:vue_h]
      end

      # Example conversion
      #  before:
      #    (class (const nil :Foo) (const nil :Vue) nil)
      #  after:
      #    (casgn nil :Foo, (send nil, :Vue, :component, (:str, "foo"), 
      #      s(:hash)))
      def on_class(node)
        cname, inheritance, *body = node.children

        begin
          vue_class, @vue_class = @vue_class, cname
          return super unless cname.children.first == nil
          return super unless inheritance == s(:const, nil, :Vue) or
            inheritance == s(:const, s(:const, nil, :Vue), :Mixin)
        ensure
          @vue_class = vue_class
        end

        # traverse down to actual list of class statements
        if body.length == 1
          if not body.first
            body = []
          elsif body.first.type == :begin
            body = body.first.children
          end
        end

        hash = []
        methods = []
        computed = []
        setters = []
        options = []
        mixins = []

        # insert constructor if none present
        if inheritance == s(:const, nil, :Vue)
          unless body.any? {|statement| 
            statement.type == :def and statement.children.first ==:initialize}
          then
            body = body.dup
            body.unshift s(:def, :initialize, s(:args), nil)
          end
        end

        @vue_inventory = vue_walk(node)
        @vue_methods = []
        @vue_props = []
        @vue_reactive = []

        # collect instance methods (including getters and setters) and
        # reactive class attributes
        body.each do |statement|
          if statement.type == :def
            method = statement.children.first
            unless VUE_LIFECYCLE.include? method or method == :initialize
              if method.to_s.end_with? '='
                method = method.to_s[0..-2].to_sym
                @vue_props << method unless @vue_props.include? method
              elsif statement.is_method?
                @vue_methods << method unless @vue_methods.include? method
              else
                @vue_props << method unless @vue_props.include? method
              end
            end

          elsif 
            statement.type == :send and statement.children[0] == cname and
            statement.children[1].to_s.end_with? '='
          then
            @vue_reactive << statement.updated(:send, [
              s(:attr, s(:const, nil, :Vue), :util), :defineReactive, cname, 
              s(:sym, statement.children[1].to_s[0..-2]),
              process(statement.children[2])])

          end
        end

        # convert body into hash
        body.each do |statement|

          # named values (template, props, options, mixin[s])
          if statement.type == :send and statement.children.first == nil
            if [:template, :props].include? statement.children[1]
              hash << s(:pair, s(:sym, statement.children[1]), 
                statement.children[2])

            elsif 
              statement.children[1] == :options and
              statement.children[2].type == :hash
            then
              options += statement.children[2].children

            elsif statement.children[1] == :mixin or
                  statement.children[1] == :mixins
            then

              mixins += statement.children[2..-1]
            end

          # methods
          elsif statement.type == :def
            begin
              @vue_self = s(:attr, s(:self), :$data)
              method, args, block = statement.children
              if method == :render
                args = s(:args, s(:arg, :$h)) if args.children.empty?

                block = s(:begin, block) unless block and block.type == :begin

                if
                  (block.children.length != 1 and
                    not vue_wunderbar_free(block.children[0..-2])) or

                  not block.children.last or

                  (block.children.length == 1 and
                    not [:send, :block].include? block.children.first.type)
                then
                  # wrap multi-line blocks with a 'span' element
                  block = s(:return,
                    s(:block, s(:send, nil, :_span), s(:args), *block))
                end

                @vue_h = args.children.first.children.last
              elsif method == :initialize
                method = :data

                # find block
                if block == nil
                  block = s(:begin)
                elsif block.type != :begin
                  block = s(:begin, block)
                end

                simple = block.children.all? {|child| child.type == :ivasgn}

                # not so simple if ivars are being read as well as written
                if simple
                  block_inventory = vue_walk(block)
                  simple = block_inventory[:ivar].empty?
                end

                uninitialized = @vue_inventory[:ivar].dup

                block.children.each do |child|
                  if child.type == :ivasgn 
                    uninitialized.delete child.children.first
                  end
                end

                # convert to a hash
                if simple
                  # simple case: all statements are ivar assignments
                  pairs = block.children.map do |child|
                    s(:pair, s(:sym, child.children[0].to_s[1..-1]),
                     process(child.children[1]))
                  end

                  pairs += uninitialized.map do |symbol|
                    s(:pair, s(:sym, symbol.to_s[1..-1]), 
                      s(:attr, nil, :undefined))
                  end

                  block = s(:return, s(:hash, *pairs))
                else
                  # general case: build up a hash incrementally
                  block = s(:begin, s(:gvasgn, :$_, 
                    s(:hash, *uninitialized.map {|sym| 
                      s(:pair, s(:sym, sym.to_s[1..-1]),
                      s(:attr, nil, :undefined))})),
                    block, s(:return, s(:gvar, :$_)))
                  @vue_self = s(:gvar, :$_)
                end
              end

              if statement.is_method?
                method_type = :proc
              else
                method_type = :lambda
              end

              # add to hash in the appropriate location
              pair = s(:pair, s(:sym, method.to_s.chomp('=')),
                s(:block, s(:send, nil, method_type), args, process(block)))
              @comments[pair] = @comments[statement]
              if VUE_LIFECYCLE.include? method
                hash << pair
              elsif not statement.is_method? 
                computed << pair
              elsif method.to_s.end_with? '='
                setters << pair
              else
                methods << pair
              end
            ensure
              @vue_h = nil
              @vue_self = nil
            end
          end
        end

        # add options to the front
        hash.unshift(*options)

        # add properties before that
        unless hash.any? {|pair| pair.children[0].children[0] == :props}
          unless @vue_inventory[:cvar].empty?
            hash.unshift s(:pair, s(:sym, :props), s(:array, 
              *@vue_inventory[:cvar].map {|sym| s(:str, sym.to_s[2..-1])}))
          end
        end

        # add mixins before that
        unless mixins.empty?
          hash.unshift s(:pair, s(:sym, :mixins), s(:array, *mixins))
        end

        # append methods to hash
        unless methods.empty?
          hash << s(:pair, s(:sym, :methods), s(:hash, *methods))
        end

        @vue_methods = []

        # append setters to computed list
        setters.each do |setter|
          index = computed.find_index do |pair| 
            pair.children[0].children[0].to_s ==
              setter.children[0].children[0]
          end

          if index
            computed[index] = s(:pair, setter.children[0],
              s(:hash, s(:pair, s(:sym, :get), computed[index].children[1]),
                s(:pair, s(:sym, :set), setter.children[1])))
          else
            computed << s(:pair, setter.children[0],
              s(:hash, s(:pair, s(:sym, :set), setter.children[1])))
          end
        end

        # append computed to hash
        unless computed.empty?
          hash << s(:pair, s(:sym, :computed), s(:hash, *computed))
        end

        # convert class name to camel case
        cname = cname.children.last
        camel = cname.to_s.gsub(/[^\w]/, '-').
          sub(/^[A-Z]/) {|c| c.downcase}.
          gsub(/[A-Z]/) {|c| "-#{c.downcase}"}
        camel = "#{camel}-" if camel =~ /^[a-z]*$/

        if inheritance == s(:const, nil, :Vue)
          # build component
          defn = s(:casgn, nil, cname,
            s(:send, s(:const, nil, :Vue), :component, 
            s(:str, camel), s(:hash, *hash)))
        else
          # build mixin
          defn = s(:casgn, nil, cname, s(:hash, *hash))
        end

        # append class methods (if any)
        class_methods = body.select do |statement| 
          statement.type == :defs  and statement.children[0] == s(:self)
        end

        if class_methods.empty? and @vue_reactive.empty?
          defn
        else
          s(:begin, defn, *process_all(class_methods.map {|method|
            fn = if method.is_method?
              if not method.children[1].to_s.end_with? '='
                # class method
                s(:send, s(:const, nil, cname), "#{method.children[1]}=",
                  s(:block, s(:send , nil, :proc), method.children[2],
                   *process_all(method.children[3..-1])))
              else
                getter = class_methods.find do |other_method| 
                  "#{other_method.children[1]}=" == method.children[1].to_s
                end

                if getter
                  # both a getter and setter
                  s(:send, s(:const, nil, :Object), :defineProperty,
                    s(:const, nil, cname), s(:str, getter.children[1].to_s),
                    s(:hash, s(:pair, s(:sym, :enumerable), s(:true)),
                    s(:pair, s(:sym, :configurable), s(:true)),
                    s(:pair, s(:sym, :get), s(:block, s(:send, nil, :proc),
                      getter.children[2],
                      s(:autoreturn, process(getter.children[3])))),
                    s(:pair, s(:sym, :set), s(:block, s(:send, nil, :proc),
                      method.children[2],
                      *process_all(method.children[3..-1])))))
                else
                  # setter only
                  s(:send, s(:const, nil, :Object), :defineProperty,
                    s(:const, nil, cname), 
                    s(:str, method.children[1].to_s[0..-2]),
                    s(:hash, s(:pair, s(:sym, :enumerable), s(:true)),
                    s(:pair, s(:sym, :configurable), s(:true)),
                    s(:pair, s(:sym, :set), s(:block, s(:send, nil, :proc),
                      method.children[2],
                      *process_all(method.children[3..-1])))))
                end
              end

            elsif
              class_methods.any? do |other_method| 
                other_method.children[1].to_s == "#{method.children[1]}="
              end
            then
              nil

            elsif
              method.children.length == 4 and
              Converter::EXPRESSIONS.include? method.children[3].type
            then
              # class property - simple
              s(:send, s(:const, nil, cname), "#{method.children[1]}=",
                method.children[3])

            else
              # class computed property
              s(:send, s(:const, nil, :Object), :defineProperty,
                s(:const, nil, cname), s(:str, method.children[1].to_s),
                s(:hash, s(:pair, s(:sym, :enumerable), s(:true)),
                s(:pair, s(:sym, :configurable), s(:true)),
                s(:pair, s(:sym, :get), s(:block, s(:send, nil, :proc),
                  method.children[2], *process_all(method.children[3..-1])))))
            end

            @comments[fn] = @comments[method]
            fn
          }).compact, *@vue_reactive)
        end
      end

      # expand 'wunderbar' like method calls
      def on_send(node)
        if not @vue_h
	  if node.children.first == s(:const, nil, :Vue)
	    # enable React filtering within Vue class method calls or
	    # React component calls
	    begin
	      vue_h, @vue_h = @vue_h, [s(:self), :$createElement]
	      return on_send(node)
	    ensure
	      @vue_h = vue_h
	    end

          elsif node.children.first == s(:send, s(:const, nil, :Vue), :util)
            if node.children[1] == :defineReactive
              if node.children.length == 4 and @vue_class
                var = node.children[2]
                if var.type == :cvar
                  scope = @vue_class
                  var = s(:str, '_' + var.children[0].to_s[2..-1])
                elsif var.type == :ivar
                  scope = s(:self)
                  var = s(:str, '_' + var.children[0].to_s[1..-1])
                elsif var.type == :send and var.children.length == 2
                  scope = var.children[0]
                  var = s(:sym, var.children[1])
                else
                  return super
                end

                return node.updated nil, [*node.children[0..1],
                  scope, process(var), *process_all(node.children[3..-1])]
              end
            end
          end
        end

        # map method calls involving i/g/c vars to straight calls
        #
        # input:
        #   @x.(a,b,c)
        # output:
        #   @x(a,b,c)
        if @vue_self and node.children[1] == :call
          if [:ivar, :gvar, :cvar].include? node.children.first.type
            return process(s(:send, node.children.first, nil,
              *node.children[2..-1]))
          else
            return super
          end
        end

        # calls to methods (including getters) defined in this class
        if node.children[0]==nil and Symbol === node.children[1]
          if node.is_method?
            if @vue_methods.include? node.children[1]
              # calls to methods defined in this class
              return node.updated nil, [s(:self), node.children[1],
                *process_all(node.children[2..-1])]
            end
          else
            if @vue_props.include? node.children[1]
              # access to properties defined in this class
              return node.updated nil, [s(:self), node.children[1],
                *process_all(node.children[2..-1])]
            end
          end
        end

        return super unless @vue_h

        if node.children[0] == nil and node.children[1] =~ /^_\w/
          tag = node.children[1].to_s[1..-1]
          hash = Hash.new {|h, k| h[k] = {}}
          args = []
          complex_block = []
          component = (tag =~ /^[A-Z]/)

          node.children[2..-1].each do |attr|
            if attr.type == :hash
              # attributes
              # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
              pairs = attr.children.dup

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

                    if expr.type == :array
                      hash[:class] = s(:array, *expr.children,
                        *values.join(' ').split(' ').map {|str| s(:str, str)})
                    elsif expr.type == :hash
                      hash[:class] = s(:hash, *expr.children,
                        *values.join(' ').split(' ').
                          map {|str| s(:pair, s(:str, str), s(:true))})
                    else
                      if
                        expr.type == :if and expr.children[1] and
                        expr.children[1].type == :str
                      then
                        left = expr.children[1]
                        right = expr.children[2] || s(:nil)

                        expr = expr.updated(nil, 
                          [expr.children[0], left, right])
                      end

                      hash[:class] = s(:array, 
                        *values.join(' ').split(' ').map {|str| s(:str, str)},
                        expr)
                    end
                  elsif [:hash, :array].include? expr.type
                    hash[:class] = expr
                  else
                    hash[:class] = s(:array, expr)
                  end
                else
                  hash[:class] = s(:array, 
                    *values.join(' ').split(' ').map {|str| s(:str, str)})
                end
              end

              # search for the presence of a 'style' attribute
              style = pairs.find_index do |pair|
                ['style', :style].include? pair.children.first.children.first
              end

              # converts style strings into style hashes
              if style and pairs[style].children[1].type == :str
                rules = []
                value = pairs[style].children[1].children[0]
                value.split(/;\s+/).each do |prop|
                  prop.strip!
                  next unless prop =~ /^([-a-z]+):\s*(.*)$/
                  name, value = $1, $2
                  name.gsub!(/-[a-z]/) {|str| str[1].upcase}
                  if value =~ /^-?\d+$/
                    rules << s(:pair, s(:str, name), s(:int, value.to_i))
                  elsif value =~ /^-?\d+$\.\d*/
                    rules << s(:pair, s(:str, name), s(:float, value.to_f))
                  else
                    rules << s(:pair, s(:str, name), s(:str, value))
                  end
                end
                pairs.delete_at(style)
                hash[:style] =  s(:hash, *rules)
              end

              # process remaining attributes
              pairs.each do |pair|
                name = pair.children[0].children[0].to_s
                if name =~ /^(nativeOn|on)([A-Z])(.*)/
                  hash[$1]["#{$2.downcase}#$3"] = pair.children[1]
                elsif component
                  hash[:props][name] = pair.children[1]
                elsif name =~ /^domProps([A-Z])(.*)/
                  hash[:domProps]["#{$1.downcase}#$2"] = pair.children[1]
                elsif name == 'style' and pair.children[1].type == :hash
                  hash[:style] = pair.children[1]
                elsif %w(key ref refInFor slot).include? name
                  hash[name] = pair.children[1]
                else
                  hash[:attrs][name.to_s.gsub('_', '-')] = pair.children[1]
                end
              end

            elsif attr.type == :block
              # traverse down to actual list of nested statements
              statements = attr.children[2..-1]
              if statements.length == 1
                if not statements.first
                  statements = []
                elsif statements.first.type == :begin
                  statements = statements.first.children
                end
              end

              # check for normal case: only elements and text
              simple = statements.all? do |arg|
                # explicit call to Vue.createElement
                next true if arg.children[1] == :createElement and
                  arg.children[0] == s(:const, nil, :Vue)

                # wunderbar style call
                arg = arg.children.first if arg.type == :block
                while arg.type == :send and arg.children.first != nil
                  arg = arg.children.first
                end
                arg.type == :send and arg.children[1] =~ /^_/
              end

              if simple
                args << s(:array, *statements)
              else
                complex_block += statements
              end

            else
              # text or child elements
              args << node.children[2]
            end
          end

          # support controlled form components
          if %w(input select textarea).include? tag
            # search for the presence of a 'value' attribute
            value = hash[:attrs]['value']

            # search for the presence of a 'onChange' attribute
            onChange = hash['on']['input'] ||
                       hash['on']['change'] ||
                       hash['nativeOn']['input'] ||
                       hash['nativeOn']['change']

            # test if value is assignable
            test = value
            loop do
              break unless test and test.type == :send 
              break unless (test.children.length == 2 and
                test.children.last.instance_of? Symbol) or
                test.children[1] == :[]
              test = test.children.first 
            end

            if value and value.type != :cvar and (not test or 
              test.is_a? Symbol or [:ivar, :cvar, :self].include? test.type)
            then
              hash[:domProps]['value'] ||= value
              hash[:domProps]['textContent'] ||= value if tag == 'textarea'
              hash[:attrs].delete('value')

              # disable control until script is ready
              unless hash[:domProps]['disabled'] or hash[:attrs]['disabled']
                hash[:domProps]['disabled'] = s(:false)
                hash[:attrs]['disabled'] = s(:true)
              end

              # define event handler to update ivar on input events
              if not onChange
                update = s(:attr, s(:attr, s(:lvar, :event), :target), :value)

                if value.type == :ivar
                  assign = s(:ivasgn, value.children.first, update)
                elsif value.type == :cvar
                  assign = s(:cvasgn, value.children.first, update)
                elsif value.type == :send and value.children.first == nil
                  assign = value.updated :lvasgn, [value.children[1], update]
                elsif value.children[1] == :[]
                  assign = value.updated nil, [value.children[0], :[]=,
                    value.children[2], update]
                else
                  assign = value.updated nil, [value.children.first,
                    "#{value.children[1]}=", update]
                end

                hash['on']['input'] ||=
                  s(:block, s(:send, nil, :proc), s(:args, s(:arg, :event)),
                  assign)
              end
            end

            if not value and not onChange and tag == 'input'
              # search for the presence of a 'checked' attribute
              checked = hash[:attrs]['checked']

              # test if value is assignable
              test = checked
              loop do
                break unless test and test.type == :send 
                break unless (test.children.length == 2 and
                  test.children.last.instance_of? Symbol) or
                  test.children[1] == :[]
                test = test.children.first 
              end

              if checked and checked.type != :cvar and (not test or 
                test.is_a? Symbol or [:ivar, :cvar, :self].include? test.type)
              then
                hash[:domProps]['checked'] ||= checked
                hash[:attrs].delete('checked')

                # disable control until script is ready
                unless hash[:domProps]['disabled'] or hash[:attrs]['disabled']
                  hash[:domProps]['disabled'] = s(:false)
                  hash[:attrs]['disabled'] = s(:true)
                end

                # define event handler to update ivar on click events
                if not onChange
                  update = s(:send, checked, :!)

                  if checked.type == :ivar
                    assign = s(:ivasgn, checked.children.first, update)
                  elsif checked.type == :cvar
                    assign = s(:cvasgn, checked.children.first, update)
                  elsif checked.type == :send and checked.children.first == nil
                    assign = checked.updated :lvasgn, [checked.children[1],
                      update]
                  elsif checked.children[1] == :[]
                    assign = checked.updated nil, [checked.children[0], :[]=,
                      checked.children[2], update]
                  else
                    assign = checked.updated nil, [checked.children.first,
                      "#{checked.children[1]}=", update]
                  end

                  hash['on']['click'] ||=
                    s(:block, s(:send, nil, :proc), s(:args), assign)
                end
              end
            end
          end

          # put attributes up front
          unless hash.empty?
            pairs = hash.to_a.map do |k1, v1| 
              next if Hash === v1 and v1.empty?
              s(:pair, s(:str, k1.to_s), 
                if Parser::AST::Node === v1
                  v1
                else
                  s(:hash, *v1.map {|k2, v2| s(:pair, s(:str, k2.to_s), v2)})
                end
              )
            end
            args.unshift s(:hash, *pairs.compact)
          end

          # prepend element name
          if component
            args.unshift s(:const, nil, tag)
          else
            args.unshift s(:str, tag)
          end

          begin
            vue_apply = @vue_apply

            if complex_block.empty?
              @vue_apply = false

              # emit $h (createElement) call
              if @vue_h.instance_of? Array
                element = node.updated :send, [*@vue_h, *process_all(args)]
              else
                element = node.updated :send, [nil, @vue_h, *process_all(args)]
              end
            else
              # calls to $h (createElement) which contain a block
              #
              # collect array of child elements in a proc, and call that proc
              #
              #   $h('tag', hash, proc {
              #     var $_ = []
              #     $_.push($h(...))
              #     return $_
              #   }())
              #
              @vue_apply = true
              
              element = node.updated :send, [nil, @vue_h, 
                *process_all(args),
                s(:send, s(:block, s(:send, nil, :proc),
                  s(:args, s(:shadowarg, :$_)), s(:begin,
                  s(:lvasgn, :$_, s(:array)),
                  *process_all(complex_block),
                  s(:return, s(:lvar, :$_)))), :[])]
            end
          ensure
            @vue_apply = vue_apply
          end

          if @vue_apply
            # if apply is set, emit code that pushes result
            s(:send, s(:gvar, :$_), :push, element)
          else
            element
          end

        elsif node.children[0] == nil and node.children[1] == :_
          # text nodes
          # https://stackoverflow.com/questions/42414627/create-text-node-with-custom-render-function-in-vue-js
          text = s(:send, s(:self), :_v, process(node.children[2]))
          if @vue_apply
            # if apply is set, emit code that pushes text
            s(:send, s(:gvar, :$_), :push, text)
          else
            # simple/normal case: simply return the text
            text
          end

        elsif node.children[0]==s(:send, nil, :_) and node.children[1]==:[]
          if @vue_apply
            # if apply is set, emit code that pushes results
            s(:send, s(:gvar, :$_), :push, *process_all(node.children[2..-1]))
          elsif node.children.length == 3
            process(node.children[2])
          else
            # simple/normal case: simply return the element
            s(:splat, s(:array, *process_all(node.children[2..-1])))
          end

        elsif
          node.children[1] == :createElement and
          node.children[0] == s(:const, nil, :Vue)
        then
          # explicit calls to Vue.createElement
          if @vue_h.instance_of? Array
            element = node.updated nil, [*@vue_h,
              *process_all(node.children[2..-1])]
          else
            element = node.updated nil, [nil, @vue_h, 
              *process_all(node.children[2..-1])]
          end

          if @vue_apply
            # if apply is set, emit code that pushes result
            s(:send, s(:gvar, :$_), :push, element)
          else
            element
          end

        elsif
          @vue_self and VUE_METHODS.include? node.children[1] and
          node.children[0] == s(:const, nil, :Vue)
        then
          # vm methods
          node.updated nil, [s(:self), "$#{node.children[1]}", 
            *process_all(node.children[2..-1])]

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
                # convert method name to hash {class: name} pair
                pair = s(:pair, s(:sym, :class),
                  s(:str, node.children[1].to_s.gsub('_','-')))
              else
                # convert method name to hash {id: name} pair
                pair = s(:pair, s(:sym, :id),
                  s(:str, node.children[1].to_s[0..-2].gsub('_','-')))
              end

              # if a hash argument is already passed, merge in id value
              hash = children.find_index {|cnode| cnode.type == :hash}
              if hash
                children[hash] = s(:hash, pair, *children[hash].children)
              else
                children << s(:hash, pair)
              end

              # advance to next node
              node = node.children.first
            end

            # collapse series of method calls into a single call
            return process(node.updated(nil, [*node.children[0..1], *children]))

          else
            super
          end

        else
          super
        end
      end

      # convert blocks to proc arguments
      def on_block(node)
        child = node.children.first

        # map Vue.render(el, &block) to Vue.new(el: el, render: block)
        if
          child.children[1] == :render and
          child.children[0] == s(:const, nil, :Vue)
        then
          begin
            arg = node.children[1].children[0] || s(:arg, :$h)
            vue_h, @vue_h = @vue_h, arg.children.first

            block = node.children[2]
            block = s(:begin, block) unless block and block.type == :begin

            if
              block.children.length != 1 or not block.children.last or
              not [:send, :block].include? block.children.first.type
            then
              # wrap multi-line blocks with a 'span' element
              block = s(:return,
                s(:block, s(:send, nil, :_span), s(:args), *block))
            end

            return node.updated :send, [child.children[0], :new,
              s(:hash, s(:pair, s(:sym, :el), process(child.children[2])),
                s(:pair, s(:sym, :render), s(:block, s(:send, nil, :lambda),
                s(:args, s(:arg, @vue_h)), process(block))))]
          ensure
            @vue_h = vue_h
          end
        end

        return super unless @vue_h

        if
          child.children[1] == :createElement and
          child.children[0] == s(:const, nil, :Vue)
        then
          # block calls to Vue.createElement
          #
          # collect array of child elements in a proc, and call that proc
          #
          #   $h('tag', hash, proc {
          #     var $_ = []
          #     $_.push($h(...))
          #     return $_
          #   }())
          #
          begin
            vue_apply, @vue_apply = @vue_apply, true
            
            element = node.updated :send, [nil, @vue_h, 
              *child.children[2..-1],
              s(:send, s(:block, s(:send, nil, :proc),
                s(:args, s(:shadowarg, :$_)), s(:begin,
                s(:lvasgn, :$_, s(:array)), 
                process(node.children[2]),
                s(:return, s(:lvar, :$_)))), :[])]
          ensure
            @vue_apply = vue_apply
          end

          if @vue_apply
            # if apply is set, emit code that pushes result
            return s(:send, s(:gvar, :$_), :push, element)
          else
            return element
          end
        end

        # traverse through potential "css proxy" style method calls
        child = node.children.first
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
        else
          super
        end
      end

      # expand @@ to self
      def on_cvar(node)
        return super unless @vue_self
        s(:attr, s(:attr, s(:self), :$props), node.children[0].to_s[2..-1])
      end

      # expand instance properties like $options to this.$options
      def on_gvar(node)
        return super unless @vue_self
        if VUE_PROPERTIES.include? node.children[0]
          node.updated :attr, [s(:self), node.children[0]]
        else
          super
        end
      end

      # prevent attempts to assign to Vue properties
      def on_cvasgn(node)
        return super unless @vue_self
        raise NotImplementedError, "setting a Vue property"
      end

      # expand @ to @vue_self
      def on_ivar(node)
        return super unless @vue_self
        s(:attr, @vue_self, node.children[0].to_s[1..-1])
      end

      # expand @= to @vue_self.=
      def on_ivasgn(node)
        return super unless @vue_self 
        if node.children.length == 1
          s(:attr, @vue_self, "#{node.children[0].to_s[1..-1]}")
        else
          s(:send, @vue_self, "#{node.children[0].to_s[1..-1]}=", 
            process(node.children[1]))
        end
      end

      # for instance variables, map @x+= to this.x+=
      # for computed variables with setters, map x+= to this.x+=
      def on_op_asgn(node)
        return super unless @vue_self
        if node.children.first.type == :ivasgn
          node.updated nil, [s(:attr, @vue_self, 
            node.children[0].children[0].to_s[1..-1]),
            node.children[1], process(node.children[2])]

        elsif 
          node.children.first.type == :lvasgn and
          @vue_props.include? node.children[0].children[0]
        then
          node.updated nil, [s(:attr, s(:self), 
            node.children[0].children[0]),
            node.children[1], process(node.children[2])]

        else
          super
        end
      end

      # for computed variables with setters, map x= to this.x=
      def on_lvasgn(node)
        return super unless @vue_props.include? node.children.first
        s(:send, s(:self), "#{node.children.first}=",
          process(node.children[1]))
      end

      # instance methods as hash values (e.g., onClick: method)
      def on_pair(node)
        key, value = node.children
        return super unless Parser::AST::Node === value
        return super unless value.type == :send and 
          value.children.length == 2 and
          value.children[0] == nil and
          @vue_methods.include? value.children[1]
        node.updated nil, [process(key), value.updated(nil, [s(:self),
          value.children[1]])]
      end

      # ensure that there are no "wunderbar" or "createElement" calls in
      # a set of statements.
      def vue_wunderbar_free(nodes)
        nodes.each do |node|
          if Parser::AST::Node === node
            if node.type == :send
              # wunderbar style calls
              return false if node.children[0] == nil and 
                node.children[1].to_s.start_with? '_'

              # Vue.createElement calls
              return false if node.children[0] == s(:const, nil, :Vue) and 
                node.children[1] == :createElement
            end

            # recurse
            return false unless vue_wunderbar_free(node.children)
          end
        end

        # no problems found
        return true
      end

      # gather ivar and cvar usage
      def vue_walk(node, inventory = Hash.new {|h, k| h[k] = []})
        # extract ivars and cvars
        if [:ivar, :cvar].include? node.type
          symbol = node.children.first
          unless inventory[node.type].include? symbol
            inventory[node.type] << symbol
          end
        elsif node.type == :ivasgn
          symbol = nil
          symbol = node.children.first if node.children.length == 1
          if node.children.length == 2
            value = node.children[-1]
            symbol = value.children.first if value.type == :ivasgn
          end

          if symbol
            unless inventory[:ivar].include? symbol
              inventory[:ivar] << symbol
            end
          end
        end

        # recurse
        node.children.each do |child|
          vue_walk(child, inventory) if Parser::AST::Node === child
        end

        return inventory
      end
    end

    DEFAULTS.push Vue
  end
end
