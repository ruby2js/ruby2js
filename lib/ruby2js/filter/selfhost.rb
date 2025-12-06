# frozen_string_literal: true

# selfhost filter - transforms Ruby2JS internals for JavaScript execution
#
# This filter handles patterns specific to Ruby2JS's own codebase:
# - s(:type, ...) → s('type', ...) - symbol to string for AST node types
# - node.type == :str → node.type === 'str' - symbol comparisons
# - handle :type do ... end → handler registration
# - class Foo < Prism::Visitor → class with self-dispatch visit() method
#
# For spec files (when :selfhost_spec option is set):
# - gem(...) calls → removed
# - require 'minitest/autorun' → import from test_harness.mjs
# - require 'ruby2js' → import self-hosted converter
# - _(...) wrapper → just returns the inner value
# - describe Ruby2JS → describe("Ruby2JS", ...)
#
# This is NOT a general-purpose filter. It's specifically designed
# for transpiling Ruby2JS itself to JavaScript.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      include SEXP

      # Methods that should always be called as methods, never become getters
      # These are no-arg methods that have side effects or return dynamic values
      # NOTE: Do NOT add methods like to_s, to_i, upcase, etc. that the functions
      # filter transforms - they need to pass through to functions filter first
      METHOD_BLACKLIST = %i[
        convert pop shift clear dup clone
        freeze thaw taint untaint
        newline indent outdent put puts
      ].freeze

      # Method definitions that should never become getters (have side effects)
      DEF_METHOD_BLACKLIST = %i[
        convert newline indent outdent put puts
        compact capture wrap reindent respace
      ].freeze

      # JavaScript reserved words that need renaming when used as variable names
      # See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Lexical_grammar#reserved_words
      JS_RESERVED_WORDS = %i[
        break case catch class const continue debugger default delete do else
        enum export extends false finally for function if import in instanceof
        new null return super switch this throw true try typeof var void while
        with yield let static implements interface package private protected public
      ].freeze

      # Track if we're inside a Prism::Visitor subclass
      def initialize(*args)
        super
        @prism_visitor_class = false
        @selfhost_require_whitelist = nil
        @inside_ruby2js_module = false  # Track if we're inside module Ruby2JS
        @selfhost_spec = false  # Track if we're transpiling a spec file
      end

      # Classes that use Ruby's class reopening pattern.
      # When these classes appear without a superclass (reopening),
      # the methods are added to the class prototype instead of creating a nested class.
      REOPENING_CLASSES = %i[PrismWalker Converter].freeze

      # Classes to remove from transpilation entirely.
      # Source mapping helpers (SimpleLocation, etc.) are not needed in browser.
      # They provide Parser::Source::Buffer compatibility for sourcemaps.
      # Token and Line are provided as hand-written JS stubs in the preamble
      # because they use Ruby patterns that don't transpile (def [], def empty?, etc.)
      REMOVED_CLASSES = %i[
        SimpleLocation FakeSourceBuffer FakeSourceRange
        XStrLocation SendLocation DefLocation
        PrismSourceBuffer PrismSourceRange
        Token Line Serializer Error
      ].freeze

      # Legacy name for compatibility
      STUB_CLASSES = REMOVED_CLASSES

      def options=(options)
        super
        # Whitelist of require paths to keep (others are stripped)
        # If nil, all requires are stripped
        @selfhost_require_whitelist = options[:selfhost_require]
        # Enable spec mode for transpiling test files
        @selfhost_spec = options[:selfhost_spec]
      end

      # Transform Prism::Visitor subclass
      # - Remove inheritance
      # - Add self-dispatch visit() method
      # - Remove user-defined visit method (we generate our own)
      def on_class(node)
        name, superclass, body = node.children

        # Check for stub classes (Token, Line) that should be removed
        # These are provided as JavaScript stubs in the preamble
        if name&.type == :const
          class_name = name.children[1]
          if STUB_CLASSES.include?(class_name)
            # Remove this class definition entirely - it's provided in the preamble
            return nil
          end
        end

        # Handle Ruby class reopening pattern
        # When a class is reopened (no superclass) inside module Ruby2JS,
        # convert methods to prototype assignments:
        #   module Ruby2JS
        #     class Foo
        #       def bar; end
        #     end
        #   end
        # Becomes:
        #   Foo.prototype.bar = function() { }
        # Note: Only apply when inside module Ruby2JS to avoid breaking standalone classes
        if name&.type == :const && superclass.nil? && @inside_ruby2js_module
          class_name = name.children[1]
          if REOPENING_CLASSES.include?(class_name)
            # For PrismWalker reopening, set the visitor flag so super() calls are removed
            was_prism_visitor = @prism_visitor_class
            @prism_visitor_class = true if class_name == :PrismWalker

            result = convert_class_reopen_to_prototype(name, body)

            @prism_visitor_class = was_prism_visitor
            return result
          end
        end

        # Check for < Prism::Visitor
        if superclass&.type == :const &&
           superclass.children[0]&.type == :const &&
           superclass.children[0].children[1] == :Prism &&
           superclass.children[1] == :Visitor

          @prism_visitor_class = true

          # Filter out user-defined visit method before processing
          # (we generate our own self-dispatch visit method)
          if body&.type == :begin
            filtered_children = body.children.reject do |child|
              child&.type == :def && child.children[0] == :visit
            end
            body = s(:begin, *filtered_children)
          elsif body&.type == :def && body.children[0] == :visit
            body = nil
          end

          # Process body
          processed_body = process(body)

          # Create self-dispatch visit method for JS:
          # visit(node) {
          #   if (!node) return null;
          #   const method = this[`visit${node.constructor.name}`];
          #   return method ? method.call(this, node) : null;
          # }
          #
          # We use :attr for property access (not method calls) to get:
          #   node.constructor.name  (not node.constructor().name())
          visit_method = s(:def, :visit, s(:args, s(:arg, :node)),
            s(:begin,
              # if (!node) return null;
              s(:if, s(:send, s(:lvar, :node), :!),
                s(:return, s(:nil)), nil),
              # const method = this[`visit${node.constructor.name}`];
              s(:lvasgn, :method,
                s(:send, s(:self), :[],
                  s(:dstr,
                    s(:str, 'visit'),
                    s(:begin, s(:attr, s(:attr, s(:lvar, :node), :constructor), :name))))),
              # return method ? method.call(this, node) : null;
              s(:return,
                s(:if, s(:lvar, :method),
                  s(:send, s(:lvar, :method), :call, s(:self), s(:lvar, :node)),
                  s(:nil)))))

          # Add visit method to body
          if processed_body&.type == :begin
            new_body = s(:begin, visit_method, *processed_body.children)
          elsif processed_body
            new_body = s(:begin, visit_method, processed_body)
          else
            new_body = visit_method
          end

          @prism_visitor_class = false

          # Return class without superclass
          return s(:class, name, nil, new_body)
        end

        super
      end

      # Convert a class reopening to prototype method assignments
      # class Foo; def bar; end; end → Foo.prototype.bar = function() {}
      def convert_class_reopen_to_prototype(class_name, body)
        return nil if body.nil?

        # Get the class name as a symbol (e.g., :PrismWalker)
        class_sym = class_name.children[1]

        # Extract all method definitions and handle blocks from the body
        methods = []
        handle_blocks = []

        collect_items = ->(child) {
          return unless child
          if child.type == :def
            methods << child
          elsif child.type == :block
            # Check if it's a handle block: handle :type do |value| ... end
            send_node = child.children[0]
            if send_node.type == :send && send_node.children[0].nil? && send_node.children[1] == :handle
              handle_blocks << child
            end
          elsif child.type == :begin
            # Nested begin blocks from handle macro expansion
            child.children.each { |c| collect_items.call(c) }
          end
        }

        if body.type == :begin
          body.children.each { |child| collect_items.call(child) }
        else
          collect_items.call(body)
        end

        assignments = []

        # Process regular method definitions
        methods.each do |method|
          # Process the method through on_def to handle visit_*_node naming, etc.
          processed_method = process(method)
          next unless processed_method

          # Extract the processed method name and body
          if processed_method.type == :def || processed_method.type == :defm
            p_name, p_args, p_body = processed_method.children
          else
            # handle macro may have produced a begin with multiple defs
            assignments << process(method)
            next
          end

          # Build: ClassName.prototype.methodName = function(args) { body }
          # Use :defm (method) with nil name to get regular function expression
          # instead of arrow function (which doesn't bind 'this')
          proto = s(:attr, s(:const, nil, class_sym), :prototype)
          func = s(:defm, nil, p_args || s(:args), p_body)
          assignments << s(:send, proto, :"#{p_name}=", func)
        end

        # Process handle blocks: handle :type do |value| ... end
        # Convert to: Converter.prototype.on_type = function(value) { ... }
        handle_blocks.each do |block|
          send_node, args, block_body = block.children
          types = send_node.children[2..-1]  # Get all type symbols

          # Check for middle-rest pattern: |a, *b, c| which is invalid in JS
          restarg_index = args&.children&.find_index { |a| a.type == :restarg }
          if restarg_index && restarg_index < args.children.length - 1
            # Transform |a, *b, c| into |...args| with destructuring
            args_before_rest = args.children[0...restarg_index]
            rest_name = args.children[restarg_index].children.first || :_rest
            args_after_rest = args.children[(restarg_index + 1)..]

            processed_args = s(:args, s(:restarg, :$args))

            pre_stmts = []
            if args_before_rest.any?
              before_vars = args_before_rest.map { |a| s(:lvasgn, a.children.first) }
              mlhs = s(:mlhs, *before_vars, s(:splat, s(:lvasgn, :"$rest")))
              pre_stmts << s(:masgn, mlhs, s(:lvar, :$args))
            else
              pre_stmts << s(:lvasgn, :"$rest", s(:lvar, :$args))
            end

            args_after_rest.reverse.each do |arg|
              name = arg.children.first
              pre_stmts << s(:lvasgn, name, s(:send, s(:lvar, :"$rest"), :pop))
            end
            pre_stmts << s(:lvasgn, rest_name, s(:lvar, :"$rest"))

            processed_body = if block_body.type == :begin
              s(:begin, *pre_stmts, *block_body.children.map { |c| process(c) })
            else
              s(:begin, *pre_stmts, process(block_body))
            end
          else
            # Process args to rename reserved words like 'var' -> 'var_'
            processed_args = args ? process(args) : s(:args)
            processed_body = process(block_body)
          end

          types.each do |type_node|
            next unless type_node.type == :sym
            type_name = type_node.children[0]
            # Rename types with ! or ? for valid JS (send! -> send_bang)
            renamed_type = rename_method(type_name)
            method_name = :"on_#{renamed_type}"

            # Build: ClassName.prototype.on_type = function(args) { body }
            # Use :deff to generate regular function (not arrow) to preserve `this` binding
            proto = s(:attr, s(:const, nil, class_sym), :prototype)
            func = s(:deff, nil, processed_args, processed_body)
            assignments << s(:send, proto, :"#{method_name}=", func)
          end
        end

        return nil if assignments.empty?
        return assignments.first if assignments.length == 1
        s(:begin, *assignments)
      end

      # Handle module Ruby2JS when it just contains class reopenings
      # Strip the module wrapper and emit the prototype assignments directly
      def on_module(node)
        name, body = node.children

        # Check for module Ruby2JS
        if name&.type == :const && name.children[1] == :Ruby2JS
          # Set flag so on_class knows we're inside module Ruby2JS
          was_inside = @inside_ruby2js_module
          @inside_ruby2js_module = true

          # Process the body to get prototype assignments
          result = process(body)

          @inside_ruby2js_module = was_inside

          # If body is nil or empty, return nil
          return nil if result.nil?

          # If body is a single class reopening that became nil, return nil
          # Otherwise return the prototype assignments without the module wrapper
          return result
        end

        super
      end

      # Filter out nil children from begin blocks
      # (happens when we remove private/protected/public)
      def on_begin(node)
        children = process_all(node.children)
        children = children.compact
        return nil if children.empty?
        return children.first if children.length == 1
        node.updated(nil, children)
      end

      # Convert visit_*_node method names to camelCase (visitIntegerNode)
      # to match @ruby/prism constructor names
      # Also force blacklisted methods to stay as methods (not getters)
      # Also rename methods ending in ? or !
      def on_def(node)
        method_name, args, body = node.children

        # Rewrite the s() method to use the global s() function
        # The Ruby version has: if defined?(Parser::AST::Node) ... else Ruby2JS::Node.new ... end
        # For selfhost, we just want: return s(type, ...args) to delegate to the global s function
        if method_name == :s && args&.children&.length == 2
          type_arg = args.children[0]  # first arg is type
          rest_arg = args.children[1]  # second arg is *args (restarg)
          if type_arg&.type == :arg && rest_arg&.type == :restarg
            type_name = type_arg.children[0]
            args_name = rest_arg.children[0] || :args
            # Return: new Node(type, args)
            new_body = s(:send,
              s(:const, nil, :Node),
              :new,
              s(:lvar, type_name),
              s(:lvar, args_name))
            return s(:def, :s, process(args), new_body)
          end
        end

        # Check for visit_*_node pattern
        if method_name.to_s.start_with?('visit_') && method_name.to_s.end_with?('_node')
          # Convert snake_case to camelCase: visit_integer_node → visitIntegerNode
          camel_name = method_name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
          return s(:def, camel_name, process(args), process(body))
        end

        # Rename methods ending in ? or !
        renamed = rename_method(method_name)
        if renamed != method_name
          return s(:def, renamed, process(args), process(body))
        end

        # Force blacklisted no-arg methods to be methods, not getters
        # Use :defm to force method output even with no args
        if DEF_METHOD_BLACKLIST.include?(method_name) &&
           args&.children&.empty?
          return s(:defm, method_name, process(args), process(body))
        end

        super
      end

      # Remove super() calls inside Prism::Visitor subclasses
      # (since there's no superclass in the generated JS)
      def on_super(node)
        return nil if @prism_visitor_class
        super
      end

      def on_zsuper(node)
        return nil if @prism_visitor_class
        super
      end

      # Rename reserved words used as local variable names
      def on_lvasgn(node)
        name, value = node.children
        if JS_RESERVED_WORDS.include?(name)
          new_name = :"#{name}_"
          # Handle both standalone lvasgn (with value) and mlhs entries (no value)
          if value
            return s(:lvasgn, new_name, process(value))
          else
            return s(:lvasgn, new_name)
          end
        end
        super
      end

      def on_lvar(node)
        name = node.children.first
        if JS_RESERVED_WORDS.include?(name)
          return s(:lvar, :"#{name}_")
        end
        super
      end

      def on_arg(node)
        name = node.children.first
        if JS_RESERVED_WORDS.include?(name)
          return s(:arg, :"#{name}_")
        end
        super
      end

      # Methods ending in ? or ! that the functions filter handles
      # These should NOT be renamed - let functions filter transform them
      # is_method? is a Ruby2JS AST method that becomes isMethod() in JS
      FUNCTIONS_FILTER_METHODS = %i[
        respond_to? is_a? kind_of? instance_of? nil? empty? blank? present?
        include? key? has_key? member? start_with? end_with? match?
        between? zero? positive? negative? even? odd? integer? float?
        any? all? none? one? many?
        slice! map! select! reverse! gsub! sub! compact!
        is_method?
      ].freeze

      # Rename methods ending in ? or ! to valid JS identifiers
      # foo? -> is_foo, foo! -> foo_bang
      # But skip methods that functions filter handles
      # Also skip single-character operators like ! (NOT)
      def rename_method(name)
        return name if FUNCTIONS_FILTER_METHODS.include?(name)

        name_s = name.to_s
        # Don't rename single-char operators like ! (NOT operator)
        return name if name_s.length == 1

        if name_s.end_with?('?')
          base = name_s[0..-2]
          # Convert to is_foo pattern
          :"is_#{base}"
        elsif name_s.end_with?('!')
          :"#{name_s[0..-2]}_bang"
        else
          name
        end
      end

      # Check if a node (or any descendant) contains a break statement
      # Used to decide if we need to convert forEach to a for loop
      def contains_break?(node)
        return false unless node.respond_to?(:type)
        return true if node.type == :break

        # Don't descend into nested blocks/lambdas - their breaks are local
        return false if [:block, :lambda].include?(node.type)

        node.children.any? { |child| contains_break?(child) }
      end

      # Also handle singleton methods (def self.foo)
      def on_defs(node)
        target, method_name, args, body = node.children

        if method_name.to_s.start_with?('visit_') && method_name.to_s.end_with?('_node')
          camel_name = method_name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
          return s(:defs, process(target), camel_name, process(args), process(body))
        end

        super
      end

      # Instance variables from Serializer base class that need to be accessed
      # via this._name rather than private fields (since they're defined in parent)
      SERIALIZER_IVARS = %w[@sep @nl @ws @lines @indent @width @output].freeze

      def on_ivar(node)
        var_name = node.children[0].to_s
        if SERIALIZER_IVARS.include?(var_name)
          # Convert @sep to this._sep (using attr for property access)
          return s(:attr, s(:self), var_name.sub('@', '_').to_sym)
        end
        super
      end

      def on_ivasgn(node)
        var_name, value = node.children
        if SERIALIZER_IVARS.include?(var_name.to_s)
          # Convert @sep = x to this._sep = x using :send for property assignment
          prop_name = var_name.to_s.sub('@', '_')
          if value
            return s(:send, s(:self), :"#{prop_name}=", process(value))
          else
            return s(:attr, s(:self), prop_name.to_sym)
          end
        end
        super
      end

      # Handle bare class constant references: GROUP_OPERATORS -> Converter.GROUP_OPERATORS
      def on_const(node)
        parent, name = node.children
        if parent.nil? && CLASS_CONSTANTS.include?(name)
          return s(:attr, s(:const, nil, :Converter), name)
        end
        super
      end

      # Methods from Serializer (and Converter itself) that should be called as this.method()
      # when called without an explicit receiver in Ruby (bare method calls)
      # Note: s and sl are handled specially below for symbol conversion
      # Note: hoist? gets renamed to is_hoist by rename_method
      # Note: es20XX methods are getters in JS, not in this list - they become this.esXXXX (no parens)
      SELF_METHODS = %i[
        put puts sput to_s output_location capture wrap compact enable_vertical_whitespace
        parse parse_all scope jscope insert timestamp comments group
        visit visit_parameters multi_assign_declarations number_format operator_index
        parse_condition collapse_strings redoable
        is_boolean_expression rewrite conditionally_equals is_hoist
      ].freeze

      # Properties that need this. prefix but are accessed as getters (no parentheses)
      # These are no-arg methods in Ruby that become getters in JS
      SELF_PROPERTIES = %i[
        es2020 es2021 es2022 es2023 es2024 es2025
        underscored_private
      ].freeze

      # Class constants that need Converter. prefix when referenced bare
      CLASS_CONSTANTS = %i[
        LOGICAL OPERATORS INVERT_OP GROUP_OPERATORS VASGN COMPARISON_OPS
      ].freeze

      # Handle template literals (dstr) to wrap lvar in (var || "")
      # This handles Ruby's nil.to_s == "" behavior for local variables
      # that may be undefined in JavaScript
      def on_dstr(node)
        # Transform children: wrap :lvar in (lvar || "")
        new_children = node.children.map do |child|
          if child.type == :begin && child.children.length == 1 &&
             child.children[0]&.type == :lvar
            # #{var} → #{var || ""}, process lvar to handle reserved word renaming
            lvar = process(child.children[0])
            s(:begin, s(:or, lvar, s(:str, '')))
          elsif child.type == :lvar
            # Direct lvar in dstr → (lvar || ""), process to handle reserved word renaming
            s(:begin, s(:or, process(child), s(:str, '')))
          else
            process(child)
          end
        end
        node.updated(nil, new_children)
      end

      # Convert symbols to strings in s() calls
      # s(:send, ...) → s('send', ...)
      def on_send(node)
        target, method, *args = node.children

        # Convert is_method? to isMethod(node) - this is a Ruby2JS AST method
        # that checks if a node is a method call (has parentheses)
        # Use a helper function since AST nodes may not have this method
        if method == :is_method? && target
          return s(:send, nil, :isMethod, process(target))
        end

        # Convert node.updated(...) to updated(node, ...) - standalone helper
        # since AST nodes from Prism-WASM don't have the updated method
        if method == :updated && target
          return s(:send, nil, :updated, process(target), *process_all(args))
        end

        # Convert Set.new to empty array (Set methods become array methods)
        # Ruby Set#include?/<</#empty? map to Array includes/push/length==0
        if target&.type == :const && target.children == [nil, :Set] && method == :new
          return s(:array)
        end

        # Spec mode: Remove gem() calls
        if @selfhost_spec && target.nil? && method == :gem
          return nil
        end

        # Spec mode: Convert _(...) wrapper to just the inner expression
        # In Minitest: _(value).must_equal(expected) - _() is an expectation wrapper
        # We just want the value to flow through
        if @selfhost_spec && target.nil? && method == :_ && args.length == 1
          return process(args.first)
        end

        # Remove private/protected/public visibility modifiers (no-op in JS)
        if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
          return nil
        end

        # Wrap raise in IIFE to allow it in expression context (ternary operators)
        # raise Error.new("msg") → (() => { throw new Error("msg") })()
        # In JavaScript, throw is a statement, not an expression
        if target.nil? && method == :raise && args.length == 1
          # Create: (() => { throw arg })()
          throw_stmt = s(:send, nil, :raise, process(args.first))
          arrow_fn = s(:block, s(:send, nil, :proc), s(:args), throw_stmt)
          return s(:send, arrow_fn, :[])
        end

        # Convert bare calls to known methods into this.method() calls
        # In Ruby: output_location → self.output_location → this.output_location() in JS
        if target.nil? && SELF_METHODS.include?(method)
          return s(:send, s(:self), method, *process_all(args))
        end

        # Convert bare calls to known properties into this.property (no parens)
        # In Ruby: es2021 → self.es2021 → this.es2021 in JS (as getter)
        if target.nil? && SELF_PROPERTIES.include?(method)
          return s(:attr, s(:self), method)
        end

        # Handle Hash[x.map {...}] → Object.fromEntries(Object.entries(x).map(...))
        # This is needed because JavaScript objects don't have .map() like Ruby hashes
        if target&.type == :const && target.children == [nil, :Hash] && method == :[]
          inner = args.first
          if inner&.type == :block
            call_node, block_args, block_body = inner.children
            if call_node&.type == :send && call_node.children[1] == :map
              obj = call_node.children[0]
              # Transform: Hash[obj.map {|k,v| ...}]
              # To: Object.fromEntries(Object.entries(obj).map(([k,v]) => ...))
              entries_call = s(:send, s(:const, nil, :Object), :entries, process(obj))
              # Wrap block args in mlhs for array destructuring: (key, value) → ([key, value])
              if block_args.type == :args && block_args.children.length > 0
                # Create mlhs (multiple left-hand side) for destructured params
                destructured_args = s(:args, s(:mlhs, *block_args.children))
              else
                destructured_args = block_args
              end
              map_call = s(:block,
                s(:send, entries_call, :map),
                destructured_args,
                process(block_body))
              return s(:send, s(:const, nil, :Object), :fromEntries, map_call)
            end
          end
        end

        # Handle @vars.select {|k,v| ...}.keys → Object.entries(@vars).filter(...).map(e => e[0])
        # This handles hash filtering patterns used in the converter
        if method == :keys && target&.type == :block
          select_call = target.children[0]
          if select_call&.type == :send && [:select, :filter].include?(select_call.children[1])
            obj = select_call.children[0]
            block_args = target.children[1]
            block_body = target.children[2]

            # Build: Object.entries(obj).filter(([k,v]) => body).map(e => e[0])
            entries_call = s(:send, s(:const, nil, :Object), :entries, process(obj))

            # Destructure args for filter
            if block_args.type == :args && block_args.children.length > 0
              destructured_args = s(:args, s(:mlhs, *block_args.children))
            else
              destructured_args = block_args
            end

            filter_call = s(:block,
              s(:send, entries_call, :filter),
              destructured_args,
              process(block_body))

            # Add .map(e => e[0]) to get keys
            return s(:block,
              s(:send, filter_call, :map),
              s(:args, s(:arg, :e)),
              s(:send, s(:lvar, :e), :[], s(:int, 0)))
          end
        end

        # Handle hash.select {|k,v| ...} without .keys → Object.fromEntries(Object.entries(hash).filter(...))
        # This returns a filtered object
        if method == :select && target&.type == :ivar &&
           [:@vars, :@handlers].include?(target.children[0]) &&
           args.empty?
          # This will be processed when we see the block
          # Just fall through and let on_block handle it
        end

        # Filter require/require_relative statements based on whitelist
        # If whitelist is set, only keep requires matching the whitelist
        # If whitelist is nil, strip all requires
        if target.nil? && [:require, :require_relative].include?(method) &&
           args.length == 1 && args.first&.type == :str
          path = args.first.children.first
          if @selfhost_require_whitelist.nil?
            return nil  # Strip all requires
          elsif !@selfhost_require_whitelist.any? { |pattern| path.include?(pattern) }
            return nil  # Not in whitelist, strip it
          end
          # Otherwise, let it through for the require filter to process
        end

        # Handle hash.merge!(other) → Object.assign(hash, other)
        # Ruby merge! merges other hash into self in place
        if method == :merge! && args.length == 1 && target
          return s(:send, s(:const, nil, :Object), :assign, process(target), process(args.first))
        end

        # Handle array.compact! → arr.splice(0, arr.length, ...arr.filter(x => x != null))
        # Ruby compact! removes nil values in place (must be before rename_method)
        if method == :compact! && args.empty? && target
          processed_target = process(target)
          # Build: arr.splice(0, arr.length, ...arr.filter(x => x != null))
          filter_call = s(:block,
            s(:send, processed_target, :filter),
            s(:args, s(:arg, :_x)),
            s(:send, s(:lvar, :_x), :'!=', s(:nil)))
          return s(:send, processed_target, :splice,
            s(:int, 0), s(:attr, processed_target, :length),
            s(:splat, filter_call))
        end

        # Rename method calls ending in ? or !
        renamed = rename_method(method)
        if renamed != method
          # Also apply SELF_METHODS check for renamed methods
          if target.nil? && SELF_METHODS.include?(renamed)
            return s(:send, s(:self), renamed, *process_all(args))
          end
          return s(:send, process(target), renamed, *process_all(args))
        end

        # Handle s(:type, ...) calls - convert symbol to string AND add this. prefix
        if target.nil? && method == :s && args.first&.type == :sym
          sym_node = args.first
          str_node = s(:str, sym_node.children.first.to_s)
          # Use s(:self) to get this.s() instead of just s()
          return s(:send, s(:self), :s, str_node, *process_all(args[1..]))
        end

        # Handle s() with string type (already processed) - add this. prefix
        if target.nil? && method == :s && args.first&.type == :str
          return s(:send, s(:self), :s, *process_all(args))
        end

        # Handle sl(:type, ...) calls - same pattern
        if target.nil? && method == :sl && args.length >= 2 && args[1]&.type == :sym
          # sl(node, :type, ...) → this.sl(node, 'type', ...)
          first_arg = process(args[0])
          sym_node = args[1]
          str_node = s(:str, sym_node.children.first.to_s)
          return s(:send, s(:self), :sl, first_arg, str_node, *process_all(args[2..]))
        end

        # Handle sl() without symbol (add this. prefix)
        if target.nil? && method == :sl
          return s(:send, s(:self), :sl, *process_all(args))
        end

        # Handle node.type == :sym comparisons
        # node.type == :str → node.type === 'str'
        if method == :== && args.length == 1 && args.first&.type == :sym
          if target&.type == :send && target.children[1] == :type
            sym = args.first.children.first
            return s(:send, process(target), :===, s(:str, sym.to_s))
          end
        end

        # Handle %i(...).include?(node.type) patterns
        # %i(send csend).include?(node.type) → ['send', 'csend'].includes(node.type)
        if method == :include? && target&.type == :array
          # Check if target is an array of symbols
          if target.children.all? { |c| c.type == :sym }
            str_array = s(:array, *target.children.map { |c| s(:str, c.children.first.to_s) })
            return s(:send, str_array, :includes, *process_all(args))
          end
        end

        # Handle .compact → .filter(x => x != null)
        if method == :compact && args.empty?
          return s(:send, process(target), :filter,
            s(:block, s(:send, nil, :proc),
              s(:args, s(:arg, :x)),
              s(:send, s(:lvar, :x), :!=, s(:nil))))
        end

        # Handle respond_to? more safely for AST children that might be primitives
        # child.respond_to?(:type) → (typeof child === 'object' && child !== null && 'type' in child)
        if method == :respond_to? && args.length == 1 && args.first.type == :sym
          prop_name = args.first.children.first.to_s
          processed_target = process(target)

          # Build: typeof target === 'object' && target !== null && 'prop' in target
          type_check = s(:send,
            s(:send, nil, :typeof, processed_target),
            :===,
            s(:str, 'object'))
          null_check = s(:send, processed_target, :'!==', s(:nil))
          in_check = s(:in?, s(:str, prop_name), processed_target)

          return s(:and, s(:and, type_check, null_check), in_check)
        end

        # Handle Hash === obj pattern - check if it's a plain object (options hash)
        # In Ruby: Hash === args.last checks if last arg is a Hash
        # In JS: Check it's an object without a .type property (not an AST node)
        if target&.type == :const && target.children == [nil, :Hash] &&
           method == :=== && args.length == 1
          # Build: (typeof obj === 'object' && obj !== null && !obj.type)
          obj = process(args.first)
          type_check = s(:send, s(:send, nil, :typeof, obj), :===, s(:str, 'object'))
          null_check = s(:send, obj, :'!==', s(:nil))
          not_node_check = s(:send, s(:attr, obj, :type), :!, nil)
          return s(:and, s(:and, type_check, null_check), not_node_check)
        end

        # Handle Hash/Map key? method
        # For class constants (plain objects): INVERT_OP.has_key?(x) → (x in INVERT_OP)
        # For Maps (@comments, etc.): @comments.key?(key) → @comments.has(key)
        if method == :key? || method == :has_key? || method == :member?
          # Check if target is a class constant (plain object, not a Map)
          if target&.type == :const && CLASS_CONSTANTS.include?(target.children[1])
            # Use 'in' operator for plain objects
            return s(:in?, process(args.first), s(:attr, s(:const, nil, :Converter), target.children[1]))
          end
          return s(:send, process(target), :has, *process_all(args))
        end

        # Handle hash.include?(key) → (key in hash)
        # Ruby Hash#include? checks for key existence, different from Array#include?
        # We detect hash usage by checking if target is @vars, @handlers, etc.
        if method == :include? && args.length == 1
          # Check if target is likely a hash (instance vars used as hashes in converter)
          if target&.type == :ivar && [:@vars, :@handlers, :@rbstack, :@comments].include?(target.children[0])
            key = process(args.first)
            processed_target = process(target)
            # Use :in? node type which produces "key in obj" syntax
            return s(:in?, key, processed_target)
          end
        end

        # Handle Ruby Method#call(*args) → JS func.call(this, *args)
        # In Ruby: handler.call(*children) calls the method with children as args
        # In JS: We need to pass 'this' as the first arg since handlers need context
        # Transform: handler.call(*args) → handler.call(this, ...args)
        # BUT: node.call (no args) is a property access (e.g., Prism node's .call property)
        # Only inject 'this' when call has arguments
        if method == :call && target && !args.empty?
          return s(:send, process(target), :call, s(:self), *process_all(args))
        end

        # Handle hash[:key].to_s → (hash.key ?? '').toString()
        # Ruby's nil.to_s returns "", but JS undefined.toString() throws
        # This pattern is common: @options[:join].to_s
        # Use nullish coalescing (??) to preserve empty strings and zeros
        if method == :to_s && args.empty? && target&.type == :send
          inner_target, inner_method, *inner_args = target.children
          if inner_method == :[] && inner_args.length == 1
            # hash[:key].to_s → (hash.key ?? '').toString()
            processed_target = process(inner_target)
            processed_key = process(inner_args.first)
            # Build: (target[key] ?? '').toString()
            return s(:send,
              s(:begin, s(:nullish, s(:send, processed_target, :[], processed_key), s(:str, ''))),
              :toString)
          end
        end

        # Handle .dup → {...obj} or [...arr] (shallow copy)
        # For simplicity, use [...target] which works for arrays
        # Hash.dup would need {...target} but we'll use Object.assign for safety
        if method == :dup && args.empty? && target
          # Use spread syntax: [...target] for arrays, {...target} for hashes
          # Since we don't know the type at transpile time, use a safe approach
          return s(:send, s(:const, nil, :Object), :assign,
            s(:hash), process(target))
        end

        # Handle array << value → array.push(value)
        if method == :<< && args.length == 1 && target
          return s(:send, process(target), :push, process(args.first))
        end

        # Force blacklisted methods to be called as methods (with parens)
        # This prevents them from becoming getters
        if METHOD_BLACKLIST.include?(method) && args.empty?
          if target
            # Use :send! to force method call syntax
            return node.updated(:send!, [process(target), method])
          else
            # No target means implicit self - use this.method()
            return node.updated(:send!, [s(:self), method])
          end
        end

        super
      end

      # Transform @@handlers.each { |name| @handlers[name] = method(...) }
      # Into code that discovers handlers by scanning for on_* methods
      #
      # This is needed because in Ruby, handle(:type) populates @@handlers,
      # but when we transpile with selfhost filter, we generate direct method
      # definitions without populating @@handlers.
      def on_block(node)
        call, block_args, body = node.children

        # Check for @@handlers.each pattern in constructor
        if call.type == :send &&
           call.children[0]&.type == :cvar &&
           call.children[0].children[0] == :@@handlers &&
           call.children[1] == :each

          # Replace with code that discovers handlers dynamically:
          # Object.getOwnPropertyNames(Object.getPrototypeOf(this))
          #   .filter(k => k.startsWith('on_'))
          #   .forEach(k => this.#handlers[k.slice(3)] = this[k].bind(this))

          # Build: for (let name of Object.getOwnPropertyNames(Object.getPrototypeOf(this)).filter(k => k.startsWith('on_'))) {
          #          this.#handlers[name.slice(3)] = this[name].bind(this)
          #        }
          proto_call = s(:send,
            s(:const, nil, :Object),
            :getOwnPropertyNames,
            s(:send, s(:const, nil, :Object), :getPrototypeOf, s(:self)))

          filter_call = s(:block,
            s(:send, proto_call, :filter),
            s(:args, s(:arg, :k)),
            s(:send, s(:lvar, :k), :startsWith, s(:str, 'on_')))

          # for (let name of filtered) { @handlers[name.slice(3)] = this[name] }
          # Note: Don't bind - we'll pass 'this' explicitly in the .call() invocation
          handler_assign = s(:send,
            s(:ivar, :@handlers),
            :[]=,
            s(:send, s(:lvar, :name), :slice, s(:int, 3)),
            s(:send, s(:self), :[], s(:lvar, :name)))

          for_loop = s(:for_of,
            s(:lvasgn, :name),
            filter_call,
            handler_assign)

          return for_loop
        end

        # Handle @vars.select {|k,v| ...} → Object.fromEntries(Object.entries(@vars).filter(...))
        # The functions filter converts .select to .filter, but @vars is a hash (object)
        # Note: check for both :select and :filter since functions filter may have already run
        if call.type == :send &&
           [:select, :filter].include?(call.children[1]) &&
           call.children[0]&.type == :ivar &&
           [:@vars, :@handlers].include?(call.children[0].children[0])
          obj = call.children[0]

          # Build: Object.fromEntries(Object.entries(obj).filter(([k,v]) => body))
          entries_call = s(:send, s(:const, nil, :Object), :entries, process(obj))

          # Destructure args for filter
          if block_args.type == :args && block_args.children.length > 0
            destructured_args = s(:args, s(:mlhs, *block_args.children))
          else
            destructured_args = block_args
          end

          filter_block = s(:block,
            s(:send, entries_call, :filter),
            destructured_args,
            process(body))

          return s(:send, s(:const, nil, :Object), :fromEntries, filter_block)
        end

        # Handle items.rindex { |a| ... } → (() => { let i = items.findLastIndex(...); return i >= 0 ? i : null })()
        # Ruby's rindex returns nil when not found, but JS findLastIndex returns -1
        # We need to convert -1 to null to match Ruby semantics for truthiness checks
        if call.type == :send && call.children[1] == :rindex
          target = call.children[0]
          # Build IIFE that converts -1 to null:
          # (() => { let i = target.findLastIndex(...); return i >= 0 ? i : null; })()
          findlast_call = s(:block,
            s(:send, process(target), :findLastIndex),
            process(block_args),
            process(body))

          # Create the IIFE wrapper
          iife = s(:send,
            s(:block, s(:send, nil, :proc), s(:args),
              s(:begin,
                s(:lvasgn, :_i, findlast_call),
                s(:return, s(:if,
                  s(:send, s(:lvar, :_i), :>=, s(:int, 0)),
                  s(:lvar, :_i),
                  s(:nil))))),
            :[])
          return iife
        end

        # Handle array.each_with_index do |item, index| ... end with break
        # JavaScript's forEach can't be broken, so convert to while loop when break is present
        # array.each_with_index { |item, index| ...; break if cond } →
        #   { let index = 0; while (index < array.length) { let item = array[index]; ...; index++ } }
        if call.type == :send && call.children[1] == :each_with_index && contains_break?(body)
          target = call.children[0]
          item_var = block_args.children[0]&.children&.first
          index_var = block_args.children[1]&.children&.first || :_idx

          # Use while loop since Ruby2JS doesn't have C-style for loop AST node
          # { let index = 0; while (index < array.length) { let item = array[index]; body; index++ } }
          processed_target = process(target)
          init = s(:lvasgn, index_var, s(:int, 0))
          condition = s(:send, s(:lvar, index_var), :<, s(:send, processed_target, :length))
          increment = s(:op_asgn, s(:lvasgn, index_var), :+, s(:int, 1))

          if item_var
            item_assign = s(:lvasgn, item_var, s(:send, processed_target, :[], s(:lvar, index_var)))
            loop_body = s(:begin, item_assign, process(body), increment)
          else
            loop_body = s(:begin, process(body), increment)
          end

          while_loop = s(:while, condition, loop_body)
          return s(:kwbegin, s(:begin, init, while_loop))
        end

        # Handle n.downto(m) do |i| ... end → { let i = n; while (i >= m) { ...; i-- } }
        # The functions filter has issues with downto when combined with selfhost filter
        # due to state issues with the block converter.
        # Generate a while loop wrapped in a block scope for proper variable isolation.
        if call.type == :send && call.children[1] == :downto
          start = call.children[0]
          finish = call.children[2]
          block_var = block_args.children[0].children[0]

          # Create: begin
          #   let i = start
          #   while (i >= finish) { body; i-- }
          # end
          # Use a block scope to isolate the loop variable
          init = s(:lvasgn, block_var, process(start))
          decrement = s(:op_asgn, s(:lvasgn, block_var), :-, s(:int, 1))
          condition = s(:send, s(:lvar, block_var), :>=, process(finish))
          loop_body = s(:begin, process(body), decrement)
          while_loop = s(:while, condition, loop_body)
          return s(:kwbegin, s(:begin, init, while_loop))
        end

        if call.type == :send && call.children[0].nil? && call.children[1] == :handle
          types = call.children[2..]

          # Check for middle-rest pattern: |a, *b, c| which is invalid in JS
          # JS requires rest parameter to be last
          restarg_index = block_args.children.find_index { |a| a.type == :restarg }
          if restarg_index && restarg_index < block_args.children.length - 1
            # Transform |a, *b, c| into |...args| with destructuring
            # let [a, ...rest] = args; let c = rest.pop(); let b = rest;
            args_before_rest = block_args.children[0...restarg_index]
            rest_name = block_args.children[restarg_index].children.first || :_rest
            args_after_rest = block_args.children[(restarg_index + 1)..]

            # New args: (...$args)
            processed_args = s(:args, s(:restarg, :$args))

            # Build destructuring: let [a, ...rest] = $args
            # Then: let c = rest.pop(); let b = rest;
            pre_stmts = []

            # First extract the args before rest
            if args_before_rest.any?
              before_vars = args_before_rest.map { |a| s(:lvasgn, a.children.first) }
              mlhs = s(:mlhs, *before_vars, s(:splat, s(:lvasgn, :"$rest")))
              pre_stmts << s(:masgn, mlhs, s(:lvar, :$args))
            else
              pre_stmts << s(:lvasgn, :"$rest", s(:lvar, :$args))
            end

            # Extract args after rest (from the end)
            args_after_rest.reverse.each do |arg|
              name = arg.children.first
              pre_stmts << s(:lvasgn, name, s(:send, s(:lvar, :"$rest"), :pop))
            end

            # Assign the rest to the original rest variable
            pre_stmts << s(:lvasgn, rest_name, s(:lvar, :"$rest"))

            # Prepend to body
            processed_body = if body.type == :begin
              s(:begin, *pre_stmts, *body.children.map { |c| process(c) })
            else
              s(:begin, *pre_stmts, process(body))
            end
          else
            # Process block args and body normally
            processed_args = process(block_args)
            processed_body = process(body)
          end

          # Create method definitions for each type
          # handle :foo, :bar do |x| ... end  →  def on_foo(x) ... end; def on_bar(x) ... end
          methods = types.map do |t|
            type_name = t.type == :sym ? t.children.first.to_s : t.children.first
            method_name = :"on_#{type_name}"
            # Use :defm to force method (not getter) output
            s(:defm, method_name, processed_args, processed_body)
          end

          if methods.length == 1
            return methods.first
          else
            return s(:begin, *methods)
          end
        end

        super
      end

      # Strip if defined?(Parser::AST::Node) blocks
      # These are Ruby-specific monkey-patches that shouldn't be in JS
      def on_if(node)
        condition, then_body, else_body = node.children

        # Helper to check if a const path includes Parser
        check_parser_const = lambda do |target|
          return false unless target&.type == :const
          path = []
          node_to_check = target
          while node_to_check&.type == :const
            path.unshift(node_to_check.children[1])
            node_to_check = node_to_check.children[0]
          end
          path.include?(:Parser)
        end

        # Check for if defined?(Parser::AST::Node) && ... or similar
        # This pattern is used to conditionally add methods to the Parser gem's Node class
        if condition&.type == :and
          left, right = condition.children
          if left&.type == :defined?
            target = left.children.first
            if check_parser_const.call(target)
              # Strip this entire if block - it's a Ruby-specific monkey-patch
              return nil
            end
          end
        end

        # Single defined? check
        if condition&.type == :defined?
          target = condition.children.first
          if check_parser_const.call(target)
            return nil
          end
        end

        super
      end

      # Convert case node.type; when :str patterns
      def on_case(node)
        expr, *whens, else_body = node.children

        # Check if this is a case on node.type
        if expr&.type == :send && expr.children[1] == :type
          new_whens = whens.map do |when_node|
            conditions, body = when_node.children[0...-1], when_node.children.last

            # Convert symbol conditions to strings
            new_conditions = conditions.map do |cond|
              if cond.type == :sym
                s(:str, cond.children.first.to_s)
              else
                process(cond)
              end
            end

            s(:when, *new_conditions, process(body))
          end

          return s(:case, process(expr), *new_whens, else_body ? process(else_body) : nil)
        end

        super
      end
    end

    DEFAULTS.push Selfhost
  end
end

