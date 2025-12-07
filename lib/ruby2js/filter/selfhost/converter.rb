# frozen_string_literal: true

# Selfhost Converter Filter - Transformations for Converter transpilation
#
# Handles patterns specific to the converter codebase:
# - handle :type do...end → method definitions
# - Class reopening → merged class definitions
# - Serializer ivar access (@sep, @nl, etc.)
#
# Status: STUB - To be implemented when transpiling converter.rb

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Converter
        include SEXP

        # Placeholder - converter-specific transformations will be added here
        # as we work on transpiling converter.rb and its handlers

        # Example patterns to handle (not yet implemented):
        # - handle :type do |*args| ... end
        # - Class.class_eval do ... end
        # - Serializer instance variable access
      end

      # NOTE: Converter is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling converter files
    end
  end
end
