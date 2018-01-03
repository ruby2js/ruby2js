require 'ruby2js'

module Ruby2JS
  module Filter
    module ES2015
      def process(ast)
        @options[:eslevel] = :es2015
        super
      end
    end

    DEFAULTS.push ES2015
  end
end
