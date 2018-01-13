require 'ruby2js'

module Ruby2JS
  module Filter
    module ES2017
      def process(ast)
        unless @options[:eslevel] and @options[:eslevel] >= 2017
          @options[:eslevel] = 2017
        end

        super
      end
    end

    DEFAULTS.push ES2017
  end
end
