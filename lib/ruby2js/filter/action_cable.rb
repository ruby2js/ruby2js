# Support for ActionCable (Rails WebSocket) subscriptions.
#
# Converts Ruby DSL for ActionCable consumer subscriptions:
#   consumer.subscriptions.create "ChatChannel",
#     connected: -> { console.log "Connected" },
#     received: ->(data) { handle(data) },
#     disconnected: -> { console.log "Disconnected" }
#
# To JavaScript:
#   consumer.subscriptions.create("ChatChannel", {
#     connected() { console.log("Connected") },
#     received(data) { this.handle(data) },
#     disconnected() { console.log("Disconnected") }
#   })
#
# Also supports ActionCable.createConsumer() and subscription methods.
#
# Works with @rails/actioncable.

require 'ruby2js'

module Ruby2JS
  module Filter
    module ActionCable
      include SEXP
      extend SEXP

      # ActionCable subscription callbacks
      SUBSCRIPTION_CALLBACKS = Set.new(%i[
        connected
        disconnected
        received
        rejected
        initialized
      ])

      # ActionCable subscription instance methods
      SUBSCRIPTION_METHODS = Set.new(%i[
        perform
        send
        unsubscribe
        consumer
        identifier
      ])

      def initialize(*args)
        super
        @action_cable_subscription = false
      end

      def on_send(node)
        target, method, *args = node.children

        # ActionCable.createConsumer() or ActionCable.createConsumer(url)
        if target == s(:const, nil, :ActionCable) && method == :createConsumer
          if modules_enabled?
            prepend_list << s(:import,
              ['@rails/actioncable'],
              [s(:const, nil, :createConsumer)])
          end
          return s(:send, nil, :createConsumer, *process_all(args))
        end

        # consumer.subscriptions.create "Channel", { callbacks }
        if method == :create &&
           target&.type == :send &&
           target.children[1] == :subscriptions

          channel_arg = args.first
          options_arg = args[1]

          # Process the options hash if present
          if options_arg&.type == :hash
            begin
              @action_cable_subscription = true
              processed_options = process_subscription_hash(options_arg)
            ensure
              @action_cable_subscription = false
            end

            return s(:send, process(target), :create,
              process(channel_arg),
              processed_options)
          end
        end

        # Inside subscription: perform("action", data)
        if @action_cable_subscription && target.nil? &&
           SUBSCRIPTION_METHODS.include?(method)
          return s(:send, s(:self), method, *process_all(args))
        end

        super
      end

      private

      # Process subscription hash, converting lambda callbacks to methods
      def process_subscription_hash(hash_node)
        pairs = hash_node.children.map do |pair|
          key = pair.children[0]
          value = pair.children[1]

          key_name = key.type == :sym ? key.children[0] : nil

          # Convert lambda callbacks to method definitions
          if SUBSCRIPTION_CALLBACKS.include?(key_name) && value.type == :block
            # -> { ... } or ->(arg) { ... }
            lambda_call = value.children[0]
            lambda_args = value.children[1]
            lambda_body = value.children[2]

            if lambda_call == s(:send, nil, :lambda) ||
               lambda_call == s(:lambda)
              # Process the body with subscription context
              processed_body = lambda_body ? process(lambda_body) : nil
              s(:pair, key, s(:block, s(:send, nil, :proc), lambda_args, processed_body))
            else
              s(:pair, process(key), process(value))
            end
          else
            s(:pair, process(key), process(value))
          end
        end

        s(:hash, *pairs)
      end
    end

    DEFAULTS.push ActionCable
  end
end
