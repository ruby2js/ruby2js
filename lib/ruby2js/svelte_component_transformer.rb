require 'ruby2js'
require 'ruby2js/node'
require 'ruby2js/svelte_template_compiler'

module Ruby2JS
  # Transforms Ruby component files with __END__ templates into Svelte components.
  #
  # Input format:
  #   @post = nil
  #
  #   def on_mount
  #     @post = await Post.find(params[:id])
  #   end
  #
  #   def delete_post
  #     await @post.destroy
  #     goto('/posts')
  #   end
  #   __END__
  #   {#if post}
  #     <article>
  #       <h1>{post.title}</h1>
  #       <button on:click={deletePost}>Delete</button>
  #     </article>
  #   {:else}
  #     <p>Loading...</p>
  #   {/if}
  #
  # Output format (Svelte component):
  #   <script>
  #   import { onMount } from 'svelte'
  #   import { goto } from '$app/navigation'
  #   import { page } from '$app/stores'
  #   import { Post } from '$lib/models/post'
  #
  #   let post = null
  #
  #   onMount(async () => {
  #     post = await Post.find($page.params.id)
  #   })
  #
  #   async function deletePost() {
  #     await post.destroy()
  #     goto('/posts')
  #   }
  #   </script>
  #
  #   {#if post}
  #     <article>
  #       <h1>{post.title}</h1>
  #       <button on:click={deletePost}>Delete</button>
  #     </article>
  #   {:else}
  #     <p>Loading...</p>
  #   {/if}
  #
  class SvelteComponentTransformer
    # Result of component transformation
    Result = Struct.new(:component, :script, :template, :imports, :errors, keyword_init: true)

    # Svelte lifecycle hook mappings (Ruby method name → Svelte)
    # Use string keys to prevent camelCase conversion during transpilation
    LIFECYCLE_HOOKS = {
      'on_mount' => 'onMount',
      'on_destroy' => 'onDestroy',
      'before_update' => 'beforeUpdate',
      'after_update' => 'afterUpdate'
    }.freeze

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
      @lifecycle_hooks = []
      @imports = {
        svelte: Set.new,
        sveltekitNavigation: Set.new,
        sveltekitStores: Set.new,
        models: Set.new
      }
    end

    # Transform the component, returning a Result
    def transform
      # Build conversion options with SFC and camelCase filters
      convert_options = @options.merge(template: :svelte)
      convert_options[:filters] ||= []

      # Add SFC filter for @var → let var transformation
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
          script: script_js,
          template: nil,
          imports: {},
          errors: @errors
        )
      end

      # Analyze the Ruby code to find vars, methods, lifecycle hooks
      analyze_ruby_code

      # Transform the script
      transformed_script = transform_script(script_js)

      # Compile the template (convert Ruby expressions if any)
      compiled_template = compile_template(template_raw)

      # Build the final Svelte component
      component = build_component(transformed_script, compiled_template)

      Result.new(
        component: component,
        script: transformed_script,
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
      return unless Ruby2JS.ast_node?(node)

      case node.type
      when :ivasgn
        # Instance variable assignment → let declaration
        var_name = node.children.first.to_s[1..-1]  # Remove @
        @vars << var_name unless @vars.include?(var_name)

      when :ivar
        # Instance variable reference
        var_name = node.children.first.to_s[1..-1]
        @vars << var_name unless @vars.include?(var_name)

      when :def
        method_name = node.children.first
        method_name_str = method_name.to_s
        if LIFECYCLE_HOOKS.key?(method_name_str)
          @lifecycle_hooks << method_name
          @imports[:svelte] << LIFECYCLE_HOOKS[method_name_str] # Pragma: set
        else
          @methods << method_name
        end

      when :send
        # Check for navigation/routing usage
        target, method, *args = node.children
        if target.nil?
          case method
          when :goto
            @imports[:sveltekitNavigation] << 'goto' # Pragma: set
          when :invalidate
            @imports[:sveltekitNavigation] << 'invalidate' # Pragma: set
          when :invalidate_all
            @imports[:sveltekitNavigation] << 'invalidateAll' # Pragma: set
          when :prefetch
            @imports[:sveltekitNavigation] << 'prefetch' # Pragma: set
          when :params
            @imports[:sveltekitStores] << 'page' # Pragma: set
          end
        elsif Ruby2JS.ast_node?(target) && target.type == :send
          inner_target, inner_method = target.children
          if inner_target.nil? && inner_method == :params
            @imports[:sveltekitStores] << 'page' # Pragma: set
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
      node.children.each do |child|
        analyze_ast(child) if Ruby2JS.ast_node?(child)
      end
    end

    # Transform JavaScript to Svelte style
    def transform_script(js)
      lines = []

      # Build imports
      # Note: Use Array() instead of .to_a for JS compatibility (Sets)
      svelte_imports = Array(@imports[:svelte]).sort
      unless svelte_imports.empty?
        lines << "import { #{svelte_imports.join(', ')} } from 'svelte'"
      end

      nav_imports = Array(@imports[:sveltekitNavigation]).sort
      unless nav_imports.empty?
        lines << "import { #{nav_imports.join(', ')} } from '$app/navigation'"
      end

      store_imports = Array(@imports[:sveltekitStores]).sort
      unless store_imports.empty?
        lines << "import { #{store_imports.join(', ')} } from '$app/stores'"
      end

      @imports[:models].each do |model|
        lines << "import { #{model} } from '$lib/models/#{to_snake_case(model)}'"
      end

      lines << "" if lines.any?

      # Transform the script content
      transformed = transform_script_content(js)
      lines << transformed unless transformed.empty?

      lines.join("\n")
    end

    # Transform the main script content
    def transform_script_content(js)
      result = js.to_s  # Use to_s instead of dup for JS compatibility (strings are immutable)

      # Transform lifecycle hooks
      LIFECYCLE_HOOKS.each do |ruby_name, svelte_name|
        # Pattern: function onMount() { ... } → onMount(() => { ... })
        # or: async function onMount() { ... } → onMount(async () => { ... })
        camel_name = to_camel_case(ruby_name.to_s)
        result.gsub!(/^(\s*)(async )?function #{camel_name}\(\) \{/m) do
          indent = $1
          is_async = $2
          "#{indent}#{svelte_name}(#{is_async}() => {"
        end

        # Also handle if the method name wasn't camelCased by Ruby2JS
        result.gsub!(/^(\s*)(async )?function #{ruby_name}\(\) \{/m) do
          indent = $1
          is_async = $2
          "#{indent}#{svelte_name}(#{is_async}() => {"
        end
      end

      # Transform params[:id] to $page.params.id
      result.gsub!(/params\[:(\w+)\]/, '$page.params.\1')
      result.gsub!(/params\["(\w+)"\]/, '$page.params.\1')
      result.gsub!(/params\.(\w+)/, '$page.params.\1')

      result
    end

    # Compile the template using SvelteTemplateCompiler
    def compile_template(template)
      result = SvelteTemplateCompiler.compile(template, @options)
      @errors.concat(result.errors.map { |e| { type: 'templateError', **e } })
      result.template
    end

    # Build the final Svelte component
    def build_component(script, template)
      <<~SVELTE
        <script>
        #{script}
        </script>

        #{template}
      SVELTE
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
