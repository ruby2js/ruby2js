require 'ruby2js'

module Ruby2JS
  # Compiles Svelte-style templates with Ruby expressions to Svelte templates with JS expressions.
  #
  # Transforms:
  # - `{ruby_expr}` interpolations → `{jsExpr}`
  # - `{#each ruby_collection as item}` → `{#each jsCollection as item}`
  # - `{#if ruby_condition}` → `{#if jsCondition}`
  # - `{:else if ruby_condition}` → `{:else if jsCondition}`
  # - `on:event={ruby_handler}` → `on:event={jsHandler}`
  # - `bind:prop={ruby_ref}` → `bind:prop={jsRef}`
  # - `{@html ruby_expr}` → `{@html jsExpr}`
  # - `{@debug ruby_vars}` → `{@debug jsVars}`
  #
  # == Usage
  #
  #   compiler = Ruby2JS::SvelteTemplateCompiler.new(template, options)
  #   result = compiler.compile
  #   result.template  # => compiled Svelte template
  #   result.errors    # => any compilation errors
  #
  # == Options
  #
  # - `:filters` - Ruby2JS filters to apply during expression conversion
  # - `:eslevel` - ES level for output (default: 2022)
  # - `:camelCase` - Convert snake_case to camelCase in expressions (default: true)
  #
  class SvelteTemplateCompiler
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
      result = []
      pos = 0

      while pos < @template.length
        # Find next { that's not escaped
        brace_start = find_next_brace(@template, pos)

        if brace_start.nil?
          # No more braces, add remaining text
          result << @template[pos..-1]
          break
        end

        # Add text before brace
        result << @template[pos...brace_start] if brace_start > pos

        # Find matching closing brace
        brace_end = find_matching_brace(@template, brace_start)

        if brace_end.nil?
          # Unmatched brace - treat as literal
          @errors << { type: :unmatched_brace, position: brace_start }
          result << @template[brace_start..-1]
          break
        end

        # Extract content between braces
        content = @template[(brace_start + 1)...brace_end]

        # Process based on content type
        result << "{" << process_brace_content(content) << "}"

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

    # Process content inside braces
    def process_brace_content(content)
      content = content.strip

      # Handle block constructs using if/elsif for JS compatibility
      # (Ruby case/when with regex doesn't transpile to JS switch correctly)
      if content =~ /^#each\s+(.+?)\s+as\s+(.+)$/
        # {#each collection as item} or {#each collection as item, index} or {#each collection as item (key)}
        process_each_block($1, $2)
      elsif content =~ /^#if\s+(.+)$/
        # {#if condition}
        process_if_block($1)
      elsif content =~ /^:else\s+if\s+(.+)$/
        # {:else if condition}
        process_else_if_block($1)
      elsif content =~ /^:else$/
        # {:else}
        content
      elsif content =~ /^\/each$/ || content =~ /^\/if$/ || content =~ /^\/await$/ || content =~ /^\/key$/
        # Closing tags - pass through
        content
      elsif content =~ /^#await\s+(.+)$/
        # {#await promise}
        process_await_block($1)
      elsif content =~ /^:then\s*(.*)$/
        # {:then value}
        process_then_block($1)
      elsif content =~ /^:catch\s*(.*)$/
        # {:catch error}
        process_catch_block($1)
      elsif content =~ /^#key\s+(.+)$/
        # {#key expression}
        process_key_block($1)
      elsif content =~ /^@html\s+(.+)$/
        # {@html expression}
        "@html #{convert_expression($1)}"
      elsif content =~ /^@debug\s+(.+)$/
        # {@debug variables}
        "@debug #{convert_expression($1)}"
      elsif content =~ /^@const\s+(\w+)\s*=\s*(.+)$/
        # {@const name = expression}
        "@const #{$1} = #{convert_expression($2)}"
      else
        # Plain expression - use begin/rescue with explicit returns for JS compatibility
        begin
          return convert_expression(content)
        rescue => e
          @errors << { type: :expression, content: content, error: e.message }
          return content
        end
      end
    end

    # Process {#each collection as item} or {#each collection as item, index (key)}
    def process_each_block(collection_expr, as_clause)
      js_collection = convert_expression(collection_expr.strip)

      # Parse the as clause - could be:
      # - "item"
      # - "item, index"
      # - "item (item.id)"
      # - "item, index (item.id)"
      if as_clause =~ /^(.+?)\s*\((.+)\)$/
        vars = $1.strip
        key_expr = $2.strip
        js_key = convert_expression(key_expr)
        "#each #{js_collection} as #{vars} (#{js_key})"
      else
        "#each #{js_collection} as #{as_clause.strip}"
      end
    end

    # Process {#if condition}
    def process_if_block(condition)
      js_condition = convert_expression(condition.strip)
      "#if #{js_condition}"
    end

    # Process {:else if condition}
    def process_else_if_block(condition)
      js_condition = convert_expression(condition.strip)
      ":else if #{js_condition}"
    end

    # Process {#await promise}
    def process_await_block(promise_expr)
      js_promise = convert_expression(promise_expr.strip)
      "#await #{js_promise}"
    end

    # Process {:then value}
    def process_then_block(value)
      if value.strip.empty?
        ":then"
      else
        ":then #{value.strip}"
      end
    end

    # Process {:catch error}
    def process_catch_block(error)
      if error.strip.empty?
        ":catch"
      else
        ":catch #{error.strip}"
      end
    end

    # Process {#key expression}
    def process_key_block(expression)
      js_expr = convert_expression(expression.strip)
      "#key #{js_expr}"
    end

    # Convert a Ruby expression to JavaScript using Ruby2JS
    def convert_expression(ruby_expr)
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
