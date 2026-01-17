require 'ruby2js'
require 'ruby2js/node'
require 'ruby2js/astro_template_compiler'

module Ruby2JS
  # Transforms Ruby component files with __END__ templates into Astro components.
  #
  # Input format:
  #   @post = nil
  #   @comments = []
  #
  #   # Fetch data at build/request time
  #   @post = await Post.find(params[:id])
  #   @comments = await @post.comments
  #   __END__
  #   <Layout title={post.title}>
  #     <article>
  #       <h1>{post.title}</h1>
  #       <div set:html={post.body} />
  #     </article>
  #     <CommentList comments={comments} client:visible />
  #   </Layout>
  #
  # Output format (Astro component):
  #   ---
  #   import { Post } from '../models/post'
  #
  #   const { id } = Astro.params
  #   const post = await Post.find(id)
  #   const comments = await post.comments
  #   ---
  #
  #   <Layout title={post.title}>
  #     <article>
  #       <h1>{post.title}</h1>
  #       <div set:html={post.body} />
  #     </article>
  #     <CommentList comments={comments} client:visible />
  #   </Layout>
  #
  class AstroComponentTransformer
    # Result of component transformation
    Result = Struct.new(:component, :frontmatter, :template, :imports, :errors, keyword_init: true)

    # Default options
    DEFAULT_OPTIONS = {
      eslevel: 2022,
      filters: []
    }.freeze

    attr_reader :source, :options, :errors

    def initialize(source, options = {})
      @source = source
      @options = DEFAULT_OPTIONS.merge(options)
      @errors = []
      @vars = []
      @methods = []
      @imports = {
        models: Set.new
      }
      @uses_params = false
      @uses_props = false
      @prop_names = Set.new
    end

    # Transform the component, returning a Result
    def transform
      # Build conversion options with SFC and camelCase filters
      convert_options = @options.merge(template: :astro)
      convert_options[:filters] ||= []

      # Add SFC filter for @var → const var transformation
      require 'ruby2js/filter/sfc'
      unless convert_options[:filters].include?(Ruby2JS::Filter::SFC)
        convert_options[:filters] = convert_options[:filters] + [Ruby2JS::Filter::SFC]
      end

      # Add camelCase filter for method/variable name conversion
      require 'ruby2js/filter/camelCase'
      unless convert_options[:filters].include?(Ruby2JS::Filter::CamelCase)
        convert_options[:filters] = convert_options[:filters] + [Ruby2JS::Filter::CamelCase]
      end

      # Extract template from __END__
      result = Ruby2JS.convert(@source, convert_options)
      script_js = result.to_s
      template_raw = result.template

      if template_raw.nil? || template_raw.empty?
        @errors << { type: 'noTemplate', message: "No __END__ template found" }
        return Result.new(
          component: nil,
          frontmatter: script_js,
          template: nil,
          imports: {},
          errors: @errors
        )
      end

      # Analyze the Ruby code to find vars, methods, params/props usage
      analyze_ruby_code

      # Transform the script to Astro frontmatter
      transformed_frontmatter = transform_frontmatter(script_js)

      # Compile the template (convert Ruby expressions if any)
      compiled_template = compile_template(template_raw)

      # Build the final Astro component
      component = build_component(transformed_frontmatter, compiled_template)

      Result.new(
        component: component,
        frontmatter: transformed_frontmatter,
        template: compiled_template,
        imports: @imports,
        errors: @errors
      )
    end

    # Class method for simple one-shot transformation
    def self.transform(source, options = {})
      self.new(source, options).transform
    end

    private

    # Analyze Ruby source to extract component structure
    def analyze_ruby_code
      # Parse just the Ruby code (before __END__)
      ruby_code = @source.split(/^__END__\r?\n?/, 2).first

      begin
        ast, _ = Ruby2JS.parse(ruby_code)
        analyze_ast(ast) if ast
      rescue => e
        @errors << { type: 'parseError', message: e.message }
      end
    end

    # Analyze AST to find instance variables, methods, etc.
    def analyze_ast(node)
      return unless node.is_a?(Ruby2JS::Node)

      case node.type
      when :ivasgn
        # Instance variable assignment → const declaration
        var_name = node.children.first.to_s[1..-1]  # Remove @
        @vars << var_name unless @vars.include?(var_name)

      when :ivar
        # Instance variable reference
        var_name = node.children.first.to_s[1..-1]
        @vars << var_name unless @vars.include?(var_name)

      when :def
        method_name = node.children.first
        @methods << method_name

      when :send
        # Check for params/props usage
        target, method, *args = node.children
        if target.nil?
          case method
          when :params
            @uses_params = true
          when :props
            @uses_props = true
          end
        elsif target.is_a?(Ruby2JS::Node) && target.type == :send
          inner_target, inner_method = target.children
          if inner_target.nil?
            if inner_method == :params
              @uses_params = true
              # Track which param is accessed
              if args.first&.type == :sym
                @prop_names << args.first.children.first.to_s # Pragma: set
              end
            elsif inner_method == :props
              @uses_props = true
              if args.first&.type == :sym
                @prop_names << args.first.children.first.to_s # Pragma: set
              end
            end
          end
        end

      when :const
        # Model references
        const_name = node.children.last.to_s
        if const_name =~ /^[A-Z]/
          @imports[:models] << const_name # Pragma: set
        end
      end

      # Recurse into children
      # Check child is an object before checking for :type (JS compatibility)
      node.children.each do |child|
        analyze_ast(child) if child.is_a?(Ruby2JS::Node)
      end
    end

    # Transform JavaScript to Astro frontmatter style
    def transform_frontmatter(js)
      lines = []

      # Build imports
      @imports[:models].each do |model|
        lines << "import { #{model} } from '../models/#{to_snake_case(model)}'"
      end

      lines << "" if lines.any?

      # Add Astro.params destructuring if params are used
      if @uses_params
        if @prop_names.size > 0
          camel_names = [*@prop_names].map { |n| to_camel_case(n) }
          lines << "const { #{camel_names.join(', ')} } = Astro.params"
        else
          lines << "const params = Astro.params"
        end
      end

      # Add Astro.props destructuring if props are used
      if @uses_props
        if @prop_names.size > 0
          camel_names = [*@prop_names].map { |n| to_camel_case(n) }
          lines << "const { #{camel_names.join(', ')} } = Astro.props"
        else
          lines << "const props = Astro.props"
        end
      end

      # Transform the script content
      transformed = transform_script_content(js)
      lines << transformed unless transformed.empty?

      lines.join("\n")
    end

    # Transform the main script content
    def transform_script_content(js)
      result = js.to_s  # Use to_s instead of dup for JS compatibility (strings are immutable)

      # Transform params[:id] to id (already destructured from Astro.params)
      result.gsub!(/params\[:([\w]+)\]/) do
        to_camel_case($1)
      end
      result.gsub!(/params\["([\w]+)"\]/) do
        to_camel_case($1)
      end
      result.gsub!(/params\.([\w]+)/) do
        to_camel_case($1)
      end

      # Transform props[:name] similarly
      result.gsub!(/props\[:([\w]+)\]/) do
        to_camel_case($1)
      end
      result.gsub!(/props\["([\w]+)"\]/) do
        to_camel_case($1)
      end
      result.gsub!(/props\.([\w]+)/) do
        to_camel_case($1)
      end

      result
    end

    # Compile the template using AstroTemplateCompiler
    def compile_template(template)
      result = AstroTemplateCompiler.compile(template, @options)
      @errors.concat(result.errors.map { |e| { type: 'templateError', **e } })
      result.template
    end

    # Build the final Astro component
    def build_component(frontmatter, template)
      if frontmatter && !frontmatter.strip.empty?
        <<~ASTRO
          ---
          #{frontmatter}
          ---

          #{template}
        ASTRO
      else
        template
      end
    end

    # Convert camelCase to snake_case
    def to_snake_case(str)
      str.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
    end

    # Convert snake_case to camelCase
    def to_camel_case(str)
      str.gsub(/_([a-z])/) { $1.upcase }
    end
  end
end
