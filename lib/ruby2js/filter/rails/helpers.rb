require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Helpers
        include SEXP
        # Note: This filter overrides Erb's hook methods (process_erb_block_append,
        # process_erb_block_helper). In the filter list, Rails::Helpers must come
        # BEFORE Erb so the overrides take precedence in Ruby2JS's filter chain.

        # Browser databases - these run in browser with History API navigation
        BROWSER_DATABASES = %w[dexie indexeddb sqljs sql.js pglite].freeze

        def initialize(*args)
          super
          @erb_block_var = nil   # Track current block variable (e.g., 'f' in form_for)
          @erb_model_name = nil  # Track model name for form_for (e.g., 'user')
          @erb_path_helpers = [] # Track path helper usage for imports
          @erb_view_helpers = [] # Track view helper usage (truncate, etc.) for imports
          @erb_partials = []     # Track partial usage for imports
          @erb_view_modules = [] # Track view module imports (PhotoViews, etc.)
        end

        # Check if layout mode is enabled (options are set after initialize)
        def erb_layout_mode?
          @options && @options[:layout]
        end

        # Handle yield in layout context
        # <%= yield %> -> content (the main content parameter)
        # <%= yield :head %> -> context.contentFor.head || ''
        def on_yield(node)
          return super unless erb_layout_mode?()

          args = node.children

          if args.empty?
            # yield -> content (the content parameter passed to layout function)
            s(:lvar, :content)
          else
            # yield :head -> context.contentFor.head || ''
            section = args.first
            if section.type == :sym
              section_name = section.children.first
              s(:or,
                s(:attr, s(:attr, s(:lvar, :context), :contentFor), section_name),
                s(:str, ''))
            else
              super
            end
          end
        end

        # Add imports for path helpers and view helpers
        # Called by Erb filter's on_begin via erb_prepend_imports hook
        def erb_prepend_imports
          # Add import for path helpers if any were used
          # Use @config alias (resolves to .juntos/config in Vite)
          unless @erb_path_helpers.empty?
            helpers = @erb_path_helpers.uniq.sort.map { |name| s(:const, nil, name) }
            self.prepend_list << s(:import, '@config/paths.js', helpers)
          end

          # Add import for view helpers (truncate, etc.) from rails.js
          # Use lib alias (resolves to .juntos/lib in Vite)
          unless @erb_view_helpers.empty?
            helpers = @erb_view_helpers.uniq.sort.map { |name| s(:const, nil, name) }
            self.prepend_list << s(:import, 'lib/rails.js', helpers)
          end

          # Add imports for partials
          # render "form" -> import * as _form_module from './_form.js'
          # render @article.comments -> import * as _comment_module from '../comments/_comment.js'
          # Then call _form_module.render({article})
          unless @erb_partials.empty?
            @erb_partials.uniq { |p| [p[:name], p[:directory]] }.sort_by { |p| p[:name] }.each do |partial_info|
              partial_name = partial_info[:name]
              partial_directory = partial_info[:directory]
              module_name = "_#{partial_name}_module".to_sym

              # Generate import path based on whether partial is in a different directory
              import_path = if partial_directory
                # Cross-directory partial: ../comments/_comment.js
                "../#{partial_directory}/_#{partial_name}.js"
              else
                # Same directory partial: ./_form.js
                "./_#{partial_name}.js"
              end

              # Path array format: [as_pair, from_pair] for "import * as X from Y"
              self.prepend_list << s(:import,
                [s(:pair, s(:sym, :as), s(:const, nil, module_name)),
                 s(:pair, s(:sym, :from), s(:str, import_path))],
                s(:str, '*'))
            end
          end

          # Add imports for view modules (PhotoViews, etc.)
          # These are used for turbo_stream shorthand: turbo_stream.prepend "photos", @photo
          # Import path: ../photos.js (from photos/ subdirectory)
          unless @erb_view_modules.empty?
            @erb_view_modules.uniq.each do |view_info|
              module_name = view_info[:module]
              resource = view_info[:resource]
              # Import from parent directory: ../photos.js
              self.prepend_list << s(:import, "../#{resource}.js",
                [s(:const, nil, module_name.to_sym)])
            end
          end
        end

        # Override Erb filter's hook to add $context as keyword arg
        # Views need $context for flash, contentFor, params, etc.
        # Using $ prefix to avoid conflicts with @context instance variables
        # Now returns kwarg for unified signature: render({ $context, articles })
        # In layout mode, context comes as positional arg so no extra kwargs needed
        def erb_render_extra_args
          return [] if erb_layout_mode?()
          [s(:kwarg, :"$context")]
        end

        # Helper to get the context reference for layout vs view mode
        # Layout mode: context (positional arg)
        # View mode: $context (kwarg)
        def context_ref
          if erb_layout_mode?()
            s(:lvar, :context)
          else
            s(:lvar, :"$context")
          end
        end

        # Helper to get global context reference (used in form helpers)
        # Layout mode: context (from scope)
        # View mode: $context (global)
        def context_gvar
          if erb_layout_mode?()
            s(:lvar, :context)
          else
            s(:gvar, :$context)
          end
        end

        def on_send(node)
          target, method, *args = node.children

          # Handle form builder methods: f.text_field :name, f.submit, etc.
          if @erb_block_var && target&.type == :lvar &&
             target.children.first == @erb_block_var
            return process_form_builder_method(method, args)
          end

          # Handle link_to helper
          if method == :link_to && target.nil? && args.length >= 2
            return process_link_to(args)
          end

          # Handle truncate helper
          if method == :truncate && target.nil? && args.length >= 1
            return process_truncate(args)
          end

          # Handle pluralize helper
          if method == :pluralize && target.nil? && args.length >= 2
            return process_pluralize(args)
          end

          # Handle dom_id helper
          if method == :dom_id && target.nil? && args.length >= 1
            return process_dom_id(args)
          end

          # Handle button_to helper
          if method == :button_to && target.nil? && args.length >= 2
            return process_button_to(args)
          end

          # Handle notice helper (flash message)
          if method == :notice && target.nil? && args.empty?
            return process_notice
          end

          # Handle content_for helper
          if method == :content_for && target.nil?
            return process_content_for(args)
          end

          # Handle csrf_meta_tags - returns the CSRF meta tag from server context
          # In layout mode, context is a positional arg; in view mode, $csrfMetaTag is passed globally
          if method == :csrf_meta_tags && target.nil?
            if erb_layout_mode?()
              # Layout mode: build meta tag from context.authenticityToken
              return s(:or,
                s(:dstr,
                  s(:str, '<meta name="csrf-token" content="'),
                  s(:begin, s(:or, s(:attr, s(:lvar, :context), :authenticityToken), s(:str, ''))),
                  s(:str, '">')),
                s(:str, ''))
            else
              return s(:or, s(:gvar, :$csrfMetaTag), s(:str, ''))
            end
          end

          # Handle csp_meta_tag - stub for demo (returns empty string)
          if method == :csp_meta_tag && target.nil?
            return s(:str, '')
          end

          # Handle stylesheet_link_tag - stub for demo
          if method == :stylesheet_link_tag && target.nil?
            return s(:str, '')
          end

          # Handle javascript_importmap_tags - stub for demo
          if method == :javascript_importmap_tags && target.nil?
            return s(:str, '')
          end

          # Handle render partial calls
          if method == :render && target.nil? && args.any?
            result = process_render_partial(args)
            return result if result
          end

          # Track path helper usage for imports (e.g., article_path, new_article_path)
          if target.nil? && method.to_s.end_with?('_path') && @erb_bufvar
            @erb_path_helpers << method unless @erb_path_helpers.include?(method)
          end

          # Handle turbo_stream_from helper - subscribes to broadcast channel
          # turbo_stream_from "chat_room" -> TurboBroadcast.subscribe("chat_room")
          if target.nil? && method == :turbo_stream_from && args.length >= 1
            return process_turbo_stream_from(args)
          end

          # Handle association.size/count/length patterns in ERB
          # Maps to Rails semantics:
          #   .size   -> await proxy.size()    (smart: cached or COUNT query)
          #   .count  -> await proxy.count()   (always COUNT query)
          #   .length -> (await proxy).length  (load all, array length)
          if @erb_bufvar && [:size, :count, :length].include?(method) && association_access?(target)
            self.erb_mark_async!()
            if method == :length
              # Load records first, then access array's .length property
              return s(:attr,
                s(:begin, s(:send, nil, :await, process(target))),
                :length)
            else
              # size/count are method calls on the proxy
              return s(:send, nil, :await,
                s(:send, process(target), method))
            end
          end

          super
        end

        # Override Erb's hook to handle send expressions that produce buffer operations
        # Handles turbo_stream.prepend/append/replace shortcuts without blocks
        def process_erb_send_append(send_node)
          target, method, *args = send_node.children

          # Handle turbo_stream.prepend/append/replace/etc shorthand form (without block)
          # turbo_stream.prepend "photos", @photo -> turbo-stream HTML with rendered partial
          # Note: Use element-by-element comparison for JS compatibility (array == doesn't work in JS)
          if target&.type == :send && target.children[0].nil? && target.children[1] == :turbo_stream
            turbo_actions = [:prepend, :append, :replace, :update, :remove, :before, :after]
            if turbo_actions.include?(method) && args.length >= 1
              return process_turbo_stream_shorthand(method, args)
            end
          end

          nil  # Not handled
        end

        # Override Erb's hook to handle Rails block helpers (form_for, form_tag, etc.)
        def process_erb_block_append(block_node)
          block_send = block_node.children[0]
          block_args = block_node.children[1]
          block_body = block_node.children[2]

          if block_send&.type == :send
            receiver = block_send.children[0]
            helper_name = block_send.children[1]

            # Handle turbo_stream.replace, turbo_stream.append, etc.
            # turbo_stream can be either a local variable (lvar) or a method call (send nil :turbo_stream)
            is_turbo_stream = (receiver&.type == :lvar && receiver.children[0] == :turbo_stream) ||
                              (receiver&.type == :send && receiver.children[0].nil? && receiver.children[1] == :turbo_stream)
            if is_turbo_stream
              action = helper_name.to_s  # :replace, :append, :prepend, :remove, :update
              target_arg = block_send.children[2]
              return process_turbo_stream_action(action, target_arg, block_body)
            end

            if helper_name == :form_for
              return process_form_for(block_send, block_args, block_body)
            elsif helper_name == :form_with
              return process_form_with(block_send, block_args, block_body)
            elsif helper_name == :form_tag
              return process_form_tag(block_send, block_args, block_body)
            else
              return process_block_helper(helper_name, block_send, block_args, block_body)
            end
          end

          nil  # Not handled, let Erb filter handle it
        end

        # Handle block helpers via on_block
        def process_erb_block_helper(helper_call, block_args, block_body)
          helper_name = helper_call.children[1]

          if helper_name == :form_for
            return process_form_for(helper_call, block_args, block_body)
          elsif helper_name == :form_with
            return process_form_with(helper_call, block_args, block_body)
          elsif helper_name == :form_tag
            return process_form_tag(helper_call, block_args, block_body)
          end

          # Generic block helper
          process_block_helper(helper_name, helper_call, block_args, block_body)
        end

        # Process link_to helper into anchor tag (Turbo handles navigation)
        def process_link_to(args)
          text_node = args[0]
          path_node = args[1]
          options = args[2] if args.length > 2

          # Extract options from hash
          is_delete = false
          confirm_msg = nil
          css_class = nil
          class_node = nil

          if options&.type == :hash
            options.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :method
                  is_delete = (value.type == :sym && value.children[0] == :delete)
                when :class
                  css_class = extract_class_value(value)
                  class_node = value
                when :data
                  # Look for confirm/turbo_confirm in data hash
                  if value.type == :hash
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym &&
                         [:confirm, :turbo_confirm].include?(data_key.children[0])
                        confirm_msg = data_value if data_value.type == :str
                      end
                    end
                  end
                end
              end
            end
          end

          # Build the HTML
          if is_delete
            build_delete_link(text_node, path_node, confirm_msg, css_class)
          else
            build_nav_link(text_node, path_node, css_class, class_node)
          end
        end

        # Extract class value from various formats:
        # - String: "foo bar"
        # - Array: ["foo", "bar", {"baz": condition}]
        # Returns a string for static classes (for backward compatibility)
        def extract_class_value(node)
          result = extract_class_with_conditions(node)
          return nil unless result

          # If no conditionals, return simple string
          if result[:conditionals].empty?
            result[:static].join(' ')
          else
            # Has conditionals - still return static string for simple uses
            # (callers that need dynamic should use extract_class_with_conditions)
            result[:static].join(' ')
          end
        end

        # Extract class value with full conditional support
        # Returns { static: ["class1", "class2"], conditionals: [{class: "name", condition: ast_node}] }
        def extract_class_with_conditions(node)
          return nil unless node

          case node.type
          when :str
            { static: [node.children[0]], conditionals: [] }
          when :array
            static_classes = []
            conditionals = []

            node.children.each do |child|
              if child.type == :str
                static_classes << child.children[0]
              elsif child.type == :hash
                # Conditional classes like {"border-red": errors.any?}
                child.children.each do |pair|
                  key = pair.children[0]
                  condition = pair.children[1]

                  class_name = if key.type == :str
                                 key.children[0]
                               elsif key.type == :sym
                                 key.children[0].to_s
                               end

                  if class_name
                    conditionals << { class: class_name, condition: condition }
                  end
                end
              end
            end

            { static: static_classes, conditionals: conditionals }
          else
            nil
          end
        end

        # Build class attribute - static string or dynamic template literal
        # For use in contexts that support dynamic output (template literals)
        def build_dynamic_class_attr(node)
          return ["", nil] unless node

          result = extract_class_with_conditions(node)
          return ["", nil] unless result

          if result[:conditionals].empty?
            # Static only - return simple class attribute
            class_str = result[:static].join(' ')
            return [" class=\"#{class_str}\"", nil] if class_str.length > 0
            return ["", nil]
          end

          # Has conditionals - need to generate dynamic class
          static_part = result[:static].join(' ')

          # Build AST for conditional class expression
          # Result: `${static} ${cond1 ? 'class1' : ''} ${cond2 ? 'class2' : ''}`
          conditional_exprs = result[:conditionals].map do |cond|
            # (condition ? ' class-name' : '')
            s(:if, cond[:condition],
              s(:str, " #{cond[:class]}"),
              s(:str, ''))
          end

          # Combine into a single expression
          if conditional_exprs.length == 1
            combined = conditional_exprs.first
          else
            # Join multiple conditionals with +
            combined = conditional_exprs.reduce do |acc, expr|
              s(:send, acc, :+, expr)
            end
          end

          # Build: "static" + conditionals
          if static_part.length > 0
            full_expr = s(:send, s(:str, static_part), :+, combined)
          else
            full_expr = combined
          end

          # Return template for embedding: class="${...}"
          [nil, full_expr]
        end

        # Build a navigation link
        def build_nav_link(text_node, path_node, css_class = nil, class_node = nil)
          # Handle model object as path: link_to "Show", @article or link_to "Show", article
          if path_node.type == :ivar
            # Instance variable: @article -> article_path(article)
            model_name = path_node.children.first.to_s.sub(/^@/, '')
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            path_expr = s(:send, nil, path_helper, s(:lvar, model_name.to_sym))
          elsif path_node.type == :lvar
            # Local variable: article -> article_path(article)
            model_name = path_node.children.first.to_s
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            path_expr = s(:send, nil, path_helper, path_node)
          elsif path_node.type == :send && path_node.children[0].nil? && path_node.children.length == 2
            # Bare method call (parser treats partial locals as method calls): article -> article_path(article)
            method_name = path_node.children[1].to_s
            if method_name.end_with?('_path', '_url')
              # Already a path/url helper (e.g., articles_path) - use as-is
              path_helper = method_name.to_sym
              @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
              path_expr = s(:send, nil, path_helper)
            else
              # Model name - convert to path helper: article -> article_path(article)
              path_helper = "#{method_name}_path".to_sym
              @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
              path_expr = s(:send, nil, path_helper, s(:lvar, method_name.to_sym))
            end
          elsif path_node.type == :array && path_node.children.length == 2
            # Nested resource: [@article, comment] -> comment_path(article, comment)
            parent, child = path_node.children
            child_name = child.type == :ivar ? child.children.first.to_s.sub(/^@/, '') : child.children.first.to_s
            path_helper = "#{child_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            parent_arg = parent.type == :ivar ? s(:lvar, parent.children.first.to_s.sub(/^@/, '').to_sym) : parent
            child_arg = child.type == :ivar ? s(:lvar, child.children.first.to_s.sub(/^@/, '').to_sym) : child
            path_expr = s(:send, nil, path_helper, parent_arg, child_arg)
          else
            path_expr = process(path_node)

            # Ensure path helpers without arguments are called as functions
            if path_node.type == :send && path_node.children[0].nil? && path_node.children.length == 2
              path_expr = s(:send, nil, path_node.children[1])
            end
          end

          # Check for conditional classes
          has_conditionals = false
          if class_node
            result = extract_class_with_conditions(class_node)
            has_conditionals = result && result[:conditionals].any?
          end

          if has_conditionals
            # Dynamic class with conditionals - generate runtime expression
            return build_nav_link_with_dynamic_class(text_node, path_node, path_expr, class_node)
          end

          # Build static class attribute string - Rails puts class before href
          class_attr = css_class ? "class=\"#{css_class}\" " : ""

          # Generate standard href links - Turbo Drive intercepts clicks automatically
          # Match Rails attribute order: class before href
          if text_node.type == :str && path_node.type == :str
            text_str = text_node.children[0]
            path_str = path_node.children[0]
            s(:str, "<a #{class_attr}href=\"#{path_str}\">#{text_str}</a>")
          elsif text_node.type == :str
            text_str = text_node.children[0]
            s(:dstr,
              s(:str, "<a #{class_attr}href=\""),
              s(:begin, path_expr),
              s(:str, "\">#{text_str}</a>"))
          else
            text_expr = process(text_node)
            s(:dstr,
              s(:str, "<a #{class_attr}href=\""),
              s(:begin, path_expr),
              s(:str, "\">"),
              s(:begin, text_expr),
              s(:str, '</a>'))
          end
        end

        # Build a navigation link with dynamic/conditional class attribute
        def build_nav_link_with_dynamic_class(text_node, path_node, path_expr, class_node)
          result = extract_class_with_conditions(class_node)
          static_part = result[:static].join(' ')

          # Build conditional expressions: condition ? ' class-name' : ''
          conditional_exprs = result[:conditionals].map do |cond|
            s(:if, cond[:condition],
              s(:str, " #{cond[:class]}"),
              s(:str, ''))
          end

          # Combine conditionals
          if conditional_exprs.length == 1
            combined = conditional_exprs.first
          else
            combined = conditional_exprs.reduce do |acc, expr|
              s(:send, acc, :+, expr)
            end
          end

          # Build full class expression: "static" + conditionals
          if static_part.length > 0
            class_expr = s(:send, s(:str, static_part), :+, combined)
          else
            class_expr = combined
          end

          text_str = text_node.type == :str ? text_node.children[0] : nil
          text_expr = text_str ? nil : process(text_node)

          # Generate standard href links - Turbo Drive intercepts clicks automatically
          # Match Rails attribute order: class before href
          if text_str && path_node.type == :str
            path_str = path_node.children[0]
            s(:dstr,
              s(:str, '<a class="'),
              s(:begin, class_expr),
              s(:str, "\" href=\"#{path_str}\">#{text_str}</a>"))
          elsif text_str
            s(:dstr,
              s(:str, '<a class="'),
              s(:begin, class_expr),
              s(:str, '" href="'),
              s(:begin, path_expr),
              s(:str, "\">#{text_str}</a>"))
          else
            s(:dstr,
              s(:str, '<a class="'),
              s(:begin, class_expr),
              s(:str, '" href="'),
              s(:begin, path_expr),
              s(:str, '">'),
              s(:begin, text_expr),
              s(:str, '</a>'))
          end
        end

        # Build a delete link with confirmation using Turbo data attributes
        # Turbo intercepts the link click and sends DELETE request automatically
        def build_delete_link(text_node, path_node, confirm_msg, css_class = nil)
          # Handle model object as path: link_to "Delete", @article, method: :delete
          if path_node.type == :ivar
            # Instance variable: @article -> article_path(article)
            model_name = path_node.children.first.to_s.sub(/^@/, '')
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            path_expr = s(:send, nil, path_helper, s(:lvar, model_name.to_sym))
          elsif path_node.type == :lvar
            # Local variable: article -> article_path(article)
            model_name = path_node.children.first.to_s
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            path_expr = s(:send, nil, path_helper, path_node)
          elsif path_node.type == :array && path_node.children.length == 2
            # Nested resource: [@article, comment] -> comment_path(article, comment)
            parent, child = path_node.children
            child_name = child.type == :ivar ? child.children.first.to_s.sub(/^@/, '') : child.children.first.to_s
            path_helper = "#{child_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            parent_arg = parent.type == :ivar ? s(:lvar, parent.children.first.to_s.sub(/^@/, '').to_sym) : parent
            child_arg = child.type == :ivar ? s(:lvar, child.children.first.to_s.sub(/^@/, '').to_sym) : child
            path_expr = s(:send, nil, path_helper, parent_arg, child_arg)
          else
            path_expr = process(path_node)
          end
          confirm_str = confirm_msg ? confirm_msg.children[0] : 'Are you sure?'

          # Build class attribute - Rails puts class before href
          class_attr = css_class ? "class=\"#{css_class}\" " : ""

          # Build Turbo data attributes for delete method and confirmation
          turbo_attrs = " data-turbo-method=\"delete\" data-turbo-confirm=\"#{confirm_str}\""

          text_str = text_node.type == :str ? text_node.children[0] : nil

          # Generate link with Turbo data attributes - Turbo handles the DELETE request
          # Match Rails attribute order: class before href
          if text_str && path_node.type == :str
            path_str = path_node.children[0]
            s(:str, "<a #{class_attr}href=\"#{path_str}\"#{turbo_attrs}>#{text_str}</a>")
          elsif text_str
            s(:dstr,
              s(:str, "<a #{class_attr}href=\""),
              s(:begin, path_expr),
              s(:str, "\"#{turbo_attrs}>#{text_str}</a>"))
          else
            text_expr = process(text_node)
            s(:dstr,
              s(:str, "<a #{class_attr}href=\""),
              s(:begin, path_expr),
              s(:str, "\"#{turbo_attrs}>"),
              s(:begin, text_expr),
              s(:str, '</a>'))
          end
        end

        # Process button_to helper
        # button_to "Destroy", @article, method: :delete, class: "btn", form_class: "inline"
        def process_button_to(args)
          text_node = args[0]
          path_node = args[1]
          options = args[2] if args.length > 2

          # Extract options
          http_method = :post
          confirm_msg = nil
          css_class = nil
          form_class = nil

          if options&.type == :hash
            options.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :method
                  http_method = value.children[0] if value.type == :sym
                when :class
                  css_class = extract_class_value(value)
                when :form_class
                  form_class = extract_class_value(value)
                when :data
                  if value.type == :hash
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym &&
                         [:confirm, :turbo_confirm].include?(data_key.children[0])
                        confirm_msg = data_value if data_value.type == :str
                      end
                    end
                  end
                end
              end
            end
          end

          text_str = text_node.type == :str ? text_node.children[0] : 'Submit'
          confirm_str = confirm_msg ? confirm_msg.children[0] : 'Are you sure?'

          if http_method == :delete
            build_delete_button(text_str, path_node, confirm_str, css_class, form_class)
          else
            build_form_button(text_str, path_node, http_method, css_class, form_class)
          end
        end

        # Build a delete button using Turbo-compatible form
        # Turbo intercepts the form submission and handles the DELETE request
        def build_delete_button(text_str, path_node, confirm_str, css_class = nil, form_class = nil)
          # Build class attributes - Rails uses "button_to" as default form class
          btn_class_attr = css_class ? " class=\"#{css_class}\"" : ""
          form_class_attr = " class=\"#{form_class || 'button_to'}\""

          # Convert model object to path helper call
          if path_node&.type == :lvar
            model_name = path_node.children.first.to_s
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            path_expr = s(:send, nil, path_helper, path_node)
          elsif path_node&.type == :ivar
            model_name = path_node.children.first.to_s.sub(/^@/, '')
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            # In ERB context, ivars are passed as locals
            path_expr = s(:send, nil, path_helper, s(:lvar, model_name.to_sym))
          elsif path_node&.type == :send && path_node.children[0].nil? && path_node.children.length == 2
            # Bare method call (parser treats partial locals as method calls): article -> article_path(article)
            method_name = path_node.children[1].to_s
            if method_name.end_with?('_path', '_url')
              # Already a path/url helper (e.g., articles_path) - use as-is
              path_helper = method_name.to_sym
              @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
              path_expr = s(:send, nil, path_helper)
            else
              # Model name - convert to path helper: article -> article_path(article)
              path_helper = "#{method_name}_path".to_sym
              @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
              path_expr = s(:send, nil, path_helper, s(:lvar, method_name.to_sym))
            end
          elsif path_node&.type == :array && path_node.children.length == 2
            # Nested resource: [@article, comment] -> comment_path(article, comment)
            # or [comment.article, comment] -> comment_path(comment.article_id, comment)
            parent, child = path_node.children
            # Extract child name from different node types
            child_name = case child.type
              when :ivar then child.children.first.to_s.sub(/^@/, '')
              when :lvar then child.children.first.to_s
              when :send then child.children[1].to_s  # send node: [receiver, method_name, ...]
              else child.children.first.to_s
            end
            path_helper = "#{child_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            # Convert ivars to lvars for ERB context
            # For association access like comment.article, use comment.article_id instead
            # (associations return Promises, but _id is a sync attribute)
            if parent.type == :send && parent.children[0] && parent.children[1]
              # Pattern: receiver.association -> receiver.association_id
              receiver = parent.children[0]
              assoc_name = parent.children[1]
              parent_arg = s(:attr, process(receiver), "#{assoc_name}_id".to_sym)
            elsif parent.type == :ivar
              parent_arg = s(:lvar, parent.children.first.to_s.sub(/^@/, '').to_sym)
            else
              parent_arg = process(parent)
            end
            child_arg = child.type == :ivar ? s(:lvar, child.children.first.to_s.sub(/^@/, '').to_sym) : process(child)
            path_expr = s(:send, nil, path_helper, parent_arg, child_arg)
          else
            path_expr = process(path_node)
          end

          # Use data-turbo-confirm on the button (Rails puts it there, not on the form)
          turbo_confirm = " data-turbo-confirm=\"#{confirm_str}\""

          # Generate form with action and method - Turbo handles the submission
          # Include authenticity_token for CSRF protection
          # Rails order: form, _method input, button, authenticity_token input
          s(:dstr,
            s(:str, "<form#{form_class_attr} method=\"post\" action=\""),
            s(:begin, path_expr),
            s(:str, "\"><input type=\"hidden\" name=\"_method\" value=\"delete\"><button#{btn_class_attr}#{turbo_confirm} type=\"submit\">#{text_str}</button><input type=\"hidden\" name=\"authenticity_token\" value=\""),
            s(:begin, s(:or, s(:attr, context_gvar, :authenticityToken), s(:str, ''))),
            s(:str, "\"></form>"))
        end

        # Build a regular form button
        def build_form_button(text_str, path_node, http_method, css_class = nil, form_class = nil)
          path_expr = process(path_node)

          # Build class attributes - Rails uses "button_to" as default form class
          btn_class_attr = css_class ? " class=\"#{css_class}\"" : ""
          form_class_attr = " class=\"#{form_class || 'button_to'}\""

          # Include authenticity_token for CSRF protection
          # Rails order: form, button, authenticity_token input
          s(:dstr,
            s(:str, "<form#{form_class_attr} method=\""),
            s(:str, http_method.to_s),
            s(:str, "\" action=\""),
            s(:begin, path_expr),
            s(:str, "\"><button#{btn_class_attr} type=\"submit\">#{text_str}</button><input type=\"hidden\" name=\"authenticity_token\" value=\""),
            s(:begin, s(:or, s(:attr, context_gvar, :authenticityToken), s(:str, ''))),
            s(:str, "\"></form>"))
        end

        # Process truncate helper
        def process_truncate(args)
          @erb_view_helpers << :truncate unless @erb_view_helpers.include?(:truncate)

          text_node = args[0]
          options_node = args[1]
          text_expr = process(text_node)

          length = 30  # default
          if options_node&.type == :hash
            options_node.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym && key.children[0] == :length && value.type == :int
                length = value.children[0]
              end
            end
          end

          s(:send, nil, :truncate, text_expr, s(:hash, s(:pair, s(:sym, :length), s(:int, length))))
        end

        # Process pluralize helper
        # pluralize(count, singular) -> pluralize(count, singular)
        # pluralize(count, singular, plural) -> pluralize(count, singular, plural)
        def process_pluralize(args)
          @erb_view_helpers << :pluralize unless @erb_view_helpers.include?(:pluralize)

          count_node = process(args[0])
          singular_node = process(args[1])

          if args.length >= 3
            plural_node = process(args[2])
            s(:send, nil, :pluralize, count_node, singular_node, plural_node)
          else
            s(:send, nil, :pluralize, count_node, singular_node)
          end
        end

        # Process turbo_stream_from helper - subscribes to broadcast channel
        # For browser targets: TurboBroadcast.subscribe("chat_room") || ""
        # For server targets: inline <script> with WebSocket subscription
        def process_turbo_stream_from(args)
          channel_node = process(args[0])

          if browser_target?()
            # Browser: Use BroadcastChannel API via TurboBroadcast
            @erb_view_helpers << :TurboBroadcast unless @erb_view_helpers.include?(:TurboBroadcast)

            # subscribe returns the channel object, so use || "" to return empty string
            s(:or,
              s(:send, s(:const, nil, :TurboBroadcast), :subscribe, channel_node),
              s(:str, ''))
          else
            # Server targets: Generate inline WebSocket subscription script
            # This script runs in the browser after SSR, connecting to the server's WebSocket
            build_turbo_stream_websocket_script(channel_node)
          end
        end

        # Build <turbo-cable-stream-source> element for server-side rendering
        # This element is picked up by @hotwired/turbo-rails JavaScript which
        # subscribes to the channel via Action Cable WebSocket
        # Format: <turbo-cable-stream-source channel="Turbo::StreamsChannel" signed-stream-name="...">
        # The signed-stream-name is base64-encoded JSON of the stream name (no signature needed for our server)
        def build_turbo_stream_websocket_script(channel_node)
          @erb_view_helpers << :turbo_stream_from unless @erb_view_helpers.include?(:turbo_stream_from)

          # Call the turbo_stream_from helper function which returns the HTML element
          s(:send, nil, :turbo_stream_from, channel_node)
        end

        # Process turbo_stream.replace, turbo_stream.append, etc.
        # turbo_stream.replace "target" do ... end
        # -> <turbo-stream action="replace" target="..."><template>...</template></turbo-stream>
        def process_turbo_stream_action(action, target_arg, block_body)
          # Get target as string
          target_str = if target_arg&.type == :str
            target_arg.children[0]
          else
            nil
          end

          statements = []

          # Add opening turbo-stream tag to buffer
          if target_str
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
              s(:str, "<turbo-stream action=\"#{action}\" target=\"#{target_str}\"><template>"))
          else
            # Dynamic target
            target_expr = process(target_arg)
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
              s(:dstr,
                s(:str, "<turbo-stream action=\"#{action}\" target=\""),
                s(:begin, target_expr),
                s(:str, "\"><template>")))
          end

          # Process block body (adds to buffer via form_with etc.)
          if block_body
            if block_body.type == :begin
              block_body.children.each do |child|
                processed = process(child)
                statements << processed if processed
              end
            else
              processed = process(block_body)
              statements << processed if processed
            end
          end

          # Add closing turbo-stream tag to buffer
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
            s(:str, "</template></turbo-stream>"))

          # Return a begin node containing all statements
          if statements.length == 1
            statements.first
          else
            s(:begin, *statements)
          end
        end

        # Process turbo_stream shorthand form (without block)
        # turbo_stream.prepend "photos", @photo
        # -> <turbo-stream action="prepend" target="photos"><template>..._photo partial...</template></turbo-stream>
        def process_turbo_stream_shorthand(action, args)
          target_arg = args[0]
          model_arg = args[1]  # Optional - if present, render the model's partial

          # Get target as string
          target_str = if target_arg&.type == :str
            target_arg.children[0]
          elsif target_arg&.type == :sym
            target_arg.children[0].to_s
          else
            nil
          end

          statements = []

          # Add opening turbo-stream tag to buffer
          if target_str
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
              s(:str, "<turbo-stream action=\"#{action}\" target=\"#{target_str}\"><template>"))
          else
            # Dynamic target
            target_expr = process(target_arg)
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
              s(:dstr,
                s(:str, "<turbo-stream action=\"#{action}\" target=\""),
                s(:begin, target_expr),
                s(:str, "\"><template>")))
          end

          # If model is provided, render its partial
          if model_arg
            # For @photo, infer partial as "photos/_photo" and local as "photo"
            # The model_arg is typically an ivar like s(:ivar, :@photo)
            if model_arg.type == :ivar
              ivar_name = model_arg.children[0].to_s.sub('@', '')  # "photo"

              # Track that we need the views module import
              # The view module name follows the pattern: PhotoViews for photos
              plural_name = "#{ivar_name}s"
              view_module = "#{plural_name.split('_').map(&:capitalize).join.chomp('s')}Views"
              partial_method = "_#{ivar_name}"
              local_var = ivar_name

              # Add view module to imports
              view_info = { module: view_module, resource: plural_name }
              @erb_view_modules << view_info unless @erb_view_modules.any? { |v| v[:module] == view_module }

              # Generate: _buf += PhotoViews._photo({$context, photo})
              statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                s(:send,
                  s(:const, nil, view_module.to_sym),
                  partial_method.to_sym,
                  s(:hash,
                    s(:pair, s(:sym, :"$context"), context_gvar),
                    s(:pair, s(:sym, local_var.to_sym), s(:lvar, local_var.to_sym)))))
            else
              # For other expressions, just process and add to buffer
              statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                s(:send, process(model_arg), :toString))
            end
          end

          # Add closing turbo-stream tag to buffer
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
            s(:str, "</template></turbo-stream>"))

          # Return a begin node containing all statements
          if statements.length == 1
            statements.first
          else
            s(:begin, *statements)
          end
        end

        # Process ERB block content into a string expression
        def process_erb_content(node)
          return s(:str, '') unless node

          case node.type
          when :str
            node
          when :begin
            # Multiple statements - process each and concatenate
            parts = node.children.map { |child| process_erb_content(child) }
            combine_string_parts(parts)
          when :send
            # Check for buffer operations
            target, method, *args = node.children
            if target&.type == :lvar && method == :append=
              # _buf.append= expr -> process expr
              process(args.first)
            else
              process(node)
            end
          else
            process(node)
          end
        end

        # Combine multiple string parts into a single string or dstr
        def combine_string_parts(parts)
          return s(:str, '') if parts.empty?
          return parts.first if parts.length == 1

          # Check if all parts are static strings
          if parts.all? { |p| p.type == :str }
            combined = parts.map { |p| p.children[0] }.join
            return s(:str, combined)
          end

          # Build dstr with all parts
          dstr_children = []
          parts.each do |part|
            if part.type == :str
              dstr_children << part
            elsif part.type == :dstr
              dstr_children.concat(part.children)
            else
              dstr_children << s(:begin, part)
            end
          end
          s(:dstr, *dstr_children)
        end

        # Process dom_id helper
        # dom_id(article) -> dom_id(article)
        # dom_id(article, :edit) -> dom_id(article, "edit")
        def process_dom_id(args)
          @erb_view_helpers << :dom_id unless @erb_view_helpers.include?(:dom_id)

          record_node = process(args[0])

          if args.length >= 2
            prefix_node = process(args[1])
            s(:send, nil, :dom_id, record_node, prefix_node)
          else
            s(:send, nil, :dom_id, record_node)
          end
        end

        # Process notice helper - reads from flash and returns message
        # <%= notice %> -> context.flash.consumeNotice()
        def process_notice
          # Access flash through context parameter (no import needed)
          s(:send, s(:attr, context_ref, :flash), :consumeNotice)
        end

        # Process content_for helper
        # <% content_for :title, "Articles" %> -> context.contentFor.title = "Articles"
        # <%= content_for(:title) %> -> context.contentFor.title
        def process_content_for(args)
          return s(:str, '') if args.empty?

          key = args[0]
          value = args[1]

          # Only handle symbol keys for now
          return s(:str, '') unless key.type == :sym
          key_name = key.children[0]

          if value
            # Setting content: content_for :title, "Articles"
            # context.contentFor.title = "Articles"; return ""
            s(:begin,
              s(:send,
                s(:attr, context_ref, :contentFor),
                "#{key_name}=".to_sym,
                process(value)),
              s(:str, ''))
          else
            # Getting content: content_for(:title)
            # context.contentFor.title || ""
            s(:or,
              s(:attr, s(:attr, context_ref, :contentFor), key_name),
              s(:str, ''))
          end
        end

        # Process render partial calls
        # render "form" -> _form_partial({})
        # render "form", article: @article -> _form_partial({article})
        # render partial: "form", locals: { article: @article } -> _form_partial({article})
        # render @article -> _article_partial({article: @article})
        def process_render_partial(args)
          return nil if args.empty?

          first_arg = args[0]
          locals = {}

          # Determine partial name and locals based on argument patterns
          partial_name = nil

          if first_arg.type == :str
            # render "form" or render "form", locals: { ... }
            partial_name = first_arg.children[0]

            # Check for additional hash argument with locals
            if args[1]&.type == :hash
              args[1].children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]
                if key.type == :sym
                  locals[key.children[0]] = value
                end
              end
            end

          elsif first_arg.type == :hash
            # render partial: "form", locals: { ... }
            first_arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :partial
                partial_name = value.children[0] if value.type == :str
              when :locals
                if value.type == :hash
                  value.children.each do |local_pair|
                    local_key = local_pair.children[0]
                    local_value = local_pair.children[1]
                    if local_key.type == :sym
                      locals[local_key.children[0]] = local_value
                    end
                  end
                end
              end
            end

          elsif first_arg.type == :ivar
            # render @article -> renders _article partial with article: @article
            # render @messages -> renders _message partial for each item (collection)
            ivar_name = first_arg.children[0].to_s.sub(/^@/, '')
            partial_name = singularize_partial_name(ivar_name)
            is_collection = (partial_name != ivar_name)
            collection_var = first_arg
            singular_name = partial_name.to_sym
            locals[singular_name] = s(:lvar, singular_name) if is_collection
            locals[ivar_name.to_sym] = first_arg unless is_collection

          elsif first_arg.type == :lvar
            # render article -> renders _article partial with article: article
            # render messages -> renders _message partial for each item (collection)
            var_name = first_arg.children[0].to_s
            partial_name = singularize_partial_name(var_name)
            is_collection = (partial_name != var_name)
            collection_var = first_arg
            singular_name = partial_name.to_sym
            locals[singular_name] = s(:lvar, singular_name) if is_collection
            locals[var_name.to_sym] = first_arg unless is_collection

          elsif first_arg.type == :send && first_arg.children[0]
            # render @article.comments -> renders _comment partial for each item (collection)
            # render article.comments -> same, method call returning a collection
            method_name = first_arg.children[1].to_s
            partial_name = singularize_partial_name(method_name)
            is_collection = (partial_name != method_name)
            collection_var = first_arg
            singular_name = partial_name.to_sym
            locals[singular_name] = s(:lvar, singular_name) if is_collection
            # For method calls like @article.comments, the directory is the method name (comments/)
            partial_directory = method_name if is_collection
          end

          return nil unless partial_name

          # Track this partial for import generation
          # Store as hash with name and optional directory for cross-directory partials
          partial_info = { name: partial_name, directory: partial_directory }
          unless @erb_partials.any? { |p| p[:name] == partial_name && p[:directory] == partial_directory }
            @erb_partials << partial_info
          end

          # Build the partial function call: _form_module.render({$context, article})
          module_name = "_#{partial_name}_module".to_sym

          # Build unified props hash with $context and locals
          # Use the appropriate context reference (context in layout mode, $context otherwise)
          pairs = [s(:pair, s(:sym, :"$context"), context_ref)]
          locals.keys.each do |key|
            pairs << s(:pair, s(:sym, key), process(locals[key]))
          end

          render_call = s(:send, s(:lvar, module_name), :render,
            s(:hash, *pairs))

          # For collections, wrap in Promise.all().join('')
          # (await Promise.all(messages.map(message => _message_module.render({...})))).join('')
          if is_collection
            # Check if the collection is an association access (returns Promise)
            # If so, wrap with await first
            collection_expr = process(collection_var)
            if association_access?(collection_var)
              self.erb_mark_async!()
              # Wrap in begin to get parentheses: (await article.comments).map(...)
              collection_expr = s(:begin, s(:send, nil, :await, collection_expr))
            end

            # Each partial render might be async, use Promise.all to await all
            self.erb_mark_async!()
            map_expr = s(:send, collection_expr, :map,
              s(:block,
                s(:send, nil, :lambda),
                s(:args, s(:arg, singular_name)),
                render_call))

            # (await Promise.all(map_expr)).join('')
            s(:send,
              s(:begin,
                s(:send, nil, :await,
                  s(:send, s(:const, nil, :Promise), :all, map_expr))),
              :join,
              s(:str, ''))
          else
            # Single object render - await in case partial is async
            self.erb_mark_async!()
            s(:send, nil, :await, render_call)
          end
        end

        # Singularize a variable name for partial lookup (Rails collection rendering convention)
        # render @messages -> _message partial, render @articles -> _article partial
        # But render @article stays as _article, render @status stays as _status
        def singularize_partial_name(name)
          Ruby2JS::Inflector.singularize(name)
        end

        # Extract options hash from form field args
        # Returns options hash with :class_node for dynamic class support
        def extract_field_options(args)
          options = {}
          # Options hash is typically the last argument
          if args.last&.type == :hash
            args.last.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                key_name = key.children[0]
                case key_name
                when :class
                  # Store both static value and node for dynamic support
                  options[:class] = extract_class_value(value)
                  options[:class_node] = value
                when :id
                  options[:id] = value.children[0] if value.type == :str
                when :style
                  options[:style] = value.children[0] if value.type == :str
                when :rows
                  options[:rows] = value.children[0] if value.type == :int
                when :cols
                  options[:cols] = value.children[0] if value.type == :int
                when :placeholder
                  options[:placeholder] = value.children[0] if value.type == :str
                when :disabled
                  options[:disabled] = true if value.type == :true
                when :readonly
                  options[:readonly] = true if value.type == :true
                when :required
                  options[:required] = true if value.type == :true
                when :autofocus
                  options[:autofocus] = true if value.type == :true
                when :multiple
                  options[:multiple] = true if value.type == :true
                when :min
                  options[:min] = value.children[0] if [:int, :str].include?(value.type)
                when :max
                  options[:max] = value.children[0] if [:int, :str].include?(value.type)
                when :step
                  options[:step] = value.children[0] if [:int, :str].include?(value.type)
                when :data
                  # Handle data: { key: value } -> data-key="value"
                  if value.type == :hash
                    options[:data] ||= {}
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym
                        # Convert underscores to dashes: chat_target -> chat-target
                        attr_name = data_key.children[0].to_s.gsub('_', '-')
                        if data_value.type == :str
                          options[:data][attr_name] = data_value.children[0]
                        elsif data_value.type == :true
                          options[:data][attr_name] = "true"
                        elsif data_value.type == :false
                          options[:data][attr_name] = "false"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
          options
        end

        # Build HTML attributes string from options hash (static classes only)
        def build_field_attrs(options)
          attrs = []
          attrs << "class=\"#{options[:class]}\"" if options[:class]
          attrs << "id=\"#{options[:id]}\"" if options[:id]
          attrs << "style=\"#{options[:style]}\"" if options[:style]
          attrs << "rows=\"#{options[:rows]}\"" if options[:rows]
          attrs << "cols=\"#{options[:cols]}\"" if options[:cols]
          attrs << "placeholder=\"#{options[:placeholder]}\"" if options[:placeholder]
          attrs << "disabled" if options[:disabled]
          attrs << "readonly" if options[:readonly]
          attrs << "required" if options[:required]
          attrs << "autofocus" if options[:autofocus]
          attrs << "multiple" if options[:multiple]
          attrs << "min=\"#{options[:min]}\"" if options[:min]
          attrs << "max=\"#{options[:max]}\"" if options[:max]
          attrs << "step=\"#{options[:step]}\"" if options[:step]
          # Add data-* attributes
          # Note: use .keys.each for JS compatibility (for...of doesn't work on plain objects)
          if options[:data]
            options[:data].keys.each do |key|
              value = options[:data][key]
              attrs << "data-#{key}=\"#{value}\""
            end
          end
          attrs.empty? ? "" : " " + attrs.join(" ")
        end

        # Check if options contain conditional classes
        def has_conditional_classes?(options)
          return false unless options[:class_node]
          result = extract_class_with_conditions(options[:class_node])
          result && result[:conditionals].any?
        end

        # Build HTML attributes for dynamic output (supports conditional classes)
        # Returns [static_attrs_string, dynamic_class_expr_or_nil]
        def build_field_attrs_dynamic(options)
          # Build non-class attributes
          attrs = []
          attrs << "id=\"#{options[:id]}\"" if options[:id]
          attrs << "style=\"#{options[:style]}\"" if options[:style]
          attrs << "rows=\"#{options[:rows]}\"" if options[:rows]
          attrs << "cols=\"#{options[:cols]}\"" if options[:cols]
          attrs << "placeholder=\"#{options[:placeholder]}\"" if options[:placeholder]
          attrs << "disabled" if options[:disabled]
          attrs << "readonly" if options[:readonly]
          attrs << "required" if options[:required]
          attrs << "autofocus" if options[:autofocus]
          attrs << "multiple" if options[:multiple]
          attrs << "min=\"#{options[:min]}\"" if options[:min]
          attrs << "max=\"#{options[:max]}\"" if options[:max]
          attrs << "step=\"#{options[:step]}\"" if options[:step]
          # Add data-* attributes
          # Note: use .keys.each for JS compatibility (for...of doesn't work on plain objects)
          if options[:data]
            options[:data].keys.each do |key|
              value = options[:data][key]
              attrs << "data-#{key}=\"#{value}\""
            end
          end

          static_attrs = attrs.empty? ? "" : " " + attrs.join(" ")

          # Handle class attribute
          if options[:class_node]
            static_class_attr, dynamic_class_expr = build_dynamic_class_attr(options[:class_node])
            if dynamic_class_expr
              # Has conditional classes - return dynamic expression
              return [static_attrs, dynamic_class_expr]
            elsif static_class_attr && static_class_attr.length > 0
              # Static class only
              return [static_class_attr + static_attrs, nil]
            end
          end

          [static_attrs, nil]
        end

        # Convert form builder method calls to HTML input elements
        def process_form_builder_method(method, args)
          model = @erb_model_name || 'model'
          model_is_new = @erb_model_is_new  # For Model.new, don't pre-fill values
          options = extract_field_options(args)

          case method
          when :text_field, :email_field, :password_field, :hidden_field,
               :number_field, :tel_field, :url_field, :search_field,
               :date_field, :time_field, :datetime_field, :datetime_local_field,
               :month_field, :week_field, :color_field, :range_field
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              input_type = method.to_s.sub(/_field$/, '')
              input_type = 'text' if input_type == 'text'
              input_type = 'datetime-local' if input_type == 'datetime_local'

              # Check for conditional classes
              static_attrs, dynamic_class_expr = build_field_attrs_dynamic(options)

              # For new models, use empty value; for existing, pre-fill from model
              value_expr = if model_is_new
                s(:str, '')
              else
                s(:or, s(:attr, s(:lvar, model.to_sym), name.to_sym), s(:str, ''))
              end

              if dynamic_class_expr
                # Has conditional classes - generate dynamic class attribute
                s(:dstr,
                  s(:str, %(<input type="#{input_type}" name="#{model}[#{name}]" id="#{model}_#{name}" class=")),
                  s(:begin, process(dynamic_class_expr)),
                  s(:str, %("#{static_attrs} value=")),
                  s(:begin, value_expr),
                  s(:str, '">'))
              else
                # Static classes only
                s(:dstr,
                  s(:str, %(<input type="#{input_type}" name="#{model}[#{name}]" id="#{model}_#{name}"#{static_attrs} value=")),
                  s(:begin, value_expr),
                  s(:str, '">'))
              end
            else
              super
            end

          when :text_area, :textarea
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s

              # Check for conditional classes
              static_attrs, dynamic_class_expr = build_field_attrs_dynamic(options)

              # For new models, use empty value; for existing, pre-fill from model
              value_expr = if model_is_new
                s(:str, '')
              else
                s(:or, s(:attr, s(:lvar, model.to_sym), name.to_sym), s(:str, ''))
              end

              if dynamic_class_expr
                # Has conditional classes - generate dynamic class attribute
                s(:dstr,
                  s(:str, %(<textarea name="#{model}[#{name}]" id="#{model}_#{name}" class=")),
                  s(:begin, process(dynamic_class_expr)),
                  s(:str, %("#{static_attrs}>)),
                  s(:begin, value_expr),
                  s(:str, '</textarea>'))
              else
                # Static classes only
                s(:dstr,
                  s(:str, %(<textarea name="#{model}[#{name}]" id="#{model}_#{name}"#{static_attrs}>)),
                  s(:begin, value_expr),
                  s(:str, '</textarea>'))
              end
            else
              super
            end

          when :check_box, :checkbox
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              extra_attrs = build_field_attrs(options)
              html = %(<input type="checkbox" name="#{model}[#{name}]" id="#{model}_#{name}"#{extra_attrs} value="1">)
              s(:str, html)
            else
              super
            end

          when :radio_button
            field_name = args[0]
            value = args[1]
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              val = value&.type == :sym ? value.children.first.to_s : value&.children&.first.to_s
              extra_attrs = build_field_attrs(options)
              html = %(<input type="radio" name="#{model}[#{name}]" id="#{model}_#{name}_#{val}"#{extra_attrs} value="#{val}">)
              s(:str, html)
            else
              super
            end

          when :label
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              # Inline capitalize for JS compatibility (see inflector.rb)
              label_text = name.gsub('_', ' ')
              label_text = label_text[0].upcase + label_text[1..-1].to_s
              extra_attrs = build_field_attrs(options)
              html = %(<label for="#{model}_#{name}"#{extra_attrs}>#{label_text}</label>)
              s(:str, html)
            else
              super
            end

          when :select
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              extra_attrs = build_field_attrs(options)
              html = %(<select name="#{model}[#{name}]" id="#{model}_#{name}"#{extra_attrs}></select>)
              s(:str, html)
            else
              super
            end

          when :submit
            # submit can have: submit("Save") or submit(class: "btn")
            value = args.first
            label = nil
            if value&.type == :str
              label = value.children.first
            elsif value&.type == :hash
              # No label, just options - already extracted
              label = nil
            end
            extra_attrs = build_field_attrs(options)
            if label
              html = %(<input type="submit" value="#{label}"#{extra_attrs}>)
            else
              html = %(<input type="submit"#{extra_attrs}>)
            end
            s(:str, html)

          when :button
            value = args.first
            label = nil
            if value&.type == :str
              label = value.children.first
            elsif value&.type == :hash
              label = nil
            end
            extra_attrs = build_field_attrs(options)
            if label
              html = %(<button type="submit"#{extra_attrs}>#{label}</button>)
            else
              html = %(<button type="submit"#{extra_attrs}>Submit</button>)
            end
            s(:str, html)

          else
            super
          end
        end

        # Process form_for block into JavaScript
        def process_form_for(helper_call, block_args, block_body)
          model_node = helper_call.children[2]
          model_name = model_node.children.first.to_s.sub(/^@/, '') if model_node&.type == :ivar
          block_param = block_args.children.first&.children&.first

          old_block_var = @erb_block_var
          old_model_name = @erb_model_name
          @erb_block_var = block_param
          @erb_model_name = model_name

          statements = []
          form_attrs = model_name ? " data-model=\"#{model_name}\"" : ""
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "<form#{form_attrs}>"))

          # Add authenticity_token hidden field for CSRF protection
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
            s(:dstr,
              s(:str, '<input type="hidden" name="authenticity_token" value="'),
              s(:begin, s(:or, s(:attr, context_gvar, :authenticityToken), s(:str, ''))),
              s(:str, "\">\n")))

          if block_body
            if block_body.type == :begin
              block_body.children.each do |child|
                processed = process(child)
                statements << processed if processed
              end
            else
              processed = process(block_body)
              statements << processed if processed
            end
          end

          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "</form>"))

          @erb_block_var = old_block_var
          @erb_model_name = old_model_name

          s(:begin, *statements.compact)
        end

        # Process form_with block into JavaScript (Rails 5.1+ preferred form helper)
        # form_with(model: @article) do |form| ... end
        # form_with(url: articles_path, class: "contents") do |form| ... end
        # form_with(url: "/photos", method: :post) do |form| ... end
        def process_form_with(helper_call, block_args, block_body)
          # Extract model, url, method, class, and data from keyword arguments
          model_name = nil
          parent_model_name = nil  # Track parent for nested resources
          model_is_new = false  # Track if model is Model.new (no pre-fill values)
          url_node = nil  # Track url: option for form action
          http_method = :post  # Default HTTP method
          css_class = nil
          data_attrs = {}  # Track data-* attributes for form tag
          options_node = helper_call.children[2]

          if options_node&.type == :hash
            options_node.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :model
                  # model: @article or model: article or model: [@article, Comment.new]
                  if value.type == :ivar
                    model_name = value.children.first.to_s.sub(/^@/, '')
                  elsif value.type == :lvar
                    model_name = value.children.first.to_s
                  elsif value.type == :send && value.children.first.nil?
                    # s(:send, nil, :article) - method call as local
                    model_name = value.children[1].to_s
                  elsif value.type == :send && value.children[1] == :new
                    # model: Comment.new -> comment, and mark as new (empty values)
                    const_node = value.children[0]
                    if const_node&.type == :const
                      model_name = const_node.children[1].to_s.downcase
                      model_is_new = true
                    end
                  elsif value.type == :array && value.children.length >= 2
                    # Nested resource: model: [@article, Comment.new]
                    # Extract parent model (first element) for path generation
                    parent = value.children.first
                    if parent.type == :ivar
                      parent_model_name = parent.children.first.to_s.sub(/^@/, '')
                    elsif parent.type == :lvar
                      parent_model_name = parent.children.first.to_s
                    end
                    # Use the child model (second element) for form field naming
                    child = value.children.last
                    if child.type == :send && child.children[1] == :new
                      # Comment.new -> comment, and mark as new (empty values)
                      const_node = child.children[0]
                      if const_node&.type == :const
                        model_name = const_node.children[1].to_s.downcase
                        model_is_new = true
                      end
                    end
                  end
                when :url
                  # url: "/photos" or url: photos_path
                  url_node = value
                  # Track path helper for import if it's a path helper call
                  if value.type == :send && value.children[0].nil?
                    path_helper = value.children[1]
                    @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
                  end
                when :method
                  # method: :post, method: :patch, method: :delete
                  http_method = value.children[0] if value.type == :sym
                when :class
                  css_class = extract_class_value(value)
                when :data
                  # Handle data: { key: value } -> data-key="value"
                  if value.type == :hash
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym
                        # Convert underscores to dashes: turbo_confirm -> turbo-confirm
                        attr_name = data_key.children[0].to_s.gsub('_', '-')
                        if data_value.type == :str
                          data_attrs[attr_name] = data_value.children[0]
                        elsif data_value.type == :true
                          data_attrs[attr_name] = "true"
                        elsif data_value.type == :false
                          data_attrs[attr_name] = "false"
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          block_param = block_args.children.first&.children&.first

          old_block_var = @erb_block_var
          old_model_name = @erb_model_name
          old_model_is_new = @erb_model_is_new
          @erb_block_var = block_param
          @erb_model_name = model_name
          @erb_model_is_new = model_is_new

          statements = []

          # Build class attribute string
          class_attr = css_class ? " class=\"#{css_class}\"" : ""

          # Build data attributes string
          # Use each_pair for selfhost compatibility (transpiles to Object.entries().forEach)
          data_attr = ""
          data_attrs.each_pair { |k, v| data_attr += " data-#{k}=\"#{v}\"" }

          # Build form tag with action and method - Turbo intercepts form submissions automatically
          if model_name
            # Form with action and method using path helpers
            plural_name = model_name + 's'  # Simple pluralization
            singular_path = :"#{model_name}_path"   # :article_path
            plural_path = :"#{plural_name}_path"    # :articles_path
            model_var = s(:lvar, model_name.to_sym)

            # Track path helpers for import
            @erb_path_helpers << singular_path unless @erb_path_helpers.include?(singular_path)
            @erb_path_helpers << plural_path unless @erb_path_helpers.include?(plural_path)

            if model_is_new
              # New model - POST to collection path
              # <form action="<%= articles_path() %>" method="post">
              # For nested resources: <form action="<%= comments_path(article) %>" method="post">
              if parent_model_name
                # Nested resource - pass parent model to path helper
                parent_var = s(:lvar, parent_model_name.to_sym)
                statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                  s(:dstr,
                    s(:str, "<form data-model=\"#{model_name}\"#{class_attr}#{data_attr} action=\""),
                    s(:begin, s(:send, nil, plural_path, parent_var)),
                    s(:str, "\" method=\"post\">")))
              else
                statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                  s(:dstr,
                    s(:str, "<form data-model=\"#{model_name}\"#{class_attr}#{data_attr} action=\""),
                    s(:begin, s(:send, nil, plural_path)),
                    s(:str, "\" method=\"post\">")))
              end
            else
              # Existing model - check ID to determine POST vs PATCH
              # <form action="<%= article.id ? article_path(article) : articles_path() %>" method="post">
              statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                s(:dstr,
                  s(:str, "<form data-model=\"#{model_name}\"#{class_attr}#{data_attr} action=\""),
                  s(:begin,
                    s(:if, s(:attr, model_var, :id),
                      s(:send, nil, singular_path, model_var),
                      s(:send, nil, plural_path))),
                  s(:str, "\" method=\"post\">")))

              # Add hidden _method field for existing records (PATCH)
              # <% if article.id %><input type="hidden" name="_method" value="patch"><% end %>
              statements << s(:if, s(:attr, model_var, :id),
                s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                  s(:str, '<input type="hidden" name="_method" value="patch">')),
                nil)
            end
          elsif url_node
            # Form with explicit url: option
            # form_with(url: "/photos", method: :post) or form_with(url: photos_path)
            actual_method = (http_method == :get || http_method == :post) ? http_method : :post
            needs_method_field = ![:get, :post].include?(http_method)

            if url_node.type == :str
              # Static URL string: url: "/photos"
              url_str = url_node.children[0]
              form_tag = "<form#{class_attr}#{data_attr} action=\"#{url_str}\" method=\"#{actual_method}\">"
              if needs_method_field
                form_tag += "\n<input type=\"hidden\" name=\"_method\" value=\"#{http_method}\">"
              end
              statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, form_tag))
            else
              # Dynamic URL (path helper): url: photos_path
              url_expr = process(url_node)
              if needs_method_field
                statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                  s(:dstr,
                    s(:str, "<form#{class_attr}#{data_attr} action=\""),
                    s(:begin, url_expr),
                    s(:str, "\" method=\"#{actual_method}\">\n<input type=\"hidden\" name=\"_method\" value=\"#{http_method}\">")))
              else
                statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
                  s(:dstr,
                    s(:str, "<form#{class_attr}#{data_attr} action=\""),
                    s(:begin, url_expr),
                    s(:str, "\" method=\"#{actual_method}\">")))
              end
            end
          else
            # No model or url - just output a basic form tag
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "<form#{class_attr}#{data_attr}>"))
          end

          # Add authenticity_token hidden field for CSRF protection
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
            s(:dstr,
              s(:str, '<input type="hidden" name="authenticity_token" value="'),
              s(:begin, s(:or, s(:attr, context_gvar, :authenticityToken), s(:str, ''))),
              s(:str, "\">\n")))

          if block_body
            if block_body.type == :begin
              block_body.children.each do |child|
                processed = process(child)
                statements << processed if processed
              end
            else
              processed = process(block_body)
              statements << processed if processed
            end
          end

          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "</form>"))

          @erb_block_var = old_block_var
          @erb_model_name = old_model_name
          @erb_model_is_new = old_model_is_new

          s(:begin, *statements.compact)
        end

        # Process form_tag block into JavaScript
        def process_form_tag(helper_call, block_args, block_body)
          path_node = helper_call.children[2]
          options_node = helper_call.children[3]

          http_method = :post
          if options_node&.type == :hash
            options_node.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym && key.children[0] == :method
                http_method = value.children[0] if value.type == :sym
              end
            end
          end

          if path_node&.type == :send && path_node.children[0].nil?
            path_helper = path_node.children[1]
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
          end

          statements = []

          # Generate standard form with action/method - Turbo intercepts submissions automatically
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, build_server_form_tag(path_node, http_method))

          # Add authenticity_token hidden field for CSRF protection
          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
            s(:dstr,
              s(:str, '<input type="hidden" name="authenticity_token" value="'),
              s(:begin, s(:or, s(:attr, context_gvar, :authenticityToken), s(:str, ''))),
              s(:str, "\">\n")))

          if block_body
            if block_body.type == :begin
              block_body.children.each do |child|
                processed = process(child)
                statements << processed if processed
              end
            else
              processed = process(block_body)
              statements << processed if processed
            end
          end

          statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "</form>\n"))

          s(:begin, *statements.compact)
        end

        # Build form tag with action attribute - Turbo intercepts submissions automatically
        def build_server_form_tag(path_node, http_method)
          path_expr = process(path_node)
          actual_method = (http_method == :get || http_method == :post) ? http_method : :post
          needs_method_field = ![:get, :post].include?(http_method)

          if path_node&.type == :send && path_node.children[0].nil? && path_node.children.length == 2
            path_expr = s(:send, nil, path_node.children[1])
          end

          if path_node.type == :str
            path_str = path_node.children[0]
            if needs_method_field
              s(:str, "<form action=\"#{path_str}\" method=\"#{actual_method}\">\n<input type=\"hidden\" name=\"_method\" value=\"#{http_method}\">\n")
            else
              s(:str, "<form action=\"#{path_str}\" method=\"#{actual_method}\">\n")
            end
          else
            if needs_method_field
              s(:dstr,
                s(:str, '<form action="'),
                s(:begin, path_expr),
                s(:str, "\" method=\"#{actual_method}\">\n<input type=\"hidden\" name=\"_method\" value=\"#{http_method}\">\n"))
            else
              s(:dstr,
                s(:str, '<form action="'),
                s(:begin, path_expr),
                s(:str, "\" method=\"#{actual_method}\">\n"))
            end
          end
        end

        # Process generic block helpers
        def process_block_helper(helper_name, helper_call, block_args, block_body)
          block_param = block_args.children.first&.children&.first

          old_block_var = @erb_block_var
          @erb_block_var = block_param

          statements = []

          if block_body
            if block_body.type == :begin
              block_body.children.each do |child|
                processed = process(child)
                statements << processed if processed
              end
            else
              processed = process(block_body)
              statements << processed if processed
            end
          end

          @erb_block_var = old_block_var

          return nil if statements.empty?
          statements.length == 1 ? statements.first : s(:begin, *statements.compact)
        end

        private

        # Check if a node represents an association access (e.g., article.comments)
        # Association access returns a Promise that needs to be awaited
        def association_access?(node)
          return false unless node&.type == :send
          receiver = node.children[0]
          method = node.children[1]

          # Receiver must be a model instance (lvar or ivar that's been converted to lvar)
          return false unless receiver
          return false unless [:lvar, :ivar, :send].include?(receiver.type)

          # Method name should be plural (convention for has_many associations)
          # This is a heuristic - plural method names on model instances are likely associations
          method_str = method.to_s
          singular = Ruby2JS::Inflector.singularize(method_str)
          method_str != singular
        end

        # Check if targeting browser (vs server-side rendering)
        # Explicit :target option takes precedence over database inference
        def browser_target?
          # Check for explicit target option first
          target = @options[:target]
          if target
            return target.to_s.downcase == 'browser'
          end

          # Fall back to inferring from database
          database = @options[:database]
          return true unless database
          database = database.to_s.downcase
          BROWSER_DATABASES.include?(database)
        end
      end
    end

    DEFAULTS.push Rails::Helpers
  end
end
