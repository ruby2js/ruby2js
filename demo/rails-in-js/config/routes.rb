# Routes configuration
# Defines URL patterns and maps them to controllers/actions

export module Routes
  @routes = []
  @parent_resource = nil

  def self.routes
    @routes
  end

  def self.root(controller_action)
    controller, action = controller_action.split('#')
    @routes.push({
      method: 'GET',
      path: /^\/$/,
      controller: controller,
      action: action
    })
  end

  def self.resources(name, options = {}, &block)
    # Standard RESTful routes
    @routes.push({ method: 'GET',    path: Regexp.new("^/#{name}$"),              controller: name, action: 'list' })
    @routes.push({ method: 'GET',    path: Regexp.new("^/#{name}/new$"),          controller: name, action: 'new_form' })
    @routes.push({ method: 'GET',    path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'show' })
    @routes.push({ method: 'GET',    path: Regexp.new("^/#{name}/(\\d+)/edit$"),  controller: name, action: 'edit' })
    @routes.push({ method: 'POST',   path: Regexp.new("^/#{name}$"),              controller: name, action: 'create' })
    @routes.push({ method: 'PATCH',  path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'update' })
    @routes.push({ method: 'PUT',    path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'update' })
    @routes.push({ method: 'DELETE', path: Regexp.new("^/#{name}/(\\d+)$"),       controller: name, action: 'destroy' })

    # Handle nested resources via block
    if block
      @parent_resource = name
      block.call()
      @parent_resource = nil
    end
  end

  # For nested resources
  def self.nested_resources(name, options = {})
    parent = @parent_resource
    only = options[:only] || [:list, :show, :new_form, :create, :edit, :update, :destroy]

    if only.include?(:create)
      @routes.push({
        method: 'POST',
        path: Regexp.new("^/#{parent}/(\\d+)/#{name}$"),
        controller: name,
        action: 'create',
        parent: parent
      })
    end

    if only.include?(:destroy)
      @routes.push({
        method: 'DELETE',
        path: Regexp.new("^/#{parent}/(\\d+)/#{name}/(\\d+)$"),
        controller: name,
        action: 'destroy',
        parent: parent
      })
    end
  end

  def self.match(method, path)
    @routes.each do |route|
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
  end

  def self.extract_params(match_result, route)
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
  end
end

# Define application routes
Routes.root('articles#list')
Routes.resources('articles') do
  Routes.nested_resources('comments', only: [:create, :destroy])
end
