require 'ruby2js'

Ruby2JS.module_default = :esm

module Ruby2JS
  module Filter
    module ESM
      include SEXP

      def initialize(*args)
        super
        @esm = true # signal for other filters
        @esm_imports = nil
      end

      def options=(options)
        super
        @esm_autoimports = options[:autoimports]
        return unless @esm_autoimports
      end

      def process(node)
        return super if @esm_imports or not @esm_autoimports
        @esm_imports = Set.new
        result = super

        if @esm_imports.empty?
          result
        else
          s(:begin, *@esm_imports.to_a.map {|token|
            s(:import, @esm_autoimports[token], s(:const, nil, token))
          }, result)
        end
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
            imports = (args[0].type == :const || args[0].type == :send) ?
              process(args[0]) : 
              process_all(args[0].children)
            s(:import, args[1].children, imports) unless args[1].nil?
          end
        elsif method == :export          
          s(:export, *process_all(args))
        elsif @esm_imports and args.length == 0 and @esm_autoimports[method]
          @esm_imports.add(method)
          super
        else
          super
        end
      end

      def on_const(node)
        return super unless @esm_autoimports
        if node.children.first == nil and @esm_autoimports[node.children.last]
          @esm_imports.add(node.children.last)
        end
        super
      end
    end

    DEFAULTS.push ESM
  end
end
