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
        ].freeze

        def initialize(*args)
          # Note: super must come first for JS compatibility (derived class constructor rule)
          super
          @rails_model = nil
          @rails_model_name = nil
          @rails_model_processing = false
          @rails_associations = []
          @rails_validations = []
          # Note: use plain hash for JS compatibility (Hash.new with block doesn't transpile)
          @rails_callbacks = {}
          @rails_scopes = []
          @rails_model_private_methods = {}
          @rails_model_refs = Set.new
        end

        # Detect model class and transform
        def on_class(node)
          class_name, superclass, body = node.children

          # Always create fresh Set for each class
          @rails_model_refs = Set.new

          # Skip if already processing (prevent infinite recursion)
          return super if @rails_model_processing

          # Check if this is an ActiveRecord model
          return super unless model_class?(class_name, superclass)

          @rails_model_name = class_name.children.last.to_s
          @rails_model = true
          @rails_model_processing = true

          # First pass: collect DSL declarations
          collect_model_metadata(body)

          # Second pass: transform body
          transformed_body = transform_model_body(body)

          # Build the exported class
          exported_class = s(:send, nil, :export,
            node.updated(nil, [class_name, superclass, transformed_body]))

          # Generate import for superclass (ApplicationRecord or ActiveRecord::Base)
          superclass_name = superclass.children.last.to_s
          superclass_file = superclass_name.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
          import_node = s(:send, nil, :import,
            s(:array, s(:const, nil, superclass_name.to_sym)),
            s(:str, "./#{superclass_file}.js"))

          # Generate imports for associated models
          model_import_nodes = []
          [*@rails_model_refs].sort.each do |model|
            model_file = model.downcase
            model_import_nodes.push(s(:send, nil, :import,
              s(:array, s(:const, nil, model.to_sym)),
              s(:str, "./#{model_file}.js")))
          end

          begin_node = s(:begin, import_node, *model_import_nodes, exported_class)
          result = process(begin_node)
          # Set empty comments on processed begin node to prevent first-location lookup
          # from incorrectly inheriting comments from child nodes
          @comments.set(result, [])

          @rails_model = nil
          @rails_model_name = nil
          @rails_model_processing = false
          @rails_associations = []
          @rails_validations = []
          # Note: use plain hash for JS compatibility (Hash.new with block doesn't transpile)
          @rails_callbacks = {}
          @rails_scopes = []
          @rails_model_private_methods = {}
          @rails_model_refs = Set.new

          result
        end

        private

        def model_class?(class_name, superclass)
          return false unless class_name&.type == :const
          return false unless superclass&.type == :const

          superclass_str = superclass.children.last.to_s
          superclass_str == 'ApplicationRecord' || superclass_str == 'ActiveRecord::Base'
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
            when :validates
              collect_validation(args)
            when :scope
              collect_scope(args)
            when *CALLBACKS
              collect_callback(method_name, args)
            end
          end
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
          table_name = Ruby2JS::Inflector.pluralize(@rails_model_name.downcase)
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
              next if %i[has_many has_one belongs_to validates scope].include?(method)
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
              # Transform and include the method
              transformed << process(node)
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

        def generate_has_many_method(assoc)
          # has_many :comments -> get comments() {
          #   // Return a "thenable" proxy object that:
          #   // - Has create/find methods directly accessible
          #   // - When awaited, returns the actual collection
          #   if (this._comments) return this._comments;
          #   let _id = this.id;
          #   return {
          #     create: (params) => Comment.create(Object.assign({article_id: _id}, params)),
          #     find: (id) => Comment.find(id),
          #     then: (resolve, reject) => Comment.where({article_id: _id}).then(resolve, reject)
          #   };
          # }
          # Also generates set comments(val) for preloading
          association_name = assoc[:name]
          cache_name = "_#{association_name}".to_sym
          class_name = assoc[:options][:class_name] || Ruby2JS::Inflector.singularize(association_name.to_s).capitalize
          foreign_key = assoc[:options][:foreign_key] || "#{@rails_model_name.downcase}_id"

          # Track model reference for import generation
          @rails_model_refs.add(class_name)

          # Capture this.id for use in closures (hash methods lose `this` binding)
          id_capture = s(:lvasgn, :_id, s(:attr, s(:self), :id))

          # Build the where call for the then handler (using captured _id)
          where_call = s(:send,
            s(:const, nil, class_name.to_sym),
            :where,
            s(:hash,
              s(:pair,
                s(:sym, foreign_key.to_sym),
                s(:lvar, :_id))))

          # Build the create lambda: (params) => Model.create(Object.assign({fk: _id}, params))
          create_lambda = s(:block,
            s(:send, nil, :lambda),
            s(:args, s(:arg, :params)),
            s(:send,
              s(:const, nil, class_name.to_sym),
              :create,
              s(:send,
                s(:const, nil, :Object),
                :assign,
                s(:hash,
                  s(:pair,
                    s(:sym, foreign_key.to_sym),
                    s(:lvar, :_id))),
                s(:lvar, :params))))

          # Build the find lambda: (id) => Model.find(id)
          # This overrides Array.prototype.find to provide Rails-like find-by-id behavior
          find_lambda = s(:block,
            s(:send, nil, :lambda),
            s(:args, s(:arg, :id)),
            s(:send,
              s(:const, nil, class_name.to_sym),
              :find,
              s(:lvar, :id)))

          # Build the then handler: (resolve, reject) => Model.where({fk: _id}).then(resolve, reject)
          then_lambda = s(:block,
            s(:send, nil, :lambda),
            s(:args, s(:arg, :resolve), s(:arg, :reject)),
            s(:send, where_call, :then, s(:lvar, :resolve), s(:lvar, :reject)))

          # Build the proxy object with create, find, and then methods
          proxy_object = s(:hash,
            s(:pair, s(:sym, :create), create_lambda),
            s(:pair, s(:sym, :find), find_lambda),
            s(:pair, s(:sym, :then), then_lambda))

          # Getter: returns cache if set, otherwise captures id and returns thenable proxy
          getter = s(:defget, association_name,
            s(:args),
            s(:begin,
              # if (this._comments) return this._comments;
              s(:if,
                s(:attr, s(:self), cache_name),
                s(:return, s(:attr, s(:self), cache_name)),
                nil),
              id_capture,
              s(:return, proxy_object)))

          # Setter: allows preloading with article.comments = await Comment.where(...)
          # Use method name with = suffix, class2 converter handles this as a setter
          setter_name = "#{association_name}=".to_sym
          setter = s(:def, setter_name,
            s(:args, s(:arg, :value)),
            s(:send, s(:self), "#{cache_name}=".to_sym, s(:lvar, :value)))

          s(:begin, getter, setter)
        end

        def generate_has_one_method(assoc)
          # has_one :profile -> get profile() { return Profile.find_by({user_id: this._id}) }
          # Use :defget for getter (no parentheses needed when accessing)
          # Use :attr for property access (no parentheses) to access inherited property
          association_name = assoc[:name]
          class_name = assoc[:options][:class_name] || association_name.to_s.capitalize
          foreign_key = assoc[:options][:foreign_key] || "#{@rails_model_name.downcase}_id"

          # Track model reference for import generation
          @rails_model_refs.add(class_name)

          s(:defget, association_name,
            s(:args),
            s(:autoreturn,
              s(:send,
                s(:const, nil, class_name.to_sym),
                :find_by,
                s(:hash,
                  s(:pair,
                    s(:sym, foreign_key.to_sym),
                    s(:attr, s(:self), :id))))))
        end

        def generate_belongs_to_method(assoc)
          # belongs_to :article -> get article() { return Article.find(this._attributes['article_id']) }
          # Use :defget for getter (no parentheses needed when accessing)
          # Use :attr for property access to _attributes, bracket notation for key
          association_name = assoc[:name]
          class_name = assoc[:options][:class_name] || association_name.to_s.capitalize
          foreign_key = assoc[:options][:foreign_key] || "#{association_name}_id"

          # Track model reference for import generation
          @rails_model_refs.add(class_name)

          # Access foreign key from _attributes - use :attr for property access
          # Use .to_s to force bracket notation (Ruby2JS optimizes literal strings to dot notation)
          fk_access = s(:send, s(:attr, s(:self), :_attributes), :[],
            s(:send, s(:str, foreign_key), :to_s))

          # Handle optional: true
          if assoc[:options][:optional]
            # Return nil if foreign key is nil
            s(:defget, association_name,
              s(:args),
              s(:autoreturn,
                s(:if,
                  fk_access,
                  s(:send,
                    s(:const, nil, class_name.to_sym),
                    :find,
                    fk_access),
                  s(:nil))))
          else
            s(:defget, association_name,
              s(:args),
              s(:autoreturn,
                s(:send,
                  s(:const, nil, class_name.to_sym),
                  :find,
                  fk_access)))
          end
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

          s(:def, :validate,
            s(:args),
            s(:begin, *validation_calls))
        end

        def generate_callback_method(callback_type, methods)
          # Generate callback method that calls all registered methods
          calls = methods.map do |method_name|
            s(:send, nil, method_name)
          end

          body = calls.length == 1 ? calls.first : s(:begin, *calls)

          s(:def, callback_type,
            s(:args),
            body)
        end

        def generate_scope_method(scope)
          # scope :published, -> { where(status: 'published') }
          # becomes: def self.published; self.where({status: 'published'}); end

          body = if scope[:body].type == :block
                   # -> { where(...) } is a block with lambda send
                   transform_scope_body(scope[:body].children[2])
                 else
                   s(:nil)
                 end

          s(:defs, s(:self), scope[:name],
            s(:args),
            s(:autoreturn, body))
        end

        def transform_scope_body(node)
          # Note: explicit returns for JS compatibility (case-as-expression doesn't transpile well)
          return node unless node.respond_to?(:type)

          case node.type
          when :send
            target, method, *args = node.children

            # Transform implicit self calls (where, order, limit, etc.)
            # Note: use == nil for JS compatibility (nil? doesn't exist in JS)
            if target == nil
              new_args = args.map { |a| transform_scope_body(a) }
              return s(:send, s(:self), method, *new_args)
            else
              new_target = transform_scope_body(target)
              new_args = args.map { |a| transform_scope_body(a) }
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
      end
    end

    DEFAULTS.push Rails::Model
  end
end
