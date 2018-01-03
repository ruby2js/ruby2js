require 'ruby2js'

module Ruby2JS
  module Filter
    module Strict
      include SEXP

      def initialize(*args)
        @strict = false
        super
      end

      def process(node)
        if @strict
          super
        else
          @strict = true
          s(:begin, s(:str, 'use strict'), super(node))
        end
      end
    end

    DEFAULTS.push Strict
  end
end
