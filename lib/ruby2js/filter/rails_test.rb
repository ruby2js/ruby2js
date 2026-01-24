# Rails integration test support for Minitest -> Vitest transpilation.
#
# Handles Rails-specific test patterns:
#   get articles_url -> response = await get(articles_path())
#   post articles_url, params: {...} -> response = await post(articles_path(), {...})
#   articles(:one) -> await loadFixture('articles', 'one')
#   articles_url -> articles_path()
#   article_url(@article) -> article_path(article)
#
# Used together with the Minitest filter for full Rails test transpilation.

require 'ruby2js'

module Ruby2JS
  module Filter
    module RailsTest
      include SEXP

      def initialize(*args)
        @rails_test = nil
        @rails_test_fixtures = {}
        super
      end

      # Track when we're in a test class
      def on_class(node)
        class_name, superclass, _body = node.children

        if integration_test_class?(superclass)
          @rails_test = true
          result = super
          @rails_test = nil
          @rails_test_fixtures = {}
          result
        else
          super
        end
      end

      # Handle HTTP method calls and fixture loading
      def on_send(node)
        return super unless @rails_test

        target, method, *args = node.children

        # Handle fixture loading: articles(:one) -> await loadFixture('articles', 'one')
        if target.nil? && args.length == 1 && args.first&.type == :sym
          fixture_name = method.to_s
          # Check if this looks like a fixture call (plural model name)
          if fixture_name.end_with?('s') || fixture_name == 'people'
            return transform_fixture_call(method, args.first)
          end
        end

        # Handle HTTP methods: get, post, patch, put, delete
        if target.nil? && [:get, :post, :patch, :put, :delete, :head].include?(method)
          return transform_http_call(method, args)
        end

        # Handle URL helpers: articles_url -> articles_path()
        if target.nil? && method.to_s.end_with?('_url')
          return transform_url_helper(method, args)
        end

        super
      end

      # Transform @article in test context -> article (local var from fixture)
      def on_ivar(node)
        return super unless @rails_test

        var_name = node.children.first.to_s.sub(/^@/, '')
        s(:lvar, var_name.to_sym)
      end

      # Transform @article = ... -> article = ...
      def on_ivasgn(node)
        return super unless @rails_test

        var_name = node.children.first.to_s.sub(/^@/, '')
        value = node.children[1]
        s(:lvasgn, var_name.to_sym, process(value))
      end

      private

      def integration_test_class?(superclass)
        return false unless superclass&.type == :const

        superclass_name = const_name(superclass)
        [
          'IntegrationTest',
          'ActionDispatch::IntegrationTest'
        ].any? { |name| superclass_name.include?(name.split('::').last) }
      end

      def const_name(node)
        return '' unless node&.type == :const
        parent = node.children[0]
        name = node.children[1].to_s
        parent ? "#{const_name(parent)}::#{name}" : name
      end

      def transform_fixture_call(model, key_node)
        # articles(:one) -> await loadFixture('articles', 'one')
        model_name = model.to_s
        key = key_node.children.first.to_s

        s(:send, nil, :await,
          s(:send, nil, :loadFixture,
            s(:str, model_name),
            s(:str, key)))
      end

      def transform_http_call(method, args)
        # get articles_url -> response = await get(articles_path())
        # post articles_url, params: {...} -> response = await post(articles_path(), params)

        url = args.first
        params = nil

        # Extract params from options hash
        if args.length > 1 && args[1]&.type == :hash
          args[1].children.each do |pair|
            key = pair.children[0]
            value = pair.children[1]
            if key.type == :sym && key.children[0] == :params
              params = value
            end
          end
        end

        # Build the HTTP call
        http_call = if params
                      s(:send, nil, method, process(url), process(params))
                    else
                      s(:send, nil, method, process(url))
                    end

        # response = await http_call
        s(:lvasgn, :response, s(:send, nil, :await, http_call))
      end

      def transform_url_helper(method, args)
        # articles_url -> articles_path()
        # article_url(@article) -> article_path(article)
        # new_article_url -> new_article_path()

        path_method = method.to_s.sub(/_url$/, '_path').to_sym

        if args.empty?
          s(:send!, nil, path_method)
        else
          s(:send, nil, path_method, *process_all(args))
        end
      end
    end

    DEFAULTS.push RailsTest
  end
end
