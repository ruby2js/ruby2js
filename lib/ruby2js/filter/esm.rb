require 'ruby2js'

Ruby2JS.module_default = :esm

module Ruby2JS
  module Filter
    module ESM
      include SEXP

      def options=(options)
        super
        @esm_autoexports = !@disable_autoexports && options[:autoexports]
        @esm_autoimports = options[:autoimports]
        @esm_defs = options[:defs] || {}
        @esm_explicit_tokens = Set.new
      end

      def process(node)
        return super unless @esm_autoexports

        list = [node]
        while list.length == 1 and list.first.type == :begin
          list = list.first.children.dup
        end

        replaced = []
        list.map! do |child|
          replacement = child

          if [:module, :class].include? child.type and
            child.children.first.type == :const and
            child.children.first.children.first == nil \
          then
            replacement = s(:export, child)
          elsif child.type == :casgn and child.children.first == nil
            replacement = s(:export, child)
          elsif child.type == :def
            replacement = s(:export, child)
          end

          if replacement != child
            replaced << replacement
            @comments[replacement] = @comments[child] if @comments[child]
          end

          replacement
        end

        if replaced.length == 1 and @esm_autoexports == :default
          list.map! do |child|
            if child == replaced.first
              replacement = s(:export, s(:send, nil, :default, *child.children))
              @comments[replacement] = @comments[child] if @comments[child]
              replacement
            else
              child
            end
          end
        end

        @esm_autoexports = false
        process s(:begin, *list)
      end

      def on_class(node)
        @esm_explicit_tokens << node.children.first.children.last

        super
      end

      def on_def(node)
        @esm_explicit_tokens << node.children.first

        super
      end

      def on_lvasgn(node)
        @esm_explicit_tokens << node.children.first

        super
      end

      def on_send(node)
        target, method, *args = node.children
        return super unless target.nil?

        if method == :import
          # don't do the conversion if the word import is followed by a paren
          if node.loc.respond_to? :selector
            selector = node.loc.selector
            if selector and selector.source_buffer
              return super if selector.source_buffer.source[selector.end_pos] == '('
            end
          end

          if args[0].type == :str and args.length == 1
            # import "file.css"
            #   => import "file.css"
            s(:import, args[0].children[0])
          elsif args.length == 1 and \
             args[0].type == :send and \
            args[0].children[0].nil? and \
            args[0].children[2].type == :send and \
            args[0].children[2].children[0].nil? and \
            args[0].children[2].children[1] == :from and \
            args[0].children[2].children[2].type == :str
            # import name from "file.js"
            #  => import name from "file.js"
            @esm_explicit_tokens << args[0].children[1]

            s(:import,
              [args[0].children[2].children[2].children[0]],
              process(s(:attr, nil, args[0].children[1])))

          else
            # import Stuff, "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, from: "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, as: "*", from: "file.js"
            #   => import Stuff as * from "file.js"
            # import [ Some, Stuff ], from: "file.js"
            #   => import { Some, Stuff } from "file.js"
            # import Some, [ More, Stuff ], from: "file.js"
            #   => import Some, { More, Stuff } from "file.js"
            imports = []
            if %i(const send str).include? args[0].type
              @esm_explicit_tokens << args[0].children.last
              imports << process(args.shift)
            end

            if args[0].type == :array
              args[0].children.each {|i| @esm_explicit_tokens << i.children.last}
              imports << process_all(args.shift.children)
            end

            s(:import, args[0].children, *imports) unless args[0].nil?
          end
        elsif method == :export          
          s(:export, *process_all(args))
        elsif target.nil? and found_import = find_autoimport(method)
          prepend_list << s(:import, found_import[0], found_import[1])
          super
        else
          super
        end
      end

      def on_const(node)
        if node.children.first == nil and found_import = find_autoimport(node.children.last)
          prepend_list << s(:import, found_import[0], found_import[1])

          values = @esm_defs[node.children.last]
          
	  if values
	    values = values.map {|value| 
	      if value.to_s.start_with? "@" 
		[value.to_s[1..-1].to_sym, s(:self)]
	      else
		[value.to_sym, s(:autobind, s(:self))]
	      end
	    }.to_h

	    @namespace.defineProps values, [node.children.last]
	  end
        end

        super
      end

      def on_export(node)
        s(:export, *process_all(node.children))
      end
    end

    private

    def find_autoimport(token)
      return nil if @esm_autoimports.nil?
      return nil if @esm_explicit_tokens.include?(token)

      token = camelCase(token) if respond_to?(:camelCase)

      if @esm_autoimports[token]
        [@esm_autoimports[token], s(:const, nil, token)]
      elsif found_key = @esm_autoimports.keys.find {|key| key.is_a?(Array) && key.include?(token)}
        [@esm_autoimports[found_key], found_key.map {|key| s(:const, nil, key)}]
      end
    end

    DEFAULTS.push ESM
  end
end
