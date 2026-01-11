require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Controller
        include SEXP

        # ActiveRecord class methods that should be awaited
        AR_CLASS_METHODS = %i[all find find_by where first last count create create! order].freeze

        # ActiveRecord instance methods that should be awaited
        AR_INSTANCE_METHODS = %i[save save! update update! destroy destroy! reload].freeze

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_controller = nil
          @rails_controller_name = nil
          @rails_controller_plural = nil
          @rails_before_actions = []
          @rails_private_methods = {}
          @rails_model_refs = Set.new
          @rails_needs_views = false
          @rails_needs_turbo_stream_views = false
          @rails_current_action = nil
          # Model associations for preloading - set lazily from options in model_associations method
          @rails_model_associations = nil
        end

        # Accessor for model associations - lazily loads from options
        # Can be passed via options[:model_associations] from the builder
        def model_associations
          @rails_model_associations ||= (@options && @options[:model_associations]) || {}
        end

        # Detect controller class and transform to module
        def on_class(node)
          class_name, superclass, body = node.children

          # Always create fresh Set for each class
          @rails_model_refs = Set.new

          # Check if this is a controller (inherits from ApplicationController or *Controller)
          return super unless controller_class?(class_name, superclass)

          # Extract controller name (e.g., ArticlesController -> Article, PeopleController -> Person)
          @rails_controller_plural = class_name.children.last.to_s.sub(/Controller$/, '').downcase
          @rails_controller_name = Ruby2JS::Inflector.singularize(@rails_controller_plural).capitalize
          @rails_controller = true

          # First pass: collect before_actions, private methods, and model references
          collect_controller_metadata(body)
          collect_model_references(body)

          # Second pass: transform methods
          transformed_body = transform_controller_body(body)

          # Generate imports for models and views
          imports = generate_imports.map { |node| process(node) }

          # Get comments from original class node BEFORE processing
          # (processing may lose the association)
          original_comments = @comments.get(node)
          original_comments = original_comments.is_a?(Array) ? original_comments.dup : []

          # Clear comments from original node to prevent duplication
          @comments.set(node, [])

          # Build the export module
          export_node = s(:send, nil, :export,
            s(:module, class_name, transformed_body))
          export_module = process(export_node)

          # Set comments on export_module so they appear after imports, before export
          if original_comments.any?
            @comments.set(export_module, original_comments)
          end

          result = if imports.any?
                     begin_node = s(:begin, *imports, export_module)
                     # Set empty comments on the begin node to prevent first-child-with-location
                     @comments.set(begin_node, [])
                     begin_node
                   else
                     export_module
                   end

          @rails_controller = nil
          @rails_controller_name = nil
          @rails_controller_plural = nil
          @rails_before_actions = []
          @rails_private_methods = {}
          @rails_model_refs = Set.new
          @rails_needs_views = false
          @rails_needs_turbo_stream_views = false

          result
        end

        private

        def controller_class?(class_name, superclass)
          return false unless class_name&.type == :const
          return false unless superclass&.type == :const

          class_name_str = class_name.children.last.to_s
          superclass_str = superclass.children.last.to_s

          # Match *Controller < ApplicationController or *Controller < *Controller
          class_name_str.end_with?('Controller') &&
            (superclass_str == 'ApplicationController' || superclass_str.end_with?('Controller'))
        end

        def collect_controller_metadata(body)
          return unless body

          children = body.type == :begin ? body.children : [body]

          in_private = false
          children.each do |child|
            next unless child

            # Track private section
            if child.type == :send && child.children[0].nil? && child.children[1] == :private
              in_private = true
              next
            end

            # Collect before_action declarations
            if child.type == :send && child.children[0].nil? && child.children[1] == :before_action
              collect_before_action(child)
              next
            end

            # Collect private methods for inlining
            if in_private && child.type == :def
              method_name = child.children[0]
              @rails_private_methods[method_name] = child
            end
          end
        end

        def collect_before_action(node)
          # before_action :method_name, only: [:action1, :action2]
          args = node.children[2..-1]
          return if args.empty?

          method_name = nil
          only_actions = nil
          except_actions = nil

          args.each do |arg|
            if arg.type == :sym
              method_name = arg.children[0]
            elsif arg.type == :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]

                if key.type == :sym
                  case key.children[0]
                  when :only
                    only_actions = extract_action_list(value)
                  when :except
                    except_actions = extract_action_list(value)
                  end
                end
              end
            end
          end

          # Note: use push instead of << for JS compatibility
          if method_name
            @rails_before_actions.push({
              method: method_name,
              only: only_actions,
              except: except_actions
            })
          end
        end

        def extract_action_list(node)
          if node.type == :array
            node.children.map { |c| c.children[0] if c.type == :sym }.compact
          elsif node.type == :sym
            [node.children[0]]
          else
            []
          end
        end

        def transform_controller_body(body)
          return nil unless body

          children = body.type == :begin ? body.children : [body]
          transformed = []

          in_private = false
          children.each do |child|
            next unless child

            # Skip private keyword
            if child.type == :send && child.children[0].nil? && child.children[1] == :private
              in_private = true
              next
            end

            # Skip before_action declarations (we've collected them)
            if child.type == :send && child.children[0].nil? && child.children[1] == :before_action
              next
            end

            # Skip private methods (we've collected them for inlining)
            if in_private && child.type == :def
              next
            end

            # Transform public action methods
            if child.type == :def && !in_private
              transformed << transform_action_method(child)
            else
              # Pass through other nodes (class-level code, etc.)
              transformed << process(child)
            end
          end

          transformed.length == 1 ? transformed.first : s(:begin, *transformed)
        end

        def transform_action_method(node)
          method_name = node.children[0]
          @rails_current_action = method_name
          args = node.children[1]
          body = node.children[2]

          # Collect params keys accessed in the method body (e.g., params[:article_id])
          params_keys = collect_params_keys(body)

          # Also collect params keys from before_action methods
          @rails_before_actions.each do |ba|
            should_run = if ba[:only]
                           ba[:only].include?(method_name)
                         elsif ba[:except]
                           !ba[:except].include?(method_name)
                         else
                           true
                         end

            if should_run
              method_node = @rails_private_methods[ba[:method]]
              if method_node
                # Note: use push(*arr) for JS compatibility (concat returns new array in JS)
                params_keys.push(*collect_params_keys(method_node.children[2]))
              end
            end
          end

          params_keys = params_keys.uniq

          # Collect instance variables from body AND before_action methods
          ivars = collect_instance_variables(body)

          # Also collect ivars from before_action methods that apply to this action
          @rails_before_actions.each do |ba|
            should_run = if ba[:only]
                           ba[:only].include?(method_name)
                         elsif ba[:except]
                           !ba[:except].include?(method_name)
                         else
                           true
                         end

            if should_run
              method_node = @rails_private_methods[ba[:method]]
              if method_node
                before_ivars = collect_instance_variables(method_node.children[2])
                # Note: use push(*arr) for JS compatibility (concat returns new array in JS)
                ivars.push(*before_ivars)
              end
            end
          end

          ivars = ivars.uniq.sort

          # Transform body: @ivar -> ivar (local variable)
          transformed_body = transform_ivars_to_locals(body)

          # Prepend before_action code
          before_code = generate_before_action_code(method_name)

          # Generate view call
          view_call = generate_view_call(method_name, ivars)
          @rails_needs_views = true if view_call

          # Build method body - flatten any :begin nodes
          # Note: use push(*arr) instead of concat for JS compatibility (JS concat returns new array)
          body_statements = []
          body_statements.push(*before_code) if before_code.any?

          if transformed_body
            if transformed_body.type == :begin
              body_statements.push(*transformed_body.children)
            else
              body_statements.push(transformed_body)
            end
          end

          # Preload associations for show/edit actions (async database support)
          # For each ivar that's a model, preload its has_many associations
          if %i[show edit].include?(method_name) && view_call
            preloads = generate_association_preloads(ivars)
            body_statements.push(*preloads) if preloads.any?
          end

          body_statements.push(view_call) if view_call

          # Wrap in autoreturn for implicit return behavior
          final_body = if body_statements.empty?
                         s(:autoreturn, s(:nil))
                       else
                         s(:autoreturn, *body_statements.compact)
                       end

          # Rename actions to avoid conflicts:
          # - 'new' is a JS reserved word -> 'new!' (converter handles via jsvar -> $new)
          # - 'index' conflicts with Functions filter (index -> indexOf) -> 'index!' (bang stripped by converter)
          output_name = case method_name
                        when :new then :new!
                        when :index then :index!
                        else method_name
                        end

          # Build method parameters from:
          # 0. Context (always first - contains flash, contentFor, params, request)
          # 1. Any extra params[:key] accesses (like article_id for nested resources)
          # 2. Standard RESTful params (id for show/edit/destroy, params for create/update)
          param_args = [s(:arg, :context)]

          # Add extra params keys found in method body (like article_id for nested resources)
          # Exclude :id because it's handled by standard RESTful routing
          # Note: use filter instead of - for JS array compatibility
          extra_params = params_keys.select { |k| k != :id }
          # Note: use push instead of << for JS compatibility
          extra_params.sort.each do |key|
            param_args.push(s(:arg, key))
          end

          # Add standard params based on action type
          # Note: use push instead of << for JS compatibility
          case method_name
          when :show, :edit, :destroy
            param_args.push(s(:arg, :id))
          when :update
            param_args.push(s(:arg, :id))
            param_args.push(s(:arg, :params))
          when :create
            param_args.push(s(:arg, :params))
          end

          output_args = s(:args, *param_args)

          # Create async class method (asyncs with self for async/await support)
          result = s(:asyncs, s(:self), output_name, output_args, final_body)
          @rails_current_action = nil
          result
        end

        def collect_instance_variables(node)
          # Note: use Array instead of Set for JS compatibility (Set.to_a polyfill doesn't work for Sets)
          ivars = []
          collect_ivars_recursive(node, ivars)
          ivars.uniq.sort
        end

        def collect_ivars_recursive(node, ivars)
          return unless node.respond_to?(:type) && node.respond_to?(:children)

          # Note: use .push() for JS compatibility
          if node.type == :ivasgn
            ivars.push(node.children[0].to_s.sub(/^@/, '').to_sym)
          elsif node.type == :ivar
            ivars.push(node.children[0].to_s.sub(/^@/, '').to_sym)
          end

          node.children.each { |child| collect_ivars_recursive(child, ivars) }
        end

        # Collect params[:key] accesses to determine method parameters
        def collect_params_keys(node)
          keys = []
          collect_params_keys_recursive(node, keys)
          keys
        end

        def collect_params_keys_recursive(node, keys)
          return unless node.respond_to?(:type) && node.respond_to?(:children)

          # Match params[:key] pattern
          if node.type == :send
            target, method, *args = node.children
            # Note: use args[0] instead of args.first for JS compatibility
            first_arg = args[0]

            if target&.type == :send &&
               target.children[0].nil? &&
               target.children[1] == :params &&
               method == :[] &&
               first_arg&.type == :sym
              keys << first_arg.children[0]
            end
          end

          node.children.each { |child| collect_params_keys_recursive(child, keys) }
        end

        def transform_ivars_to_locals(node)
          # Note: explicit returns for JS compatibility (case-as-expression doesn't transpile well)
          return node unless node.respond_to?(:type)

          case node.type
          when :ivasgn
            # @articles = x -> articles = x
            # Note: use unique var names per case to avoid JS temporal dead zone in switch
            asgn_name = node.children[0].to_s.sub(/^@/, '').to_sym
            asgn_value = transform_ivars_to_locals(node.children[1])
            return s(:lvasgn, asgn_name, asgn_value)

          when :ivar
            # @articles -> articles
            ref_name = node.children[0].to_s.sub(/^@/, '').to_sym
            return s(:lvar, ref_name)

          when :send
            # Check for redirect_to, render, params, and strong params
            target, method, *args = node.children

            if target.nil? && method == :redirect_to
              return transform_redirect_to(args)
            elsif target.nil? && method == :render
              return transform_render(args)
            elsif target&.type == :send &&
                  target.children[0].nil? &&
                  target.children[1] == :params &&
                  method == :[]
              # params[:id] -> id (method parameter)
              if args.first&.type == :sym
                return s(:lvar, args.first.children[0])
              else
                return node
              end
            elsif target&.type == :send &&
                  target.children[0].nil? &&
                  target.children[1] == :params &&
                  method == :expect
              # Rails 8 params.expect - two forms:
              # params.expect("id") or params.expect(:id) -> id (use method parameter)
              # params.expect({article: ["title", "body"]}) -> params (strong params)
              arg = args.first
              if arg&.type == :str || arg&.type == :sym
                # params.expect("id") -> id
                return s(:lvar, arg.children[0].to_sym)
              elsif arg&.type == :hash
                # params.expect({article: [...]}) -> params
                return s(:lvar, :params)
              else
                return node
              end
            elsif target.nil? && method.to_s.end_with?('_params')
              # article_params -> inline the method body (strong params)
              return transform_strong_params_call(method)
            elsif strong_params_chain?(node)
              # params.require(:article).permit(:title, :body) -> params
              return s(:lvar, :params)
            else
              # Process children recursively first
              new_children = node.children.map do |c|
                c.respond_to?(:type) ? transform_ivars_to_locals(c) : c
              end
              transformed = node.updated(nil, new_children)

              # Wrap model operations with await
              return wrap_with_await_if_needed(transformed)
            end

          when :block
            # Handle respond_to blocks - extract just the format.html body
            send_node = node.children[0]
            if send_node&.type == :send &&
               send_node.children[0].nil? &&
               send_node.children[1] == :respond_to
              # This is a respond_to block - extract and simplify
              block_body = node.children[2]
              return transform_respond_to_block(block_body)
            else
              # Regular block - transform children
              new_children = node.children.map do |c|
                c.respond_to?(:type) ? transform_ivars_to_locals(c) : c
              end
              return node.updated(nil, new_children)
            end

          else
            if node.children.any?
              new_children = node.children.map do |c|
                c.respond_to?(:type) ? transform_ivars_to_locals(c) : c
              end
              return node.updated(nil, new_children)
            else
              return node
            end
          end
        end

        # Transform respond_to block body - handles format.html and format.turbo_stream
        # When both are present, generates Accept header check for content negotiation
        def transform_respond_to_block(node)
          return node unless node.respond_to?(:type)

          case node.type
          when :if
            # if condition; format.html {...}; else; format.html {...}; end
            condition = transform_ivars_to_locals(node.children[0])
            then_branch = transform_respond_to_block(node.children[1])
            else_branch = node.children[2] ? transform_respond_to_block(node.children[2]) : nil

            # Wrap the condition with await if it's a model operation
            if condition.type == :send
              condition = wrap_with_await_if_needed(condition)
            end

            return s(:if, condition, then_branch, else_branch)

          when :begin
            # Multiple statements - collect format.html and format.turbo_stream blocks
            html_block = nil
            turbo_stream_block = nil
            turbo_stream_template = false  # format.turbo_stream without block

            node.children.each do |child|
              if child.type == :block
                block_send = child.children[0]
                if block_send&.type == :send
                  receiver = block_send.children[0]
                  method = block_send.children[1]
                  if receiver&.type == :lvar
                    if method == :html
                      html_block = child.children[2]
                    elsif method == :turbo_stream
                      turbo_stream_block = child.children[2]
                    end
                  end
                end
              elsif child.type == :send
                # format.turbo_stream without block - render template
                receiver = child.children[0]
                method = child.children[1]
                if receiver&.type == :lvar && method == :turbo_stream
                  turbo_stream_template = true
                end
              end
            end

            # If turbo_stream template render is needed (no block), generate template call
            if turbo_stream_template && html_block
              return generate_format_conditional_with_template(html_block)
            elsif turbo_stream_template
              return generate_turbo_stream_template_render
            end

            # If both formats present, generate Accept header conditional
            if html_block && turbo_stream_block
              return generate_format_conditional(html_block, turbo_stream_block)
            elsif html_block
              return transform_ivars_to_locals(html_block)
            elsif turbo_stream_block
              # Only turbo_stream - return it directly
              return transform_ivars_to_locals(turbo_stream_block)
            end

            # No format blocks found - transform all children
            new_children = node.children.map { |c| transform_respond_to_block(c) }
            return s(:begin, *new_children)

          when :block
            # Single format block - check if it's format.html or format.turbo_stream
            block_send = node.children[0]
            if block_send&.type == :send
              receiver = block_send.children[0]
              method = block_send.children[1]
              if receiver&.type == :lvar && (method == :html || method == :turbo_stream)
                return transform_ivars_to_locals(node.children[2])
              end
            end
            # Not a format block - transform normally
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? transform_ivars_to_locals(c) : c
            end
            return node.updated(nil, new_children)

          else
            return transform_ivars_to_locals(node)
          end
        end

        # Generate conditional for Turbo Stream content negotiation
        # Checks Accept header for 'text/vnd.turbo-stream.html'
        def generate_format_conditional(html_block, turbo_stream_block)
          # Build: const accept = context.request.headers.accept || '';
          #        if (accept.includes('text/vnd.turbo-stream.html')) { ... } else { ... }
          # Use :attr for property access instead of :send for method calls
          accept_var = s(:lvasgn, :accept,
            s(:or,
              s(:attr,
                s(:attr,
                  s(:attr, s(:lvar, :context), :request),
                  :headers),
                :accept),
              s(:str, '')))

          condition = s(:send,
            s(:lvar, :accept),
            :includes,
            s(:str, 'text/vnd.turbo-stream.html'))

          turbo_branch = transform_ivars_to_locals(turbo_stream_block)
          html_branch = transform_ivars_to_locals(html_block)

          s(:begin,
            accept_var,
            s(:if, condition, turbo_branch, html_branch))
        end

        # Generate format conditional when format.turbo_stream is a template render (no block)
        # Checks Accept header and returns turbo_stream response or html response
        # Uses ternary to ensure proper return behavior (bare hash literals in if/else
        # are misinterpreted as labeled blocks in JS)
        def generate_format_conditional_with_template(html_block)
          @rails_needs_turbo_stream_views = true

          # Build: (context.request.headers.accept || '').includes('text/vnd.turbo-stream.html')
          #        ? { turbo_stream: ... } : html_response
          accept_check = s(:send,
            s(:begin,
              s(:or,
                s(:attr,
                  s(:attr,
                    s(:attr, s(:lvar, :context), :request),
                    :headers),
                  :accept),
                s(:str, ''))),
            :includes,
            s(:str, 'text/vnd.turbo-stream.html'))

          turbo_branch = generate_turbo_stream_template_render
          html_branch = transform_ivars_to_locals(html_block)

          # Use ternary for proper expression context
          s(:if, accept_check, turbo_branch, html_branch)
        end

        # Generate turbo_stream template render call
        # Returns: { turbo_stream: MessageTurboStreams.create({$context: context, message}) }
        def generate_turbo_stream_template_render
          @rails_needs_turbo_stream_views = true

          model_name = @rails_controller_name.downcase.to_sym
          view_module = "#{@rails_controller_name}TurboStreams"
          action = @rails_current_action

          # Build view call: MessageTurboStreams.create({$context: context, message})
          s(:hash,
            s(:pair, s(:sym, :turbo_stream),
              s(:send,
                s(:const, nil, view_module.to_sym),
                action,
                s(:hash,
                  s(:pair, s(:sym, :"$context"), s(:lvar, :context)),
                  s(:pair, s(:sym, model_name), s(:lvar, model_name))))))
        end

        # Wrap ActiveRecord operations with await for async database support
        def wrap_with_await_if_needed(node)
          return node unless node.type == :send

          target, method, *_args = node.children

          # Check for class method calls on model constants (e.g., Article.find)
          if target&.type == :const && target.children[0].nil?
            const_name = target.children[1].to_s
            # Convert Set to Array for JS compatibility (Set.include? doesn't exist in JS)
            model_refs_array = @rails_model_refs ? [*@rails_model_refs] : []
            if model_refs_array.include?(const_name) && AR_CLASS_METHODS.include?(method)
              # Use updated(:await!) to force parens (method call, not property access)
              return node.updated(:await!)
            end
          end

          # Check for chained method calls ending with an AR class method
          # e.g., Article.includes(:comments).all, Article.where(...).first
          if target&.type == :send && AR_CLASS_METHODS.include?(method)
            # Walk up the chain to find the root target
            chain_start = target
            while chain_start&.type == :send
              chain_start = chain_start.children[0]
            end
            # If chain starts with a model constant, await the whole thing
            if chain_start&.type == :const && chain_start.children[0].nil?
              const_name = chain_start.children[1].to_s
              model_refs_array = @rails_model_refs ? [*@rails_model_refs] : []
              if model_refs_array.include?(const_name)
                return node.updated(:await!)
              end
            end
          end

          # Check for instance method calls on local variables (e.g., article.save)
          if target&.type == :lvar && AR_INSTANCE_METHODS.include?(method)
            return node.updated(:await!)
          end

          # Check for association method chains (e.g., article.comments.find(id), article.comments.create(params))
          # These are: lvar.accessor.method where method is :find or :create
          if target&.type == :send && %i[find create].include?(method)
            assoc_target, _assoc_method = target.children
            # If the chain starts from a local variable (e.g., article.comments.find)
            if assoc_target&.type == :lvar
              return node.updated(:await)
            end
          end

          node
        end

        def transform_redirect_to(args)
          return s(:hash, s(:pair, s(:sym, :redirect), s(:str, '/'))) if args.empty?

          # Note: use args[0] instead of args.first for JS compatibility
          target = args[0]

          # Extract notice from options hash (second argument)
          notice_node = nil
          if args.length > 1 && args[1]&.type == :hash
            args[1].children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym && key.children[0] == :notice
                notice_node = value
              end
            end
          end

          # Note: avoid case-as-expression for JS compatibility (doesn't transpile correctly)
          path = nil
          if target.type == :ivar
            # redirect_to @article -> "/articles/#{article.id}"
            ivar_name = target.children[0].to_s.sub(/^@/, '')
            resource = ivar_name.downcase
            path = s(:dstr,
              s(:str, "/#{resource}s/"),
              s(:begin, s(:attr, s(:lvar, ivar_name.to_sym), :id)))
          elsif target.type == :send
            # redirect_to articles_path -> "/articles"
            if target.children[0].nil? && target.children[1].to_s.end_with?('_path')
              path_helper = target.children[1].to_s
              if path_helper =~ /^(\w+)_path$/
                # Path helper name already contains the pluralized resource name
                # e.g., messages_path -> /messages, articles_path -> /articles
                path = s(:str, "/#{$1}")
              else
                path = s(:str, '/')
              end
            else
              path = transform_ivars_to_locals(target)
            end
          else
            path = transform_ivars_to_locals(target)
          end

          # Build result hash with redirect and optional notice
          pairs = [s(:pair, s(:sym, :redirect), path)]
          if notice_node
            pairs << s(:pair, s(:sym, :notice), notice_node)
          end

          s(:hash, *pairs)
        end

        def transform_render(args)
          return nil if args.empty?

          target = args.first

          if target.type == :sym
            # render :new -> ArticleViews.$new({$context: context, article})
            # Call the view directly with the model (including validation errors)
            action = target.children[0]
            model_name = @rails_controller_name.downcase.to_sym
            view_module = "#{@rails_controller_name}Views"

            # Use $new for reserved word (matches view module export)
            view_action = action == :new ? :$new : action

            # Build view call with unified props: ArticleViews.$new({$context: context, article})
            s(:hash,
              s(:pair, s(:sym, :render),
                s(:send,
                  s(:const, nil, view_module.to_sym),
                  view_action,
                  s(:hash,
                    s(:pair, s(:sym, :"$context"), s(:lvar, :context)),
                    s(:pair, s(:sym, model_name), s(:lvar, model_name))))))
          else
            # More complex render - pass through for now
            nil
          end
        end

        # Generate association preloads for async database support
        # For show/edit actions, preload has_many associations so views can iterate
        def generate_association_preloads(ivars)
          preloads = []

          # Infer model name from controller name (ArticlesController -> Article)
          model_name = @rails_controller_name.to_s.sub(/Controller$/, '')
          singular_model = Ruby2JS::Inflector.singularize(model_name).downcase.to_sym

          # If we have a singular model variable (e.g., :article), preload its associations
          if ivars.include?(singular_model)
            # Look up associations for this model from tracked has_many relationships
            associations = model_associations[singular_model] || []

            associations.each do |assoc_name|
              # Generate: article.comments = await article.comments
              # The getter returns a Promise, so await it and store back via setter
              # Note: await is s(:send, nil, :await, expr) not s(:await, expr)
              await_expr = s(:send, nil, :await, s(:attr, s(:lvar, singular_model), assoc_name))
              preloads << s(:send,
                s(:lvar, singular_model),
                "#{assoc_name}=".to_sym,
                await_expr)
            end
          end

          preloads
        end

        def generate_before_action_code(action_name)
          statements = []

          @rails_before_actions.each do |ba|
            # Check if this action should run the before_action
            should_run = if ba[:only]
                           ba[:only].include?(action_name)
                         elsif ba[:except]
                           !ba[:except].include?(action_name)
                         else
                           true
                         end

            next unless should_run

            # Get the private method body
            method_node = @rails_private_methods[ba[:method]]
            if method_node
              # Inline the method body, transforming ivars
              inlined = transform_ivars_to_locals(method_node.children[2])

              # Handle params[:id] -> id (use the method parameter)
              inlined = transform_params_id(inlined)

              statements << inlined if inlined
            end
          end

          statements.compact
        end

        def transform_params_id(node)
          return node unless node.respond_to?(:type)

          if node.type == :send
            target, method, *args = node.children

            # params[:id] -> id
            if target&.type == :send &&
               target.children[0].nil? &&
               target.children[1] == :params &&
               method == :[] &&
               args.first&.type == :sym &&
               args.first.children[0] == :id
              return s(:lvar, :id)
            end
          end

          if node.children.any?
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? transform_params_id(c) : c
            end
            node.updated(nil, new_children)
          else
            node
          end
        end

        def generate_view_call(action_name, ivars)
          return nil if ivars.empty? && %i[create update destroy].include?(action_name)

          # Skip view call for actions that return redirect/render hashes
          return nil if %i[create update destroy].include?(action_name)

          view_module = "#{@rails_controller_name}Views"
          # Use $new for reserved word (matches view module export)
          # Use index! to avoid Functions filter collision (bang stripped)
          view_action = case action_name
                        when :new then :$new
                        when :index then :index!
                        else action_name
                        end

          # Build unified props hash: { $context: context, articles }
          pairs = [s(:pair, s(:sym, :"$context"), s(:lvar, :context))]
          ivars.each do |ivar|
            pairs << s(:pair, s(:sym, ivar), s(:lvar, ivar))
          end

          # Pass single props object with $context and locals
          s(:send,
            s(:const, nil, view_module.to_sym),
            view_action,
            s(:hash, *pairs))
        end

        def collect_model_references(node)
          return unless node.respond_to?(:type) && node.respond_to?(:children)

          # Look for constant references that look like model names (capitalized, no namespace)
          if node.type == :const && node.children[0].nil?
            const_name = node.children[1].to_s
            # Skip known non-model constants
            # Note: use .add() for JS Set compatibility (Ruby Set supports both << and add)
            unless %w[ApplicationController].include?(const_name) || const_name.end_with?('Controller', 'Views')
              @rails_model_refs.add(const_name)
            end
          end

          node.children.each { |child| collect_model_references(child) }
        end

        def generate_imports
          imports = []

          # Import each referenced model
          [*@rails_model_refs].sort.each do |model|
            model_file = model.downcase
            imports << s(:send, nil, :import,
              s(:array, s(:const, nil, model.to_sym)),
              s(:str, "../models/#{model_file}.js"))
          end

          # Import the view module only if views are used
          if @rails_needs_views
            view_module = "#{@rails_controller_name}Views"
            imports << s(:send, nil, :import,
              s(:array, s(:const, nil, view_module.to_sym)),
              s(:str, "../views/#{@rails_controller_plural}.js"))
          end

          # Import turbo stream views if needed
          if @rails_needs_turbo_stream_views
            turbo_module = "#{@rails_controller_name}TurboStreams"
            imports << s(:send, nil, :import,
              s(:array, s(:const, nil, turbo_module.to_sym)),
              s(:str, "../views/#{@rails_controller_plural}_turbo_streams.js"))
          end

          imports
        end

        # Transform article_params call by inlining and transforming
        def transform_strong_params_call(method_name)
          method_node = @rails_private_methods[method_name]
          if method_node
            body = method_node.children[2]
            transform_ivars_to_locals(body)
          else
            # If we can't find the method, just return params
            s(:lvar, :params)
          end
        end

        # Detect params.require(:x).permit(:a, :b) chain
        def strong_params_chain?(node)
          return false unless node.respond_to?(:type) && node.type == :send

          target, method, *_args = node.children

          # Check for .permit(...) at the end
          return false unless method == :permit

          # Check target is .require(...) on params
          return false unless target&.type == :send
          require_target, require_method, *_require_args = target.children
          return false unless require_method == :require

          # Check that require is called on params
          return false unless require_target&.type == :send
          params_target, params_method = require_target.children
          params_target.nil? && params_method == :params
        end
      end
    end

    DEFAULTS.push Rails::Controller
  end
end
