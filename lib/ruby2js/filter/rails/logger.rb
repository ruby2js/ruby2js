require 'ruby2js'

module Ruby2JS
  module Filter
    module Rails
      module Logger
        include SEXP

        # Map Rails.logger methods to console methods
        LOGGER_METHODS = {
          debug: :debug,
          info: :info,
          warn: :warn,
          error: :error,
          fatal: :error,  # console doesn't have fatal, use error
          unknown: :log
        }.freeze

        def on_send(node)
          target, method, *args = node.children

          # Check for Rails.logger.xxx pattern
          if rails_logger?(target) && LOGGER_METHODS.key?(method)
            console_method = LOGGER_METHODS[method]
            process(s(:send, s(:const, nil, :console), console_method, *args))
          else
            super
          end
        end

        private

        def rails_logger?(node)
          return false unless node&.type == :send
          target, method = node.children
          # Note: use explicit element comparison for JS compatibility (array == array compares refs in JS)
          method == :logger &&
            target&.type == :const &&
            target.children[0].nil? && target.children[1] == :Rails
        end
      end
    end

    DEFAULTS.push Rails::Logger
  end
end
