require 'ruby2js'

module Ruby2JS
  # Compiles Astro-style templates with Ruby expressions to Astro templates with JS expressions.
  #
  # Astro uses JSX-like syntax with `{expression}` interpolations, similar to Svelte but
  # without special block syntax ({#each}, {#if}). Instead, Astro uses JavaScript directly:
  #
  # - `{ruby_expr}` interpolations → `{jsExpr}`
  # - `{items.map { |item| ... }}` → `{items.map(item => ...)}`
  # - `{condition ? "yes" : "no"}` → `{condition ? "yes" : "no"}`
  # - `prop={ruby_value}` → `prop={jsValue}`
  # - `{...spread_obj}` → `{...spreadObj}`
  #
  # Astro-specific attributes are preserved:
  # - `client:load`, `client:visible`, `client:idle`, `client:only`
  # - `set:html={expr}`, `set:text={expr}`
  # - `is:raw`, `is:inline`
  #
  # == Usage
  #
  #   compiler = Ruby2JS::AstroTemplateCompiler.new(template, options)
  #   result = compiler.compile
  #   result.template  # => compiled Astro template
  #   result.errors    # => any compilation errors
  #
  # == Options
  #
  # - `:filters` - Ruby2JS filters to apply during expression conversion
  # - `:eslevel` - ES level for output (default: 2022)
  # - `:camelCase` - Convert snake_case to camelCase in expressions (default: true)
  #
  class AstroTemplateCompiler
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
      # First pass: convert snake_case attribute names to camelCase
      processed = convert_attribute_names(@template)

      # Second pass: process {expression} blocks
      result = []
      pos = 0

      while pos < processed.length
        # Find next { that's not escaped
        brace_start = find_next_brace(processed, pos)

        if brace_start.nil?
          # No more braces, add remaining text
          result << processed[pos..-1]
          break
        end

        # Add text before brace
        result << processed[pos...brace_start] if brace_start > pos

        # Find matching closing brace
        brace_end = find_matching_brace(processed, brace_start)

        if brace_end.nil?
          # Unmatched brace - treat as literal
          @errors << { type: :unmatched_brace, position: brace_start }
          result << processed[brace_start..-1]
          break
        end

        # Extract content between braces
        content = processed[(brace_start + 1)...brace_end]

        # Process the expression
        result << "{" << process_expression(content) << "}"

        pos = brace_end + 1
      end

      Result.new(
        template: result.join,
        errors: @errors,
        warnings: @warnings
      )
    end

    # Class method for simple one-shot compilation
    def self.compile(template, options = {})
      self.new(template, options).compile
    end

    private

    # Convert snake_case attribute names to camelCase in JSX
    # e.g., show_count={true} → showCount={true}
    def convert_attribute_names(template)
      camel_case_enabled = @options.fetch(:camelCase, true)
      return template unless camel_case_enabled

      # Match attribute patterns: name={...} or name="..."
      # Only convert snake_case names (containing underscores)
      template.gsub(/(\s)([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(=)/) do
        space = $1
        attr_name = $2
        equals = $3
        camel_name = attr_name.gsub(/_([a-z0-9])/) { $1.upcase }
        "#{space}#{camel_name}#{equals}"
      end
    end

    # Find the next unescaped opening brace
    def find_next_brace(str, start_pos)
      pos = start_pos
      while pos < str.length
        idx = str.index('{', pos)
        return nil if idx.nil?

        # Check if escaped (preceded by backslash)
        if idx > 0 && str[idx - 1] == '\\'
          pos = idx + 1
          next
        end

        return idx
      end
      nil
    end

    # Find the matching closing brace, handling nesting and strings
    def find_matching_brace(str, open_pos)
      depth = 1
      pos = open_pos + 1
      in_string = nil
      escape_next = false

      while pos < str.length && depth > 0
        char = str[pos]

        if escape_next
          escape_next = false
          pos += 1
          next
        end

        if char == '\\'
          escape_next = true
          pos += 1
          next
        end

        if in_string
          # Check for end of string
          if char == in_string
            in_string = nil
          end
        else
          case char
          when '"', "'"
            in_string = char
          when '`'
            in_string = char
          when '{'
            depth += 1
          when '}'
            depth -= 1
          end
        end

        pos += 1
      end

      depth == 0 ? pos - 1 : nil
    end

    # Process an expression inside braces
    def process_expression(content)
      content = content.strip

      # Handle spread operator: {...obj}
      if content.start_with?('...')
        expr = content[3..-1].strip
        return "...#{convert_expression(expr)}"
      end

      # Handle Ruby block with JSX: collection.map { |item| <jsx> }
      # Pattern: expr.map { |var| jsx_content } or expr.map { |var, idx| jsx_content }
      if content =~ /\A(.+?)\.map\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}\z/m
        collection = $1.strip
        block_vars = $2.strip
        block_body = $3.strip

        # Check if block body looks like JSX (starts with <)
        if block_body.start_with?('<')
          return process_map_block(collection, block_vars, block_body)
        end
      end

      # Handle .each (convert to .map for JSX output)
      if content =~ /\A(.+?)\.each\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}\z/m
        collection = $1.strip
        block_vars = $2.strip
        block_body = $3.strip

        if block_body.start_with?('<')
          return process_map_block(collection, block_vars, block_body)
        end
      end

      # Handle .select/.filter with block
      if content =~ /\A(.+?)\.(select|filter)\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}\z/m
        collection = $1.strip
        method = $2
        block_var = $3.strip
        block_body = $4.strip

        js_collection = convert_expression(collection)
        js_body = convert_expression(block_body)
        return "#{js_collection}.filter(#{block_var} => #{js_body})"
      end

      # Regular expression - use begin/rescue with explicit returns for JS compatibility
      begin
        return convert_expression(content)
      rescue => e
        @errors << { type: :expression, content: content, error: e.message }
        return content
      end
    end

    # Process a .map block with JSX body
    def process_map_block(collection, block_vars, jsx_body)
      # Convert collection expression
      js_collection = convert_expression(collection)

      # Process the JSX body recursively (convert {expr} inside it)
      processed_body = process_jsx_body(jsx_body)

      # Build the JavaScript .map() call
      "#{js_collection}.map(#{block_vars} => #{processed_body})"
    end

    # Process JSX body, converting {expr} expressions inside it
    def process_jsx_body(jsx)
      result = []
      pos = 0

      while pos < jsx.length
        brace_start = find_next_brace(jsx, pos)

        if brace_start.nil?
          result << jsx[pos..-1]
          break
        end

        result << jsx[pos...brace_start] if brace_start > pos

        brace_end = find_matching_brace(jsx, brace_start)
        if brace_end.nil?
          result << jsx[brace_start..-1]
          break
        end

        content = jsx[(brace_start + 1)...brace_end]
        result << "{" << process_expression(content) << "}"

        pos = brace_end + 1
      end

      result.join
    end

    # Convert a Ruby expression to JavaScript using Ruby2JS
    def convert_expression(ruby_expr)
      return ruby_expr if ruby_expr.empty?

      # Build options for Ruby2JS
      convert_options = {
        eslevel: @options[:eslevel],
        filters: build_filters
      }

      # Wrap expression in array - [expr] becomes [jsExpr] in JS
      # This prevents bare identifiers from being treated as declarations
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
      camel_case_enabled = @options.fetch(:camelCase, true)
      if camel_case_enabled
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
