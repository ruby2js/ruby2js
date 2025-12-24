# frozen_string_literal: true

require 'ruby2js'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/functions'

module Ruby2JS
  module Spa
    # Transpiles Ruby model files to JavaScript using Ruby2JS filters.
    #
    # Uses the Rails::Model filter to transform ActiveRecord DSL (has_many,
    # validates, etc.) into JavaScript class methods and getters.
    #
    # Example:
    #   transpiler = ModelTranspiler.new('/path/to/rails/app')
    #   js_code = transpiler.transpile(:Article)
    #
    class ModelTranspiler
      attr_reader :rails_root, :models_path

      DEFAULT_FILTERS = [
        Ruby2JS::Filter::Rails::Model,
        Ruby2JS::Filter::ESM,
        Ruby2JS::Filter::Functions
      ].freeze

      def initialize(rails_root, filters: nil)
        @rails_root = rails_root.to_s
        @models_path = File.join(@rails_root, 'app', 'models')
        @filters = filters || DEFAULT_FILTERS
      end

      # Transpile a single model to JavaScript
      def transpile(model_name)
        file_path = model_file_path(model_name)
        return nil unless File.exist?(file_path)

        source = File.read(file_path)
        Ruby2JS.convert(source, filters: @filters).to_s
      end

      # Transpile multiple models and return a hash of { model_name => js_code }
      def transpile_all(model_names)
        result = {}

        model_names.each do |name|
          js = transpile(name)
          result[name] = js if js
        end

        result
      end

      # Transpile and write all models to output directory
      def transpile_to_files(model_names, output_dir)
        FileUtils.mkdir_p(output_dir)

        model_names.each do |name|
          js = transpile(name)
          next unless js

          file_name = "#{snake_case(name.to_s)}.js"
          File.write(File.join(output_dir, file_name), js)
        end
      end

      private

      def model_file_path(model_name)
        File.join(@models_path, "#{snake_case(model_name.to_s)}.rb")
      end

      def snake_case(str)
        str.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
      end
    end
  end
end
