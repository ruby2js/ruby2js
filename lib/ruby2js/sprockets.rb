# frozen_string_literal: true
# TODO: This feature is deprecated.

require 'sprockets/source_map_utils'
require 'ruby2js'
require 'ruby2js/version'

module Ruby2JS
  module SprocketsTransformer
    include Sprockets
    VERSION = '1'

    @@options = {}

    def self.options=(options)
      @@options = options
    end

    def self.cache_key
      @cache_key ||= "#{name}:#{Ruby2JS::VERSION::STRING}:#{VERSION}".freeze
    end

    def self.call(input)
      data = input[:data]

      js, map = input[:cache].fetch([self.cache_key, data]) do
        result = Ruby2JS.convert(data, {**@@options, file: input[:filename]})
        [result.to_s, result.sourcemap.transform_keys {|key| key.to_s}]
      end

      map = SourceMapUtils.format_source_map(map, input)
      map = SourceMapUtils.combine_source_maps(input[:metadata][:map], map)

      { data: js, map: map }
    end
  end
end

Sprockets.register_mime_type 'application/ruby', extensions: ['.rb', '.js.rb']

Sprockets.register_transformer 'application/ruby', 'application/javascript',
  Ruby2JS::SprocketsTransformer
