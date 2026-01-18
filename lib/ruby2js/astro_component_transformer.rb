require 'ruby2js'
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
    Result = Struct.new(:component, :frontmatter, :template, :errors, keyword_init: true)

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
    end

    # Transform the component, returning a Result
    def transform
      # Build conversion options with SFC and camelCase filters
      convert_options = @options.merge(template: :astro)
      convert_options[:filters] ||= []

      # Add ESM filter for import/export handling
      require 'ruby2js/filter/esm'
      unless convert_options[:filters].include?(Ruby2JS::Filter::ESM)
        convert_options[:filters] = convert_options[:filters] + [Ruby2JS::Filter::ESM]
      end

      # Add functions filter for method parentheses (.pop → .pop())
      require 'ruby2js/filter/functions'
      unless convert_options[:filters].include?(Ruby2JS::Filter::Functions)
        convert_options[:filters] = convert_options[:filters] + [Ruby2JS::Filter::Functions]
      end

      # Add return filter for implicit returns in blocks
      require 'ruby2js/filter/return'
      unless convert_options[:filters].include?(Ruby2JS::Filter::Return)
        convert_options[:filters] = convert_options[:filters] + [Ruby2JS::Filter::Return]
      end

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
          errors: @errors
        )
      end

      # The converted JS is already transformed by filters (ESM, SFC, etc.)
      transformed_frontmatter = script_js

      # Compile the template (convert Ruby expressions if any)
      compiled_template = compile_template(template_raw)

      # Build the final Astro component
      component = build_component(transformed_frontmatter, compiled_template)

      Result.new(
        component: component,
        frontmatter: transformed_frontmatter,
        template: compiled_template,
        errors: @errors
      )
    end

    # Class method for simple one-shot transformation
    def self.transform(source, options = {})
      self.new(source, options).transform
    end

    private

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
  end
end
