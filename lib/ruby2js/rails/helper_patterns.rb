# Shared helper pattern matching for Rails ERB transformations
#
# This module extracts and analyzes Rails helper calls, returning structured
# data that can be used by different output formats (JavaScript AST, Astro templates, etc.)
#
# Usage:
#   patterns = HelperPatterns.new(ast_node)
#   if result = patterns.match_link_to
#     # result is a hash with :text, :path, :options, etc.
#   end

require 'ruby2js/inflector'

module Ruby2JS
  module Rails
    class HelperPatterns
      def initialize(options = {})
        @options = options
      end

      # Match link_to helper and extract components
      # Returns: { text:, path:, method:, confirm:, css_class:, css_class_node:, is_delete: }
      def match_link_to(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :link_to && target.nil? && args.length >= 2

        text_node = args[0]
        path_node = args[1]
        options_node = args[2]

        result = {
          text_node: text_node,
          text: extract_string(text_node),
          path_node: path_node,
          path: extract_path_info(path_node),
          is_delete: false,
          confirm: nil,
          css_class: nil,
          css_class_node: nil
        }

        if options_node&.type == :hash
          extract_link_options(options_node, result)
        end

        result
      end

      # Match button_to helper and extract components
      # Returns: { text:, path:, method:, confirm:, css_class:, form_class: }
      def match_button_to(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :button_to && target.nil? && args.length >= 2

        text_node = args[0]
        path_node = args[1]
        options_node = args[2]

        result = {
          text_node: text_node,
          text: extract_string(text_node) || 'Submit',
          path_node: path_node,
          path: extract_path_info(path_node),
          method: :post,
          confirm: nil,
          css_class: nil,
          form_class: nil
        }

        if options_node&.type == :hash
          extract_button_options(options_node, result)
        end

        result
      end

      # Match render helper and extract components
      # Returns: { partial_name:, locals:, is_collection:, collection_node:, directory: }
      def match_render(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :render && target.nil? && args.any?

        first_arg = args[0]
        result = {
          partial_name: nil,
          locals: {},
          is_collection: false,
          collection_node: nil,
          directory: nil
        }

        case first_arg.type
        when :str
          # render "form" or render "form", article: @article
          result[:partial_name] = first_arg.children[0]
          extract_render_locals(args[1], result) if args[1]

        when :hash
          # render partial: "form", locals: { ... }
          extract_render_hash_options(first_arg, result)

        when :ivar
          # render @article or render @messages (collection)
          ivar_name = first_arg.children[0].to_s.sub(/^@/, '')
          result[:partial_name] = singularize(ivar_name)
          result[:is_collection] = (result[:partial_name] != ivar_name)
          result[:collection_node] = first_arg
          if result[:is_collection]
            result[:locals][result[:partial_name].to_sym] = :loop_var
          else
            result[:locals][ivar_name.to_sym] = first_arg
          end

        when :lvar
          # render article or render messages (collection)
          var_name = first_arg.children[0].to_s
          result[:partial_name] = singularize(var_name)
          result[:is_collection] = (result[:partial_name] != var_name)
          result[:collection_node] = first_arg
          if result[:is_collection]
            result[:locals][result[:partial_name].to_sym] = :loop_var
          else
            result[:locals][var_name.to_sym] = first_arg
          end

        when :send
          if first_arg.children[0].nil?
            # Bare method call like: render article (parsed as s(:send, nil, :article))
            # This happens when article is a local variable in the ERB context
            var_name = first_arg.children[1].to_s
            result[:partial_name] = singularize(var_name)
            result[:is_collection] = (result[:partial_name] != var_name)
            result[:collection_node] = first_arg
            if result[:is_collection]
              result[:locals][result[:partial_name].to_sym] = :loop_var
            else
              result[:locals][var_name.to_sym] = first_arg
            end
          else
            # render @article.comments or render article.comments (collection)
            method_name = first_arg.children[1].to_s
            result[:partial_name] = singularize(method_name)
            result[:is_collection] = (result[:partial_name] != method_name)
            result[:collection_node] = first_arg
            result[:directory] = method_name if result[:is_collection]
            if result[:is_collection]
              result[:locals][result[:partial_name].to_sym] = :loop_var
            end
          end
        end

        return nil unless result[:partial_name]
        result
      end

      # Match truncate helper
      # Returns: { text_node:, length: }
      def match_truncate(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :truncate && target.nil? && args.length >= 1

        result = {
          text_node: args[0],
          length: 30  # default
        }

        if args[1]&.type == :hash
          args[1].children.each do |pair|
            key, value = pair.children
            if key.type == :sym && key.children[0] == :length && value.type == :int
              result[:length] = value.children[0]
            end
          end
        end

        result
      end

      # Match pluralize helper
      # Returns: { count_node:, singular_node:, plural_node: }
      def match_pluralize(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :pluralize && target.nil? && args.length >= 2

        {
          count_node: args[0],
          singular_node: args[1],
          plural_node: args[2]
        }
      end

      # Match dom_id helper
      # Returns: { record_node:, prefix_node: }
      def match_dom_id(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :dom_id && target.nil? && args.length >= 1

        {
          record_node: args[0],
          prefix_node: args[1]
        }
      end

      # Match form_with block
      # Returns: { model_name:, model_node:, model_is_new:, parent_model_name:, url_node:, method:, css_class:, data_attrs: }
      def match_form_with(block_node)
        return nil unless block_node.type == :block
        send_node = block_node.children[0]
        return nil unless send_node.type == :send

        target, method = send_node.children[0..1]
        return nil unless method == :form_with && target.nil?

        block_args = block_node.children[1]
        block_body = block_node.children[2]
        options_node = send_node.children[2]

        result = {
          model_name: nil,
          model_node: nil,
          model_is_new: false,
          parent_model_name: nil,
          url_node: nil,
          method: :post,
          css_class: nil,
          data_attrs: {},
          block_param: block_args.children.first&.children&.first,
          block_body: block_body
        }

        if options_node&.type == :hash
          extract_form_with_options(options_node, result)
        end

        result
      end

      # Match content_for helper
      # Returns: { key:, value_node:, is_getter: }
      def match_content_for(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :content_for && target.nil?
        return nil if args.empty?

        key_node = args[0]
        value_node = args[1]

        return nil unless key_node.type == :sym

        {
          key: key_node.children[0],
          value_node: value_node,
          is_getter: value_node.nil?
        }
      end

      # Match turbo_stream_from helper
      # Returns: { channel_node: }
      def match_turbo_stream_from(node)
        return nil unless node.type == :send
        target, method, *args = node.children
        return nil unless method == :turbo_stream_from && target.nil? && args.length >= 1

        { channel_node: args[0] }
      end

      # Extract class information from a node
      # Returns: { static: ["class1", "class2"], conditionals: [{class: "name", condition: node}] }
      def extract_class_info(node)
        return nil unless node

        case node.type
        when :str
          { static: [node.children[0]], conditionals: [] }
        when :array
          static = []
          conditionals = []

          node.children.each do |child|
            if child.type == :str
              static << child.children[0]
            elsif child.type == :hash
              child.children.each do |pair|
                key, condition = pair.children
                class_name = case key.type
                when :str then key.children[0]
                when :sym then key.children[0].to_s
                end
                conditionals << { class: class_name, condition: condition } if class_name
              end
            end
          end

          { static: static, conditionals: conditionals }
        else
          nil
        end
      end

      # Extract path information from a node
      # Returns: { type:, helper:, model:, args:, static_path: }
      def extract_path_info(node)
        return nil unless node

        case node.type
        when :str
          { type: :static, static_path: node.children[0] }

        when :ivar
          # @article -> article_path(article)
          model = node.children[0].to_s.sub(/^@/, '')
          { type: :model, model: model, helper: "#{model}_path" }

        when :lvar
          # article -> article_path(article)
          model = node.children[0].to_s
          { type: :model, model: model, helper: "#{model}_path" }

        when :send
          if node.children[0].nil?
            method_name = node.children[1].to_s
            args = node.children[2..-1]
            if method_name.end_with?('_path', '_url')
              { type: :helper, helper: method_name, args: args }
            else
              # Bare method call treated as model
              { type: :model, model: method_name, helper: "#{method_name}_path" }
            end
          else
            { type: :expression, node: node }
          end

        when :array
          # Nested resource: [@article, comment]
          if node.children.length == 2
            parent, child = node.children
            parent_model = extract_model_name(parent)
            child_model = extract_model_name(child)
            { type: :nested, parent: parent_model, child: child_model,
              helper: "#{child_model}_path", parent_node: parent, child_node: child }
          else
            { type: :expression, node: node }
          end

        else
          { type: :expression, node: node }
        end
      end

      private

      def extract_string(node)
        return nil unless node
        node.type == :str ? node.children[0] : nil
      end

      def extract_model_name(node)
        case node.type
        when :ivar then node.children[0].to_s.sub(/^@/, '')
        when :lvar then node.children[0].to_s
        when :send then node.children[1].to_s
        else nil
        end
      end

      def extract_link_options(options_node, result)
        options_node.children.each do |pair|
          key, value = pair.children
          next unless key.type == :sym

          case key.children[0]
          when :method
            result[:is_delete] = (value.type == :sym && value.children[0] == :delete)
            result[:method] = value.children[0] if value.type == :sym
          when :class
            result[:css_class] = extract_static_class(value)
            result[:css_class_node] = value
          when :data
            extract_data_options(value, result)
          end
        end
      end

      def extract_button_options(options_node, result)
        options_node.children.each do |pair|
          key, value = pair.children
          next unless key.type == :sym

          case key.children[0]
          when :method
            result[:method] = value.children[0] if value.type == :sym
          when :class
            result[:css_class] = extract_static_class(value)
          when :form_class
            result[:form_class] = extract_static_class(value)
          when :data
            extract_data_options(value, result)
          end
        end
      end

      def extract_data_options(value, result)
        return unless value.type == :hash
        value.children.each do |data_pair|
          data_key, data_value = data_pair.children
          if data_key.type == :sym && [:confirm, :turbo_confirm].include?(data_key.children[0])
            result[:confirm] = data_value.children[0] if data_value.type == :str
          end
        end
      end

      def extract_static_class(node)
        case node.type
        when :str
          node.children[0]
        when :array
          node.children.select { |c| c.type == :str }.map { |c| c.children[0] }.join(' ')
        else
          nil
        end
      end

      def extract_render_locals(hash_node, result)
        return unless hash_node&.type == :hash
        hash_node.children.each do |pair|
          key, value = pair.children
          result[:locals][key.children[0]] = value if key.type == :sym
        end
      end

      def extract_render_hash_options(hash_node, result)
        hash_node.children.each do |pair|
          key, value = pair.children
          next unless key.type == :sym

          case key.children[0]
          when :partial
            result[:partial_name] = value.children[0] if value.type == :str
          when :locals
            extract_render_locals(value, result)
          end
        end
      end

      def extract_form_with_options(options_node, result)
        options_node.children.each do |pair|
          key, value = pair.children
          next unless key.type == :sym

          case key.children[0]
          when :model
            extract_form_model(value, result)
          when :url
            result[:url_node] = value
          when :method
            result[:method] = value.children[0] if value.type == :sym
          when :class
            result[:css_class] = extract_static_class(value)
          when :data
            extract_form_data_attrs(value, result)
          end
        end
      end

      def extract_form_model(value, result)
        case value.type
        when :ivar
          result[:model_name] = value.children[0].to_s.sub(/^@/, '')
          result[:model_node] = value
        when :lvar
          result[:model_name] = value.children[0].to_s
          result[:model_node] = value
        when :send
          if value.children[0].nil?
            result[:model_name] = value.children[1].to_s
            result[:model_node] = value
          elsif value.children[1] == :new
            # Model.new
            const_node = value.children[0]
            if const_node&.type == :const
              result[:model_name] = const_node.children[1].to_s.downcase
              result[:model_is_new] = true
            end
          end
        when :array
          # Nested resource: [@article, Comment.new]
          if value.children.length >= 2
            parent = value.children.first
            child = value.children.last
            result[:parent_model_name] = extract_model_name(parent)
            if child.type == :send && child.children[1] == :new
              const_node = child.children[0]
              if const_node&.type == :const
                result[:model_name] = const_node.children[1].to_s.downcase
                result[:model_is_new] = true
              end
            end
          end
        end
      end

      def extract_form_data_attrs(value, result)
        return unless value.type == :hash
        value.children.each do |data_pair|
          data_key, data_value = data_pair.children
          next unless data_key.type == :sym
          attr_name = data_key.children[0].to_s.gsub('_', '-')
          case data_value.type
          when :str then result[:data_attrs][attr_name] = data_value.children[0]
          when :true then result[:data_attrs][attr_name] = "true"
          when :false then result[:data_attrs][attr_name] = "false"
          end
        end
      end

      def singularize(name)
        Ruby2JS::Inflector.singularize(name)
      end
    end
  end
end
