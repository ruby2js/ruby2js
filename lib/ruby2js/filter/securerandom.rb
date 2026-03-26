require 'ruby2js'

# SecureRandom filter - maps Ruby's SecureRandom to Web Crypto API
#
# Supported methods:
#   SecureRandom.uuid              → crypto.randomUUID()
#   SecureRandom.alphanumeric(n)   → helper using getRandomValues
#   SecureRandom.hex(n)            → helper using getRandomValues
#   SecureRandom.random_number(n)  → getRandomValues
#   SecureRandom.base64(n)         → helper using getRandomValues + btoa

module Ruby2JS
  module Filter
    module SecureRandom
      include SEXP

      ALPHANUMERIC_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

      def on_send(node)
        target, method, *args = node.children

        return super unless target == s(:const, nil, :SecureRandom)

        case method
        when :uuid
          # crypto.randomUUID()
          s(:send, s(:lvar, :crypto), :randomUUID)

        when :alphanumeric
          # SecureRandom.alphanumeric(n) → _secureRandomAlphanumeric(n)
          prepend_helper_alphanumeric
          n = args[0] ? process(args[0]) : s(:int, 16)
          s(:send, nil, :_secureRandomAlphanumeric, n)

        when :hex
          # SecureRandom.hex(n) → _secureRandomHex(n)
          prepend_helper_hex
          n = args[0] ? process(args[0]) : s(:int, 16)
          s(:send, nil, :_secureRandomHex, n)

        when :random_number
          prepend_helper_random_number
          if args.length == 0
            # Random float [0, 1)
            s(:send, nil, :_secureRandomNumber)
          else
            # Random integer [0, n)
            s(:send, nil, :_secureRandomNumber, process(args[0]))
          end

        when :base64
          prepend_helper_base64
          n = args[0] ? process(args[0]) : s(:int, 16)
          s(:send, nil, :_secureRandomBase64, n)

        else
          super
        end
      end

      private

      def prepend_helper_alphanumeric
        return if @secure_random_alphanumeric_added
        @secure_random_alphanumeric_added = true
        self.prepend_list << s(:jsraw,
          "function _secureRandomAlphanumeric(n) { " \
          "const chars = '#{ALPHANUMERIC_CHARS}'; " \
          "let result = ''; " \
          "const bytes = crypto.getRandomValues(new Uint8Array(n * 2)); " \
          "for (let i = 0; i < bytes.length && result.length < n; i++) { " \
          "if (bytes[i] < 248) result += chars[bytes[i] % 62]; " \
          "} return result }")
      end

      def prepend_helper_hex
        return if @secure_random_hex_added
        @secure_random_hex_added = true
        self.prepend_list << s(:jsraw,
          "function _secureRandomHex(n) { " \
          "return Array.from(crypto.getRandomValues(new Uint8Array(n)), " \
          "b => b.toString(16).padStart(2, '0')).join('') }")
      end

      def prepend_helper_random_number
        return if @secure_random_number_added
        @secure_random_number_added = true
        self.prepend_list << s(:jsraw,
          "function _secureRandomNumber(n) { " \
          "const v = crypto.getRandomValues(new Uint32Array(1))[0]; " \
          "return n == null ? v / 4294967296 : v % n }")
      end

      def prepend_helper_base64
        return if @secure_random_base64_added
        @secure_random_base64_added = true
        self.prepend_list << s(:jsraw,
          "function _secureRandomBase64(n) { " \
          "return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(n)))) }")
      end
    end

    DEFAULTS.push SecureRandom
  end
end
