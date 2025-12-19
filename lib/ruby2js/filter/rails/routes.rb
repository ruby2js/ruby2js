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
          @rails_root_path = nil
        end

        # Detect Rails.application.routes.draw block
        def on_block(node)
          call, args, body = node.children

          # Check for Rails.application.routes.draw
          return super unless routes_draw_block?(call)

          # Initialize state if needed (JS compatibility - constructor may not run in filter pipeline)
          @rails_resources ||= []
          @rails_routes_list ||= []
          @rails_path_helpers ||= []
          @rails_route_nesting ||= []

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
          @rails_root_path = nil

          result
        end

        private

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
          when :resources, :resource
            # resources without block
            process_resources(args, nil)
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

          # Track root path for Router.root() generation
          @rails_root_path = "/#{controller}"

          @rails_routes_list << {
            path: '/',
            controller: controller_name,
            action: action_name.to_s
          }

          # Add root_path helper
          @rails_path_helpers << {
            name: :root_path,
            path: '/',
            params: []
          }
        end

        def process_custom_route(http_method, args)
          return if args.empty?

          path = nil
          controller = nil
          action = nil

          args.each do |arg|
            case arg.type
            when :str, :sym
              path ||= "/#{arg.children[0]}"
            when :hash
              arg.children.each do |pair|
                key = pair.children[0]
                value = pair.children[1]
                next unless key.type == :sym

                case key.children[0]
                when :to
                  if value.type == :str
                    ctrl, act = value.children[0].split('#')
                    controller = "#{ctrl.split('_').map(&:capitalize).join}Controller"
                    action = act
                  end
                end
              end
            end
          end

          return unless path && controller && action

          @rails_routes_list << {
            path: path,
            controller: controller,
            action: transform_action_name(action.to_sym).to_s,
            method: http_method.to_s.upcase
          }
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

          # Build path prefix from nesting
          path_prefix = @rails_route_nesting.map { |n| "/#{n[:path]}/:#{n[:param]}" }.join
          resource_path = "#{path_prefix}/#{resource_name}"

          controller_name = "#{resource_name.to_s.split('_').map(&:capitalize).join}Controller"
          singular_name = Ruby2JS::Inflector.singularize(resource_name.to_s)

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
          RESTFUL_ROUTES.each do |route|
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

          # Generate path helpers
          generate_path_helpers(resource_name, singular_name, resource_path, actions)

          # Process nested resources
          if body
            @rails_route_nesting.push({
              path: resource_name,
              param: "#{singular_name}_id"
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

          path_prefix = @rails_route_nesting.map { |n| "/#{n[:path]}/:#{n[:param]}" }.join
          resource_path = "#{path_prefix}/#{resource_name}"

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

          # Process nested resources
          if body
            @rails_route_nesting.push({
              path: resource_name,
              param: "#{resource_name}_id"
            })
            process_routes_body(body)
            @rails_route_nesting.pop
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

        def generate_path_helpers(resource_name, singular_name, resource_path, actions)
          # Collection path: articles_path
          if actions.include?(:index) || actions.include?(:create)
            @rails_path_helpers << {
              name: "#{resource_name}_path".to_sym,
              path: resource_path,
              params: nesting_params
            }
          end

          # New path: new_article_path
          if actions.include?(:new)
            @rails_path_helpers << {
              name: "new_#{singular_name}_path".to_sym,
              path: "#{resource_path}/new",
              params: nesting_params
            }
          end

          # Member path: article_path(article)
          if actions.include?(:show) || actions.include?(:update) || actions.include?(:destroy)
            @rails_path_helpers << {
              name: "#{singular_name}_path".to_sym,
              path: "#{resource_path}/:id",
              params: nesting_params + [singular_name.to_sym]
            }
          end

          # Edit path: edit_article_path(article)
          if actions.include?(:edit)
            @rails_path_helpers << {
              name: "edit_#{singular_name}_path".to_sym,
              path: "#{resource_path}/:id/edit",
              params: nesting_params + [singular_name.to_sym]
            }
          end
        end

        def nesting_params
          @rails_route_nesting.map { |n| n[:param].sub(/_id$/, '').to_sym }
        end

        def build_routes_module
          statements = []

          # Import Router, Application, formData, handleFormResult from rails.js
          # Wrap in array to get named imports: import { X, Y } from "..."
          statements << s(:import, '../lib/rails.js',
            [s(:const, nil, :Router),
             s(:const, nil, :Application),
             s(:const, nil, :formData),
             s(:const, nil, :handleFormResult)])

          # Import Schema
          statements << s(:import, './schema.js',
            [s(:const, nil, :Schema)])

          # Import Seeds
          statements << s(:import, '../db/seeds.js',
            [s(:const, nil, :Seeds)])

          # Import controllers - collect all controllers from resources
          all_controllers = collect_all_controllers(@rails_resources)
          all_controllers.each do |ctrl|
            statements << s(:import, "../controllers/#{ctrl[:controller_file]}.js",
              [s(:const, nil, ctrl[:controller_name].to_sym)])
          end

          # Generate extract_id helper if we have path helpers with params
          if @rails_path_helpers.any? { |h| h[:params].any? }
            statements << build_extract_id_helper
          end

          # Generate path helper functions
          @rails_path_helpers.each do |helper|
            statements << build_path_helper(helper)
          end

          # Generate Router.root() if defined
          if @rails_root_path
            statements << s(:send,
              s(:const, nil, :Router), :root,
              s(:str, @rails_root_path))
          end

          # Generate Router.resources() calls for each top-level resource
          @rails_resources.each do |resource|
            statements << build_router_resources_call(resource)
          end

          # Generate routes dispatch object
          statements << build_routes_dispatch_object

          # Generate Application.configure()
          statements << s(:send,
            s(:const, nil, :Application), :configure,
            s(:hash,
              s(:pair, s(:sym, :schema), s(:const, nil, :Schema)),
              s(:pair, s(:sym, :seeds), s(:const, nil, :Seeds))))

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
          if @comments.respond_to?(:set)
            @comments.set(result, [])
          else
            @comments[result] = []
          end
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
                # create(parent_id, params) - parent id first, then params
                controller_call = s(:send, controller, :create,
                  s(:lvar, :parentId),
                  s(:send, nil, :formData, s(:lvar, :event)))
                collection_methods << s(:pair, s(:sym, :post),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :event), s(:arg, :parentId)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, collection_name), s(:hash, *collection_methods)) if collection_methods.any?

              # Member route: article_comment (delete)
              member_name = "#{parent_singular}_#{singular}".to_sym
              member_methods = []

              if !resource[:only] || resource[:only].include?(:destroy)
                # destroy(parent_id, id) - parent id first, then id
                controller_call = s(:send, controller, :destroy,
                  s(:lvar, :parentId),
                  s(:lvar, :id))
                member_methods << s(:pair, s(:sym, :delete),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :parentId), s(:arg, :id)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, member_name), s(:hash, *member_methods)) if member_methods.any?
            else
              # Top-level resource: articles, article

              # Collection route: articles (get, post)
              collection_methods = []

              if !resource[:only] || resource[:only].include?(:index)
                # Use :index! to bypass functions filter (which transforms .index() to .indexOf())
                collection_methods << s(:pair, s(:sym, :get),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args),
                    s(:send, controller, :index!)))
              end

              if !resource[:only] || resource[:only].include?(:create)
                # post: (event) => { let result = Controller.create(...); handleFormResult(result); return false }
                controller_call = s(:send, controller, :create,
                  s(:send, nil, :formData, s(:lvar, :event)))
                collection_methods << s(:pair, s(:sym, :post),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :event)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, plural.to_sym), s(:hash, *collection_methods)) if collection_methods.any?

              # Member route: article (get, put, patch, delete)
              member_methods = []

              if !resource[:only] || resource[:only].include?(:show)
                # show(id) - plain id
                member_methods << s(:pair, s(:sym, :get),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :id)),
                    s(:send, controller, :show, s(:lvar, :id))))
              end

              if !resource[:only] || resource[:only].include?(:update)
                # update(id, params) - id first, then params
                controller_call = s(:send, controller, :update,
                  s(:lvar, :id),
                  s(:send, nil, :formData, s(:lvar, :event)))
                update_block = s(:block,
                  s(:send, nil, :proc),
                  s(:args, s(:arg, :event), s(:arg, :id)),
                  wrap_with_result_handler(controller_call))
                member_methods << s(:pair, s(:sym, :put), update_block)
                member_methods << s(:pair, s(:sym, :patch), update_block)
              end

              if !resource[:only] || resource[:only].include?(:destroy)
                # destroy(id) - plain id
                controller_call = s(:send, controller, :destroy, s(:lvar, :id))
                member_methods << s(:pair, s(:sym, :delete),
                  s(:block,
                    s(:send, nil, :proc),
                    s(:args, s(:arg, :id)),
                    wrap_with_result_handler(controller_call)))
              end

              pairs << s(:pair, s(:sym, singular.to_sym), s(:hash, *member_methods)) if member_methods.any?
            end

            # Process nested resources
            if resource[:nested]&.any?
              collect_routes_entries(resource[:nested], { singular: singular, plural: plural }, pairs)
            end
          end
        end

        # Wrap a controller call with result handling
        # Generates: { let result = controllerCall; handleFormResult(result); return false }
        def wrap_with_result_handler(controller_call)
          s(:begin,
            s(:lvasgn, :result, controller_call),
            s(:send, nil, :handleFormResult, s(:lvar, :result)),
            s(:return, s(:false)))
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
          path = helper[:path]
          params = helper[:params]

          if params.empty?
            # Simple static path
            body = s(:str, path)
          else
            # Path with interpolations
            parts = []
            remaining = path

            # Handle nesting params
            params.each do |param|
              param_pattern = ":#{param}_id"
              if remaining.include?(param_pattern)
                before, remaining = remaining.split(param_pattern, 2)
                parts << s(:str, before) unless before.empty?
                parts << s(:begin, s(:send, nil, :extract_id, s(:lvar, param)))
              end
            end

            # Handle :id at the end (member routes)
            if remaining.include?(':id')
              before, after = remaining.split(':id', 2)
              parts << s(:str, before) unless before.empty?
              # Last param is the resource
              last_param = params.last
              parts << s(:begin, s(:send, nil, :extract_id, s(:lvar, last_param)))
              parts << s(:str, after) unless after.empty?
              remaining = ''
            end

            parts << s(:str, remaining) unless remaining.empty?

            body = if parts.length == 1 && parts[0].type == :str
                     parts[0]
                   else
                     s(:dstr, *parts)
                   end
          end

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
      end
    end

    DEFAULTS.push Rails::Routes
  end
end
