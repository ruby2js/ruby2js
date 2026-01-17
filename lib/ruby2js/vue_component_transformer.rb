require 'ruby2js'
require 'ruby2js/node'
require 'ruby2js/vue_template_compiler'

module Ruby2JS
  # Transforms Ruby component files with __END__ templates into Vue Single File Components.
  #
  # Input format:
  #   @post = nil
  #
  #   def mounted
  #     @post = await Post.find(params[:id])
  #   end
  #
  #   def delete_post
  #     await @post.destroy
  #     router.push('/posts')
  #   end
  #   __END__
  #   <article v-if="post">
  #     <h1>{{ post.title }}</h1>
  #     <button @click="deletePost">Delete</button>
  #   </article>
  #
  # Output format (Vue SFC with <script setup>):
  #   <script setup>
  #   import { ref, onMounted } from 'vue'
  #   import { useRouter, useRoute } from 'vue-router'
  #
  #   const router = useRouter()
  #   const route = useRoute()
  #   const post = ref(null)
  #
  #   onMounted(async () => {
  #     post.value = await Post.find(route.params.id)
  #   })
  #
  #   async function deletePost() {
  #     await post.value.destroy()
  #     router.push('/posts')
  #   }
  #   </script>
  #
  #   <template>
  #     <article v-if="post">
  #       <h1>{{ post.title }}</h1>
  #       <button @click="deletePost">Delete</button>
  #     </article>
  #   </template>
  #
  class VueComponentTransformer
    # Result of component transformation
    Result = Struct.new(:sfc, :script, :template, :imports, :errors, keyword_init: true)

    # Vue lifecycle hook mappings (Ruby method name → Vue composition API)
    LIFECYCLE_HOOKS = {
      mounted: :onMounted,
      before_mount: :onBeforeMount,
      updated: :onUpdated,
      before_update: :onBeforeUpdate,
      unmounted: :onUnmounted,
      before_unmount: :onBeforeUnmount,
      activated: :onActivated,
      deactivated: :onDeactivated,
      error_captured: :onErrorCaptured,
      render_tracked: :onRenderTracked,
      render_triggered: :onRenderTriggered
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
      @refs = []
      @methods = []
      @lifecycle_hooks = []
      @imports = {
        vue: Set.new,
        vueRouter: Set.new,
        models: Set.new
      }
    end

    # Transform the component, returning a Result
    def transform
      # Build conversion options with SFC and camelCase filters
      convert_options = @options.merge(template: :vue)
      convert_options[:filters] ||= []

      # Add SFC filter for @var → const var = ref(value) transformation
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
          sfc: nil,
          script: script_js,
          template: nil,
          imports: {},
          errors: @errors
        )
      end

      # Analyze the Ruby code to find refs, methods, lifecycle hooks
      analyze_ruby_code

      # Transform the script
      transformed_script = transform_script(script_js)

      # Compile the template (convert Ruby expressions if any)
      compiled_template = compile_template(template_raw)

      # Build the final SFC
      sfc = build_sfc(transformed_script, compiled_template)

      Result.new(
        sfc: sfc,
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
      return unless node.is_a?(Ruby2JS::Node)

      case node.type
      when :ivasgn
        # Instance variable assignment → ref
        var_name = node.children.first.to_s[1..-1]  # Remove @
        @refs << var_name unless @refs.include?(var_name)
        @imports[:vue] << 'ref' # Pragma: set

      when :ivar
        # Instance variable reference
        var_name = node.children.first.to_s[1..-1]
        @refs << var_name unless @refs.include?(var_name)
        @imports[:vue] << 'ref' # Pragma: set

      when :def
        method_name = node.children.first
        if LIFECYCLE_HOOKS.key?(method_name)
          @lifecycle_hooks << method_name
          @imports[:vue] << LIFECYCLE_HOOKS[method_name].to_s # Pragma: set
        else
          @methods << method_name
        end

      when :send
        # Check for router/route usage
        target, method, *args = node.children
        if target.nil?
          case method
          when :router, :navigate
            @imports[:vueRouter] << 'useRouter' # Pragma: set
          when :route, :params
            @imports[:vueRouter] << 'useRoute' # Pragma: set
          end
        elsif target.is_a?(Ruby2JS::Node) && target.type == :send
          inner_target, inner_method = target.children
          if inner_target.nil? && inner_method == :params
            @imports[:vueRouter] << 'useRoute' # Pragma: set
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
        analyze_ast(child) if child.is_a?(Ruby2JS::Node)
      end
    end

    # Transform JavaScript to Vue composition API style
    def transform_script(js)
      lines = []

      # Build imports
      # Note: Use Array() instead of .to_a for JS compatibility (Sets)
      vue_imports = Array(@imports[:vue]).sort
      unless vue_imports.empty?
        lines << "import { #{vue_imports.join(', ')} } from 'vue'"
      end

      router_imports = Array(@imports[:vueRouter]).sort
      unless router_imports.empty?
        lines << "import { #{router_imports.join(', ')} } from 'vue-router'"
      end

      @imports[:models].each do |model|
        lines << "import { #{model} } from '@/models/#{to_snake_case(model)}'"
      end

      lines << "" if lines.any?

      # Add router/route initialization
      # Note: Use router_imports array (already converted from Set) for JS compatibility
      if router_imports.include?('useRouter')
        lines << "const router = useRouter()"
      end
      if router_imports.include?('useRoute')
        lines << "const route = useRoute()"
      end

      # Transform the script content
      transformed = transform_script_content(js)
      lines << transformed unless transformed.empty?

      lines.join("\n")
    end

    # Transform the main script content
    def transform_script_content(js)
      result = js.to_s  # Use to_s instead of dup for JS compatibility (strings are immutable)

      # Transform instance variable declarations to refs
      # Pattern: let varName = value → const varName = ref(value)
      @refs.each do |ref_name|
        camel_name = to_camel_case(ref_name)
        # Handle initial assignment
        result.gsub!(/let #{camel_name} = (.+?)(;|\n)/) do
          value = $1
          "const #{camel_name} = ref(#{value})#{$2}"
        end
        # Handle .value access for refs (in method bodies)
        # This is tricky - we need to add .value when accessing refs
      end

      # Transform lifecycle hooks
      LIFECYCLE_HOOKS.each do |ruby_name, vue_name|
        # Pattern: function mounted() { ... } → onMounted(() => { ... })
        # or: async function mounted() { ... } → onMounted(async () => { ... })
        result.gsub!(/^(\s*)(async )?function #{to_camel_case(ruby_name.to_s)}\(\) \{/m) do
          indent = $1
          is_async = $2
          "#{indent}#{vue_name}(#{is_async}() => {"
        end

        # Close the lifecycle hook properly
        # This is simplified - real implementation would need proper brace matching
      end

      # Transform params[:id] to route.params.id
      result.gsub!(/params\[:(\w+)\]/, 'route.params.\1')
      result.gsub!(/params\["(\w+)"\]/, 'route.params.\1')
      result.gsub!(/params\.(\w+)/, 'route.params.\1')

      # Transform router.push
      result.gsub!(/router\.push\(/, 'router.push(')

      result
    end

    # Compile the template using VueTemplateCompiler
    def compile_template(template)
      result = VueTemplateCompiler.compile(template, @options)
      @errors.concat(result.errors.map { |e| { type: 'templateError', **e } })
      result.template
    end

    # Build the final Vue SFC
    def build_sfc(script, template)
      <<~SFC
        <script setup>
        #{script}
        </script>

        <template>
        #{indent_template(template)}
        </template>
      SFC
    end

    # Indent template content for prettier output
    # Note: Use split instead of lines for JS compatibility
    # Note: Use explicit parens for JS compatibility
    def indent_template(template)
      template.split("\n").map { |line| "  " + line.rstrip() }.join("\n").strip()
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
