require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Routes
        include SEXP

        # Standard RESTful actions and their HTTP methods
        RESTFUL_ROUTES = [
          { action: :index,   method: 'GET',    path: '',        has_id: false },
          { action: :new,     method: 'GET',    path: '/new',    has_id: false },
          { action: :create,  method: 'POST',   path: '',        has_id: false },
          { action: :show,    method: 'GET',    path: '/:id',    has_id: true },
          { action: :edit,    method: 'GET',    path: '/:id/edit', has_id: true },
          { action: :update,  method: 'PATCH',  path: '/:id',    has_id: true },
          { action: :destroy, method: 'DELETE', path: '/:id',    has_id: true },
        ].freeze

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_routes = nil
          @rails_routes_list = []
          @rails_path_helpers = []
          @rails_route_nesting = []
          @rails_resources = []  # Track resources for Router.resources() generation
          @rails_root_route = nil
        end

        # Detect Rails.application.routes.draw block
        def on_block(node)
          call, args, body = node.children

          # Check for Rails.application.routes.draw
          return super unless routes_draw_block?(call)

          @rails_routes = true
          @rails_routes_list = []
          @rails_path_helpers = []
          @rails_route_nesting = []

          # Process the routes DSL
          process_routes_body(body)

          # Build the Routes module
          result = build_routes_module

          @rails_routes = nil
          @rails_routes_list = []
          @rails_path_helpers = []
          @rails_route_nesting = []
          @rails_resources = []
          @rails_root_route = nil

          result
        end

        private

        # Get the base path prefix from options (e.g., '/blog' when serving from subdirectory)
        # Removes trailing slash to avoid double slashes when concatenating
        def base_path
          base = @options[:base]
          return '' unless base
          base.to_s.chomp('/')
        end

        def routes_draw_block?(node)
          return false unless node&.type == :send

          # Rails.application.routes.draw
          target, method = node.children[0..1]
          return false unless method == :draw

          # Check for .routes on Rails.application
          return false unless target&.type == :send
          routes_target, routes_method = target.children[0..1]
          return false unless routes_method == :routes

          # Check for Rails.application
          return false unless routes_target&.type == :send
          rails_target, app_method = routes_target.children[0..1]
          return false unless app_method == :application

          # Check for Rails constant
          rails_target&.type == :const && rails_target.children[1] == :Rails
        end

        def process_routes_body(body)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            case child.type
            when :send
              process_route_send(child)
            when :block
              process_route_block(child)
            end
          end
        end

        def process_route_send(node)
          target, method, *args = node.children
          return unless target.nil?

          case method
          when :root
            process_root(args)
          when :get, :post, :patch, :put, :delete
            process_custom_route(method, args)
          when :resources
            # resources without block
            process_resources(args, nil)
          when :resource
            # singular resource without block
            process_resource_singular(args, nil)
          end
        end

        def process_route_block(node)
          call, _block_args, body = node.children
          return unless call.type == :send

          target, method, *args = call.children
          return unless target.nil?

          case method
          when :resources
            process_resources(args, body)
          when :resource
            process_resource_singular(args, body)
          when :namespace
            process_namespace(args, body)
          when :scope
            process_scope(args, body)
          when :collection
            process_collection(body)
          end
        end

        def process_root(args)
          return if args.empty?

          # root "articles#index" or root to: "articles#index"
          target = extract_route_target(args)
          return unless target

          controller, action = target.split('#')
          controller_name = "#{controller.capitalize}Controller"
          action_name = transform_action_name(action.to_sym)

          # Track root route info for Router.root() generation
          # Use plain action name for Router.root() (not transformed)
          root_base = base_path.empty? ? '/' : "#{base_path}/"
          @rails_root_route = {
            base: root_base,
            controller: controller_name,
            action: action  # Plain action name, not transformed
          }

          @rails_routes_list << {
            path: "#{base_path}/",
            controller: controller_name,
            action: action_name.to_s
          }

          # Add root_path helper
          @rails_path_helpers << {
            name: :root_path,
            path: "#{base_path}/",
            params: []
          }
        end

        def process_custom_route(http_method, args)
          return if args.empty?

          raw_path = nil
          controller = nil
          action = nil
          as_name = nil
          on_collection = false

          args.each do |arg|
            case arg.type
            when :str, :sym
              raw_path ||= arg.children[0].to_s
            when :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]

                # Handle hashrocket syntax: "path" => "controller#action"
                if key.type == :str && value.type == :str
                  raw_path ||= key.children[0].to_s
                  ctrl, act = value.children[0].split('#')
                  if ctrl && act
                    controller = "#{ctrl.split('/').map { |p| p.split('_').map(&:capitalize).join }.join('::')}Controller"
                    action = act
                  end
                  next
                end

                next unless key.type == :sym

                case key.children[0]
                when :to
                  if value.type == :str
                    ctrl, act = value.children[0].split('#')
                    controller = "#{ctrl.split('/').map { |p| p.split('_').map(&:capitalize).join }.join('::')}Controller"
                    action = act
                  end
                when :as
                  as_name = value.children[0].to_s if value.type == :sym || value.type == :str
                when :on
                  on_collection = true if value.type == :sym && value.children[0] == :collection
                end
              end
            end
          end

          # For on: :collection, temporarily remove parent's param
          saved_parent = nil
          if on_collection && @rails_route_nesting.any?
            parent = @rails_route_nesting.last
            saved_parent = { param: parent[:param], type: parent[:type] }
            parent[:param] = nil
            parent[:type] = :namespace
          end

          # Build full path with nesting prefix
          path_prefix = @rails_route_nesting.map { |n|
            next '' unless n[:path]
            n[:param] ? "/#{n[:path]}/:#{n[:param]}" : "/#{n[:path]}"
          }.join
          full_path = "#{base_path}#{path_prefix}/#{raw_path}" if raw_path

          if full_path && controller && action
            @rails_routes_list << {
              path: full_path,
              controller: controller,
              action: transform_action_name(action.to_sym).to_s,
              method: http_method.to_s.upcase
            }
          end

          # Generate path helper if as: is specified
          if as_name
            helper_path = full_path || "#{base_path}#{path_prefix}"
            # Extract dynamic segments as params
            params = nesting_params
            # Add any :param segments from the path itself (except nesting ones)
            if raw_path
              raw_path.scan(/:(\w+)/).each do |match|
                param_name = match[0].to_sym
                params << param_name unless params.include?(param_name)
              end
            end

            @rails_path_helpers << {
              name: "#{as_name}_path".to_sym,
              path: helper_path,
              params: params
            }

            if controller
              store_route_mapping("#{as_name}_path", controller, false, nesting_prefix)
            end
          end

          # Restore parent's param if we saved it
          if saved_parent
            parent = @rails_route_nesting.last
            parent[:param] = saved_parent[:param]
            parent[:type] = saved_parent[:type]
          end
        end

        def process_resources(args, body)
          return if args.empty?

          resource_name = args[0].children[0] if args[0].type == :sym
          return unless resource_name

          options = extract_resource_options(args)
          only_actions = options[:only]
          except_actions = options[:except]

          # Determine which actions to generate
          # Note: use select/reject for JS compatibility (&= and -= don't work on arrays in JS)
          actions = RESTFUL_ROUTES.map { |r| r[:action] }
          if only_actions
            actions = actions.select { |a| only_actions.include?(a) }
          elsif except_actions
            actions = actions.reject { |a| except_actions.include?(a) }
          end

          # Build path prefix from nesting (base_path always prepended)
          path_prefix = @rails_route_nesting.map { |n|
            next '' unless n[:path]
            n[:param] ? "/#{n[:path]}/:#{n[:param]}" : "/#{n[:path]}"
          }.join

          # Use custom path option if specified, otherwise use resource_name
          url_segment = options[:path] || resource_name
          resource_path = "#{base_path}#{path_prefix}/#{url_segment}"

          controller_name = "#{resource_name.to_s.split('_').map(&:capitalize).join}Controller"
          singular_name = Ruby2JS::Inflector.singularize(resource_name.to_s)

          # Use custom param if specified
          param_name = options[:param] ? "#{options[:param]}" : "#{singular_name}_id"

          # Track resource for Router.resources() generation
          resource_info = {
            name: resource_name.to_s,
            controller_name: controller_name,
            controller_file: "#{resource_name}_controller",
            only: only_actions,
            nested: []
          }

          # If nested, add to parent; otherwise add to top level
          if @rails_route_nesting.any?
            parent_name = @rails_route_nesting.last[:path].to_s
            parent = @rails_resources.find { |r| r[:name] == parent_name }
            parent[:nested] << resource_info if parent
          else
            @rails_resources << resource_info
          end

          # Generate routes for each action
          # Use custom param in route paths if specified
          id_segment = options[:param] ? ":#{options[:param]}" : ":id"
          RESTFUL_ROUTES.each do |route|
            next unless actions.include?(route[:action])

            route_path = route[:path].sub(':id', id_segment)
            full_path = "#{resource_path}#{route_path}"
            action_name = transform_action_name(route[:action])

            @rails_routes_list << {
              path: full_path,
              controller: controller_name,
              action: action_name.to_s,
              method: route[:method]
            }
          end

          # Generate path helpers
          generate_path_helpers(resource_name, singular_name, resource_path, actions, options)

          # Process nested resources
          if body
            @rails_route_nesting.push({
              path: url_segment,
              param: param_name,
              type: :resource
            })
            process_routes_body(body)
            @rails_route_nesting.pop
          end
        end

        def process_resource_singular(args, body)
          # resource :profile (singular resource, no :id in paths)
          return if args.empty?

          resource_name = args[0].children[0] if args[0].type == :sym
          return unless resource_name

          options = extract_resource_options(args)
          only_actions = options[:only]
          except_actions = options[:except]

          # Singular resources don't have index
          # Note: use select/reject for JS compatibility (&= and -= don't work on arrays in JS)
          actions = [:show, :new, :create, :edit, :update, :destroy]
          if only_actions
            actions = actions.select { |a| only_actions.include?(a) }
          elsif except_actions
            actions = actions.reject { |a| except_actions.include?(a) }
          end

          # Build path prefix from nesting (base_path always prepended)
          path_prefix = @rails_route_nesting.map { |n|
            next '' unless n[:path]
            n[:param] ? "/#{n[:path]}/:#{n[:param]}" : "/#{n[:path]}"
          }.join
          resource_path = "#{base_path}#{path_prefix}/#{resource_name}"

          controller_name = "#{resource_name.to_s.split('_').map(&:capitalize).join}Controller"

          # Singular resource routes (no :id)
          singular_routes = [
            { action: :show,    method: 'GET',    path: '' },
            { action: :new,     method: 'GET',    path: '/new' },
            { action: :create,  method: 'POST',   path: '' },
            { action: :edit,    method: 'GET',    path: '/edit' },
            { action: :update,  method: 'PATCH',  path: '' },
            { action: :destroy, method: 'DELETE', path: '' },
          ]

          singular_routes.each do |route|
            next unless actions.include?(route[:action])

            full_path = "#{resource_path}#{route[:path]}"
            action_name = transform_action_name(route[:action])

            @rails_routes_list << {
              path: full_path,
              controller: controller_name,
              action: action_name.to_s,
              method: route[:method]
            }
          end

          # Generate path helpers for singular resource (no :id)
          generate_singular_path_helpers(resource_name, resource_path, actions)

          # Process nested resources — singular resource uses resource_name as param
          if body
            @rails_route_nesting.push({
              path: resource_name,
              param: "#{resource_name}_id",
              type: :resource
            })
            process_routes_body(body)
            @rails_route_nesting.pop
          end
        end

        def process_namespace(args, body)
          return if args.empty?
          name = args[0].children[0] if args[0].type == :sym
          return unless name

          @rails_route_nesting.push({
            path: name,
            param: nil,
            type: :namespace
          })
          process_routes_body(body) if body
          @rails_route_nesting.pop
        end

        def process_scope(args, body)
          # Extract options from scope args
          as_name = nil
          module_only = false

          args.each do |arg|
            next unless arg.type == :hash
            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym
              case key.children[0]
              when :as
                as_name = value.children[0] if value.type == :sym || value.type == :str
              when :module
                module_only = true
              end
            end
          end

          if as_name
            # scope as: :name → name prefix only, no URL path change
            @rails_route_nesting.push({ path: nil, name: as_name, param: nil, type: :namespace })
            process_routes_body(body) if body
            @rails_route_nesting.pop
          elsif module_only
            # scope module: :name → transparent for paths, just recurse
            process_routes_body(body) if body
          else
            process_routes_body(body) if body
          end
        end

        def process_collection(body)
          return unless body
          if @rails_route_nesting.any?
            # Save and modify parent: no :id param, no naming prefix
            parent = @rails_route_nesting.last
            saved_param = parent[:param]
            saved_type = parent[:type]
            saved_name = parent[:name]
            parent[:param] = nil
            parent[:type] = :namespace
            parent[:name] = ''  # Clear naming prefix for collection-level resources
            process_routes_body(body)
            parent[:param] = saved_param
            parent[:type] = saved_type
            parent[:name] = saved_name
          else
            process_routes_body(body)
          end
        end

        def extract_resource_options(args)
          options = {}

          args[1..-1].each do |arg|
            next unless arg.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :only
                options[:only] = extract_action_list(value)
              when :except
                options[:except] = extract_action_list(value)
              when :param
                options[:param] = value.children[0].to_s if value.type == :sym || value.type == :str
              when :path
                options[:path] = value.children[0].to_s if value.type == :sym || value.type == :str
              end
            end
          end

          options
        end

        def extract_action_list(node)
          case node.type
          when :array
            node.children.map { |c| c.children[0] if c.type == :sym }.compact
          when :sym
            [node.children[0]]
          else
            []
          end
        end

        def extract_route_target(args)
          args.each do |arg|
            case arg.type
            when :str
              return arg.children[0]
            when :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]
                if key.type == :sym && key.children[0] == :to && value.type == :str
                  return value.children[0]
                end
              end
            end
          end
          nil
        end

        def transform_action_name(action)
          case action
          when :index then :index!
          when :new then :$new
          else action
          end
        end

        def generate_path_helpers(resource_name, singular_name, resource_path, actions, options = {})
          prefix = nesting_prefix
          ctrl_resource = resource_name.to_s

          # Use custom param in path templates if specified
          id_segment = options[:param] ? ":#{options[:param]}" : ":id"

          # Collection path: articles_path or board_articles_path (nested)
          if actions.include?(:index) || actions.include?(:create)
            @rails_path_helpers << {
              name: "#{prefix}#{resource_name}_path".to_sym,
              path: resource_path,
              params: nesting_params
            }
            store_route_mapping("#{prefix}#{resource_name}_path", ctrl_resource, false, prefix)
          end

          # New path: new_article_path or new_board_article_path (nested)
          if actions.include?(:new)
            @rails_path_helpers << {
              name: "new_#{prefix}#{singular_name}_path".to_sym,
              path: "#{resource_path}/new",
              params: nesting_params
            }
            store_route_mapping("new_#{prefix}#{singular_name}_path", ctrl_resource, true, prefix)
          end

          # Member path: article_path(article) or board_article_path(board, article)
          if actions.include?(:show) || actions.include?(:update) || actions.include?(:destroy)
            @rails_path_helpers << {
              name: "#{prefix}#{singular_name}_path".to_sym,
              path: "#{resource_path}/#{id_segment}",
              params: nesting_params + [singular_name.to_sym]
            }
            store_route_mapping("#{prefix}#{singular_name}_path", ctrl_resource, true, prefix)
          end

          # Edit path: edit_article_path(article) or edit_board_article_path(board, article)
          if actions.include?(:edit)
            @rails_path_helpers << {
              name: "edit_#{prefix}#{singular_name}_path".to_sym,
              path: "#{resource_path}/#{id_segment}/edit",
              params: nesting_params + [singular_name.to_sym]
            }
            store_route_mapping("edit_#{prefix}#{singular_name}_path", ctrl_resource, true, prefix)
          end
        end

        def generate_singular_path_helpers(resource_name, resource_path, actions)
          # Singular resources don't have :id in paths
          # resource :profile generates profile_path, new_profile_path, edit_profile_path
          # Nested: column_left_position_path (singular under columns)
          prefix = nesting_prefix
          ctrl_resource = resource_name.to_s + 's'  # singular resource -> pluralize for controller name

          # Main path: profile_path (for show/update/destroy/create)
          if actions.include?(:show) || actions.include?(:update) || actions.include?(:destroy) || actions.include?(:create)
            @rails_path_helpers << {
              name: "#{prefix}#{resource_name}_path".to_sym,
              path: resource_path,
              params: nesting_params
            }
            store_route_mapping("#{prefix}#{resource_name}_path", ctrl_resource, true, prefix)
          end

          # New path: new_profile_path
          if actions.include?(:new)
            @rails_path_helpers << {
              name: "new_#{prefix}#{resource_name}_path".to_sym,
              path: "#{resource_path}/new",
              params: nesting_params
            }
            store_route_mapping("new_#{prefix}#{resource_name}_path", ctrl_resource, true, prefix)
          end

          # Edit path: edit_profile_path
          if actions.include?(:edit)
            @rails_path_helpers << {
              name: "edit_#{prefix}#{resource_name}_path".to_sym,
              path: "#{resource_path}/edit",
              params: nesting_params
            }
            store_route_mapping("edit_#{prefix}#{resource_name}_path", ctrl_resource, true, prefix)
          end
        end

        def nesting_params
          @rails_route_nesting.select { |n| n[:param] }.map { |n| n[:param].sub(/_id$/, '').to_sym }
        end

        # Build prefix for nested resource path helper names
        # e.g., for cards nested under boards, returns "board_"
        # Namespace entries use name/path as-is (already singular), resource entries singularize
        def nesting_prefix
          parts = @rails_route_nesting.map { |n|
            label = (n[:name] || n[:path]).to_s
            n[:type] == :namespace ? label : Ruby2JS::Inflector.singularize(label)
          }
          # Filter out empty labels (from entries with nil path and nil name)
          parts = parts.reject { |p| p.empty? }
          prefix = parts.join('_')
          prefix.empty? ? '' : "#{prefix}_"
        end

        def store_route_mapping(helper_name, resource_name, is_singular, prefix_str)
          return unless @options[:metadata]
          mapping = (@options[:metadata][:routes_mapping] ||= {})
          ctrl = "#{resource_name.to_s.split('_').map(&:capitalize).join}Controller"
          parent = prefix_str.chomp('_')
          mapping[helper_name.to_s] = {
            controller: ctrl,
            base: resource_name.to_s,
            singular: is_singular,
            action_or_parent: parent.empty? ? nil : parent
          }
        end

        def build_routes_module
          # Check if we should generate only path helpers (for paths.js)
          # This is set via @options[:paths_only]
          if @options[:paths_only]
            return build_paths_only_module
          end

          statements = []

          # Import Router, Application, createContext, formData, handleFormResult from rails.js
          # Wrap in array to get named imports: import { X, Y } from "..."
          statements << s(:import, '../lib/rails.js',
            [s(:const, nil, :Router),
             s(:const, nil, :Application),
             s(:const, nil, :createContext),
             s(:const, nil, :formData),
             s(:const, nil, :handleFormResult)])

          # Import migrations (for migrations-based approach)
          statements << s(:import, '../db/migrate/index.js',
            [s(:const, nil, :migrations)])

          # Import Seeds
          statements << s(:import, '../db/seeds.js',
            [s(:const, nil, :Seeds)])

          # Import layout for server targets
          if self.server_target?()
            statements << s(:import, '../app/views/layouts/application.js',
              [s(:const, nil, :layout)])
          end

          # Import controllers - collect all controllers from resources (deduplicated)
          all_controllers = collect_all_controllers(@rails_resources)
          seen_controllers = {}
          all_controllers.each do |ctrl|
            next if seen_controllers[ctrl[:controller_name]]
            seen_controllers[ctrl[:controller_name]] = true
            statements << s(:import, "../app/controllers/#{ctrl[:controller_file]}.js",
              [s(:const, nil, ctrl[:controller_name].to_sym)])
          end

          # Check if we should import from paths.js or inline path helpers
          if @options[:paths_file]
            # Import path helpers from paths.js
            helper_names = []
            helper_names << :extract_id if @rails_path_helpers.any? { |h| h[:params].any? }
            @rails_path_helpers.each { |h| helper_names << h[:name] }

            if helper_names.any?
              statements << s(:import, @options[:paths_file],
                helper_names.map { |name| s(:const, nil, name) })
            end
          else
            # Import createPathHelper for callable path helpers with HTTP methods
            statements << s(:import, 'juntos/path_helper.mjs',
              s(:array, s(:const, nil, :createPathHelper)))

            # Generate extract_id helper if we have path helpers with params
            if @rails_path_helpers.any? { |h| h[:params].any? }
              statements << build_extract_id_helper
            end

            # Generate path helper functions
            @rails_path_helpers.each do |helper|
              statements << build_path_helper(helper)
            end
          end

          # Generate Router.root() if defined
          # Pass base path, controller, and action (renders directly, no redirect)
          if @rails_root_route
            statements << s(:send,
              s(:const, nil, :Router), :root,
              s(:str, @rails_root_route[:base]),
              s(:const, nil, @rails_root_route[:controller].to_sym),
              s(:str, @rails_root_route[:action]))
          end

          # Generate Router.resources() calls for each top-level resource
          @rails_resources.each do |resource|
            statements << build_router_resources_call(resource)
          end

          # Generate routes dispatch object
          statements << build_routes_dispatch_object

          # Generate Application.configure()
          config_pairs = [
            s(:pair, s(:sym, :migrations), s(:const, nil, :migrations)),
            s(:pair, s(:sym, :seeds), s(:const, nil, :Seeds))
          ]
          if self.server_target?()
            config_pairs << s(:pair, s(:sym, :layout), s(:const, nil, :layout))
          end
          statements << s(:send,
            s(:const, nil, :Application), :configure,
            s(:hash, *config_pairs))

          # Export Application, routes, and path helpers
          exports = [s(:const, nil, :Application), s(:const, nil, :routes)]
          @rails_path_helpers.each do |helper|
            exports << s(:const, nil, helper[:name])
          end
          statements << s(:export, s(:array, *exports))

          begin_node = s(:begin, *statements)
          result = process(begin_node)
          # Set empty comments on processed begin node to prevent first-location lookup
          # from incorrectly inheriting comments from child nodes
          @comments.set(result, [])
          result
        end

        def collect_all_controllers(resources, result = [])
          resources.each do |resource|
            result << resource
            collect_all_controllers(resource[:nested] || [], result)
          end
          result
        end

        def build_router_resources_call(resource)
          args = [
            s(:str, resource[:name]),
            s(:const, nil, resource[:controller_name].to_sym)
          ]

          # Build options hash if needed
          options = []

          if resource[:only]
            only_array = resource[:only].map { |a| s(:str, a.to_s) }
            options << s(:pair, s(:sym, :only), s(:array, *only_array))
          end

          if resource[:nested]&.any?
            nested_configs = resource[:nested].map do |nested|
              nested_pairs = [
                s(:pair, s(:sym, :name), s(:str, nested[:name])),
                s(:pair, s(:sym, :controller), s(:const, nil, nested[:controller_name].to_sym))
              ]
              if nested[:only]
                only_array = nested[:only].map { |a| s(:str, a.to_s) }
                nested_pairs << s(:pair, s(:sym, :only), s(:array, *only_array))
              end
              s(:hash, *nested_pairs)
            end
            options << s(:pair, s(:sym, :nested), s(:array, *nested_configs))
          end

          args << s(:hash, *options) if options.any?

          s(:send, s(:const, nil, :Router), :resources, *args)
        end

        def build_routes_dispatch_object
          # Build routes dispatch object with route names as keys
          # Structure: routes.articles.post(event), routes.article.delete(id), etc.
          pairs = []

          collect_routes_entries(@rails_resources, nil, pairs)

          s(:casgn, nil, :routes, s(:hash, *pairs))
        end

        def collect_routes_entries(resources, parent_info, pairs)
          resources.each do |resource|
            plural = resource[:name]
            singular = Ruby2JS::Inflector.singularize(plural)
            controller = s(:const, nil, resource[:controller_name].to_sym)

            if parent_info
              # Nested resource: article_comments, article_comment
              parent_singular = parent_info[:singular]
              parent_id_param = "#{parent_singular}_id".to_sym

              # Collection route: article_comments (post)
              collection_name = "#{parent_singular}_#{plural}".to_sym
              collection_methods = []

              if !resource[:only] || resource[:only].include?(:create)
                # create(context, parent_id, params) - async
                controller_call = s(:send, controller, :create,
                  s(:lvar, :context),
                  s(:lvar, :parentId),
                  s(:lvar, :params))
                collection_methods << s(:pair, s(:sym, :post),
                  s(:block,
                    s(:send, nil, :async),
                    s(:args, s(:arg, :event), s(:arg, :parentId)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, collection_name), s(:hash, *collection_methods)) if collection_methods.any?

              # Member route: article_comment (delete)
              member_name = "#{parent_singular}_#{singular}".to_sym
              member_methods = []

              if !resource[:only] || resource[:only].include?(:destroy)
                # destroy(context, parent_id, id) - async
                controller_call = s(:send, controller, :destroy,
                  s(:lvar, :context),
                  s(:lvar, :parentId),
                  s(:lvar, :id))
                member_methods << s(:pair, s(:sym, :delete),
                  s(:block,
                    s(:send, nil, :async),
                    s(:args, s(:arg, :parentId), s(:arg, :id)),
                    wrap_with_result_handler(controller_call, has_params: false)))
              end

              pairs << s(:pair, s(:sym, member_name), s(:hash, *member_methods)) if member_methods.any?
            else
              # Top-level resource: articles, article

              # Collection route: articles (get, post)
              collection_methods = []

              if !resource[:only] || resource[:only].include?(:index)
                # Use :index! to bypass functions filter (which transforms .index() to .indexOf())
                # GET handlers create context and pass it to the controller
                collection_methods << s(:pair, s(:sym, :get),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args),
                    s(:send, controller, :index!, s(:send, nil, :createContext))))
              end

              if !resource[:only] || resource[:only].include?(:create)
                # post: async (event) => { let params = formData(event); let context = createContext(params); let result = await Controller.create(context, params); handleFormResult(context, result); return false }
                controller_call = s(:send, controller, :create,
                  s(:lvar, :context),
                  s(:lvar, :params))
                collection_methods << s(:pair, s(:sym, :post),
                  s(:block,
                    s(:send, nil, :async),
                    s(:args, s(:arg, :event)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, plural.to_sym), s(:hash, *collection_methods)) if collection_methods.any?

              # Member route: article (get, put, patch, delete)
              member_methods = []

              if !resource[:only] || resource[:only].include?(:show)
                # show(context, id) - context created inline
                member_methods << s(:pair, s(:sym, :get),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :id)),
                    s(:send, controller, :show, s(:send, nil, :createContext), s(:lvar, :id))))
              end

              if !resource[:only] || resource[:only].include?(:update)
                # update(context, id, params) - async
                controller_call = s(:send, controller, :update,
                  s(:lvar, :context),
                  s(:lvar, :id),
                  s(:lvar, :params))
                update_block = s(:block,
                  s(:send, nil, :async),
                  s(:args, s(:arg, :event), s(:arg, :id)),
                  wrap_with_result_handler(controller_call))
                member_methods << s(:pair, s(:sym, :put), update_block)
                member_methods << s(:pair, s(:sym, :patch), update_block)
              end

              if !resource[:only] || resource[:only].include?(:destroy)
                # destroy(context, id) - async
                controller_call = s(:send, controller, :destroy, s(:lvar, :context), s(:lvar, :id))
                member_methods << s(:pair, s(:sym, :delete),
                  s(:block,
                    s(:send, nil, :async),
                    s(:args, s(:arg, :id)),
                    wrap_with_result_handler(controller_call, has_params: false)))
              end

              pairs << s(:pair, s(:sym, singular.to_sym), s(:hash, *member_methods)) if member_methods.any?
            end

            # Process nested resources
            if resource[:nested]&.any?
              collect_routes_entries(resource[:nested], { singular: singular, plural: plural }, pairs)
            end
          end
        end

        # Wrap a controller call with result handling (async)
        # Generates:
        #   let params = formData(event);
        #   let context = createContext(params);
        #   let result = await Controller.action(context, ...);
        #   handleFormResult(context, result);
        #   return false
        def wrap_with_result_handler(controller_call, has_params: true)
          statements = []

          if has_params
            # let params = formData(event)
            statements << s(:lvasgn, :params, s(:send, nil, :formData, s(:lvar, :event)))
            # let context = createContext(params)
            statements << s(:lvasgn, :context, s(:send, nil, :createContext, s(:lvar, :params)))
          else
            # let context = createContext()
            statements << s(:lvasgn, :context, s(:send, nil, :createContext))
          end

          # let result = await controller.action(context, ...)
          statements << s(:lvasgn, :result, controller_call.updated(:await!))

          # handleFormResult(context, result)
          statements << s(:send, nil, :handleFormResult, s(:lvar, :context), s(:lvar, :result))

          # return false
          statements << s(:return, s(:false))

          s(:begin, *statements)
        end

        # Create an async block (arrow function)
        def async_block(args_node, body)
          s(:block,
            s(:send, nil, :async),
            args_node,
            body)
        end

        def build_routes_method
          route_entries = @rails_routes_list.map do |route|
            pairs = [
              s(:pair, s(:sym, :path), s(:str, route[:path])),
              s(:pair, s(:sym, :controller), s(:str, route[:controller])),
              s(:pair, s(:sym, :action), s(:str, route[:action]))
            ]
            pairs << s(:pair, s(:sym, :method), s(:str, route[:method])) if route[:method]
            s(:hash, *pairs)
          end

          s(:defs, s(:self), :routes,
            s(:args),
            s(:autoreturn, s(:array, *route_entries)))
        end

        def build_path_helper(helper)
          # Build the path string with interpolations for params
          # Note: helper[:path] already includes base_path from generate_path_helpers
          path = helper[:path]
          params = helper[:params]

          if params.empty?
            # Simple static path
            path_expr = s(:str, path)
          else
            # Path with interpolations — replace each :placeholder with extract_id(param)
            parts = []
            remaining = path
            param_index = 0

            # Find all :placeholder segments and replace them with corresponding params
            while remaining.include?(':') && param_index < params.length
              # Find the next :placeholder
              # Use match then indexOf(string) for JS compatibility
              # (pre_match/post_match don't exist in JS)
              match = remaining.match(/:(\w+)/)
              break unless match

              placeholder = match[0]  # e.g., ":user_id", ":id", ":token", ":code"
              idx = remaining.index(placeholder)
              before = remaining[0, idx]
              after = remaining[(idx + placeholder.length)..]

              parts << s(:str, before) unless before.empty?
              parts << s(:begin, s(:send, nil, :extract_id, s(:lvar, params[param_index])))
              param_index += 1
              remaining = after
            end

            parts << s(:str, remaining) unless remaining.empty?

            path_expr = if parts.length == 1 && parts[0].type == :str
                          parts[0]
                        else
                          s(:dstr, *parts)
                        end
          end

          # Wrap path in createPathHelper() for callable path helpers with HTTP methods
          body = s(:send, nil, :createPathHelper, path_expr)

          args = params.map { |p| s(:arg, p) }

          # Use regular function definition (not class method)
          s(:def, helper[:name],
            s(:args, *args),
            s(:autoreturn, body))
        end

        def build_extract_id_helper
          # function extract_id(obj) {
          #   return (obj && obj.id) || obj
          # }
          # Handles both objects with id property and raw id values
          s(:def, :extract_id,
            s(:args, s(:arg, :obj)),
            s(:autoreturn,
              s(:or,
                s(:and,
                  s(:lvar, :obj),
                  s(:attr, s(:lvar, :obj), :id)),
                s(:lvar, :obj))))
        end

        # Build a module with only path helpers (for paths.js)
        def build_paths_only_module
          statements = []

          if @rails_path_helpers.empty?
            # No path helpers — emit a valid empty ESM module
            return process(s(:str, ''))
          end

          # Import createPathHelper for callable path helpers with HTTP methods
          statements << s(:import, 'juntos/path_helper.mjs',
            s(:array, s(:const, nil, :createPathHelper)))

          # Generate extract_id helper if we have path helpers with params
          if @rails_path_helpers.any? { |h| h[:params].any? }
            statements << build_extract_id_helper
          end

          # Deduplicate path helpers by name (skip duplicates)
          seen_names = {}
          unique_helpers = []
          @rails_path_helpers.each do |h|
            name = h[:name].to_s
            unless seen_names[name]
              seen_names[name] = true
              unique_helpers.push(h)
            end
          end

          # Generate path helper functions
          unique_helpers.each do |helper|
            statements << build_path_helper(helper)
          end

          # Export all helpers
          exports = []
          exports << s(:const, nil, :extract_id) if unique_helpers.any? { |h| h[:params].any? }
          unique_helpers.each do |helper|
            exports << s(:const, nil, helper[:name])
          end
          statements << s(:export, s(:array, *exports))

          process(s(:begin, *statements))
        end

        # Browser-only databases (IndexedDB, WASM-based)
        BROWSER_DATABASES = %w[dexie indexeddb sqljs sql.js pglite].freeze

        def server_target?
          # Explicit target option takes precedence
          target = @options[:target]
          return false if target && target.to_s.downcase == 'browser'

          database = @options[:database]
          return false unless database
          database = database.to_s.downcase
          !BROWSER_DATABASES.include?(database)
        end

        # HTTP methods that path helpers support
        PATH_HELPER_METHODS = %i[get post put patch delete].freeze

        # Transform path_helper.get(...) to path_helper().get(...)
        # Path helpers are functions that return objects with HTTP methods,
        # so they must be called before accessing .get(), .post(), etc.
        def on_send(node)
          receiver, method, *args = node.children

          # Check if this is a call to an HTTP method on a path helper
          return super unless PATH_HELPER_METHODS.include?(method)
          return super unless receiver

          # Check if receiver is a path helper call (send with no receiver, name ends in _path)
          if receiver.type == :send
            recv_receiver, recv_method, *recv_args = receiver.children
            if recv_receiver.nil? && recv_method.to_s.end_with?('_path')
              # Transform: notes_path.get(...) => notes_path().get(...)
              # Use :send! to force parentheses on zero-arg method call
              # (send! forces interpretation as a method call even with zero parameters)
              forced_call = receiver.updated(:send!)
              return process(s(:send, forced_call, method, *args))
            end
          end

          super
        end
      end
    end

    DEFAULTS.push Rails::Routes
  end
end
