require 'ruby2js'

module Ruby2JS
  module Filter
    module ES2016
      def process(ast)
        unless @options[:eslevel] and @options[:eslevel] >= 2016
          @options[:eslevel] = 2016
        end

        super
      end
    end

    DEFAULTS.push ES2016
  end
end
