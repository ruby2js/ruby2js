require 'ruby2js'

module Ruby2JS
  module Filter
    module ESM
      include SEXP

      def initialize(*args)
        super
        @esm = true # signal for other filters
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
              s(:attr, nil, args[0].children[1]))
          else
            # import Stuff, "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, from: "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, as: "*", from: "file.js"
            #   => import Stuff as * from "file.js"
            # import [ Some, Stuff ], from: "file.js"
            #   => import { Some, Stuff } from "file.js"
            imports = (args[0].type == :const || args[0].type == :send) ? args[0] : args[0].children
            s(:import, args[1].children, imports) unless args[1].nil?
          end
        elsif method == :export          
          s(:export, *process_all(args))
        else
          super
        end
      end
    end

    DEFAULTS.push ESM
  end
end
