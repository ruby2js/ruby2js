require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Model
        include SEXP

        # Callback types we support
        CALLBACKS = %i[
          before_validation after_validation
          before_save after_save
          before_create after_create
          before_update after_update
          before_destroy after_destroy
          after_commit
          after_create_commit after_update_commit after_destroy_commit after_save_commit
          after_touch
        ].freeze

        # Turbo broadcast methods
        BROADCAST_METHODS = %i[
          broadcast_replace_to broadcast_replace_later_to
          broadcast_append_to broadcast_append_later_to
          broadcast_prepend_to broadcast_prepend_later_to
          broadcast_update_to broadcast_update_later_to
          broadcast_remove_to broadcast_remove_later_to
          broadcast_before_to broadcast_after_to
          broadcast_json_to
        ].freeze

        # Map broadcast methods to their turbo-stream actions
        BROADCAST_TO_ACTION = {
          broadcast_replace_to: :replace,
          broadcast_replace_later_to: :replace,
          broadcast_append_to: :append,
          broadcast_append_later_to: :append,
          broadcast_prepend_to: :prepend,
          broadcast_prepend_later_to: :prepend,
          broadcast_update_to: :update,
          broadcast_update_later_to: :update,
          broadcast_remove_to: :remove,
          broadcast_remove_later_to: :remove,
          broadcast_before_to: :before,
          broadcast_after_to: :after
        }.freeze

        # ActiveRecord class methods that need self. prefix when called
        # bare inside class methods (def self.X)
        AR_CLASS_METHODS = %i[
          create create! new build
          find find_by find_by! find_each find_in_batches find_or_create_by
          find_or_create_by! find_or_initialize_by find_sole_by
          where all first last take count sum average minimum maximum
          exists? any? none? many? one?
          order group limit offset select distinct joins includes
          left_outer_joins preload eager_load
          pluck pick ids
          destroy_all delete_all update_all
          transaction
        ].freeze

        def initialize(*args)
          # Note: super must come first for JS compatibility (derived class constructor rule)
          super
          @rails_model = nil
          @rails_model_name = nil
          @rails_model_class_name = nil
          @rails_model_processing = false
          @rails_associations = []
          @rails_validations = []
          # Note: use plain hash for JS compatibility (Hash.new with block doesn't transpile)
          @rails_callbacks = {}
          @rails_scopes = []
          @rails_enums = []
          @rails_broadcasts_to = []  # broadcasts_to declarations
          @rails_attachments = []    # Active Storage attachments
          @rails_nested_attributes = []  # accepts_nested_attributes_for declarations
          @rails_url_helpers = false  # include Rails.application.routes.url_helpers
          @rails_model_private_methods = {}
          @rails_model_refs = Set.new
          @in_callback_block = false  # Track when processing callback body
          @uses_broadcast = false  # Track if model uses broadcast methods
          @inside_class_method = false  # Track when inside def self.X
        end

        # Detect model class and transform
        def on_class(node)
          class_name, superclass, body = node.children

          # Always create fresh Set for each class
          @rails_model_refs = Set.new

          # Skip if already processing (prevent infinite recursion)
          return super if @rails_model_processing

          # Check if this is an ActiveRecord model
          unless model_class?(class_name, superclass)
            # Handle CurrentAttributes: prefix bare attribute refs with self.
            if !@current_attrs_processing && current_attributes_class?(superclass) && body
              attr_names = collect_current_attribute_names(body)
              unless attr_names.empty?
                @current_attrs_processing = true
                new_body = rewrite_current_attributes_body(body, attr_names)
                result = process(node.updated(nil, [class_name, superclass, new_body]))
                @current_attrs_processing = false
                return result
              end
            end

            # For non-model classes, still handle include Rails.application.routes.url_helpers
            if body && body_has_url_helpers_include?(body)
              new_body = strip_url_helpers_include(body)
              new_class = node.updated(nil, [class_name, superclass, new_body])
              url_helpers_import = s(:send, nil, :import,
                s(:array,
                  s(:const, nil, :polymorphic_url),
                  s(:const, nil, :polymorphic_path)),
                s(:str, "juntos:url-helpers"))
              return process(s(:begin, url_helpers_import, new_class))
            end
            return super
          end

          @rails_model_name = class_name.children.last.to_s
          @rails_model_class_name = class_name
          @rails_model = true
          @rails_model_processing = true

          # First pass: collect DSL declarations
          collect_model_metadata(body)

          # Record metadata for cross-file filter context (test filter reads this)
          record_model_metadata

          # Second pass: transform body
          transformed_body = transform_model_body(body)

          # Build the exported class
          # For namespaced classes like Identity::AccessToken, use just the leaf name
          # for export. JS doesn't support `export X.Y = class`, only `export class Y`.
          export_class_name = class_name.children.first ?
            s(:const, nil, class_name.children.last) : class_name
          exported_class = s(:send, nil, :export,
            node.updated(nil, [export_class_name, superclass, transformed_body]))

          # Generate import for superclass (ApplicationRecord or ActiveRecord::Base)
          superclass_name = superclass.children.last.to_s
          superclass_file = superclass_name.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')

          # Check if model has has_many associations (need CollectionProxy)
          has_has_many = @rails_associations.any? { |a| a[:type] == :has_many }
          has_belongs_to = @rails_associations.any? { |a| a[:type] == :belongs_to }
          has_has_one = @rails_associations.any? { |a| a[:type] == :has_one }
          has_associations = @rails_associations.any?

          # Build import list: always include superclass, add CollectionProxy/modelRegistry if needed
          import_list = [s(:const, nil, superclass_name.to_sym)]
          import_list.push(s(:const, nil, :CollectionProxy)) if has_has_many
          import_list.push(s(:const, nil, :modelRegistry)) if has_associations
          import_list.push(s(:const, nil, :Reference)) if has_belongs_to
          import_list.push(s(:const, nil, :HasOneReference)) if has_has_one

          import_node = s(:send, nil, :import,
            s(:array, *import_list),
            s(:str, "./#{superclass_file}.js"))

          # No cross-model imports needed — association methods use modelRegistry
          # for lazy resolution, avoiding circular dependencies
          model_import_nodes = []

          # Check if model uses broadcast methods (for BroadcastChannel import)
          # Include both explicit broadcast_*_to calls and broadcasts_to declarations
          uses_broadcast = body_uses_broadcasts?(body) || @rails_broadcasts_to.any?
          if uses_broadcast
            broadcast_import = s(:send, nil, :import,
              s(:array, s(:const, nil, :BroadcastChannel)),
              s(:str, "../../lib/rails.js"))
            model_import_nodes.push(broadcast_import)

            # Collect and import broadcast partials
            # Includes both explicit broadcast_*_to partials and inferred broadcasts_to partial
            partials = collect_broadcast_partials(body)

            # Add inferred partial from broadcasts_to (model name -> model partial)
            # Article with broadcasts_to -> articles/article partial
            if @rails_broadcasts_to.any?
              model_name_lower = @rails_model_name.downcase
              model_partial = "#{Ruby2JS::Inflector.pluralize(model_name_lower)}/#{model_name_lower}"
              partials << model_partial unless partials.include?(model_partial)
            end

            if partials.length > 0
              partial_path = partials.first
              # Build path: messages/message -> ../views/messages/_message.js
              parts = partial_path.split('/')
              partial_file = "_#{parts.last}.js"
              partial_dir = parts[0..-2].join('/')
              import_path = "../views/#{partial_dir}/#{partial_file}"

              # Import { render } from "..."
              partial_import = s(:send, nil, :import,
                s(:array, s(:const, nil, :render)),
                s(:str, import_path))
              model_import_nodes.push(partial_import)
            end
          end

          # Check if model uses Active Storage (for hasOneAttached/hasManyAttached import)
          if @rails_attachments.any?
            active_storage_import = s(:send, nil, :import,
              s(:array,
                s(:const, nil, :hasOneAttached),
                s(:const, nil, :hasManyAttached)),
              s(:str, "juntos:active-storage"))
            model_import_nodes.push(active_storage_import)
          end

          # Check if model includes url_helpers (for polymorphic_url/polymorphic_path import)
          if @rails_url_helpers
            url_helpers_import = s(:send, nil, :import,
              s(:array,
                s(:const, nil, :polymorphic_url),
                s(:const, nil, :polymorphic_path)),
              s(:str, "juntos:url-helpers"))
            model_import_nodes.push(url_helpers_import)
          end

          # Add Model.renderPartial = render assignment so broadcast_replace_to
          # can use the partial at runtime when called from other models
          render_partial_assignment = nil
          if @rails_broadcasts_to.any?
            render_partial_assignment = s(:send,
              s(:const, nil, @rails_model_name.to_sym),
              :renderPartial=,
              s(:lvar, :render))
          end

          begin_node = if render_partial_assignment
            s(:begin, import_node, *model_import_nodes, exported_class, render_partial_assignment)
          else
            s(:begin, import_node, *model_import_nodes, exported_class)
          end
          result = process(begin_node)
          # Set empty comments on processed begin node to prevent first-location lookup
          # from incorrectly inheriting comments from child nodes
          @comments.set(result, [])

          @rails_model = nil
          @rails_model_name = nil
          @rails_model_class_name = nil
          @rails_model_processing = false
          @rails_associations = []
          @rails_validations = []
          # Note: use plain hash for JS compatibility (Hash.new with block doesn't transpile)
          @rails_callbacks = {}
          @rails_scopes = []
          @rails_enums = []
          @rails_broadcasts_to = []
          @rails_attachments = []
          @rails_nested_attributes = []
          @rails_url_helpers = false
          @rails_model_private_methods = {}
          @rails_model_refs = Set.new

          result
        end

        # Handle callback blocks (after_create_commit do ... end)
        # Transform to accept record parameter: (record) => { ... }
        # If associations are accessed, generates async callback with await
        def on_block(node)
          send_node, args_node, body = node.children
          return super unless send_node&.type == :send

          target, method = send_node.children
          return super unless target.nil?
          return super unless CALLBACKS.include?(method)
          return super unless @rails_model

          # Transform the callback body to use 'record' parameter
          # Replace: self -> record, id -> record.id, etc.
          # Track if any associations are accessed (they're async)
          @callback_uses_associations = false
          transformed_body = transform_callback_body(body)
          uses_associations = @callback_uses_associations

          # Set flag so broadcast methods know to use 'record' instead of 'this'
          @in_callback_block = true
          processed_body = process(transformed_body)
          @in_callback_block = false

          # Preserve original body's location for comment re-association
          if body && body.loc && processed_body.respond_to?(:updated)
            processed_body = body.updated(processed_body.type, processed_body.children)
          end

          # Generate callback - async if associations are accessed
          if uses_associations
            # Generate: ClassName.callback_method(async ($record) => { ... })
            s(:send,
              s(:const, nil, @rails_model_name.to_sym),
              method,
              s(:block,
                s(:send, nil, :async),
                s(:args, s(:arg, :"$record")),
                processed_body))
          else
            # Generate: ClassName.callback_method(($record) => { ... })
            s(:send,
              s(:const, nil, @rails_model_name.to_sym),
              method,
              s(:block,
                s(:send, nil, :proc),
                s(:args, s(:arg, :"$record")),
                processed_body))
          end
        end

        # Track when inside a class method (def self.X) so bare class method
        # calls like `create(...)` get prefixed with `self.` → `this.create(...)`
        def on_defs(node)
          return super unless @rails_model

          @inside_class_method = true
          result = super
          @inside_class_method = false
          result
        end

        # Handle broadcast_*_to method calls and enum predicates/mutators inside model
        def on_send(node)
          target, method, *args = node.children

          # --- AR method renames (run regardless of model context) ---

          # any? on AR chains: rename to :any so functions filter doesn't
          # convert to .length > 0 (which breaks on Relation objects).
          # Use :send! to force parens (.any() not .any property access).
          if method == :any? && args.empty? && target&.type == :send
            chain_start = target
            chain_start = chain_start.children[0] while chain_start&.type == :send
            if chain_start&.type == :const
              return process s(:send!, target, :any)
            end
          end

          # find_by! → findByBang: preserve "raise on not found" semantics.
          # The converter strips ! from method names, losing the distinction.
          if method == :find_by!
            return process s(:send!, target, :findByBang, *args)
          end

          # Only handle remaining transforms when processing a model
          return super unless @rails_model

          # Only handle unqualified (implicit self) calls
          return super unless target.nil?

          # Inline-transform enum predicate and bang calls
          if @rails_enums.any?
            method_str = method.to_s
            if method_str.end_with?('?') || method_str.end_with?('!')
              base = method_str[0..-2]
              @rails_enums.each do |enum_data|
                prefix = enum_data[:options][:prefix]
                enum_vals = enum_data[:values]
                # Note: use keys loop for JS compatibility
                enum_vals.keys.each do |name|
                  val = enum_vals[name]
                  method_name = prefix ? "#{prefix}_#{name}" : name
                  if base == method_name
                    if method_str.end_with?('?')
                      # published? → this.status === "published"
                      return s(:send, s(:attr, s(:self), enum_data[:field]), :===, val)
                    else
                      # published! → this.update({status: "published"})
                      return s(:send, s(:self), :update,
                        s(:hash, s(:pair, s(:sym, enum_data[:field]), val)))
                    end
                  end
                end
              end
            end
          end

          # Inside class methods (def self.X), bare calls to AR class methods
          # and scopes need self. prefix: create(...) → self.create(...)
          if @inside_class_method
            scope_names = @rails_scopes.map { |sc| sc[:name] }
            if AR_CLASS_METHODS.include?(method) || scope_names.include?(method)
              return process s(:send, s(:self), method, *args)
            end
          end

          # Check if this is a broadcast method
          return super unless BROADCAST_METHODS.include?(method)

          process_broadcast_call(method, args)
        end

        private

        # Transform callback body to use '$record' parameter instead of self/id
        # Uses $record to avoid conflicts with user-defined 'record' variables
        # Wraps association accesses with await and sets @callback_uses_associations
        def transform_callback_body(node)
          return node unless node.respond_to?(:type)

          case node.type
          when :self
            # self -> $record
            s(:lvar, :"$record")

          when :send
            target, method, *args = node.children

            if target.nil?
              # Bare method call - could be a record attribute/method or broadcast_json_to
              if association_method?(method)
                # Association access - wrap with await: article -> (await $record.article)
                # Use :begin to ensure parentheses when used as receiver for method chain
                @callback_uses_associations = true
                s(:begin,
                  s(:send, nil, :await,
                    s(:attr,
                      s(:lvar, :"$record"),
                      method)))
              elsif instance_method?(method)
                # id, article_id, created_at, etc. -> $record.id, $record.article_id, etc.
                # Use :attr for property access (no parentheses in JS)
                s(:attr,
                  s(:lvar, :"$record"),
                  method)
              elsif method == :broadcast_json_to
                # broadcast_json_to -> $record.broadcast_json_to(...)
                # Add $record receiver - the method is called directly (no HTML transformation)
                # Other turbo-stream broadcast methods are handled by on_send
                s(:send,
                  s(:lvar, :"$record"),
                  method,
                  *args.map { |arg| transform_callback_body(arg) })
              else
                # Keep other bare calls (including turbo-stream broadcast methods)
                # These will be processed by on_send
                node.updated(nil, [target, method, *args.map { |arg| transform_callback_body(arg) }])
              end
            elsif target&.type == :self
              # self.foo -> check if it's an association
              if association_method?(method)
                @callback_uses_associations = true
                s(:begin,
                  s(:send, nil, :await,
                    s(:attr,
                      s(:lvar, :"$record"),
                      method)))
              else
                # self.foo -> $record.foo (property access)
                s(:attr,
                  s(:lvar, :"$record"),
                  method)
              end
            else
              # Recurse into target and args
              node.updated(nil, [
                transform_callback_body(target),
                method,
                *args.map { |arg| transform_callback_body(arg) }
              ])
            end

          when :lvar, :ivar
            # Keep local/instance variables as-is
            node

          else
            # Recurse into children
            return node.updated(nil, node.children.map { |child| transform_callback_body(child) }) if node.children.any?
            node
          end
        end

        # Check if a method name is a known association (async access)
        def association_method?(method)
          method_str = method.to_s
          @rails_associations&.any? { |a| a[:name].to_s == method_str }
        end

        # Check if a method name looks like an instance method (attribute accessor or association)
        def instance_method?(method)
          method_str = method.to_s
          # Common ActiveRecord attribute accessors
          return true if method_str == 'id'
          return true if method_str.end_with?('_id')  # foreign keys
          return true if method_str.end_with?('_at')  # timestamps
          return true if %w[created_at updated_at].include?(method_str)
          # Check if it's a known association name
          return true if association_method?(method)
          false
        end

        # Check if the class body contains any broadcast method calls
        def body_uses_broadcasts?(node)
          return false unless node.respond_to?(:type)

          if node.type == :send
            method = node.children[1]
            return true if BROADCAST_METHODS.include?(method)
          end

          # Recurse into children
          node.children.any? { |child| body_uses_broadcasts?(child) }
        end

        # Collect all broadcast partial paths from the class body (pre-pass)
        def collect_broadcast_partials(node, partials = [])
          return partials unless node.respond_to?(:type)

          if node.type == :send
            method = node.children[1]
            if BROADCAST_METHODS.include?(method)
              args = node.children[2..-1]
              args.each do |arg|
                next unless arg.type == :hash
                arg.children.each do |pair|
                  key_node, value_node = pair.children
                  if key_node.children[0].to_s == 'partial' && value_node.type == :str
                    partials << value_node.children[0]
                  end
                end
              end
            end
          end

          # Recurse into children
          node.children.each { |child| collect_broadcast_partials(child, partials) }
          partials.uniq
        end

        # Process broadcast_*_to method calls
        # Example: broadcast_append_to "article_#{article_id}_comments", partial: "...", target: "comments"
        # Generates: BroadcastChannel.broadcast("channel", `<turbo-stream ...>...</turbo-stream>`)
        def process_broadcast_call(method, args)
          return super if args.empty?

          # Mark that this model uses broadcasting (for import generation)
          @uses_broadcast = true

          # First argument is the channel name
          channel_node = args[0]

          # Get the action from the method name
          action = BROADCAST_TO_ACTION[method]
          return super unless action

          # Extract options from remaining arguments
          target_node = nil
          partial_node = nil
          locals_node = nil

          args[1..-1].each do |arg|
            next unless arg.type == :hash
            arg.children.each do |pair|
              key_node, value_node = pair.children
              key = key_node.children[0].to_s
              case key
              when 'target' then target_node = value_node
              when 'partial' then partial_node = value_node
              when 'locals' then locals_node = value_node
              end
            end
          end

          # For remove action, we only need target
          # For other actions, we need content from partial
          stream_html = build_broadcast_stream_html(action, channel_node, target_node, partial_node, locals_node)

          # Check if this is a _later method (deferred execution)
          is_later = method.to_s.include?('_later')

          # Build the broadcast call
          broadcast_call = s(:send,
            s(:const, nil, :BroadcastChannel),
            :broadcast,
            process(channel_node),
            stream_html)

          if is_later
            # Wrap in setTimeout for _later methods
            s(:send, nil, :setTimeout,
              s(:block,
                s(:send, nil, :proc),
                s(:args),
                broadcast_call),
              s(:int, 0))
          else
            broadcast_call
          end
        end

        # Build the turbo-stream HTML for broadcasting
        def build_broadcast_stream_html(action, channel_node, target_node, partial_node, locals_node)
          # Use '$record' in callbacks, 'this' otherwise
          receiver = @in_callback_block ? s(:lvar, :"$record") : s(:self)

          # For remove action, no template content needed
          if action == :remove
            # If target is static
            if target_node&.type == :str
              target_val = target_node.children[0]
              return s(:str, "<turbo-stream action=\"remove\" target=\"#{target_val}\"></turbo-stream>")
            elsif target_node&.type == :sym
              target_val = target_node.children[0].to_s
              return s(:str, "<turbo-stream action=\"remove\" target=\"#{target_val}\"></turbo-stream>")
            elsif target_node
              # Dynamic target specified - use template literal
              return s(:dstr,
                s(:str, '<turbo-stream action="remove" target="'),
                s(:begin, process(target_node)),
                s(:str, '"></turbo-stream>'))
            else
              # No target specified - use dom_id(self) pattern: model_name_id
              model_prefix = @rails_model_name.downcase
              return s(:dstr,
                s(:str, "<turbo-stream action=\"remove\" target=\"#{model_prefix}_"),
                s(:begin, s(:attr, receiver, :id)),
                s(:str, '"></turbo-stream>'))
            end
          end

          # For other actions, we need to render content
          # If partial is specified, use the compiled partial render function
          # Otherwise fall back to record.toHTML

          content_expr = if partial_node&.type == :str
            # Extract partial path: "messages/message" -> render function call
            partial_path = partial_node.children[0]
            # Track this partial and get its index for function name
            @broadcast_partials ||= []
            partial_index = @broadcast_partials.index(partial_path)
            if partial_index.nil?
              partial_index = @broadcast_partials.length
              @broadcast_partials << partial_path
            end
            render_call = build_partial_render_call(partial_index, locals_node, receiver)
            render_call
          else
            # No partial specified, use toHTML
            s(:send, receiver, :toHTML)
          end

          # Handle target
          target_expr = nil
          if target_node&.type == :str
            target_expr = target_node.children[0]
          elsif target_node&.type == :sym
            target_expr = target_node.children[0].to_s
          end

          if target_expr
            # Static target
            s(:dstr,
              s(:str, "<turbo-stream action=\"#{action}\" target=\"#{target_expr}\"><template>"),
              s(:begin, content_expr),
              s(:str, '</template></turbo-stream>'))
          else
            # Dynamic target
            s(:dstr,
              s(:str, "<turbo-stream action=\"#{action}\" target=\""),
              s(:begin, process(target_node)),
              s(:str, '"><template>'),
              s(:begin, content_expr),
              s(:str, '</template></turbo-stream>'))
          end
        end

        # Build a call to the partial's render function
        def build_partial_render_call(partial_index, locals_node, receiver)
          # Build locals object from locals_node
          # locals: { message: self } -> { message: record }
          locals_hash = if locals_node&.type == :hash
            pairs = locals_node.children.map do |pair|
              key_node, value_node = pair.children
              # Transform the value (self -> record in callbacks)
              transformed_value = if value_node.type == :self
                receiver
              else
                process(value_node)
              end
              s(:pair, key_node, transformed_value)
            end
            s(:hash, *pairs)
          else
            # No locals specified, pass empty object
            s(:hash)
          end

          # Build: render({}, locals)
          s(:send, nil, :render, s(:hash), locals_hash)
        end

        def model_class?(class_name, superclass)
          return false unless class_name&.type == :const
          return false unless superclass&.type == :const

          # Check for ApplicationRecord (simple const)
          superclass_name = superclass.children.last.to_s
          return true if superclass_name == 'ApplicationRecord'

          # Check for ActiveRecord::Base (nested const)
          # AST: s(:const, s(:const, nil, :ActiveRecord), :Base)
          if superclass_name == 'Base'
            parent_const = superclass.children.first
            if parent_const&.type == :const && parent_const.children.last == :ActiveRecord
              return true
            end
          end

          false
        end

        # Check if this is a CurrentAttributes subclass
        def current_attributes_class?(superclass)
          return false unless superclass&.type == :const
          name = superclass.children.last.to_s
          return true if name == 'CurrentAttributes'
          # Check for ActiveSupport::CurrentAttributes or ApplicationRecord::CurrentAttributes
          parent = superclass.children.first
          if parent&.type == :const && name == 'CurrentAttributes'
            return true
          end
          false
        end

        # Collect attribute names from Current.attribute(:session, :user, ...) calls
        def collect_current_attribute_names(body)
          names = []
          children = body.type == :begin ? body.children : [body]
          children.each do |child|
            next unless child&.type == :send
            # attribute :session, :user, :identity, :account
            if child.children[0].nil? && child.children[1] == :attribute
              child.children[2..].each do |arg|
                names.push(arg.children.first) if arg.type == :sym
              end
            end
          end
          names
        end

        # Rewrite bare sends to attribute names as self.name in CurrentAttributes body
        def rewrite_current_attributes_body(body, attr_names)
          children = body.type == :begin ? body.children : [body]
          new_children = children.map do |child|
            rewrite_current_attributes_node(child, attr_names)
          end
          body.type == :begin ? body.updated(nil, new_children) : new_children.first
        end

        def rewrite_current_attributes_node(node, attr_names)
          return node unless node.respond_to?(:type)

          # Rewrite bare sends: s(:send, nil, :account) → s(:send, s(:self), :account)
          if node.type == :send && node.children[0].nil? && attr_names.include?(node.children[1])
            return node.updated(nil, [s(:self), *node.children[1..]])
          end

          # Recurse into children
          new_children = node.children.map do |child|
            if child.respond_to?(:type)
              rewrite_current_attributes_node(child, attr_names)
            else
              child
            end
          end
          node.updated(nil, new_children)
        end

        def collect_model_metadata(body)
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

            # Collect private methods
            if in_private && child.type == :def
              method_name = child.children[0]
              @rails_model_private_methods[method_name] = child
              next
            end

            next unless child.type == :send && child.children[0].nil?

            method_name = child.children[1]
            args = child.children[2..-1]

            case method_name
            when :has_many, :has_one
              collect_association(:has_many, args) if method_name == :has_many
              collect_association(:has_one, args) if method_name == :has_one
            when :belongs_to
              collect_association(:belongs_to, args)
            when :has_one_attached
              collect_attachment(:has_one_attached, args)
            when :has_many_attached
              collect_attachment(:has_many_attached, args)
            when :validates
              collect_validation(args)
            when :scope
              collect_scope(args)
            when :broadcasts_to
              collect_broadcasts_to(args)
            when :enum
              collect_enum(args)
            when :accepts_nested_attributes_for
              collect_nested_attributes(args)
            when :include
              if args.length == 1 && is_url_helpers_include?(args[0])
                @rails_url_helpers = true
              end
            when *CALLBACKS
              collect_callback(method_name, args)
            end
          end
        end

        # Record model metadata into shared options hash for cross-file context.
        # Model metadata is populated during collect_model_metadata and recorded
        # here so that the test filter can make informed await/sync decisions.
        def record_model_metadata
          return unless @options[:metadata] && @rails_model_name

          meta = @options[:metadata]
          # Use string keys for JS object compatibility
          meta['models'] = {} unless meta['models']

          model_meta = {}

          # Association names and types (for awaitable getter detection)
          assocs = []
          @rails_associations.each do |a|
            assocs.push({ 'name' => a[:name].to_s, 'type' => a[:type].to_s })
          end
          model_meta['associations'] = assocs

          # Scope names (zero-arg scopes become getters)
          scope_names = []
          @rails_scopes.each do |s|
            scope_names.push(s[:name].to_s)
          end
          model_meta['scopes'] = scope_names

          # Enum predicate names (synchronous, should NOT be awaited)
          predicates = []
          @rails_enums.each do |e|
            e[:values].each do |v, _val| # Pragma: entries
              predicates.push(v.to_s + '?')
            end
          end
          model_meta['enum_predicates'] = predicates

          # Enum bang setter names (synchronous state transitions)
          bangs = []
          @rails_enums.each do |e|
            e[:values].each do |v, _val| # Pragma: entries
              bangs.push(v.to_s + '!')
            end
          end
          model_meta['enum_bangs'] = bangs

          # File path for import generation in test filter
          model_meta['file'] = @options[:file] if @options[:file]

          meta['models'][@rails_model_name] = model_meta
        end

        # Check if an AST node matches Rails.application.routes.url_helpers
        def is_url_helpers_include?(node)
          node.type == :send &&
            node.children[1] == :url_helpers &&
            node.children[0]&.type == :send &&
            node.children[0].children[1] == :routes
        end

        # Check if class body contains include Rails.application.routes.url_helpers
        def body_has_url_helpers_include?(body)
          children = body.type == :begin ? body.children : [body]
          children.any? do |child|
            child.type == :send && child.children[0].nil? &&
              child.children[1] == :include &&
              child.children.length == 3 &&
              is_url_helpers_include?(child.children[2])
          end
        end

        # Strip include Rails.application.routes.url_helpers from class body
        def strip_url_helpers_include(body)
          children = body.type == :begin ? body.children : [body]
          filtered = children.reject do |child|
            child.type == :send && child.children[0].nil? &&
              child.children[1] == :include &&
              child.children.length == 3 &&
              is_url_helpers_include?(child.children[2])
          end
          if filtered.length == 1
            filtered[0]
          else
            body.updated(:begin, filtered)
          end
        end

        # Collect enum declarations
        # Supports: enum :field, %w[...].index_by(&:itself)  (string values)
        #           enum :field, %i[...].index_by(&:itself)  (string values)
        def collect_nested_attributes(args)
          return if args.empty?
          name = args.first.children[0] if args.first.type == :sym
          return unless name

          options = {}
          args[1..-1].each do |arg|
            next unless arg.type == :hash
            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              options[key.children[0]] = value if key.type == :sym
            end
          end

          @rails_nested_attributes.push({ name: name, options: options })
        end

        #           enum :field, %i[...]                      (integer values)
        #           enum :field, %w[...]                      (integer values)
        # Options:  prefix: :name / prefix: true, scopes: false, default: :value
        def collect_enum(args)
          return if args.size < 2
          field = args[0].children[0] if args[0].type == :sym
          return unless field

          values_node = args[1]
          values = extract_enum_values(field, values_node)
          return unless values

          options = {}
          # Check for trailing hash of options
          last_arg = args.last
          if last_arg.type == :hash
            last_arg.children.each do |pair|
              next unless pair.type == :pair
              key_node = pair.children[0]
              val_node = pair.children[1]
              next unless key_node.type == :sym
              key = key_node.children[0]

              case key
              when :prefix
                if val_node.type == :true
                  options[:prefix] = field.to_s
                elsif val_node.type == :sym || val_node.type == :str
                  options[:prefix] = val_node.children[0].to_s
                end
              when :scopes
                options[:scopes] = !(val_node.type == :false)
              when :default
                if val_node.type == :sym || val_node.type == :str
                  options[:default] = val_node.children[0]
                end
              end
            end
          end

          @rails_enums.push({ field: field, values: values, options: options })
        end

        def extract_enum_values(field, node)
          # Pattern 1: array.index_by(&:itself) → string values
          if node.type == :send && node.children[1] == :index_by
            array_node = node.children[0]
            if array_node&.type == :array
              names = array_node.children.map { |c| c.children[0].to_s }
              result = {}
              names.each { |n| result[n] = s(:str, n) }
              return result
            end
          end

          # Pattern 2: bare array → integer values (0, 1, 2, ...)
          if node.type == :array
            names = node.children.map { |c| c.children[0].to_s }
            result = {}
            names.each_with_index { |n, i| result[n] = s(:int, i) }
            return result
          end

          nil
        end

        # Collect Active Storage attachments
        def collect_attachment(type, args)
          return if args.empty?

          name = args.first.children[0] if args.first.type == :sym
          return unless name

          options = {}
          args[1..-1].each do |arg|
            next unless arg.type == :hash
            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                options[key.children[0]] = extract_value(value)
              end
            end
          end

          # Note: use push instead of << for JS compatibility
          @rails_attachments.push({
            type: type,
            name: name,
            options: options
          })
        end

        def collect_association(type, args)
          return if args.empty?

          name = args.first.children[0] if args.first.type == :sym
          return unless name

          options = {}
          args[1..-1].each do |arg|
            next unless arg.type == :hash
            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                options[key.children[0]] = extract_value(value)
              end
            end
          end

          # Ensure foreign_key is a string (may be a Symbol from AST)
          if options[:foreign_key]
            options[:foreign_key] = "#{options[:foreign_key]}"
          end

          # Note: use push instead of << for JS compatibility (autoreturn + << = bitwise shift)
          @rails_associations.push({
            type: type,
            name: name,
            options: options
          })
        end

        def collect_validation(args)
          return if args.empty?

          # First args are attribute names (symbols)
          attributes = []
          validations = {}

          args.each do |arg|
            if arg.type == :sym
              attributes << arg.children[0]
            elsif arg.type == :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]
                if key.type == :sym
                  validations[key.children[0]] = extract_validation_value(value)
                end
              end
            end
          end

          # Note: use push instead of << for JS compatibility
          attributes.each do |attr|
            @rails_validations.push({
              attribute: attr,
              validations: validations
            })
          end
        end

        def collect_scope(args)
          return if args.size < 2

          name = args[0].children[0] if args[0].type == :sym
          lambda_node = args[1]

          return unless name && lambda_node

          # Note: use push instead of << for JS compatibility (autoreturn + << = bitwise shift)
          @rails_scopes.push({
            name: name,
            body: lambda_node
          })
        end

        # Collect broadcasts_to declarations
        # broadcasts_to ->(record) { "stream_name" }
        # broadcasts_to ->(record) { "stream_name" }, inserts_by: :prepend
        # broadcasts_to ->(record) { "stream_name" }, inserts_by: :prepend, target: "items"
        def collect_broadcasts_to(args)
          return if args.empty?

          # First arg is lambda/proc for stream name
          stream_lambda = args[0]
          return unless stream_lambda&.type == :block

          # Extract the lambda body (the stream expression)
          # ->(record) { "stream_name" } has structure: block(send(nil, :lambda), args(arg(:record)), body)
          lambda_args = stream_lambda.children[1]
          stream_body = stream_lambda.children[2]

          # Get lambda parameter name (e.g., :comment from ->(comment) { ... })
          param_name = nil
          if lambda_args&.type == :args && lambda_args.children[0]&.type == :arg
            param_name = lambda_args.children[0].children[0]
          end

          # Extract options from second arg (hash)
          options = {}
          if args[1]&.type == :hash
            args[1].children.each do |pair|
              key_node, value_node = pair.children
              if key_node.type == :sym
                key = key_node.children[0]
                options[key] = extract_value(value_node)
              end
            end
          end

          # Note: use push instead of << for JS compatibility
          @rails_broadcasts_to.push({
            stream: stream_body,
            param_name: param_name,
            inserts_by: options[:inserts_by] || :append,
            target: options[:target]
          })
        end

        def collect_callback(type, args)
          # Initialize key if needed (JS compatibility - no Hash.new with default)
          @rails_callbacks[type] ||= []
          args.each do |arg|
            if arg.type == :sym
              @rails_callbacks[type].push(arg.children[0])
            end
          end
        end

        def extract_value(node)
          case node.type
          when :sym then node.children[0]
          when :str then node.children[0]
          when :int then node.children[0]
          when :true then true
          when :false then false
          when :nil then nil
          else node
          end
        end

        def extract_validation_value(node)
          # Note: use explicit returns for JS compatibility (case-as-expression doesn't transpile well)
          case node.type
          when :true then return true
          when :false then return false
          when :hash
            result = {}
            node.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                result[key.children[0]] = extract_value(value)
              end
            end
            return result
          else
            return extract_value(node)
          end
        end

        def transform_model_body(body)
          children = body ? (body.type == :begin ? body.children : [body]) : []
          transformed = []

          # Add table_name as a static getter (not a method) so it can be accessed as this.table_name
          # Use underscore for proper CamelCase handling (NotNow -> not_now -> not_nows)
          leaf_name = Ruby2JS::Inflector.underscore(@rails_model_name)
          # For namespaced models (Card::NotNow), Rails prefixes with parent table name
          # when parent is an AR model: card_not_nows
          parent_const = @rails_model_class_name.children.first
          if parent_const && parent_const.type == :const
            parent_name = Ruby2JS::Inflector.underscore(parent_const.children.last.to_s)
            table_name = Ruby2JS::Inflector.pluralize("#{parent_name}_#{leaf_name}")
          else
            table_name = Ruby2JS::Inflector.pluralize(leaf_name)
          end
          transformed << s(:send, s(:self), :table_name=,
            s(:str, table_name))

          in_private = false
          children.each do |child|
            next unless child

            # Skip private keyword
            if child.type == :send && child.children[0].nil? && child.children[1] == :private
              in_private = true
              next
            end

            # Skip DSL declarations (already collected)
            if child.type == :send && child.children[0].nil?
              method = child.children[1]
              next if %i[has_many has_one belongs_to validates scope broadcasts_to has_one_attached has_many_attached has_rich_text store enum include accepts_nested_attributes_for].include?(method)
              next if CALLBACKS.include?(method)
            end

            # Keep non-private methods
            if child.type == :def && !in_private
              transformed << process(child)
            elsif !in_private && child.type != :def
              # Pass through other class-level code
              transformed << process(child)
            end
          end

          # Generate association methods
          @rails_associations.each do |assoc|
            transformed << generate_association_method(assoc)
          end

          # Generate _resolveDefaults() for belongs_to with default: lambda
          resolve_defaults = generate_resolve_defaults
          transformed << resolve_defaults if resolve_defaults

          # Generate static associations metadata for eager loading
          if @rails_associations.any?
            assoc_pairs = @rails_associations.map do |assoc|
              # Derive class name from association name or options[:class_name]
              # For has_many, singularize and capitalize: comments -> Comment
              # For belongs_to, just capitalize: article -> Article
              class_name = assoc[:options][:class_name]
              # Strip Ruby namespace qualifiers (e.g., "Card::NotNow" → "NotNow", "::Card" → "Card")
              class_name = class_name.split('::').last if class_name
              unless class_name
                name_str = assoc[:name].to_s
                if assoc[:type] == :has_many
                  name_str = Ruby2JS::Inflector.singularize(name_str)
                end
                class_name = name_str.split('_').map(&:capitalize).join
              end

              # Build { type: 'has_many', model: 'Comment', foreignKey: 'article_id' }
              # Use string reference to avoid circular dependency issues
              props = [
                s(:pair, s(:sym, :type), s(:str, assoc[:type].to_s)),
                s(:pair, s(:sym, :model), s(:str, class_name))
              ]
              if assoc[:options][:foreign_key]
                props << s(:pair, s(:sym, :foreignKey), s(:str, assoc[:options][:foreign_key]))
              end
              # Polymorphic associations: include foreignType and ownerType
              if assoc[:options][:as]
                poly_name = assoc[:options][:as].to_s
                props << s(:pair, s(:sym, :foreignKey), s(:str, "#{poly_name}_id"))
                props << s(:pair, s(:sym, :foreignType), s(:str, "#{poly_name}_type"))
                props << s(:pair, s(:sym, :ownerType), s(:str, @rails_model_name))
              end
              s(:pair, s(:sym, assoc[:name]), s(:hash, *props))
            end
            transformed << s(:send, s(:self), :associations=, s(:hash, *assoc_pairs))
          end

          # Generate Active Storage attachment methods
          @rails_attachments.each do |attachment|
            transformed << generate_attachment_method(attachment)
          end

          # Generate destroy method if any dependent: :destroy associations
          destroy_method = generate_destroy_method
          transformed << destroy_method if destroy_method

          # Generate validate method
          validate_method = generate_validate_method
          transformed << validate_method if validate_method

          # Generate callback methods
          # Note: use keys loop for JS compatibility (hash.each doesn't work with for...of)
          @rails_callbacks.keys.each do |callback_type|
            methods = @rails_callbacks[callback_type]
            next if methods.empty?
            callback_method = generate_callback_method(callback_type, methods)
            transformed << callback_method if callback_method
          end

          # Generate scope methods
          @rails_scopes.each do |scope|
            transformed << generate_scope_method(scope)
          end

          # Generate enum methods (predicates, scopes, frozen values)
          # Note: use push loop instead of concat for JS compatibility (JS concat returns new array)
          @rails_enums.each do |enum_data|
            generate_enum_methods(enum_data, children).each do |node|
              transformed.push(node)
            end
          end

          # Generate enum defaults: first value in each enum is the default for new records
          unless @rails_enums.empty?
            default_pairs = []
            @rails_enums.each do |enum_data|
              field = enum_data[:field]
              first_key = enum_data[:values].keys.first
              first_val = enum_data[:values][first_key]
              default_pairs.push(s(:pair, s(:sym, field), first_val))
            end
            transformed << s(:send, s(:self), :_enumDefaults=,
              s(:hash, *default_pairs))
          end

          # Generate callbacks from broadcasts_to declarations
          @rails_broadcasts_to.each do |broadcast|
            transformed << generate_broadcasts_to_callbacks(broadcast)
          end

          # Generate nested attributes setters and registration
          @rails_nested_attributes.each do |nested|
            generate_nested_attributes(nested).each do |node|
              transformed.push(node)
            end
          end

          # Keep private methods that aren't inlined elsewhere
          # Note: collect all callback method names for lookup
          all_callback_methods = []
          @rails_callbacks.keys.each do |cb_type|
            methods = @rails_callbacks[cb_type]
            methods.each { |m| all_callback_methods.push(m) }
          end

          @rails_model_private_methods.keys.each do |name|
            node = @rails_model_private_methods[name]
            # Check if used in callbacks
            used_in_callbacks = all_callback_methods.include?(name)
            if used_in_callbacks
              # Rewrite bare sends to self sends in method body.
              # Ruby allows bare `title` to call the attribute getter;
              # JS requires explicit `this.title`.
              args_node = node.children[1]
              locals = []
              if args_node
                args_node.children.each do |arg|
                  locals.push(arg.children[0]) if arg.respond_to?(:children) && arg.children[0]
                end
              end
              rewritten = node.updated(nil, [
                node.children[0],
                node.children[1],
                rewrite_bare_sends_to_self(node.children[2], locals)
              ])
              # Convert to :defm since callback methods are called by framework
              method_node = rewritten.updated(:defm, rewritten.children)
              transformed << process(method_node)
            end
          end

          transformed.compact.length == 1 ? transformed.first : s(:begin, *transformed.compact)
        end

        def generate_association_method(assoc)
          case assoc[:type]
          when :has_many
            generate_has_many_method(assoc)
          when :has_one
            generate_has_one_method(assoc)
          when :belongs_to
            generate_belongs_to_method(assoc)
          end
        end

        # Generate Active Storage attachment getter
        # has_one_attached :audio -> get audio() { return hasOneAttached(this, 'audio') }
        # has_many_attached :images -> get images() { return hasManyAttached(this, 'images') }
        def generate_attachment_method(attachment)
          name = attachment[:name]
          type = attachment[:type]

          if type == :has_one_attached
            # get audio() { return hasOneAttached(this, 'audio') }
            s(:defget, name,
              s(:args),
              s(:autoreturn,
                s(:send, nil, :hasOneAttached,
                  s(:self),
                  s(:str, name.to_s))))
          else
            # get images() { return hasManyAttached(this, 'images') }
            s(:defget, name,
              s(:args),
              s(:autoreturn,
                s(:send, nil, :hasManyAttached,
                  s(:self),
                  s(:str, name.to_s))))
          end
        end

        def generate_has_many_method(assoc)
          # has_many :comments -> get comments() {
          #   // Return CollectionProxy - either cached or new
          #   if (this._comments) return this._comments;
          #   return new CollectionProxy(this, { name: 'comments', type: 'has_many', foreignKey: 'article_id' }, Comment);
          # }
          # Also generates set comments(val) for preloading
          association_name = assoc[:name]
          cache_name = "_#{association_name}".to_sym
          class_name = (assoc[:options][:class_name] || '').split('::').last || ''
          class_name = Ruby2JS::Inflector.classify(Ruby2JS::Inflector.singularize(association_name.to_s)) if class_name.empty?
          # Polymorphic: has_many :events, as: :eventable → foreignKey: "eventable_id"
          polymorphic_name = assoc[:options][:as]
          foreign_key = assoc[:options][:foreign_key] ||
            (polymorphic_name ? "#{polymorphic_name}_id" : "#{@rails_model_name.downcase}_id")

          # Build association metadata object: { name: 'comments', type: 'has_many', foreignKey: 'article_id' }
          # For polymorphic: also includes foreignType and ownerType
          metadata_pairs = [
            s(:pair, s(:sym, :name), s(:str, association_name.to_s)),
            s(:pair, s(:sym, :type), s(:str, 'has_many')),
            s(:pair, s(:sym, :foreignKey), s(:str, foreign_key))
          ]
          if polymorphic_name
            metadata_pairs.push(
              s(:pair, s(:sym, :foreignType), s(:str, "#{polymorphic_name}_type")),
              s(:pair, s(:sym, :ownerType), s(:str, @rails_model_name)))
          end
          assoc_metadata = s(:hash, *metadata_pairs)

          # Build: new CollectionProxy(this, metadata, modelRegistry["Comment"])
          model_ref = s(:send, s(:lvar, :modelRegistry), :[], s(:str, class_name))
          collection_proxy = s(:send,
            s(:const, nil, :CollectionProxy),
            :new,
            s(:self),
            assoc_metadata,
            model_ref)

          # Getter: returns cache if set, otherwise creates and caches new CollectionProxy
          getter = s(:defget, association_name,
            s(:args),
            s(:begin,
              # if (this._comments) return this._comments;
              s(:if,
                s(:attr, s(:self), cache_name),
                s(:return, s(:attr, s(:self), cache_name)),
                nil),
              # return this._comments = new CollectionProxy(...);
              s(:return, s(:send, s(:self), "#{cache_name}=".to_sym, collection_proxy))))

          # Setter: allows preloading with article.comments = await Comment.where(...)
          # Use method name with = suffix, class2 converter handles this as a setter
          setter_name = "#{association_name}=".to_sym
          setter = s(:def, setter_name,
            s(:args, s(:arg, :value)),
            s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :value)))

          s(:begin, getter, setter)
        end

        def generate_has_one_method(assoc)
          # has_one :profile generates:
          #   get profile() {
          #     if (this._profile_loaded) return this._profile;
          #     return new HasOneReference(modelRegistry["Profile"],
          #       {user_id: this.id}, v => { this._profile = v; this._profile_loaded = true; });
          #   }
          association_name = assoc[:name]
          cache_name = "_#{association_name}".to_sym
          loaded_flag = "_#{association_name}_loaded".to_sym
          class_name = (assoc[:options][:class_name] || '').split('::').last || ''
          class_name = Ruby2JS::Inflector.classify(association_name.to_s) if class_name.empty?
          foreign_key = assoc[:options][:foreign_key] || "#{@rails_model_name.downcase}_id"

          model_ref = s(:send, s(:lvar, :modelRegistry), :[], s(:str, class_name))

          # Conditions hash: {user_id: this.id}
          conditions = s(:hash,
            s(:pair,
              s(:sym, foreign_key.to_sym),
              s(:attr, s(:self), :id)))

          # Cache callback: v => { this._profile = v; this._profile_loaded = true; }
          cache_callback = s(:block,
            s(:send, nil, :proc),
            s(:args, s(:arg, :v)),
            s(:begin,
              s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :v)),
              s(:send, s(:self), "#{loaded_flag}=".to_sym, s(:true))))

          # HasOneReference constructor
          reference_call = s(:send, s(:const, nil, :HasOneReference), :new,
            model_ref, conditions, cache_callback)

          # Getter: return cached value if loaded flag is set, otherwise Reference
          # The loaded flag distinguishes "never loaded" from "loaded but null"
          getter = s(:defget, association_name,
            s(:args),
            s(:begin,
              s(:if,
                s(:attr, s(:self), loaded_flag),
                s(:return, s(:attr, s(:self), cache_name)),
                nil),
              s(:return, reference_call)))

          # Setter: set closure(value) { this._closure = value; this._closure_loaded = true; }
          setter_name = "#{association_name}=".to_sym
          setter = s(:def, setter_name,
            s(:args, s(:arg, :value)),
            s(:begin,
              s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :value)),
              s(:send, s(:self), "#{loaded_flag}=".to_sym, s(:true))))

          # create_X method: Rails auto-generates create_X! for has_one
          # async create_closure(attrs={}) { this.closure = await Closure.create({...attrs, fk: this.id}); return this.closure; }
          create_method_name = "create_#{association_name}".to_sym
          create_method = s(:async, create_method_name,
            s(:args, s(:optarg, :attrs, s(:hash))),
            s(:begin,
              s(:send, s(:self), "#{association_name}=".to_sym,
                s(:send, nil, :await,
                  s(:send, model_ref, :create,
                    s(:hash,
                      s(:kwsplat, s(:lvar, :attrs)),
                      s(:pair, s(:sym, foreign_key.to_sym), s(:attr, s(:self), :id)))))),
              s(:return, s(:attr, s(:self), cache_name))))

          s(:begin, getter, setter, create_method)
        end

        def generate_belongs_to_method(assoc)
          association_name = assoc[:name]
          cache_name = "_#{association_name}".to_sym
          class_name = (assoc[:options][:class_name] || '').split('::').last || ''
          class_name = Ruby2JS::Inflector.classify(association_name.to_s) if class_name.empty?
          foreign_key = assoc[:options][:foreign_key] || "#{association_name}_id"
          is_polymorphic = assoc[:options][:polymorphic] == true

          # Access foreign key from attributes
          fk_access = s(:send, s(:attr, s(:self), :attributes), :[],
            s(:str, foreign_key))

          if is_polymorphic
            # Polymorphic belongs_to: model type determined by _type column at runtime
            type_column = "#{association_name}_type"
            type_access = s(:send, s(:attr, s(:self), :attributes), :[],
              s(:str, type_column))

            # Getter: returns cached value or looks up model via _type column
            getter = s(:defget, association_name,
              s(:args),
              s(:begin,
                s(:if,
                  s(:attr, s(:self), cache_name),
                  s(:return, s(:attr, s(:self), cache_name)),
                  nil),
                s(:return, s(:nil))))

            # Setter: sets _id, _type, and cache
            setter_name = "#{association_name}=".to_sym
            setter = s(:def, setter_name,
              s(:args, s(:arg, :value)),
              s(:begin,
                s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :value)),
                s(:send, s(:attr, s(:self), :attributes), :[]=,
                  s(:str, foreign_key),
                  s(:if, s(:lvar, :value),
                    s(:attr, s(:lvar, :value), :id),
                    s(:nil))),
                s(:send, s(:attr, s(:self), :attributes), :[]=,
                  s(:str, type_column),
                  s(:if, s(:lvar, :value),
                    s(:attr, s(:attr, s(:lvar, :value), :constructor), :name),
                    s(:nil)))))

            fk_getter = s(:defget, foreign_key.to_sym,
              s(:args),
              s(:autoreturn, fk_access))

            type_getter = s(:defget, type_column.to_sym,
              s(:args),
              s(:autoreturn, type_access))

            return s(:begin, getter, setter, fk_getter, type_getter)
          end

          # Non-polymorphic belongs_to
          model_ref = s(:send, s(:lvar, :modelRegistry), :[], s(:str, class_name))

          cache_callback = s(:block,
            s(:send, nil, :proc),
            s(:args, s(:arg, :v)),
            s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :v)))

          reference_call = s(:send, s(:const, nil, :Reference), :new,
            model_ref, fk_access, cache_callback)

          getter = s(:defget, association_name,
            s(:args),
            s(:begin,
              s(:if,
                s(:attr, s(:self), cache_name),
                s(:return, s(:attr, s(:self), cache_name)),
                nil),
              s(:if,
                s(:send, fk_access, :!),
                s(:return, s(:nil)),
                nil),
              s(:return, reference_call)))

          setter_name = "#{association_name}=".to_sym
          setter = s(:def, setter_name,
            s(:args, s(:arg, :value)),
            s(:begin,
              s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :value)),
              s(:send,
                s(:attr, s(:self), :attributes),
                :[]=,
                s(:str, foreign_key),
                s(:if, s(:lvar, :value),
                  s(:attr, s(:lvar, :value), :id),
                  s(:nil)))))

          fk_getter = s(:defget, foreign_key.to_sym,
            s(:args),
            s(:autoreturn, fk_access))

          s(:begin, getter, setter, fk_getter)
        end

        # Generate _resolveDefaults() method for belongs_to associations
        # with default: -> { ... } lambdas. Called before save to auto-populate
        # nil FK values from the lambda (Rails behavior).
        def generate_resolve_defaults
          # Note: check for AST node using .is_a?(Parser::AST::Node) pattern,
          # but use duck-typing for JS compatibility
          defaults = @rails_associations.select { |a|
            default_val = a[:options][:default]
            a[:type] == :belongs_to && default_val != nil &&
              default_val != true && default_val != false &&
              default_val.respond_to?(:type) && default_val.type == :block
          }
          return nil if defaults.empty?

          stmts = []
          defaults.each do |assoc|
            name = assoc[:name]
            foreign_key = assoc[:options][:foreign_key] || "#{name}_id"
            lambda_node = assoc[:options][:default]
            lambda_body = lambda_node.children[2]

            # Transform the lambda body: bare sends → self sends
            # e.g. `board.account` → `this.board.account`
            # e.g. `Current.user` stays as `Current.user`
            transformed_body = rewrite_default_lambda_body(lambda_body)

            # Check: if (!this.attributes["account_id"]) { this.account = await ...; }
            fk_check = s(:send,
              s(:send, s(:attr, s(:self), :attributes), :[],
                s(:str, foreign_key)),
              :!)

            assign = s(:send, s(:self), :"#{name}=",
              s(:send, nil, :await, transformed_body))

            stmts.push(s(:if, fk_check, assign, nil))
          end

          s(:async, :_resolveDefaults,
            s(:args),
            s(:begin, *stmts))
        end

        # Rewrite bare sends (no receiver) to self sends in model method bodies.
        # Ruby `title.blank?` → `self.title.blank?` so JS gets `this.title`.
        # Skips local variables, known Ruby builtins, and class-level calls.
        BARE_SEND_EXCEPTIONS = %i[
          puts print raise fail return break next
          lambda proc loop
          Array Hash String Integer Float
          freeze_time travel_to travel_back
        ]

        def rewrite_bare_sends_to_self(node, locals)
          return node unless node.respond_to?(:type)

          case node.type
          when :send
            target, method, *args = node.children
            if target.nil? && !locals.include?(method) &&
               !BARE_SEND_EXCEPTIONS.include?(method) &&
               method.to_s =~ /\A[a-z_]/
              new_args = args.map { |a| rewrite_bare_sends_to_self(a, locals) }
              return node.updated(nil, [s(:self), method, *new_args])
            end
          when :lvasgn
            # Track local variable assignments
            locals = locals + [node.children[0]]
          when :block
            # Track block args as locals
            block_locals = locals.dup
            block_args = node.children[1]
            if block_args && block_args.type == :args
              block_args.children.each do |arg|
                block_locals.push(arg.children[0]) if arg.respond_to?(:children)
              end
            end
            new_children = []
            idx = 0
            node.children.each do |c|
              if idx == 2
                new_children.push(rewrite_bare_sends_to_self(c, block_locals))
              elsif c.respond_to?(:type)
                new_children.push(rewrite_bare_sends_to_self(c, locals))
              else
                new_children.push(c)
              end
              idx = idx + 1
            end
            return node.updated(nil, new_children)
          end

          # Recurse into children
          new_children = []
          node.children.each do |c|
            if c.respond_to?(:type)
              new_children.push(rewrite_bare_sends_to_self(c, locals))
            else
              new_children.push(c)
            end
          end
          node.updated(nil, new_children)
        end

        # Transform a belongs_to default lambda body for JS output.
        # Bare method calls (no receiver) become property access on self.
        # Association accesses are wrapped with await since getters return
        # Reference proxies that need resolution.
        def rewrite_default_lambda_body(node)
          return node unless node.respond_to?(:type)

          if node.type == :send
            target, method, *args = node.children
            if target.nil? && args.empty?
              # Bare zero-arg call like `board` → `await this.board`
              # Wrap in await + begin for proper parentheses: (await this.board)
              assoc = @rails_associations.find { |a| a[:name] == method }
              base = s(:attr, s(:self), method)
              if assoc
                return s(:begin, s(:send, nil, :await, base))
              end
              return base
            elsif target.nil?
              # Bare call with args → method call `this.method(args)`
              new_args = args.map { |a| rewrite_default_lambda_body(a) }
              return s(:send, s(:self), method, *new_args)
            else
              new_target = rewrite_default_lambda_body(target)
              # Zero-arg chained call → property access
              if args.empty?
                return s(:attr, new_target, method)
              end
              new_args = args.map { |a| rewrite_default_lambda_body(a) }
              return node.updated(nil, [new_target, method, *new_args])
            end
          end

          if node.children.any?
            new_children = node.children.map { |c|
              c.respond_to?(:type) ? rewrite_default_lambda_body(c) : c
            }
            return node.updated(nil, new_children)
          end

          node
        end

        def generate_destroy_method
          # Find associations with dependent: :destroy
          dependent_destroy = @rails_associations.select do |assoc|
            assoc[:options][:dependent] == :destroy
          end

          return nil if dependent_destroy.empty?

          # Generate: async destroy() { for (let record of await this.comments) { await record.destroy() }; return super.destroy(); }
          # Must await the association (thenable proxy) to get the collection
          # Use for...of with await inside to properly handle async destroy calls
          destroy_calls = dependent_destroy.map do |assoc|
            # for (let record of await this.comments) { await record.destroy() }
            s(:for_of,
              s(:lvasgn, :record),
              s(:send, nil, :await, s(:attr, s(:self), assoc[:name])),
              s(:send, nil, :await, s(:send, s(:lvar, :record), :destroy)))
          end

          # Add super.destroy() call
          destroy_calls << s(:zsuper)

          # Use :async for async instance method
          s(:async, :destroy,
            s(:args),
            s(:autoreturn, *destroy_calls))
        end

        def generate_validate_method
          return nil if @rails_validations.empty?

          validation_calls = []

          @rails_validations.each do |v|
            attr = v[:attribute]
            # Note: use keys loop for JS compatibility (hash.each doesn't work with for...of)
            # Note: push directly to avoid case-as-expression which doesn't transpile to JS
            v[:validations].keys.each do |validation_type|
              options = v[:validations][validation_type]
              case validation_type
              when :presence
                if options == true
                  validation_calls.push(s(:send, s(:self), :validates_presence_of, s(:str, attr.to_s)))
                end
              when :length
                if options.is_a?(Hash)
                  # Note: use keys loop for JS compatibility (hash.map doesn't work in JS)
                  opts = options.keys.map do |k|
                    val = options[k]
                    s(:pair, s(:sym, k), s(:int, val))
                  end
                  validation_calls.push(s(:send, s(:self), :validates_length_of, s(:str, attr.to_s), s(:hash, *opts)))
                end
              when :uniqueness
                if options == true
                  validation_calls.push(s(:send, s(:self), :validates_uniqueness_of, s(:str, attr.to_s)))
                end
              when :format
                if options.is_a?(Hash) && options[:with]
                  # Handle regex format validation
                  validation_calls.push(s(:send, s(:self), :validates_format_of, s(:str, attr.to_s), s(:hash,
                    s(:pair, s(:sym, :with), s(:regexp, s(:str, options[:with].to_s), s(:regopt))))))
                end
              when :numericality
                if options == true
                  validation_calls.push(s(:send, s(:self), :validates_numericality_of, s(:str, attr.to_s)))
                elsif options.is_a?(Hash)
                  # Note: use keys loop for JS compatibility (hash.map doesn't work in JS)
                  opts = options.keys.map do |k|
                    val = options[k]
                    # Note: use if/elsif instead of case-as-expression for JS compatibility
                    value_node = nil
                    if val.is_a?(Integer)
                      value_node = s(:int, val)
                    elsif val == true
                      value_node = s(:true)
                    elsif val == false
                      value_node = s(:false)
                    else
                      value_node = s(:str, val.to_s)
                    end
                    s(:pair, s(:sym, k), value_node)
                  end
                  validation_calls.push(s(:send, s(:self), :validates_numericality_of, s(:str, attr.to_s), s(:hash, *opts)))
                end
              when :inclusion
                if options.is_a?(Hash) && options[:in]
                  values = options[:in]
                  if values.is_a?(Array)
                    array_node = s(:array, *values.map { |v| s(:str, v.to_s) })
                    validation_calls.push(s(:send, s(:self), :validates_inclusion_of, s(:str, attr.to_s), s(:hash,
                      s(:pair, s(:sym, :in), array_node))))
                  end
                end
              end
            end
          end

          return nil if validation_calls.empty?

          # Use :defm to ensure validate is a method (called by framework)
          s(:defm, :validate,
            s(:args),
            s(:begin, *validation_calls))
        end

        def generate_callback_method(callback_type, methods)
          # Generate callback method that calls all registered methods
          # Use :send! with s(:self) receiver for this.method_name() with parens
          calls = methods.map do |method_name|
            s(:send!, s(:self), method_name)
          end

          body = calls.length == 1 ? calls.first : s(:begin, *calls)

          # Use :defm to ensure callback invoker is a method (called by framework)
          s(:defm, callback_type,
            s(:args),
            body)
        end

        # Generate enum methods: frozen values constant, instance predicates, static scopes
        def generate_enum_methods(enum_data, children)
          result = []
          field = enum_data[:field]
          enum_values = enum_data[:values]
          prefix = enum_data[:options][:prefix]
          generate_scopes = enum_data[:options][:scopes] != false

          # Collect explicitly defined method names to avoid conflicts
          explicit_methods = Set.new
          children.each do |child|
            next unless child
            if child.type == :def
              explicit_methods.add(child.children[0].to_s.sub(/[?!]$/, ''))
            end
          end

          # Frozen values static property (e.g., Export.statuses = Object.freeze({...}))
          # Note: use keys loop for JS compatibility (hash.each doesn't work with for...of)
          pairs = []
          enum_values.keys.each do |name|
            val = enum_values[name]
            pairs.push(s(:pair, s(:sym, name.to_sym), val))
          end
          plural_field = Ruby2JS::Inflector.pluralize(field.to_s)
          result << s(:send, s(:self), :"#{plural_field}=",
            s(:send, s(:const, nil, :Object), :freeze, s(:hash, *pairs)))

          # Note: use keys loop for JS compatibility (hash.each doesn't work with for...of)
          enum_values.keys.each do |name|
            val = enum_values[name]
            method_name = prefix ? "#{prefix}_#{name}" : name
            next if explicit_methods.include?(method_name)

            # Instance predicate getter: get drafted() { return this.status === "drafted" }
            result << s(:defget, method_name.to_sym, s(:args),
              s(:send, s(:attr, s(:self), field), :===, val))

            # Static scope getter: static get drafted() { return this.where({status: "drafted"}) }
            # Use :defp to force getter (synthesized nodes lack location for is_method? check)
            if generate_scopes
              result << s(:defp, s(:self), method_name.to_sym, s(:args),
                s(:autoreturn, s(:send, s(:self), :where,
                  s(:hash, s(:pair, s(:sym, field), val)))))
            end
          end

          result
        end

        def generate_scope_method(scope)
          # scope :published, -> { where(status: 'published') }
          # becomes: static get published() { return this.where({status: 'published'}) }

          body = if scope[:body].type == :block
                   # -> { where(...) } is a block with lambda send
                   transform_scope_body(scope[:body].children[2])
                 else
                   s(:nil)
                 end

          # Check if lambda has parameters
          lambda_args = scope[:body].type == :block ? scope[:body].children[1] : nil
          has_params = lambda_args && lambda_args.children.any?

          if has_params
            # Scope with params: static method (called with arguments)
            s(:defs, s(:self), scope[:name],
              lambda_args,
              s(:autoreturn, body))
          else
            # Zero-arg scope: static getter (property access, e.g. Card.closed)
            # Use :defp to force getter in class2 converter (synthesized nodes
            # lack location info, so is_method? returns true for :defs)
            s(:defp, s(:self), scope[:name],
              s(:args),
              s(:autoreturn, body))
          end
        end

        # Collect names of all zero-arg scopes and enum scopes (which become
        # static getters). Used by transform_scope_body to generate property
        # access instead of method calls for scope-to-scope chaining.
        # Note: use Array instead of Set for JS compatibility (Set#include?
        # transpiles to .includes() which doesn't exist on JS Set)
        def getter_scope_names
          names = []

          # Zero-arg scopes
          @rails_scopes.each do |scope|
            lambda_node = scope[:body]
            if lambda_node.type == :block
              lambda_args = lambda_node.children[1]
              has_params = lambda_args && lambda_args.children.any?
              names.push(scope[:name]) unless has_params
            end
          end

          # Enum scopes (each enum value generates a static getter scope)
          @rails_enums.each do |enum_data|
            next if enum_data[:options][:scopes] == false
            prefix = enum_data[:options][:prefix]
            enum_data[:values].keys.each do |name|
              scope_name = prefix ? "#{prefix}_#{name}" : name
              names.push(scope_name.to_sym)
            end
          end

          names
        end

        def transform_scope_body(node)
          # Note: explicit returns for JS compatibility (case-as-expression doesn't transpile well)
          return node unless node.respond_to?(:type)

          case node.type
          when :send
            target, method, *args = node.children

            # Simplify arel_table[:column] to just the column name string
            if target.respond_to?(:type) && target.type == :send &&
               target.children[0] == nil && target.children[1] == :arel_table &&
               method == :[] && args.length == 1 && args[0].type == :sym
              return s(:str, args[0].children[0].to_s)
            end

            # Transform implicit self calls (where, order, limit, etc.)
            # Note: use == nil for JS compatibility (nil? doesn't exist in JS)
            if target == nil
              new_args = args.map { |a| transform_scope_body(a) }
              # Zero-arg call to a getter scope: use property access (not method call)
              if new_args.empty? && getter_scope_names.include?(method)
                return s(:attr, s(:self), method)
              end
              return s(:send, s(:self), method, *new_args)
            else
              new_target = transform_scope_body(target)
              new_args = args.map { |a| transform_scope_body(a) }
              # Zero-arg chained call to a getter scope: use property access
              if new_args.empty? && getter_scope_names.include?(method)
                return s(:attr, new_target, method)
              end
              return s(:send, new_target, method, *new_args)
            end
          else
            if node.children.any?
              new_children = node.children.map do |c|
                c.respond_to?(:type) ? transform_scope_body(c) : c
              end
              return node.updated(nil, new_children)
            else
              return node
            end
          end
        end

        # Generate callbacks from broadcasts_to declaration
        # broadcasts_to ->(record) { "stream" }, inserts_by: :prepend, target: "items"
        # Generates:
        #   Model.after_create_commit(($record) => BroadcastChannel.broadcast(...))
        #   Model.after_update_commit(($record) => BroadcastChannel.broadcast(...))
        #   Model.after_destroy_commit(($record) => BroadcastChannel.broadcast(...))
        def generate_broadcasts_to_callbacks(broadcast)
          stream_expr = broadcast[:stream]
          param_name = broadcast[:param_name]
          inserts_by = broadcast[:inserts_by]
          custom_target = broadcast[:target]

          # Determine create action based on inserts_by option
          create_action = inserts_by == :prepend ? :prepend : :append

          # Infer target from model name if not specified
          # Article -> "articles", Message -> "messages"
          default_target = Ruby2JS::Inflector.pluralize(@rails_model_name.downcase)
          target = custom_target || default_target

          # Infer partial from model name: Article -> "articles/article"
          partial_name = "#{default_target}/#{@rails_model_name.downcase}"

          # Transform stream expression to use $record instead of the lambda parameter
          # The lambda body might reference the record parameter (e.g., comment.article_id)
          transformed_stream = transform_broadcasts_to_stream(stream_expr, param_name)

          # Generate the three callbacks
          callbacks = []

          # after_create_commit - append or prepend
          callbacks.push(generate_broadcast_callback(
            :after_create_commit, create_action, transformed_stream, target, partial_name))

          # after_update_commit - replace
          callbacks.push(generate_broadcast_callback(
            :after_update_commit, :replace, transformed_stream, nil, partial_name))

          # after_destroy_commit - remove
          callbacks.push(generate_broadcast_callback(
            :after_destroy_commit, :remove, transformed_stream, nil, nil))

          s(:begin, *callbacks)
        end

        # Generate nested attributes setter and static registration call
        # Produces:
        #   set <name>_attributes(value) {
        #     if (!this._pending_nested_attributes) this._pending_nested_attributes = {};
        #     this._pending_nested_attributes.<name> = value;
        #   }
        #   Model.accepts_nested_attributes_for("<name>", { allow_destroy: true, ... })
        def generate_nested_attributes(nested)
          name = nested[:name]
          options = nested[:options]
          nodes = []

          # Generate setter using def with = suffix (class2 converter handles as setter)
          setter_name = :"#{name}_attributes="
          setter_body = s(:begin,
            # if (!this._pending_nested_attributes) this._pending_nested_attributes = {};
            s(:if,
              s(:send,
                s(:attr, s(:self), :_pending_nested_attributes),
                :!),
              s(:send, s(:self), :_pending_nested_attributes=,
                s(:hash)),
              nil),
            # this._pending_nested_attributes.<name> = value;
            s(:send,
              s(:attr, s(:self), :_pending_nested_attributes),
              :"#{name}=",
              s(:lvar, :value)))

          nodes.push(s(:def, setter_name,
            s(:args, s(:arg, :value)),
            setter_body))

          # Generate static registration call:
          # Model.accepts_nested_attributes_for("name", { ... })
          opt_pairs = []
          options.keys.each do |key|
            val = options[key]
            opt_pairs.push(s(:pair, s(:sym, key), val))
          end

          call_args = [s(:str, name.to_s)]
          call_args.push(s(:hash, *opt_pairs)) unless opt_pairs.empty?

          model_const = s(:const, nil, @rails_model_name.to_sym)
          nodes.push(s(:send, model_const, :accepts_nested_attributes_for, *call_args))

          nodes
        end

        # Transform the stream expression from broadcasts_to lambda
        # Replace references to the lambda parameter with $record
        # Note: explicit returns and == nil for JS compatibility
        def transform_broadcasts_to_stream(node, param_name = nil)
          return node unless node.respond_to?(:type)

          case node.type
          when :lvar
            # Local variable reference - check if it matches the lambda parameter
            var_name = node.children[0]
            if param_name && var_name == param_name
              # Replace lambda parameter with $record
              return s(:lvar, :"$record")
            end
            return node
          when :send
            target = node.children[0]
            method = node.children[1]
            args = node.children[2..-1] || []
            # Note: use == nil for JS compatibility (nil? doesn't exist in JS)
            if target == nil
              # Bare method call - treat as record attribute
              return s(:attr, s(:lvar, :"$record"), method)
            else
              new_target = transform_broadcasts_to_stream(target, param_name)
              new_args = args.map { |a| a.respond_to?(:type) ? transform_broadcasts_to_stream(a, param_name) : a }
              return node.updated(nil, [new_target, method, *new_args])
            end
          when :dstr
            # String interpolation - transform each part
            new_children = node.children.map do |child|
              child.respond_to?(:type) ? transform_broadcasts_to_stream(child, param_name) : child
            end
            return node.updated(nil, new_children)
          when :begin
            # Begin block (interpolation content)
            new_children = node.children.map do |child|
              child.respond_to?(:type) ? transform_broadcasts_to_stream(child, param_name) : child
            end
            return node.updated(nil, new_children)
          when :str
            # Simple string - return as-is
            return node
          else
            if node.children.any?
              new_children = node.children.map do |c|
                c.respond_to?(:type) ? transform_broadcasts_to_stream(c, param_name) : c
              end
              return node.updated(nil, new_children)
            else
              return node
            end
          end
        end

        # Generate a single broadcast callback
        def generate_broadcast_callback(callback_type, action, stream_node, target, partial_name)
          # Build the broadcast call body
          broadcast_body = build_broadcasts_to_body(action, stream_node, target, partial_name)

          # For remove action, callback doesn't need async (no render call)
          # For other actions, callback is async since render() is async
          if action == :remove
            # Model.callback_type(($record) => { ... })
            s(:send,
              s(:const, nil, @rails_model_name.to_sym),
              callback_type,
              s(:block,
                s(:send, nil, :proc),
                s(:args, s(:arg, :"$record")),
                broadcast_body))
          else
            # Model.callback_type(async ($record) => { ... })
            # Use s(:send, nil, :async, block) pattern for async arrow
            s(:send,
              s(:const, nil, @rails_model_name.to_sym),
              callback_type,
              s(:send, nil, :async,
                s(:block,
                  s(:send, nil, :proc),
                  s(:args, s(:arg, :"$record")),
                  broadcast_body)))
          end
        end

        # Build the body of a broadcast callback
        def build_broadcasts_to_body(action, stream_node, target, partial_name)
          receiver = s(:lvar, :"$record")
          model_name_sym = @rails_model_name.downcase.to_sym

          # For remove action, use dom_id for target
          if action == :remove
            # Target is dom_id($record) -> "model_123"
            # Inline the dom_id expression directly in the dstr to avoid nested backticks
            html = s(:dstr,
              s(:str, "<turbo-stream action=\"remove\" target=\"#{@rails_model_name.downcase}_"),
              s(:begin, s(:attr, receiver, :id)),
              s(:str, '"></turbo-stream>'))

            return s(:send,
              s(:const, nil, :BroadcastChannel),
              :broadcast,
              process(stream_node),
              html)
          end

          # For replace action, target is also dom_id
          if action == :replace
            target_expr = s(:dstr,
              s(:str, "#{@rails_model_name.downcase}_"),
              s(:begin, s(:attr, receiver, :id)))
          else
            # For append/prepend, use the specified target
            target_expr = s(:str, target)
          end

          # Content is rendered via the partial: await render({ $context: {...}, article: $record })
          # The partial is imported as 'render' from the views directory
          # Pass a minimal $context with empty authenticityToken (forms won't work in broadcasts anyway)
          context_obj = s(:hash,
            s(:pair, s(:sym, :authenticityToken), s(:str, '')),
            s(:pair, s(:sym, :flash), s(:hash)),
            s(:pair, s(:sym, :contentFor), s(:hash)))

          content_expr = s(:send, nil, :await,
            s(:send, nil, :render,
              s(:hash,
                s(:pair, s(:sym, :"$context"), context_obj),
                s(:pair, s(:sym, model_name_sym), receiver))))

          html = s(:dstr,
            s(:str, "<turbo-stream action=\"#{action}\" target=\""),
            s(:begin, target_expr),
            s(:str, '"><template>'),
            s(:begin, content_expr),
            s(:str, '</template></turbo-stream>'))

          s(:send,
            s(:const, nil, :BroadcastChannel),
            :broadcast,
            process(stream_node),
            html)
        end
      end
    end

    DEFAULTS.push Rails::Model
  end
end
