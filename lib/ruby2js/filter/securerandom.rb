require 'ruby2js'
require 'set'

# Experimental secure random support

module Ruby2JS
  module Filter
    module SecureRandom
      include SEXP

      # Lazy-initialized import node (avoids need for extend SEXP)
      def import_base62_random
        @import_base62_random ||= s(:import, ['base62-random'],
          s(:attr, nil, :base62_random))
      end

      def on_send(node)
        target, method, *args = node.children

        if target == s(:const, nil, :SecureRandom)
          if method == :alphanumeric and args.length == 1
            self.prepend_list << import_base62_random
            node.updated(nil, [nil, :base62_random, *args])
          else
            super
          end
        else
          super
        end
      end
    end

    DEFAULTS.push SecureRandom
  end
end
