# Routes configuration
# Defines URL patterns and maps them to controllers/actions

Routes = {
  routes: [],

  root: ->(controller_action) {
    controller, action = controller_action.split('#')
    Routes.routes << {
      method: 'GET',
      path: /^\/$/,
      controller: controller,
      action: action
    }
  },

  resources: ->(name, options = {}, &block) {
    # Standard RESTful routes
    Routes.routes << { method: 'GET',    path: Regexp.new("^/#{name}$"),              controller: name, action: 'index' }
    Routes.routes << { method: 'GET',    path: Regexp.new("^/#{name}/new$"),          controller: name, action: 'new' }
    Routes.routes << { method: 'GET',    path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'show' }
    Routes.routes << { method: 'GET',    path: Regexp.new("^/#{name}/(\\d+)/edit$"),  controller: name, action: 'edit' }
    Routes.routes << { method: 'POST',   path: Regexp.new("^/#{name}$"),              controller: name, action: 'create' }
    Routes.routes << { method: 'PATCH',  path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'update' }
    Routes.routes << { method: 'PUT',    path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'update' }
    Routes.routes << { method: 'DELETE', path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'destroy' }

    # Handle nested resources via block
    if block
      @parent_resource = name
      block.call
      @parent_resource = nil
    end
  },

  # For nested resources
  nested_resources: ->(name, options = {}) {
    parent = @parent_resource
    only = options[:only] || [:index, :show, :new, :create, :edit, :update, :destroy]

    if only.include?(:create)
      Routes.routes << {
        method: 'POST',
        path: Regexp.new("^/#{parent}/(\\d+)/#{name}$"),
        controller: name,
        action: 'create',
        parent: parent
      }
    end

    if only.include?(:destroy)
      Routes.routes << {
        method: 'DELETE',
        path: Regexp.new("^/#{parent}/(\\d+)/#{name}/(\\d+)$"),
        controller: name,
        action: 'destroy',
        parent: parent
      }
    end
  },

  match: ->(method, path) {
    Routes.routes.each do |route|
      next unless route[:method] == method
      match_result = path.match(route[:path])
      if match_result
        return {
          controller: route[:controller],
          action: route[:action],
          params: extract_params(match_result, route)
        }
      end
    end
    nil
  },

  extract_params: ->(match_result, route) {
    params = {}
    if route[:parent]
      # Nested resource: first capture is parent_id, second is id
      params["#{route[:parent].to_s.chomp('s')}_id"] = match_result[1].to_i if match_result[1]
      params['id'] = match_result[2].to_i if match_result[2]
    else
      # Regular resource: first capture is id
      params['id'] = match_result[1].to_i if match_result[1]
    end
    params
  }
}

# Define application routes
Routes.root('articles#index')
Routes.resources('articles') do
  Routes.nested_resources('comments', only: [:create, :destroy])
end
