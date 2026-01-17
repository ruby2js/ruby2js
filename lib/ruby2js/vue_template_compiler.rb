require 'ruby2js'

module Ruby2JS
  # Compiles Vue-style templates with Ruby expressions to Vue templates with JS expressions.
  #
  # Transforms:
  # - `{{ ruby_expr }}` interpolations → `{{ jsExpr }}`
  # - `v-for="item in ruby_collection"` → `v-for="item in jsCollection"`
  # - `v-if="ruby_condition"` → `v-if="jsCondition"`
  # - `:prop="ruby_value"` bindings → `:prop="jsValue"`
  # - `v-bind:prop="ruby_value"` → `v-bind:prop="jsValue"`
  # - `v-model="ruby_ref"` → `v-model="jsRef"`
  # - `v-show="ruby_condition"` → `v-show="jsCondition"`
  #
  # Event handlers like `@click="methodName"` are passed through unchanged
  # since method names are already valid JS identifiers.
  #
  # == Usage
  #
  #   compiler = Ruby2JS::VueTemplateCompiler.new(template, options)
  #   result = compiler.compile
  #   result.template  # => compiled Vue template
  #   result.errors    # => any compilation errors
  #
  # == Options
  #
  # - `:filters` - Ruby2JS filters to apply during expression conversion
  # - `:eslevel` - ES level for output (default: 2022)
  # - `:camelCase` - Convert snake_case to camelCase in expressions (default: true)
  #
  class VueTemplateCompiler
    # Result of template compilation
    Result = Struct.new(:template, :errors, :warnings, keyword_init: true)

    # Default options for Ruby2JS conversion
    DEFAULT_OPTIONS = {
      eslevel: 2022,
      filters: []
    }.freeze

    attr_reader :template, :options, :errors, :warnings

    def initialize(template, options = {})
      @template = template
      @options = DEFAULT_OPTIONS.merge(options)
      @errors = []
      @warnings = []
    end

    # Compile the template, returning a Result
    def compile
      result = @template.dup

      # Process Vue interpolations: {{ expression }}
      result = process_interpolations(result)

      # Process v-for directives
      result = process_v_for(result)

      # Process v-if/v-else-if/v-show directives
      result = process_conditionals(result)

      # Process v-bind shorthand and full syntax
      result = process_bindings(result)

      # Process v-model
      result = process_v_model(result)

      Result.new(
        template: result,
        errors: @errors,
        warnings: @warnings
      )
    end

    # Class method for simple one-shot compilation
    def self.compile(template, options = {})
      new(template, options).compile
    end

    private

    # Process {{ expression }} interpolations
    def process_interpolations(template)
      template.gsub(/\{\{\s*(.+?)\s*\}\}/m) do |match|
        ruby_expr = $1
        begin
          js_expr = convert_expression(ruby_expr)
          "{{ #{js_expr} }}"
        rescue => e
          @errors << { type: :interpolation, expression: ruby_expr, error: e.message }
          match # Return original on error
        end
      end
    end

    # Process v-for="item in collection" and v-for="(item, index) in collection"
    def process_v_for(template)
      # Match v-for with various patterns:
      # v-for="item in items"
      # v-for="(item, index) in items"
      # v-for="(value, key) in object"
      # v-for="(value, key, index) in object"
      template.gsub(/v-for="(.+?)\s+in\s+(.+?)"/) do |match|
        vars = $1
        ruby_collection = $2.strip
        begin
          js_collection = convert_expression(ruby_collection)
          "v-for=\"#{vars} in #{js_collection}\""
        rescue => e
          @errors << { type: :v_for, expression: ruby_collection, error: e.message }
          match
        end
      end
    end

    # Process v-if, v-else-if, v-show conditionals
    def process_conditionals(template)
      # Process v-if="condition"
      result = template.gsub(/v-if="(.+?)"/) do |match|
        process_directive_expression('v-if', $1, match)
      end

      # Process v-else-if="condition"
      result = result.gsub(/v-else-if="(.+?)"/) do |match|
        process_directive_expression('v-else-if', $1, match)
      end

      # Process v-show="condition"
      result = result.gsub(/v-show="(.+?)"/) do |match|
        process_directive_expression('v-show', $1, match)
      end

      result
    end

    # Process :prop="value" and v-bind:prop="value" bindings
    def process_bindings(template)
      # Process shorthand :prop="value" (but not ::prop or @click)
      result = template.gsub(/(?<!:):(\w[\w-]*)="(.+?)"/) do |match|
        prop = $1
        ruby_value = $2
        begin
          js_value = convert_expression(ruby_value)
          ":#{prop}=\"#{js_value}\""
        rescue => e
          @errors << { type: :binding, prop: prop, expression: ruby_value, error: e.message }
          match
        end
      end

      # Process v-bind:prop="value"
      result = result.gsub(/v-bind:(\w[\w-]*)="(.+?)"/) do |match|
        prop = $1
        ruby_value = $2
        begin
          js_value = convert_expression(ruby_value)
          "v-bind:#{prop}=\"#{js_value}\""
        rescue => e
          @errors << { type: :v_bind, prop: prop, expression: ruby_value, error: e.message }
          match
        end
      end

      result
    end

    # Process v-model="ref"
    def process_v_model(template)
      template.gsub(/v-model="(.+?)"/) do |match|
        ruby_ref = $1
        begin
          js_ref = convert_expression(ruby_ref)
          "v-model=\"#{js_ref}\""
        rescue => e
          @errors << { type: :v_model, expression: ruby_ref, error: e.message }
          match
        end
      end
    end

    # Helper to process a directive with an expression
    def process_directive_expression(directive, ruby_expr, original)
      js_expr = convert_expression(ruby_expr)
      "#{directive}=\"#{js_expr}\""
    rescue => e
      @errors << { type: directive.to_sym, expression: ruby_expr, error: e.message }
      original
    end

    # Convert a Ruby expression to JavaScript using Ruby2JS
    def convert_expression(ruby_expr)
      # For Vue templates, we're converting expressions that will be evaluated
      # in a context where variables already exist (reactive refs, props, etc.)
      #
      # Strategy: Wrap in an array literal and extract the first element.
      # This avoids the issue of bare identifiers being treated as declarations.

      # Build options for Ruby2JS
      convert_options = {
        eslevel: @options[:eslevel],
        filters: build_filters
      }

      # Wrap expression in array - [expr] becomes [jsExpr] in JS
      wrapped = "[#{ruby_expr}]"

      # Convert the wrapped expression
      result = Ruby2JS.convert(wrapped, convert_options)
      js = result.to_s.strip

      # Remove trailing semicolon
      js = js.chomp(';').strip

      # Extract the expression from the array: [expr] -> expr
      if js.start_with?('[') && js.end_with?(']')
        js = js[1...-1].strip
      end

      js
    end

    # Build the filter list for Ruby2JS conversion
    def build_filters
      filters = Array(@options[:filters]).dup

      # Add camelCase filter if enabled (default)
      if @options.fetch(:camelCase, true)
        require 'ruby2js/filter/camelCase'
        filters << Ruby2JS::Filter::CamelCase unless filters.include?(Ruby2JS::Filter::CamelCase)
      end

      # Add functions filter for common Ruby->JS method conversions
      require 'ruby2js/filter/functions'
      filters << Ruby2JS::Filter::Functions unless filters.include?(Ruby2JS::Filter::Functions)

      filters
    end
  end
end
