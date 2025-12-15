# Ruby2JS Filter Processor
#
# This file contains the core filter infrastructure:
# - SEXP module for AST node creation
# - Processor class for walking AST and dispatching to on_<type> methods
#
# Used by both the main Ruby2JS and the selfhost bundle.

module Ruby2JS
  module Filter
    DEFAULTS = []

    module SEXP
      # construct an AST Node
      def s(type, *args)
        if defined?(Parser::AST::Node)
          Parser::AST::Node.new(type, args)
        else
          Ruby2JS::Node.new(type, args)
        end
      end

      # For compatibility - some code uses S() to update @ast
      def S(type, *args)
        @ast.updated(type, args)
      end

      # Check if object is an AST node (works with both Parser::AST::Node and Ruby2JS::Node)
      def ast_node?(obj)
        obj.respond_to?(:type) && obj.respond_to?(:children) && obj.respond_to?(:updated)
      end
    end

    # Processor walks Ruby2JS AST and dispatches to on_<type> methods
    class Processor
      BINARY_OPERATORS = %i[+ - * / % ** & | ^ << >> == === != < > <= >= <=> =~]

      attr_accessor :prepend_list, :disable_autoimports, :disable_autoexports, :namespace

      def initialize(comments)
        @comments = comments
        @ast = nil
        @exclude_methods = []
        @prepend_list = []
      end

      # Check if object is an AST node (works with both Parser::AST::Node and Ruby2JS::Node)
      def ast_node?(obj)
        obj.respond_to?(:type) && obj.respond_to?(:children) && obj.respond_to?(:updated)
      end

      # Instance methods for include/exclude tracking (moved from Filter module)

      # determine if a method is NOT to be processed
      def excluded?(method)
        if @included
          not @included.include? method
        else
          return true if @exclude_methods.flatten.include? method
          @excluded&.include? method
        end
      end

      # indicate that all methods are to be processed
      def include_all
        @included = nil
        @excluded = []
      end

      # indicate that only the specified methods are to be processed
      def include_only(*methods)
        @included = methods.flatten
      end

      # indicate that the specified methods are to be processed
      def include(*methods)
        if @included
          @included += methods.flatten
        else
          @excluded -= methods.flatten
        end
      end

      # indicate that the specified methods are not to be processed
      def exclude(*methods)
        if @included
          @included -= methods.flatten
        else
          @excluded += methods.flatten
        end
      end

      def options=(options)
        @options = options

        @included = Filter.included_methods
        @excluded = Filter.excluded_methods

        self.include_all if options[:include_all]
        self.include_only(options[:include_only]) if options[:include_only]
        self.include(options[:include]) if options[:include]
        self.exclude(options[:exclude]) if options[:exclude]

        filters = options[:filters] || DEFAULTS
        @modules_enabled =
          (defined? Ruby2JS::Filter::ESM and
          filters.include? Ruby2JS::Filter::ESM) or
          (defined? Ruby2JS::Filter::CJS and
          filters.include? Ruby2JS::Filter::CJS)
      end

      def modules_enabled?
        @modules_enabled
      end

      def es2015
        @options[:eslevel] >= 2015
      end

      def es2016
        @options[:eslevel] >= 2016
      end

      def es2017
        @options[:eslevel] >= 2017
      end

      def es2018
        @options[:eslevel] >= 2018
      end

      def es2019
        @options[:eslevel] >= 2019
      end

      def es2020
        @options[:eslevel] >= 2020
      end

      def es2021
        @options[:eslevel] >= 2021
      end

      def es2022
        @options[:eslevel] >= 2022
      end

      def es2023
        @options[:eslevel] >= 2023
      end

      def es2024
        @options[:eslevel] >= 2024
      end

      def es2025
        @options[:eslevel] >= 2025
      end

      # Process a node by dispatching to on_<type> method
      def process(node)
        return node unless ast_node?(node)

        ast, @ast = @ast, node

        # Dispatch to handler method
        handler = "on_#{node.type}"
        if self.respond_to?(handler)
          replacement = self.send(handler, node)
        else
          # Default: process children
          replacement = process_children(node)
        end

        return replacement
      ensure
        @ast = ast
      end

      # Process all children of a node, returning updated node if any changed
      def process_children(node)
        return node unless ast_node?(node)

        new_children = node.children.map do |child|
          if ast_node?(child)
            process(child)
          else
            child
          end
        end

        if new_children != node.children
          node.updated(nil, new_children)
        else
          node
        end
      end

      # Helper to create nodes
      def s(type, *children)
        if defined?(Parser::AST::Node)
          Parser::AST::Node.new(type, children)
        else
          Ruby2JS::Node.new(type, children)
        end
      end

      # Process all children of a node (like process_children but returns array)
      def process_all(nodes)
        return [] if nodes.nil?
        nodes.map { |node| process(node) }
      end

      # handle all of the 'invented/synthetic' ast types
      def on_assign(node); self.process_children(node); end
      def on_async(node); self.on_def(node); end
      def on_asyncs(node); self.on_defs(node); end
      def on_attr(node); self.on_send(node); end
      def on_autoreturn(node); self.on_return(node); end
      def on_await(node); self.on_send(node); end
      def on_call(node); self.on_send(node); end
      def on_class_extend(node); self.on_send(node); end
      def on_class_hash(node); self.on_class(node); end
      def on_class_module(node); self.on_send(node); end
      def on_constructor(node); self.on_def(node); end
      def on_deff(node); self.on_def(node); end
      def on_defm(node); self.on_defs(node); end
      def on_defp(node); self.on_defs(node); end
      def on_for_of(node); self.on_for(node); end
      def on_in?(node); self.on_send(node); end
      def on_instanceof(node); self.on_send(node); end
      def on_method(node); self.on_send(node); end
      def on_module_hash(node); self.on_module(node); end
      def on_nullish_or(node); self.on_or(node); end
      def on_nullish_asgn(node); self.on_or_asgn(node); end
      def on_logical_or(node); self.on_or(node); end
      def on_logical_asgn(node); self.on_or_asgn(node); end
      def on_prop(node); self.on_array(node); end
      def on_prototype(node); self.on_begin(node); end
      def on_send!(node); self.on_send(node); end
      def on_sendw(node); self.on_send(node); end
      def on_undefined?(node); self.on_defined?(node); end
      def on_defineProps(node); self.process_children(node); end
      def on_hide(node); self.on_begin(node); end
      def on_xnode(node); self.process_children(node); end
      def on_export(node); self.process_children(node); end
      def on_import(node); self.process_children(node); end
      def on_taglit(node); self.on_pair(node); end

      # Default handlers that process children
      def on_nil(node); node; end
      def on_sym(node); node; end
      def on_int(node); node; end
      def on_float(node); node; end
      def on_str(node); node; end
      def on_true(node); node; end
      def on_false(node); node; end
      def on_self(node); node; end

      # Handlers that process children by default
      # Note: send and csend are explicitly defined below with special handling
      %i[
        lvar ivar cvar gvar const
        lvasgn ivasgn cvasgn gvasgn casgn
        block def defs class module
        if case when while until for
        and or not
        array hash pair splat kwsplat
        args arg optarg restarg kwarg kwoptarg kwrestarg blockarg
        return break next redo retry
        begin kwbegin rescue resbody ensure
        masgn mlhs
        op_asgn and_asgn or_asgn
        regexp regopt
        dstr dsym xstr
        yield super zsuper
        defined? alias undef
        irange erange
        sclass
        match_pattern match_var
      ].each do |type|
        define_method("on_#{type}") do |node|
          process_children(node)
        end unless method_defined?("on_#{type}")
      end

      # convert numbered parameters block to a normal block
      def on_numblock(node)
        call, count, block = node.children

        process s(:block,
          call,
          s(:args, *((1..count).map {|i| s(:arg, :"_#{i}")})),
          block
        )
      end

      # convert map(&:symbol) to a block
      def on_send(node)
        node = process_children(node)
        return node unless ast_node?(node) && [:send, :csend].include?(node.type)

        if node.children.length > 2 and
           ast_node?(node.children.last) and
           node.children.last.type == :block_pass
          block_pass = node.children.last
          if ast_node?(block_pass.children.first) &&
             block_pass.children.first.type == :sym
            method = block_pass.children.first.children.first
            # preserve csend type for optional chaining
            call_type = node.type == :csend ? :csend : :send
            if BINARY_OPERATORS.include?(method)
              return self.on_block s(:block, s(call_type, *node.children[0..-2]),
                s(:args, s(:arg, :a), s(:arg, :b)), s(:return,
                process(s(:send, s(:lvar, :a), method, s(:lvar, :b)))))
            else
              return self.on_block s(:block, s(call_type, *node.children[0..-2]),
                s(:args, s(:arg, :item)), s(:return,
                process(s(:attr, s(:lvar, :item), method))))
            end
          end
        end
        node
      end

      def on_csend(node)
        self.on_send(node)
      end
    end
  end
end
