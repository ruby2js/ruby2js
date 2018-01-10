require 'ruby2js'

module Ruby2JS
  module Filter
    module ES2015
      def process(ast)
        unless @options[:eslevel] and @options[:eslevel] >= 2015
          @options[:eslevel] = 2015
        end

        super
      end
    end

    DEFAULTS.push ES2015
  end
end
