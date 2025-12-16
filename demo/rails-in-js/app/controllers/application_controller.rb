# Base controller class
class ApplicationController
  attr_accessor :params, :request, :response

  def initialize
    @params = {}
    @instance_variables = {}
  end

  # Instance variable handling for views
  def set_instance_variable(name, value)
    @instance_variables[name] = value
  end

  def get_instance_variables
    @instance_variables
  end

  # Render a view template
  def render(template, options = {})
    status = options[:status] || 200
    locals = @instance_variables.dup

    # template can be :new, :edit, etc. or "articles/show"
    if template.is_a?(Symbol)
      template = "#{controller_name}/#{template}"
    end

    html = Views.render(template, locals)
    { status: status, body: html, type: 'html' }
  end

  # Redirect to a path
  def redirect_to(target)
    path = if target.is_a?(String)
      target
    elsif target.respond_to?(:id)
      # redirect_to @article
      "/#{target.class.name.downcase}s/#{target.id}"
    else
      target.to_s
    end
    { status: 302, redirect: path }
  end

  # Helper to get controller name from class
  def controller_name
    self.class.name.gsub('Controller', '').downcase
  end

  # Strong parameters helpers
  class Parameters
    def initialize(hash)
      @hash = hash || {}
    end

    def require(key)
      value = @hash[key.to_s] || @hash[key]
      raise "param is missing or the value is empty: #{key}" unless value
      Parameters.new(value)
    end

    def permit(*keys)
      result = {}
      keys.each do |key|
        key_s = key.to_s
        result[key_s] = @hash[key_s] if @hash.key?(key_s)
        result[key_s] = @hash[key] if @hash.key?(key)
      end
      result
    end

    def [](key)
      @hash[key.to_s] || @hash[key]
    end

    def to_h
      @hash
    end
  end

  def params
    @params_obj ||= Parameters.new(@params)
  end

  # before_action support
  class << self
    def before_actions
      @before_actions ||= []
    end

    def before_action(method_name, options = {})
      before_actions << { method: method_name, options: options }
    end

    def run_before_actions(controller, action)
      before_actions.each do |ba|
        only = ba[:options][:only]
        except = ba[:options][:except]

        should_run = true
        should_run = only.include?(action) if only
        should_run = !except.include?(action) if except

        controller.send(ba[:method]) if should_run
      end
    end
  end
end
