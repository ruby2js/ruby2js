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

        # Map Rails.env predicate methods to environment names
        ENV_PREDICATES = {
          :test? => 'test',
          :development? => 'development',
          :production? => 'production'
        }.freeze

        def on_send(node)
          target, method, *args = node.children

          # Check for Rails.logger.xxx pattern
          if rails_logger?(target) && LOGGER_METHODS.key?(method)
            console_method = LOGGER_METHODS[method]
            process(s(:send, s(:const, nil, :console), console_method, *args))

          # Check for Rails.env.test? / .development? / .production?
          elsif rails_env?(target) && ENV_PREDICATES.key?(method)
            env_name = ENV_PREDICATES[method]
            # import.meta.env.MODE works across all Vite targets (browser, node, edge)
            s(:send,
              s(:attr, s(:attr, s(:attr, nil, :"import.meta"), :env), :MODE),
              :===, s(:str, env_name))

          # Check for bare Rails.env (without predicate)
          elsif target&.type == :const &&
                target.children[0].nil? && target.children[1] == :Rails &&
                method == :env && args.empty?
            s(:attr, s(:attr, s(:attr, nil, :"import.meta"), :env), :MODE)

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

        def rails_env?(node)
          return false unless node&.type == :send
          target, method = node.children
          method == :env &&
            target&.type == :const &&
            target.children[0].nil? && target.children[1] == :Rails
        end
      end
    end

    DEFAULTS.push Rails::Logger
  end
end
