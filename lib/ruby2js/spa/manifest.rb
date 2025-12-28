# frozen_string_literal: true

module Ruby2JS
  module Spa
    # Manifest DSL for configuring SPA generation
    #
    # Example:
    #   Ruby2JS::Spa.configure do
    #     name :scoring
    #     mount_path '/offline/scores'
    #
    #     routes do
    #       only controllers: [:scores], actions: [:heat, :card, :update]
    #     end
    #
    #     models do
    #       include :Heat, :Entry, :Score
    #     end
    #
    #     views do
    #       include 'scores/_table_heat.html.erb'
    #     end
    #
    #     stimulus do
    #       include 'score_controller.js'
    #     end
    #
    #     sync do
    #       endpoint '/api/spa/sync'
    #       writable :Score
    #     end
    #   end
    #
    class Manifest
      attr_reader :name, :mount_path, :runtime, :database, :css, :root_route
      attr_reader :route_config, :model_config, :view_config
      attr_reader :controller_config, :stimulus_config, :sync_config

      # Valid runtime/database combinations
      VALID_COMBINATIONS = {
        browser: %i[dexie sqljs pglite],
        node: %i[better_sqlite3 pg mysql],
        bun: %i[better_sqlite3 pg mysql],
        deno: %i[pg mysql]
      }.freeze

      # Valid CSS framework options
      VALID_CSS_OPTIONS = %i[none pico tailwind].freeze

      def initialize
        @runtime = :browser
        @database = :dexie
        @css = :none
        @root_route = nil
        @route_config = RouteConfig.new
        @model_config = ModelConfig.new
        @view_config = ViewConfig.new
        @controller_config = ControllerConfig.new
        @stimulus_config = StimulusConfig.new
        @sync_config = SyncConfig.new
      end

      # DSL methods
      def name(value = nil)
        return @name if value.nil?
        @name = value.to_sym
      end

      def mount_path(value = nil)
        return @mount_path if value.nil?
        @mount_path = value
      end

      def runtime(value = nil)
        return @runtime if value.nil?
        @runtime = value.to_sym
      end

      def database(value = nil)
        return @database if value.nil?
        @database = value.to_sym
      end

      def css(value = nil)
        return @css if value.nil?
        @css = value.to_sym
      end

      def root(value = nil)
        return @root_route if value.nil?
        @root_route = value
      end

      # Check if this is a browser-based SPA
      def browser?
        @runtime == :browser
      end

      # Check if this targets a server runtime
      def server?
        !browser?
      end

      def routes(&block)
        @route_config.instance_eval(&block) if block_given?
        @route_config
      end

      def models(&block)
        @model_config.instance_eval(&block) if block_given?
        @model_config
      end

      def views(&block)
        @view_config.instance_eval(&block) if block_given?
        @view_config
      end

      def controllers(&block)
        @controller_config.instance_eval(&block) if block_given?
        @controller_config
      end

      def stimulus(&block)
        @stimulus_config.instance_eval(&block) if block_given?
        @stimulus_config
      end

      def sync(&block)
        @sync_config.instance_eval(&block) if block_given?
        @sync_config
      end

      # Validation
      def valid?
        errors.empty?
      end

      def errors
        errs = []
        errs << 'name is required' unless @name
        errs << 'mount_path is required' unless @mount_path

        # Validate runtime/database combination
        unless VALID_COMBINATIONS.key?(@runtime)
          errs << "invalid runtime '#{@runtime}' (valid: #{VALID_COMBINATIONS.keys.join(', ')})"
        else
          valid_dbs = VALID_COMBINATIONS[@runtime]
          unless valid_dbs.include?(@database)
            errs << "invalid database '#{@database}' for runtime '#{@runtime}' (valid: #{valid_dbs.join(', ')})"
          end
        end

        # Validate CSS framework
        unless VALID_CSS_OPTIONS.include?(@css)
          errs << "invalid css '#{@css}' (valid: #{VALID_CSS_OPTIONS.join(', ')})"
        end

        errs
      end
    end

    # Route filtering configuration
    class RouteConfig
      attr_reader :controllers, :actions, :only_routes, :except_routes

      def initialize
        @controllers = []
        @actions = []
        @only_routes = []
        @except_routes = []
      end

      def only(controllers: nil, actions: nil)
        @controllers = Array(controllers).map(&:to_sym) if controllers
        @actions = Array(actions).map(&:to_sym) if actions
      end

      def include_route(pattern)
        @only_routes << pattern
      end

      def exclude_route(pattern)
        @except_routes << pattern
      end

      def matches_controller?(name)
        return true if @controllers.empty?
        @controllers.include?(name.to_sym)
      end

      def matches_action?(name)
        return true if @actions.empty?
        @actions.include?(name.to_sym)
      end
    end

    # Model configuration
    class ModelConfig
      attr_reader :included_models, :excluded_models

      def initialize
        @included_models = []
        @excluded_models = []
      end

      def include(*model_names)
        @included_models.concat(model_names.flatten.map(&:to_sym))
      end

      def exclude(*model_names)
        @excluded_models.concat(model_names.flatten.map(&:to_sym))
      end

      def includes?(model_name)
        name = model_name.to_sym
        return false if @excluded_models.include?(name)
        return true if @included_models.empty?
        @included_models.include?(name)
      end
    end

    # View configuration
    class ViewConfig
      attr_reader :included_views

      def initialize
        @included_views = []
      end

      def include(*patterns)
        @included_views.concat(patterns.flatten)
      end
    end

    # Controller configuration
    class ControllerConfig
      attr_reader :included_controllers

      def initialize
        @included_controllers = {}
      end

      # Include a controller with optional action filtering
      # Usage:
      #   include :articles                    # all actions
      #   include :scores, only: [:heat, :card]  # specific actions
      def include(controller_name, only: nil, except: nil)
        name = controller_name.to_sym
        @included_controllers[name] = {
          only: only&.map(&:to_sym),
          except: except&.map(&:to_sym)
        }
      end

      # Get the list of actions to include for a controller
      def actions_for(controller_name)
        config = @included_controllers[controller_name.to_sym]
        return nil unless config
        config[:only]
      end

      # Check if a controller should be included
      def includes?(controller_name)
        @included_controllers.key?(controller_name.to_sym)
      end
    end

    # Stimulus controller configuration
    class StimulusConfig
      attr_reader :included_controllers

      def initialize
        @included_controllers = []
      end

      def include(*controller_names)
        @included_controllers.concat(controller_names.flatten)
      end
    end

    # Sync configuration
    class SyncConfig
      attr_reader :endpoint, :writable_models

      def initialize
        @writable_models = []
      end

      def endpoint(value = nil)
        return @endpoint if value.nil?
        @endpoint = value
      end

      def writable(*model_names)
        @writable_models.concat(model_names.flatten.map(&:to_sym))
      end
    end
  end
end
