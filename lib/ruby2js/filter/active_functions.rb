require 'ruby2js'

module Ruby2JS
  module Filter
    module ActiveFunctions
      include SEXP

      def on_send(node)
        target, method, *args = node.children
        return super unless args.empty?

        if es2015 and method == :blank?
          create_or_update_import("blank$")
          process node.updated :send, [nil, "blank$", target]
        elsif es2015 and method == :present?
          create_or_update_import("present$")
          process node.updated :send, [nil, "present$", target]
        elsif es2015 and method == :presence
          create_or_update_import("presence$")
          process node.updated :send, [nil, "presence$", target]
        else
          super
        end
      end

      private

      def create_or_update_import(token)
        af_import = @options[:import_from_skypack] ? "https://cdn.skypack.dev/@ruby2js/active-functions" : "@ruby2js/active-functions"

        if found_node = prepend_list.find {|ast| ast.type == :import && ast.children.first == af_import}
          unless found_node.children.last.find {|const| const.children.last == token}
            prepend_list.delete found_node
            prepend_list << s(:import, found_node.children.first, found_node.children.last.push(s(:const, nil, token)))
          end
        else
          prepend_list << s(:import, af_import, [s(:const, nil, token)])
        end
      end
    end

    DEFAULTS.push ActiveFunctions
  end
end
