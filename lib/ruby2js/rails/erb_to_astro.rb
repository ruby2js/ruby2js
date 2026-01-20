# ERB-to-Astro converter
#
# Converts Rails ERB templates + controller actions to Astro pages.
# Produces complete .astro files with frontmatter and template sections.
#
# Uses shared HelperPatterns for consistent helper transformation across
# output formats (Astro templates, JavaScript AST, etc.)
#
# Usage:
#   ErbToAstro.convert(
#     erb: erb_template,
#     action: controller_action_code,
#     controller: 'articles',
#     action_name: 'index',
#     options: {}
#   )
#
require 'strscan'
require_relative 'helper_patterns'

module Ruby2JS
  module Rails
    class ErbToAstro
      # Main entry point
      def self.convert(erb:, action: nil, controller: nil, action_name: nil, options: {})
        new(erb, action, controller, action_name, options).convert
      end

      def initialize(erb, action, controller, action_name, options = {})
        @erb = erb
        @action = action
        @controller = controller
        @action_name = action_name
        @options = options
        @imports = []
        @frontmatter_lines = []
        @partials_used = []
        @helpers_used = Set.new
        @patterns = HelperPatterns.new(options)
      end

      def convert
        # Parse controller action to extract instance variable assignments
        parse_action if @action

        # Convert ERB template to Astro template
        template = convert_erb_to_astro_template

        # Build the complete .astro file
        build_astro_file(template)
      end

      private

      # Parse Ruby code into AST for pattern matching
      def parse_ruby(code)
        ast, _ = Ruby2JS.parse(code)
        ast
      rescue => e
        # If parsing fails, return nil
        nil
      end

      # Parse controller action to extract data fetching
      def parse_action
        return unless @action

        # Extract instance variable assignments
        # Pattern: @var = expr
        @action.scan(/@(\w+)\s*=\s*(.+)$/) do |var, expr|
          js_expr = transform_ruby_expr(expr.strip)
          @frontmatter_lines << "const #{var} = await #{js_expr};"
        end
      end

      # Convert ERB template to Astro template syntax
      def convert_erb_to_astro_template
        @scanner = StringScanner.new(@erb)
        result = parse_content
        result
      end

      # Parse content until we hit a stopping condition
      def parse_content(stop_at = nil)
        parts = []

        until @scanner.eos?
          # Check for stop conditions
          if stop_at
            case stop_at
            when :else_or_end
              break if @scanner.check(/<%\s*(else|elsif|end)\s*-?%>/)
            when :end
              break if @scanner.check(/<%\s*end\s*-?%>/)
            end
          end

          if @scanner.check(/<%=/)
            parts << parse_erb_output
          elsif @scanner.check(/<%/)
            part = parse_erb_control
            parts << part if part
          else
            text = parse_text
            parts << text if text && !text.empty?
          end
        end

        parts.join
      end

      # Parse <%= expr %> - output tag
      def parse_erb_output
        @scanner.scan(/<%=\s*/)
        expr = scan_until_erb_close
        transform_output_expr(expr)
      end

      # Parse <% ... %> - control tag
      def parse_erb_control
        @scanner.scan(/<%-?\s*/)
        code = scan_until_erb_close.strip

        case code
        when /^if\s+(.+)$/
          parse_if($1)
        when /^unless\s+(.+)$/
          parse_unless($1)
        when /^elsif\s+(.+)$/
          # Handled by parse_if
          nil
        when /^(\S+)\.each\s+do\s*\|([^|]+)\|$/
          parse_each($1, $2)
        when /^(\S+)\.map\s+do\s*\|([^|]+)\|$/
          parse_each($1, $2)
        when /^content_for\s+:(\w+),\s*["'](.+)["']$/
          # content_for :title, "Text" -> store for Layout prop
          @page_title = $2
          nil
        when /^content_for\s+:(\w+)$/
          # content_for block - skip for now
          parse_content(:end)
          @scanner.scan(/<%\s*end\s*-?%>/)
          nil
        when 'else', 'end', /^elsif/
          # These are handled by parent constructs
          nil
        when /^turbo_stream_from/
          # Deferred: real-time functionality
          "<!-- turbo_stream_from (deferred) -->"
        else
          # Unknown control - skip
          nil
        end
      end

      # Parse if/elsif/else/end
      def parse_if(condition)
        then_content = parse_content(:else_or_end)

        if @scanner.check(/<%\s*elsif\s+/)
          @scanner.scan(/<%\s*elsif\s+/)
          elsif_cond = scan_until_erb_close.strip
          elsif_content = parse_if(elsif_cond)
          "{(#{transform_condition(condition)}) ? (<>#{then_content}</>) : (#{elsif_content})}"
        elsif @scanner.scan(/<%\s*else\s*-?%>/)
          else_content = parse_content(:end)
          @scanner.scan(/<%\s*end\s*-?%>/)
          "{(#{transform_condition(condition)}) ? (<>#{then_content}</>) : (<>#{else_content}</>)}"
        else
          @scanner.scan(/<%\s*end\s*-?%>/)
          "{(#{transform_condition(condition)}) && (<>#{then_content}</>)}"
        end
      end

      # Parse unless/end
      def parse_unless(condition)
        content = parse_content(:end)
        @scanner.scan(/<%\s*end\s*-?%>/)
        "{!(#{transform_condition(condition)}) && (<>#{content}</>)}"
      end

      # Parse each/end
      def parse_each(collection, var)
        var = var.strip
        content = parse_content(:end)
        @scanner.scan(/<%\s*end\s*-?%>/)
        "{#{transform_ruby_expr(collection)}.map((#{var}) => (<>#{content}</>))}"
      end

      # Parse plain text
      def parse_text
        text = ''
        until @scanner.eos?
          break if @scanner.check(/<%/)
          char = @scanner.getch
          text += char if char
        end
        text
      end

      # Scan until %> and return content
      def scan_until_erb_close
        result = ''
        until @scanner.eos?
          if @scanner.scan(/-?%>/)
            return result.strip
          else
            char = @scanner.getch
            result += char if char
          end
        end
        result.strip
      end

      # Transform a Rails output expression to Astro
      def transform_output_expr(expr)
        expr = expr.strip

        # turbo_stream_from - deferred
        if expr =~ /^turbo_stream_from/
          return "<!-- turbo_stream_from (deferred) -->"
        end

        # Try to parse and use HelperPatterns
        ast = parse_ruby(expr)
        if ast
          # Try each helper pattern
          if result = @patterns.match_link_to(ast)
            return render_link_to(result)
          end

          if result = @patterns.match_button_to(ast)
            return render_button_to(result)
          end

          if result = @patterns.match_render(ast)
            return render_partial(result)
          end

          if result = @patterns.match_truncate(ast)
            @helpers_used << :truncate
            return render_truncate(result)
          end

          if result = @patterns.match_pluralize(ast)
            @helpers_used << :pluralize
            return render_pluralize(result)
          end

          if result = @patterns.match_dom_id(ast)
            @helpers_used << :dom_id
            return render_dom_id(result)
          end
        end

        # Fallback: regex-based transformations for expressions not handled by patterns

        # Path helpers: article_path(article), new_article_path, etc.
        if expr =~ /^(\w+)_path(\((.+)\))?$/
          return transform_path_helper($1, $3)
        end

        # Simple instance variable
        if expr =~ /^@(\w+)$/
          return "{#{$1}}"
        end

        # Method call on instance variable
        if expr =~ /^@(\w+)\.(.+)$/
          return "{#{$1}.#{transform_ruby_expr($2)}}"
        end

        # Default: wrap in braces
        "{#{transform_ruby_expr(expr)}}"
      end

      # --- Astro Renderers for Helper Patterns ---

      # Render link_to as Astro anchor tag
      def render_link_to(result)
        path_info = result[:path]
        href = render_path_info(path_info)

        attrs = ["href={#{href}}"]

        if result[:css_class]
          attrs << "class=\"#{result[:css_class]}\""
        end

        text = result[:text] || "{#{render_node(result[:text_node])}}"

        if result[:is_delete]
          # Delete link - render as form
          confirm = result[:confirm] || 'Are you sure?'
          <<~HTML.strip
            <form method="POST" action={#{href}} style="display: inline;">
            <input type="hidden" name="_action" value="delete" />
            <button type="submit" #{attrs[1..-1].join(' ')} onclick="return confirm('#{confirm}')">#{text}</button>
            </form>
          HTML
        else
          "<a #{attrs.join(' ')}>#{text}</a>"
        end
      end

      # Render button_to as Astro form with button
      def render_button_to(result)
        path_info = result[:path]
        href = render_path_info(path_info)

        form_parts = ["<form method=\"POST\" action={#{href}} style=\"display: inline;\">"]

        if result[:method] == :delete
          form_parts << '<input type="hidden" name="_action" value="delete" />'
        end

        button_attrs = ['type="submit"']
        button_attrs << "class=\"#{result[:css_class]}\"" if result[:css_class]
        if result[:confirm]
          button_attrs << "onclick=\"return confirm('#{result[:confirm]}')\""
        end

        form_parts << "<button #{button_attrs.join(' ')}>#{result[:text]}</button>"
        form_parts << '</form>'

        form_parts.join
      end

      # Render partial as Astro component
      def render_partial(result)
        partial_name = result[:partial_name]

        # Convert partial name to component name: "form" -> "Form", "article_card" -> "ArticleCard"
        component = partial_name.split('_').map(&:capitalize).join

        # Track partial for imports
        @partials_used << { name: "_#{partial_name}", component: component }

        # Build props from locals
        props = result[:locals].map do |key, value|
          if value == :loop_var
            "#{key}={#{key}}"
          else
            var_name = render_node(value)
            "#{key}={#{var_name}}"
          end
        end.join(' ')

        if result[:is_collection]
          # Collection rendering: {collection.map(item => <Component item={item} />)}
          collection_expr = render_node(result[:collection_node])
          singular = result[:partial_name]
          "{#{collection_expr}.map((#{singular}) => (<#{component} #{singular}={#{singular}} />))}"
        else
          "<#{component} #{props} />"
        end
      end

      # Render truncate helper call
      def render_truncate(result)
        text_expr = render_node(result[:text_node])
        "{truncate(#{text_expr}, { length: #{result[:length]} })}"
      end

      # Render pluralize helper call
      def render_pluralize(result)
        count_expr = render_node(result[:count_node])
        singular_expr = render_node(result[:singular_node])
        if result[:plural_node]
          plural_expr = render_node(result[:plural_node])
          "{pluralize(#{count_expr}, #{singular_expr}, #{plural_expr})}"
        else
          "{pluralize(#{count_expr}, #{singular_expr})}"
        end
      end

      # Render dom_id helper call
      def render_dom_id(result)
        record_expr = render_node(result[:record_node])
        if result[:prefix_node]
          prefix_expr = render_node(result[:prefix_node])
          "{dom_id(#{record_expr}, #{prefix_expr})}"
        else
          "{dom_id(#{record_expr})}"
        end
      end

      # Render path info to Astro expression
      def render_path_info(info)
        return '""' unless info

        case info[:type]
        when :static
          "\"#{info[:static_path]}\""
        when :model
          # article -> `/articles/${article.id}`
          model = info[:model]
          "`/#{model}s/${#{model}.id}`"
        when :helper
          helper = info[:helper]
          if helper =~ /^new_(\w+)_path$/
            model = $1
            "\"/#{model}s/new\""
          elsif helper =~ /^edit_(\w+)_path$/
            model = $1
            args = info[:args]
            if args && args.any?
              var = render_node(args.first)
              "`/#{model}s/${#{var}.id}/edit`"
            else
              "\"/#{model}s/edit\""
            end
          elsif helper =~ /^(\w+)_path$/
            model = $1
            args = info[:args]
            if args && args.any?
              var = render_node(args.first)
              if model.end_with?('s')
                "\"/#{model}\""
              else
                "`/#{model}s/${#{var}.id}`"
              end
            else
              "\"/#{model}\""
            end
          else
            "\"#{helper}\""
          end
        when :nested
          # [@article, comment] -> `/articles/${article.id}/comments/${comment.id}`
          parent = info[:parent]
          child = info[:child]
          "`/#{parent}s/${#{parent}.id}/#{child}s/${#{child}.id}`"
        when :expression
          render_node(info[:node])
        else
          '""'
        end
      end

      # Render AST node to JavaScript expression string
      def render_node(node)
        return 'null' unless node

        case node.type
        when :str
          "\"#{node.children[0]}\""
        when :sym
          "\"#{node.children[0]}\""
        when :int, :float
          node.children[0].to_s
        when :true
          'true'
        when :false
          'false'
        when :nil
          'null'
        when :lvar
          node.children[0].to_s
        when :ivar
          # @article -> article
          node.children[0].to_s.sub(/^@/, '')
        when :send
          target, method, *args = node.children
          if target.nil?
            # Method call without receiver
            args_str = args.map { |a| render_node(a) }.join(', ')
            args.empty? ? method.to_s : "#{method}(#{args_str})"
          else
            # Method call with receiver
            target_str = render_node(target)
            args_str = args.map { |a| render_node(a) }.join(', ')
            if args.empty?
              "#{target_str}.#{method}"
            else
              "#{target_str}.#{method}(#{args_str})"
            end
          end
        when :const
          # Constant like Article
          if node.children[0]
            "#{render_node(node.children[0])}.#{node.children[1]}"
          else
            node.children[1].to_s
          end
        else
          # Fallback
          'null'
        end
      end

      # --- Fallback transformations (for expressions not handled by patterns) ---

      # Transform path helper expression
      def transform_path_helper(name, args)
        if args
          path = "#{name}_path(#{args})"
        else
          path = "#{name}_path"
        end
        "{#{transform_path_string(path)}}"
      end

      # Transform path string to Astro expression
      def transform_path_string(path)
        path = path.strip.gsub(/^["']|["']$/, '')

        # new_article_path -> "/articles/new"
        if path =~ /^new_(\w+)_path$/
          model = $1
          return "\"/#{model.gsub('_', '-')}s/new\""
        end

        # edit_article_path(article) -> `/articles/${article.id}/edit`
        if path =~ /^edit_(\w+)_path\((.+)\)$/
          model = $1
          var = $2.strip.gsub(/^@/, '')
          return "`/#{model.gsub('_', '-')}s/${#{var}.id}/edit`"
        end

        # article_path(article) -> `/articles/${article.id}`
        if path =~ /^(\w+)_path\((.+)\)$/
          model = $1
          var = $2.strip.gsub(/^@/, '')
          if model.end_with?('s')
            return "\"/#{model.gsub('_', '-')}\""
          end
          return "`/#{model.gsub('_', '-')}s/${#{var}.id}`"
        end

        # articles_path -> "/articles"
        if path =~ /^(\w+)_path$/
          model = $1
          return "\"/#{model.gsub('_', '-')}\""
        end

        "\"#{path}\""
      end

      # Transform Ruby condition to JavaScript
      def transform_condition(cond)
        cond = cond.strip

        # .present? -> truthy check
        cond = cond.gsub(/\.present\?/, '')

        # .any? -> .length > 0
        cond = cond.gsub(/\.any\?/, '.length > 0')

        # .empty? -> .length === 0
        cond = cond.gsub(/\.empty\?/, '.length === 0')

        # .nil? -> == null
        cond = cond.gsub(/\.nil\?/, ' == null')

        # Remove @ from instance variables
        cond = cond.gsub(/@(\w+)/, '\1')

        cond
      end

      # Transform Ruby expression to JavaScript
      def transform_ruby_expr(expr)
        expr = expr.strip

        # Remove @ from instance variables
        expr = expr.gsub(/@(\w+)/, '\1')

        # .includes(:assoc) -> .includes('assoc')
        expr = expr.gsub(/\.includes\(:(\w+)\)/, ".includes('\\1')")

        # .all -> .order({ created_at: "desc" }).toArray() (for Dexie compatibility)
        expr = expr.gsub(/\.all\b(?!\()/, '.order({ created_at: "desc" }).toArray()')

        # Symbol to string
        expr = expr.gsub(/:(\w+)(?!\()/, "'\\1'")

        # .size -> .length
        expr = expr.gsub(/\.size/, '.length')

        # .to_s -> toString()
        expr = expr.gsub(/\.to_s/, '.toString()')

        expr
      end

      # Build the complete .astro file
      def build_astro_file(template)
        lines = ['---']

        # Standard imports
        lines << "import Layout from '#{layout_path}';"

        # Component imports for partials
        @partials_used.uniq { |p| p[:component] }.each do |partial|
          lines << "import #{partial[:component]} from '#{component_path(partial[:component])}';"
        end

        # Database and model imports
        lines << "import { setupDatabase } from '#{db_path}';"
        lines << "import { #{model_imports} } from '#{models_path}';"

        # Helper imports
        unless @helpers_used.empty?
          helpers = @helpers_used.to_a.join(', ')
          lines << "import { #{helpers} } from 'ruby2js-rails/targets/browser/rails.js';"
        end

        lines << ''
        lines << '// Initialize database'
        lines << 'await setupDatabase();'
        lines << ''

        # Flash message support
        lines << '// Flash message (from query param)'
        lines << "const notice = Astro.url.searchParams.get('notice');"
        lines << ''

        # Add controller action code
        @frontmatter_lines.each do |line|
          lines << line
        end

        lines << '---'
        lines << ''

        # Determine title
        title = @page_title || "#{@action_name&.capitalize} - #{@controller&.capitalize}"

        # Wrap in Layout
        lines << "<Layout title=\"#{title}\">"
        lines << template
        lines << '</Layout>'

        lines.join("\n")
      end

      # Path helpers for imports
      def layout_path
        case @action_name
        when 'edit'
          '../../../layouts/Layout.astro'
        else
          '../../layouts/Layout.astro'
        end
      end

      def component_path(component)
        case @action_name
        when 'edit'
          "../../../components/#{component}.astro"
        else
          "../../components/#{component}.astro"
        end
      end

      def db_path
        case @action_name
        when 'edit'
          '../../../lib/db.mjs'
        else
          '../../lib/db.mjs'
        end
      end

      def models_path
        case @action_name
        when 'edit'
          '../../../lib/models/index.js'
        else
          '../../lib/models/index.js'
        end
      end

      def model_imports
        # Infer from controller name
        if @controller
          singular = @controller.chomp('s')
          [singular.capitalize, 'Comment'].join(', ')
        else
          'Article, Comment'
        end
      end
    end
  end
end
