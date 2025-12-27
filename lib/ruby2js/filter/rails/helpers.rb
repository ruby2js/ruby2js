require 'ruby2js'

module Ruby2JS
  module Filter
    module Rails
      module Helpers
        include SEXP
        # Note: This filter overrides Erb's hook methods (process_erb_block_append,
        # process_erb_block_helper). In the filter list, Rails::Helpers must come
        # BEFORE Erb so the overrides take precedence in Ruby2JS's filter chain.

        # Browser databases - these run in browser with History API navigation
        BROWSER_DATABASES = %w[dexie indexeddb sqljs sql.js].freeze

        def initialize(*args)
          super
          @erb_block_var = nil   # Track current block variable (e.g., 'f' in form_for)
          @erb_model_name = nil  # Track model name for form_for (e.g., 'user')
          @erb_path_helpers = [] # Track path helper usage for imports
          @erb_view_helpers = [] # Track view helper usage (truncate, etc.) for imports
          @erb_partials = []     # Track partial usage for imports
        end

        # Add imports for path helpers and view helpers
        # Called by Erb filter's on_begin via erb_prepend_imports hook
        def erb_prepend_imports
          # Add import for path helpers if any were used
          unless @erb_path_helpers.empty?
            helpers = @erb_path_helpers.uniq.sort.map { |name| s(:const, nil, name) }
            self.prepend_list << s(:import, '../../config/paths.js', helpers)
          end

          # Add import for view helpers (truncate, etc.) from rails.js
          unless @erb_view_helpers.empty?
            helpers = @erb_view_helpers.uniq.sort.map { |name| s(:const, nil, name) }
            self.prepend_list << s(:import, '../../lib/rails.js', helpers)
          end

          # Add imports for partials
          # render "form" -> import * as _form_module from './_form.js'
          # Then call _form_module.render({article})
          unless @erb_partials.empty?
            @erb_partials.uniq.sort.each do |partial_name|
              module_name = "_#{partial_name}_module".to_sym
              # Path array format: [as_pair, from_pair] for "import * as X from Y"
              self.prepend_list << s(:import,
                [s(:pair, s(:sym, :as), s(:const, nil, module_name)),
                 s(:pair, s(:sym, :from), s(:str, "./_#{partial_name}.js"))],
                s(:str, '*'))
            end
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

          # Handle render partial calls
          if method == :render && target.nil? && args.any?
            result = process_render_partial(args)
            return result if result
          end

          # Track path helper usage for imports (e.g., article_path, new_article_path)
          if target.nil? && method.to_s.end_with?('_path') && @erb_bufvar
            @erb_path_helpers << method unless @erb_path_helpers.include?(method)
          end

          super
        end

        # Override Erb's hook to handle Rails block helpers (form_for, form_tag, etc.)
        def process_erb_block_append(block_node)
          block_send = block_node.children[0]
          block_args = block_node.children[1]
          block_body = block_node.children[2]

          if block_send&.type == :send
            helper_name = block_send.children[1]

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

        # Process link_to helper into anchor tag with navigate
        def process_link_to(args)
          text_node = args[0]
          path_node = args[1]
          options = args[2] if args.length > 2

          # Check for method: :delete option
          is_delete = false
          confirm_msg = nil
          if options&.type == :hash
            options.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :method
                  is_delete = (value.type == :sym && value.children[0] == :delete)
                when :data
                  # Look for confirm in data hash
                  if value.type == :hash
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym && data_key.children[0] == :confirm
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
            build_delete_link(text_node, path_node, confirm_msg)
          else
            build_nav_link(text_node, path_node)
          end
        end

        # Build a navigation link
        def build_nav_link(text_node, path_node)
          # Handle model object as path: link_to "Show", @article or link_to "Show", article
          if path_node.type == :ivar
            # Instance variable: @article
            model_name = path_node.children.first.to_s.sub(/^@/, '')
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            # Generate /models/:id path
            path_expr = s(:dstr,
              s(:str, "/#{model_name}s/"),
              s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)))
          elsif path_node.type == :lvar
            # Local variable: article (from a loop)
            model_name = path_node.children.first.to_s
            path_helper = "#{model_name}_path".to_sym
            @erb_path_helpers << path_helper unless @erb_path_helpers.include?(path_helper)
            # Generate /models/:id path
            path_expr = s(:dstr,
              s(:str, "/#{model_name}s/"),
              s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)))
          else
            path_expr = process(path_node)

            # Ensure path helpers without arguments are called as functions
            if path_node.type == :send && path_node.children[0].nil? && path_node.children.length == 2
              path_expr = s(:send, nil, path_node.children[1])
            end
          end

          if self.browser_target?()
            # Browser target - SPA navigation with onclick handlers
            if text_node.type == :str && path_node.type == :str
              text_str = text_node.children[0]
              path_str = path_node.children[0]
              s(:str, "<a href=\"#{path_str}\" onclick=\"return navigate(event, '#{path_str}')\">#{text_str}</a>")
            elsif text_node.type == :str
              text_str = text_node.children[0]
              s(:dstr,
                s(:str, '<a href="'),
                s(:begin, path_expr),
                s(:str, "\" onclick=\"return navigate(event, '"),
                s(:begin, path_expr),
                s(:str, "')\" style=\"cursor: pointer\">#{text_str}</a>"))
            else
              text_expr = process(text_node)
              s(:dstr,
                s(:str, '<a href="'),
                s(:begin, path_expr),
                s(:str, "\" onclick=\"return navigate(event, '"),
                s(:begin, path_expr),
                s(:str, "')\" style=\"cursor: pointer\">"),
                s(:begin, text_expr),
                s(:str, '</a>'))
            end
          else
            # Node target - traditional href links
            if text_node.type == :str && path_node.type == :str
              text_str = text_node.children[0]
              path_str = path_node.children[0]
              s(:str, "<a href=\"#{path_str}\">#{text_str}</a>")
            elsif text_node.type == :str
              text_str = text_node.children[0]
              s(:dstr,
                s(:str, '<a href="'),
                s(:begin, path_expr),
                s(:str, "\">#{text_str}</a>"))
            else
              text_expr = process(text_node)
              s(:dstr,
                s(:str, '<a href="'),
                s(:begin, path_expr),
                s(:str, '">'),
                s(:begin, text_expr),
                s(:str, '</a>'))
            end
          end
        end

        # Build a delete link with confirmation
        def build_delete_link(text_node, path_node, confirm_msg)
          path_expr = process(path_node)
          confirm_str = confirm_msg ? confirm_msg.children[0] : 'Are you sure?'

          if self.browser_target?()
            text_str = text_node.type == :str ? text_node.children[0] : nil

            if path_node&.type == :send && path_node.children[0].nil?
              path_helper = path_node.children[1].to_s
              path_args = path_node.children[2..-1]
              base_name = path_helper.sub(/_path$/, '')

              if path_args.length == 2
                # Nested resource: comment_path(@article, comment)
                parent_arg = path_args[0]
                child_arg = path_args[1]
                parent_name = parent_arg.type == :ivar ? parent_arg.children.first.to_s.sub(/^@/, '') : 'parent'
                route_name = "#{parent_name}_#{base_name}"

                return s(:dstr,
                  s(:str, "<a href=\"#\" onclick=\"if(confirm('#{confirm_str}')) { routes.#{route_name}.delete("),
                  s(:begin, s(:attr, s(:lvar, parent_name.to_sym), :id)),
                  s(:str, ", "),
                  s(:begin, s(:attr, process(child_arg), :id)),
                  s(:str, ") } return false;\" style=\"color: red; cursor: pointer;\">#{text_str || 'Delete'}</a>"))
              elsif path_args.length == 1
                arg = path_args.first
                model_name = arg.type == :ivar ? arg.children.first.to_s.sub(/^@/, '') : nil

                if model_name
                  return s(:dstr,
                    s(:str, "<a href=\"#\" onclick=\"if(confirm('#{confirm_str}')) { routes.#{base_name}.delete("),
                    s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                    s(:str, ") } return false;\" style=\"color: red; cursor: pointer;\">#{text_str || 'Delete'}</a>"))
                end
              end
            end

            # Fallback
            if text_str
              s(:str, "<a href=\"#\" onclick=\"if(confirm('#{confirm_str}')) { /* delete */ } return false;\">#{text_str}</a>")
            else
              text_expr = process(text_node)
              s(:dstr,
                s(:str, "<a href=\"#\" onclick=\"if(confirm('#{confirm_str}')) { /* delete */ } return false;\">"),
                s(:begin, text_expr),
                s(:str, '</a>'))
            end
          else
            # Node target - form-based delete
            if text_node.type == :str && path_node.type == :str
              text_str = text_node.children[0]
              path_str = path_node.children[0]
              s(:str, "<form method=\"post\" action=\"#{path_str}\" style=\"display:inline\" data-confirm=\"#{confirm_str}\"><input type=\"hidden\" name=\"_method\" value=\"delete\"><button type=\"submit\">#{text_str}</button></form>")
            elsif text_node.type == :str
              text_str = text_node.children[0]
              s(:dstr,
                s(:str, '<form method="post" action="'),
                s(:begin, path_expr),
                s(:str, "\" style=\"display:inline\" data-confirm=\"#{confirm_str}\"><input type=\"hidden\" name=\"_method\" value=\"delete\"><button type=\"submit\">#{text_str}</button></form>"))
            else
              text_expr = process(text_node)
              s(:dstr,
                s(:str, '<form method="post" action="'),
                s(:begin, path_expr),
                s(:str, "\" style=\"display:inline\" data-confirm=\"#{confirm_str}\"><input type=\"hidden\" name=\"_method\" value=\"delete\"><button type=\"submit\">"),
                s(:begin, text_expr),
                s(:str, '</button></form>'))
            end
          end
        end

        # Process button_to helper
        # button_to "Destroy", @article, method: :delete
        def process_button_to(args)
          text_node = args[0]
          path_node = args[1]
          options = args[2] if args.length > 2

          # Check for method: :delete option
          http_method = :post
          confirm_msg = nil
          if options&.type == :hash
            options.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :method
                  http_method = value.children[0] if value.type == :sym
                when :data
                  if value.type == :hash
                    value.children.each do |data_pair|
                      data_key = data_pair.children[0]
                      data_value = data_pair.children[1]
                      if data_key.type == :sym && data_key.children[0] == :confirm
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
            build_delete_button(text_str, path_node, confirm_str)
          else
            build_form_button(text_str, path_node, http_method)
          end
        end

        # Build a delete button (form with onclick handler for SPA)
        def build_delete_button(text_str, path_node, confirm_str)
          if self.browser_target?()
            # Browser target - onclick handler
            if path_node&.type == :send && path_node.children[0].nil?
              path_helper = path_node.children[1].to_s
              path_args = path_node.children[2..-1]
              base_name = path_helper.sub(/_path$/, '')

              if path_args.length == 1
                arg = path_args.first
                model_name = arg.type == :ivar ? arg.children.first.to_s.sub(/^@/, '') : nil

                if model_name
                  return s(:dstr,
                    s(:str, "<form style=\"display:inline\"><button type=\"button\" onclick=\"if(confirm('#{confirm_str}')) { routes.#{base_name}.delete("),
                    s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                    s(:str, ") }\">#{text_str}</button></form>"))
                end
              elsif path_args.length == 2
                # Nested resource
                parent_arg = path_args[0]
                child_arg = path_args[1]
                parent_name = parent_arg.type == :ivar ? parent_arg.children.first.to_s.sub(/^@/, '') : 'parent'
                route_name = "#{parent_name}_#{base_name}"

                return s(:dstr,
                  s(:str, "<form style=\"display:inline\"><button type=\"button\" onclick=\"if(confirm('#{confirm_str}')) { routes.#{route_name}.delete("),
                  s(:begin, s(:attr, s(:lvar, parent_name.to_sym), :id)),
                  s(:str, ", "),
                  s(:begin, s(:attr, process(child_arg), :id)),
                  s(:str, ") }\">#{text_str}</button></form>"))
              end
            end

            # Handle @model directly (not path helper)
            if path_node&.type == :ivar
              model_name = path_node.children.first.to_s.sub(/^@/, '')
              return s(:dstr,
                s(:str, "<form style=\"display:inline\"><button type=\"button\" onclick=\"if(confirm('#{confirm_str}')) { routes.#{model_name}.delete("),
                s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                s(:str, ") }\">#{text_str}</button></form>"))
            end

            # Fallback
            s(:str, "<form style=\"display:inline\"><button type=\"button\" onclick=\"if(confirm('#{confirm_str}')) { /* delete */ }\">#{text_str}</button></form>")
          else
            # Node target - form-based delete
            path_expr = process(path_node)
            s(:dstr,
              s(:str, '<form method="post" action="'),
              s(:begin, path_expr),
              s(:str, "\" style=\"display:inline\"><input type=\"hidden\" name=\"_method\" value=\"delete\"><button type=\"submit\" data-confirm=\"#{confirm_str}\">#{text_str}</button></form>"))
          end
        end

        # Build a regular form button
        def build_form_button(text_str, path_node, http_method)
          path_expr = process(path_node)
          s(:dstr,
            s(:str, '<form method="'),
            s(:str, http_method.to_s),
            s(:str, '" action="'),
            s(:begin, path_expr),
            s(:str, "\" style=\"display:inline\"><button type=\"submit\">#{text_str}</button></form>"))
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
        # <%= notice %> -> flash.consumeNotice()
        def process_notice
          @erb_view_helpers << :flash unless @erb_view_helpers.include?(:flash)
          s(:send, s(:lvar, :flash), :consumeNotice)
        end

        # Process content_for helper
        # <% content_for :title, "Articles" %> -> stores content (returns empty string)
        # <%= content_for(:title) %> -> retrieves content
        def process_content_for(args)
          return s(:str, '') if args.empty?

          key = args[0]
          value = args[1]

          if value
            # Setting content: content_for :title, "Articles"
            # For now, handle :title specially to set document.title
            if key.type == :sym && key.children[0] == :title
              # Set document.title and return empty string
              s(:begin,
                s(:send, s(:attr, nil, :document), :title=, process(value)),
                s(:str, ''))
            else
              # Other keys: just return empty string (no-op for now)
              s(:str, '')
            end
          else
            # Getting content: content_for(:title)
            # For :title, return document.title
            if key.type == :sym && key.children[0] == :title
              s(:attr, s(:lvar, :document), :title)
            else
              s(:str, '')
            end
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
            ivar_name = first_arg.children[0].to_s.sub(/^@/, '')
            partial_name = ivar_name
            locals[ivar_name.to_sym] = first_arg

          elsif first_arg.type == :lvar
            # render article -> renders _article partial with article: article
            var_name = first_arg.children[0].to_s
            partial_name = var_name
            locals[var_name.to_sym] = first_arg
          end

          return nil unless partial_name

          # Track this partial for import generation
          @erb_partials << partial_name unless @erb_partials.include?(partial_name)

          # Build the partial function call: _form_module.render({article})
          module_name = "_#{partial_name}_module".to_sym

          # Build locals hash for the call
          # Note: use keys iteration for JS compatibility (Hash#map doesn't transpile well)
          pairs = []
          locals.keys.each do |key|
            pairs << s(:pair, s(:sym, key), process(locals[key]))
          end

          if pairs.empty?
            s(:send, s(:lvar, module_name), :render, s(:hash))
          else
            s(:send, s(:lvar, module_name), :render, s(:hash, *pairs))
          end
        end

        # Convert form builder method calls to HTML input elements
        def process_form_builder_method(method, args)
          model = @erb_model_name || 'model'

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
              # Include current value from model
              s(:dstr,
                s(:str, %(<input type="#{input_type}" name="#{model}[#{name}]" id="#{model}_#{name}" value=")),
                s(:begin, s(:or, s(:attr, s(:lvar, model.to_sym), name.to_sym), s(:str, ''))),
                s(:str, '">'))
            else
              super
            end

          when :text_area, :textarea
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              # Include current value from model inside textarea
              s(:dstr,
                s(:str, %(<textarea name="#{model}[#{name}]" id="#{model}_#{name}">)),
                s(:begin, s(:or, s(:attr, s(:lvar, model.to_sym), name.to_sym), s(:str, ''))),
                s(:str, '</textarea>'))
            else
              super
            end

          when :check_box, :checkbox
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              html = %(<input type="checkbox" name="#{model}[#{name}]" id="#{model}_#{name}" value="1">)
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
              html = %(<input type="radio" name="#{model}[#{name}]" id="#{model}_#{name}_#{val}" value="#{val}">)
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
              html = %(<label for="#{model}_#{name}">#{label_text}</label>)
              s(:str, html)
            else
              super
            end

          when :select
            field_name = args.first
            if field_name&.type == :sym
              name = field_name.children.first.to_s
              html = %(<select name="#{model}[#{name}]" id="#{model}_#{name}"></select>)
              s(:str, html)
            else
              super
            end

          when :submit
            value = args.first
            if value&.type == :str
              label = value.children.first
              html = %(<input type="submit" value="#{label}">)
            else
              html = %(<input type="submit">)
            end
            s(:str, html)

          when :button
            value = args.first
            if value&.type == :str
              label = value.children.first
              html = %(<button type="submit">#{label}</button>)
            else
              html = %(<button type="submit">Submit</button>)
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
        # form_with(url: articles_path) do |form| ... end
        def process_form_with(helper_call, block_args, block_body)
          # Extract model or url from keyword arguments
          model_name = nil
          options_node = helper_call.children[2]

          if options_node&.type == :hash
            options_node.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym && key.children[0] == :model
                # model: @article or model: article
                if value.type == :ivar
                  model_name = value.children.first.to_s.sub(/^@/, '')
                elsif value.type == :lvar
                  model_name = value.children.first.to_s
                elsif value.type == :send && value.children.first.nil?
                  # s(:send, nil, :article) - method call as local
                  model_name = value.children[1].to_s
                end
              end
            end
          end

          block_param = block_args.children.first&.children&.first

          old_block_var = @erb_block_var
          old_model_name = @erb_model_name
          @erb_block_var = block_param
          @erb_model_name = model_name

          statements = []

          # Build form tag - add onsubmit handler for browser/SPA target
          if model_name && self.browser_target?
            # Browser/SPA target - use routes pattern like form_tag
            # Generate: <form onsubmit="return (model.id ? routes.model.patch(event, model.id) : routes.models.post(event))">
            plural_name = model_name + 's'  # Simple pluralization
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+,
              s(:dstr,
                s(:str, "<form data-model=\"#{model_name}\" onsubmit=\"return ("),
                s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                s(:str, " ? routes.#{model_name}.patch(event, "),
                s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                s(:str, ") : routes.#{plural_name}.post(event))\">")))
          elsif model_name
            # Server target - standard form
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "<form data-model=\"#{model_name}\">"))
          else
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, s(:str, "<form>"))
          end

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

          if self.browser_target?()
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, build_browser_form_tag(path_node, http_method))
          else
            statements << s(:op_asgn, s(:lvasgn, self.erb_bufvar), :+, build_server_form_tag(path_node, http_method))
          end

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

        # Build browser form tag with onsubmit handler
        def build_browser_form_tag(path_node, http_method)
          if path_node&.type == :send && path_node.children[0].nil?
            path_helper = path_node.children[1].to_s
            path_args = path_node.children[2..-1]
            base_name = path_helper.sub(/_path$/, '')

            if path_args.empty?
              s(:str, "<form onsubmit=\"return routes.#{base_name}.#{http_method}(event)\">\n")
            else
              arg = path_args.first

              if base_name.end_with?('s') && path_args.length == 1
                if arg.type == :ivar
                  parent_name = arg.children.first.to_s.sub(/^@/, '')
                  route_name = "#{parent_name}_#{base_name}"
                else
                  route_name = "article_#{base_name}"
                end
              else
                route_name = base_name
              end

              if arg.type == :ivar
                model_name = arg.children.first.to_s.sub(/^@/, '')
                s(:dstr,
                  s(:str, "<form onsubmit=\"return routes.#{route_name}.#{http_method}(event, "),
                  s(:begin, s(:attr, s(:lvar, model_name.to_sym), :id)),
                  s(:str, ")\">\n"))
              else
                s(:dstr,
                  s(:str, "<form onsubmit=\"return routes.#{route_name}.#{http_method}(event, "),
                  s(:begin, process(arg)),
                  s(:str, ")\">\n"))
              end
            end
          else
            s(:str, "<form>\n")
          end
        end

        # Build server form tag with action attribute
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

        # Derive target from database option
        def browser_target?
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
