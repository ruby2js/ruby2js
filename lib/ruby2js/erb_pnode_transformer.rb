require 'ruby2js'
require 'strscan'

module Ruby2JS
  # Transforms Ruby SFC files with ERB-style templates into Preact/React components.
  #
  # Input format (.erb.rb):
  #   import { useState, useEffect } from 'preact/hooks'
  #   import Post from '../models/Post'
  #
  #   def PostList()
  #     posts, setPosts = useState([])
  #     loading, setLoading = useState(true)
  #
  #     useEffect -> {
  #       Post.all.then { |data| setPosts(data); setLoading(false) }
  #     }, []
  #
  #     render
  #   end
  #
  #   export default PostList
  #   __END__
  #   <% if loading %>
  #     <div class="loading">Loading...</div>
  #   <% else %>
  #     <div class="posts">
  #       <% posts.each do |post| %>
  #         <article key={post.id}>
  #           <h2><%= post.title %></h2>
  #         </article>
  #       <% end %>
  #     </div>
  #   <% end %>
  #
  # Output format (JSX):
  #   import { useState, useEffect } from 'preact/hooks';
  #   import Post from '../models/Post';
  #
  #   function PostList() {
  #     const [posts, setPosts] = useState([]);
  #     const [loading, setLoading] = useState(true);
  #
  #     useEffect(() => {
  #       Post.all.then(data => { setPosts(data); setLoading(false); });
  #     }, []);
  #
  #     return loading ? (
  #       <div className="loading">Loading...</div>
  #     ) : (
  #       <div className="posts">
  #         {posts.map(post => (
  #           <article key={post.id}>
  #             <h2>{post.title}</h2>
  #           </article>
  #         ))}
  #       </div>
  #     );
  #   }
  #
  #   export default PostList;
  #
  class ErbPnodeTransformer
    # Result of component transformation
    Result = Struct.new(:component, :script, :template, :errors, keyword_init: true)

    # Default options
    DEFAULT_OPTIONS = {
      eslevel: 2022,
      filters: [],
      react: 'React'  # Default to React for Astro islands
    }.freeze

    # HTML5 void elements (self-closing)
    VOID_ELEMENTS = %w[
      area base br col embed hr img input link meta param source track wbr
    ].freeze

    attr_reader :source, :options, :errors

    def initialize(source, options = {})
      @source = source
      @options = DEFAULT_OPTIONS.merge(options)
      @errors = []
    end

    # Transform the component, returning a Result
    def transform
      # Split source at __END__
      parts = @source.split(/^__END__\r?\n?/, 2)
      ruby_code = parts[0]
      erb_template = parts[1]

      if erb_template.nil? || erb_template.strip.empty?
        @errors << { type: 'noTemplate', message: "No __END__ template found" }
        return Result.new(
          component: nil,
          script: ruby_code,
          template: nil,
          errors: @errors
        )
      end

      # Convert ERB template to Ruby code with %x{} syntax
      ruby_jsx = erb_to_ruby(erb_template.strip)

      if @errors.any?
        return Result.new(
          component: nil,
          script: ruby_code,
          template: erb_template,
          errors: @errors
        )
      end

      # Replace `render` calls with the Ruby JSX code
      modified_ruby = inject_render_body(ruby_code, ruby_jsx)

      # Convert Ruby code to JavaScript
      convert_options = build_convert_options
      result = Ruby2JS.convert(modified_ruby, convert_options)
      js_code = result.to_s

      # Add React import for SSR compatibility when in React mode
      if @options[:react] == 'React' && !js_code.include?('import React')
        js_code = "import React from \"react\";\n" + js_code
      end

      Result.new(
        component: js_code,
        script: ruby_code,
        template: erb_template,
        errors: @errors
      )
    end

    # Class method for simple one-shot transformation
    def self.transform(source, options = {})
      new(source, options).transform
    end

    private

    def build_convert_options
      convert_options = {**@options}
      convert_options[:filters] ||= []

      # Add required filters
      require 'ruby2js/filter/esm'
      require 'ruby2js/filter/functions'
      require 'ruby2js/filter/return'
      require 'ruby2js/filter/camelCase'
      require 'ruby2js/filter/react'
      require 'ruby2js/filter/jsx'

      filters_to_add = [
        Ruby2JS::Filter::ESM,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::Return,
        Ruby2JS::Filter::CamelCase,
        Ruby2JS::Filter::React,
        Ruby2JS::Filter::JSX
      ]

      filters_to_add.each do |filter|
        unless convert_options[:filters].include?(filter)
          convert_options[:filters] = convert_options[:filters] + [filter]
        end
      end

      convert_options
    end

    # Convert ERB template to Ruby code (top-level)
    # At top level, we output Ruby code with %x{} around JSX
    def erb_to_ruby(template)
      scanner = StringScanner.new(template)
      convert_top_level(scanner)
    end

    # Convert top-level content (Ruby code mode)
    # This produces Ruby code that includes %x{} blocks for JSX
    def convert_top_level(scanner)
      parts = []

      until scanner.eos?
        scanner.scan(/\s*/)
        break if scanner.eos?

        # ERB control tag at top level: <% if/unless/each %>
        if scanner.check(/<%[^=]/)
          parts << convert_top_erb_control(scanner)
        # ERB output tag: <%= ... %>
        elsif scanner.check(/<%=/)
          parts << convert_erb_output(scanner, top_level: true)
        # HTML element - wrap in %x{}
        elsif scanner.check(/<[a-zA-Z]/)
          jsx = convert_element(scanner, inside_jsx: false)
          parts << "%x{#{jsx}}"
        else
          # Skip unexpected content
          scanner.getch
        end
      end

      # Join parts with appropriate separators
      if parts.length == 1
        parts[0]
      else
        # Multiple parts need to be wrapped in a fragment
        jsx_parts = parts.map do |part|
          if part.start_with?('%x{')
            part[3..-2]  # Extract JSX from %x{...}
          else
            "{#{part}}"  # Wrap expression
          end
        end
        "%x{<>#{jsx_parts.join}</>}"
      end
    end

    # Convert an HTML element
    # inside_jsx: true means we're already inside %x{}, output raw JSX
    # inside_jsx: false means we're at top level, output will be wrapped in %x{}
    def convert_element(scanner, inside_jsx:)
      scanner.scan(/</)
      tag = scanner.scan(/[a-zA-Z][a-zA-Z0-9-]*/)
      return '' unless tag

      # Parse attributes
      attrs = []
      loop do
        scanner.scan(/\s+/)
        break if scanner.check(%r{/?>})

        name = scanner.scan(/[a-zA-Z_:][-a-zA-Z0-9_:.]*/)
        break unless name

        if scanner.scan(/\s*=\s*/)
          if scanner.scan(/"/)
            value = scanner.scan(/[^"]*/)
            scanner.scan(/"/)
            attrs << "#{name}=\"#{value}\""
          elsif scanner.scan(/'/)
            value = scanner.scan(/[^']*/)
            scanner.scan(/'/)
            attrs << "#{name}=\"#{value}\""
          elsif scanner.scan(/\{/)
            expr = scan_balanced_braces(scanner)
            attrs << "#{name}={#{expr}}"
          else
            value = scanner.scan(/[^\s>]+/)
            attrs << "#{name}=\"#{value}\""
          end
        else
          # Boolean attribute
          attrs << name
        end
      end

      attr_str = attrs.empty? ? '' : ' ' + attrs.join(' ')
      void = VOID_ELEMENTS.include?(tag.downcase)

      # Self-closing?
      if scanner.scan(%r{\s*/\s*>})
        return "<#{tag}#{attr_str} />"
      end

      scanner.scan(/\s*>/)

      if void
        return "<#{tag}#{attr_str} />"
      end

      # Parse children (we're now inside JSX)
      children = convert_jsx_children(scanner)

      # Consume closing tag
      scanner.scan(%r{</#{tag}\s*>})

      if children.empty?
        "<#{tag}#{attr_str} />"
      else
        "<#{tag}#{attr_str}>#{children}</#{tag}>"
      end
    end

    # Convert children inside JSX (inside %x{})
    # Returns raw JSX content with {} for expressions
    def convert_jsx_children(scanner)
      parts = []

      until scanner.eos?
        # Check for closing tag
        break if scanner.check(%r{</[a-zA-Z]})

        part = convert_jsx_child(scanner)
        parts << part if part && !part.empty?
      end

      parts.join
    end

    # Convert a single child inside JSX
    def convert_jsx_child(scanner)
      # Skip insignificant whitespace
      ws = scanner.scan(/\s*/)

      return nil if scanner.eos?
      return nil if scanner.check(%r{</})

      # ERB control tag inside JSX: <% if/each %> -> {expression}
      if scanner.check(/<%[^=]/)
        convert_jsx_erb_control(scanner)
      # ERB output tag: <%= expr %> -> {expr}
      elsif scanner.check(/<%=/)
        convert_erb_output(scanner, top_level: false)
      # Nested HTML element
      elsif scanner.check(/<[a-zA-Z]/)
        convert_element(scanner, inside_jsx: true)
      # Text content
      else
        convert_text(scanner)
      end
    end

    # Convert ERB output tag: <%= expr %>
    # At top level, returns the expression; inside JSX, returns {expr}
    def convert_erb_output(scanner, top_level:)
      scanner.scan(/<%=\s*/)
      expr = scanner.scan_until(/%>/)
      return '' unless expr

      expr = expr.sub(/%>\z/, '').strip
      top_level ? expr : "{#{expr}}"
    end

    # Convert ERB control tag at top level (Ruby code mode)
    # Returns Ruby code with %x{} around JSX parts
    def convert_top_erb_control(scanner)
      scanner.scan(/<%\s*/)
      code = scanner.scan_until(/%>/)
      return '' unless code

      code = code.sub(/%>\z/, '').strip

      case code
      when /^if\s+(.+)$/
        convert_top_if($1, scanner)
      when /^unless\s+(.+)$/
        convert_top_unless($1, scanner)
      when /^(\w+(?:\.\w+)*)\.each\s+do\s*\|([^|]+)\|$/
        convert_top_each($1, $2, scanner)
      when /^(\w+(?:\.\w+)*)\.map\s+do\s*\|([^|]+)\|$/
        convert_top_each($1, $2, scanner)
      when 'else', 'end'
        code  # Markers handled by parent
      else
        code  # Other code as-is
      end
    end

    # Convert ERB control tag inside JSX
    # Returns {expression} for use inside JSX
    def convert_jsx_erb_control(scanner)
      scanner.scan(/<%\s*/)
      code = scanner.scan_until(/%>/)
      return '' unless code

      code = code.sub(/%>\z/, '').strip

      case code
      when /^if\s+(.+)$/
        convert_jsx_if($1, scanner)
      when /^unless\s+(.+)$/
        convert_jsx_unless($1, scanner)
      when /^(\w+(?:\.\w+)*)\.each\s+do\s*\|([^|]+)\|$/
        convert_jsx_each($1, $2, scanner)
      when /^(\w+(?:\.\w+)*)\.map\s+do\s*\|([^|]+)\|$/
        convert_jsx_each($1, $2, scanner)
      when 'else', 'end'
        code  # Markers handled by parent
      else
        "{#{code}}"  # Other code as expression
      end
    end

    # Convert top-level if/else/end to Ruby ternary with %x{} around JSX
    def convert_top_if(condition, scanner)
      then_parts = []
      else_parts = []
      in_else = false

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*(else|elsif|end)\s*%>/)
          marker = scanner.scan(/<%\s*(else|elsif|end)\s*%>/)
          if marker =~ /else/
            in_else = true
            next
          else
            # end
            break
          end
        end

        if scanner.check(/<[a-zA-Z]/)
          jsx = convert_element(scanner, inside_jsx: false)
          part = "%x{#{jsx}}"
        elsif scanner.check(/<%=/)
          part = convert_erb_output(scanner, top_level: true)
        elsif scanner.check(/<%[^=]/)
          part = convert_top_erb_control(scanner)
        else
          scanner.scan(/\s*/)
          next if scanner.eos?
          next if scanner.check(/<%/) || scanner.check(/</)
          scanner.getch  # Skip unexpected char
          next
        end

        if part && !part.strip.empty? && part != 'else' && part != 'end'
          if in_else
            else_parts << part
          else
            then_parts << part
          end
        end
      end

      then_content = wrap_parts(then_parts)
      else_content = wrap_parts(else_parts)

      if else_content.empty?
        "(#{condition}) && (#{then_content})"
      else
        "(#{condition}) ? (#{then_content}) : (#{else_content})"
      end
    end

    # Convert top-level unless to conditional
    def convert_top_unless(condition, scanner)
      then_parts = []

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*end\s*%>/)
          scanner.scan(/<%\s*end\s*%>/)
          break
        end

        if scanner.check(/<[a-zA-Z]/)
          jsx = convert_element(scanner, inside_jsx: false)
          then_parts << "%x{#{jsx}}"
        elsif scanner.check(/<%=/)
          then_parts << convert_erb_output(scanner, top_level: true)
        elsif scanner.check(/<%[^=]/)
          part = convert_top_erb_control(scanner)
          then_parts << part if part && !part.strip.empty? && part != 'end'
        else
          scanner.scan(/\s*/)
          next if scanner.eos?
          next if scanner.check(/<%/) || scanner.check(/</)
          scanner.getch
          next
        end
      end

      then_content = wrap_parts(then_parts)
      "!(#{condition}) && (#{then_content})"
    end

    # Convert top-level each/map loop
    def convert_top_each(collection, var, scanner)
      body_parts = []
      var = var.strip

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*end\s*%>/)
          scanner.scan(/<%\s*end\s*%>/)
          break
        end

        if scanner.check(/<[a-zA-Z]/)
          jsx = convert_element(scanner, inside_jsx: false)
          body_parts << "%x{#{jsx}}"
        elsif scanner.check(/<%=/)
          body_parts << convert_erb_output(scanner, top_level: true)
        elsif scanner.check(/<%[^=]/)
          part = convert_top_erb_control(scanner)
          body_parts << part if part && !part.strip.empty? && part != 'end'
        else
          scanner.scan(/\s*/)
          next if scanner.eos?
          next if scanner.check(/<%/) || scanner.check(/</)
          scanner.getch
          next
        end
      end

      body_content = wrap_parts(body_parts)
      "#{collection}.map { |#{var}| #{body_content} }"
    end

    # Convert JSX if/else/end to ternary expression
    def convert_jsx_if(condition, scanner)
      then_parts = []
      else_parts = []
      in_else = false

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*(else|end)\s*%>/)
          marker = scanner.scan(/<%\s*(else|end)\s*%>/)
          if marker =~ /else/
            in_else = true
            next
          else
            break
          end
        end

        break if scanner.check(%r{</})

        part = convert_jsx_child(scanner)
        if part && !part.strip.empty? && part != 'else' && part != 'end'
          if in_else
            else_parts << part
          else
            then_parts << part
          end
        end
      end

      then_content = then_parts.join
      else_content = else_parts.join

      if else_content.empty?
        "{(#{condition}) && (#{then_content})}"
      else
        "{(#{condition}) ? (#{then_content}) : (#{else_content})}"
      end
    end

    # Convert JSX unless to conditional expression
    def convert_jsx_unless(condition, scanner)
      then_parts = []

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*end\s*%>/)
          scanner.scan(/<%\s*end\s*%>/)
          break
        end

        break if scanner.check(%r{</})

        part = convert_jsx_child(scanner)
        if part && !part.strip.empty? && part != 'end'
          then_parts << part
        end
      end

      then_content = then_parts.join
      "{!(#{condition}) && (#{then_content})}"
    end

    # Convert JSX each/map loop to expression
    def convert_jsx_each(collection, var, scanner)
      body_parts = []
      var = var.strip

      until scanner.eos?
        scanner.scan(/\s*/)

        if scanner.check(/<%\s*end\s*%>/)
          scanner.scan(/<%\s*end\s*%>/)
          break
        end

        break if scanner.check(%r{</})

        part = convert_jsx_child(scanner)
        if part && !part.strip.empty? && part != 'end'
          body_parts << part
        end
      end

      body_content = body_parts.join
      "{#{collection}.map { |#{var}| #{body_content} }}"
    end

    # Wrap multiple parts appropriately
    def wrap_parts(parts)
      return '' if parts.empty?
      return parts[0] if parts.length == 1

      # Multiple parts need fragment wrapper
      jsx_content = parts.map do |part|
        if part.start_with?('%x{')
          part[3..-2]  # Extract JSX
        else
          "{#{part}}"  # Wrap expression
        end
      end.join

      "%x{<>#{jsx_content}</>}"
    end

    # Convert text content
    def convert_text(scanner)
      text = +''
      until scanner.eos?
        break if scanner.check(/</) || scanner.check(/<%/)
        char = scanner.getch
        text << char if char
      end

      text.strip
    end

    # Scan balanced braces for JSX expressions
    def scan_balanced_braces(scanner)
      depth = 1
      expr = +''

      until scanner.eos? || depth == 0
        char = scanner.getch
        case char
        when '{'
          depth += 1
          expr << char
        when '}'
          depth -= 1
          expr << char if depth > 0
        else
          expr << char if char
        end
      end

      expr
    end

    # Inject Ruby JSX code into the Ruby source, replacing `render` calls
    def inject_render_body(ruby_code, ruby_jsx)
      # Replace bare `render` calls with the Ruby JSX expression
      ruby_code.gsub(/^\s*render\s*$/) do |match|
        indent = match[/^\s*/]
        "#{indent}#{ruby_jsx}"
      end
    end
  end
end
