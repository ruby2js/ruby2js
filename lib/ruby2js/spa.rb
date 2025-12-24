# frozen_string_literal: true

require_relative 'spa/manifest'
require_relative 'spa/builder'

module Ruby2JS
  module Spa
    class << self
      attr_accessor :configuration

      def configure(&block)
        self.configuration = Manifest.new
        configuration.instance_eval(&block)
        configuration
      end
    end
  end
end

# Load Rails Engine if Rails is present
if defined?(Rails::Engine)
  require_relative 'spa/engine'
end
