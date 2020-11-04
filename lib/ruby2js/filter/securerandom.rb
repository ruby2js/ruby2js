require 'ruby2js'
require 'set'

# Experimental secure random support

module Ruby2JS
  module Filter
    module SecureRandom
      include SEXP
      extend SEXP

      CJS_SETUP = {
        base62_random: s(:casgn, nil, :base62_random, 
          s(:send, nil, :require, s(:str, "base62-random")))
      }

      ESM_SETUP = {
        base62_random: s(:import, ['base62-random'],
          s(:attr, nil, :base62_random))
      }

      def initialize(*args)
        @secure_random_setup = nil
        super
      end

      def process(node)
        return super if @secure_random_setup
        @secure_random_setup = Set.new
        result = super

        if @secure_random_setup.empty?
          result
        else
          setup = @esm ? ESM_SETUP : CJS_SETUP;
          s(:begin, *@secure_random_setup.to_a.map {|token| setup[token]}, result)
        end
      end

      def on_send(node)
        target, method, *args = node.children

        if target == s(:const, nil, :SecureRandom)
          if method == :alphanumeric and args.length == 1
            @secure_random_setup << :base62_random
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
