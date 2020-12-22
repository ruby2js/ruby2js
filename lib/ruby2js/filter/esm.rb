require 'ruby2js'

Ruby2JS.module_default = :esm

module Ruby2JS
  module Filter
    module ESM
      include SEXP

      def options=(options)
        super
        @options = options
        @esm_autoexports = options[:autoexports] && !@disable_autoexports
        @esm_autoimports = options[:autoimports]
        @esm_explicit_tokens = Set.new
      end

      def process(node)
        return super unless @esm_autoexports
        @esm_autoexports = false

        list = [node]
        while list.length == 1 and list.first.type == :begin
          list = list.first.children.dup
        end

        list.map! do |child|
          replacement = child

          if [:module, :class].include? child.type and
            child.children.first.type == :const and
            child.children.first.children.first == nil \
          then
            replacement = s(:export, child)
          elsif child.type == :casgn and child.children.first == nil
            replacement = s(:export, child)
          end

          if replacement != child and @comments[child]
            @comments[replacement] = @comments[child]
          end

          replacement
        end

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

          if args[0].type == :str
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
            imports = if args[0].type == :const || args[0].type == :send
              @esm_explicit_tokens << args[0].children.last
              process(args[0])
            else
              args[0].children.each {|i| @esm_explicit_tokens << i.children.last}
              process_all(args[0].children)
            end

            s(:import, args[1].children, imports) unless args[1].nil?
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
        end

        super
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
