require 'ruby2js'
require 'set'

# Experimental secure random support

module Ruby2JS
  module Filter
    module SecureRandom
      include SEXP
      extend SEXP

      IMPORT_BASE62_RANDOM = s(:import, ['base62-random'],
        s(:attr, nil, :base62_random))

      def on_send(node)
        target, method, *args = node.children

        if target == s(:const, nil, :SecureRandom)
          if method == :alphanumeric and args.length == 1
            prepend_list << IMPORT_BASE62_RANDOM
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
