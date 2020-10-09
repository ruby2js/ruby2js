require 'ruby2js'

module Ruby2JS
  module Filter
    module ESImports
      include SEXP

      def initialize(*args)
        super
      end

      def on_send(node)
        target, method, *args = node.children
        return super unless target.nil?

        if method == :import
          if args[0].type == :str
            # import "file.css"
            #   => import "file.css"
            s(:import, args[0].children[0])
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

    DEFAULTS.push ESImports
  end
end
