require 'ruby2js'
require_relative 'active_record'

module Ruby2JS
  module Filter
    module Rails
      module Concern
        include SEXP

        def initialize(*args)
          super
          @rails_concern = nil
        end

        def on_module(node)
          return super if @rails_concern

          name = node.children.first
          body = node.children[1..-1]

          # Flatten begin wrapper
          while body.length == 1 && body.first&.type == :begin
            body = body.first.children
          end

          # Detect: is there an `extend ActiveSupport::Concern`?
          has_concern = body.any? { |n| concern_extend?(n) }
          return super unless has_concern

          @rails_concern = true

          # Transform body
          new_body = transform_concern_body(body)

          # Force the IIFE path in the module converter by adding a public marker.
          # This ensures concerns use underscored_private (@x -> this._x) instead of
          # ES2022 private fields (#x) which are invalid in object literals.
          # The module converter omits bare public markers from output.
          new_body.unshift(s(:send, nil, :public)) unless new_body.empty?

          # Rebuild module with cleaned body
          if new_body.empty?
            new_body_node = nil
          elsif new_body.length == 1
            new_body_node = new_body.first
          else
            new_body_node = s(:begin, *new_body)
          end

          result = node.updated(nil, [name, new_body_node])

          @rails_concern = nil
          super(result)
        end

        private

        # Detect: s(:send, nil, :extend, s(:const, s(:const, nil, :ActiveSupport), :Concern))
        def concern_extend?(node)
          return false unless node.respond_to?(:type)
          node.type == :send &&
            node.children[0].nil? &&
            node.children[1] == :extend &&
            node.children[2]&.type == :const &&
            node.children[2].children[1] == :Concern &&
            node.children[2].children[0]&.type == :const &&
            node.children[2].children[0].children[1] == :ActiveSupport
        end

        def transform_concern_body(body)
          result = []

          body.each do |node|
            next unless node.respond_to?(:type)

            case node.type
            when :send
              if node.children[0].nil?
                case node.children[1]
                when :extend
                  # Strip extend ActiveSupport::Concern (and any other extend)
                  next if concern_extend?(node)
                  result << node

                when :attr_accessor
                  # Transform to getter + setter def pairs
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, attr, s(:args),
                      s(:ivar, :"@#{attr}"))
                    result << s(:def, :"#{attr}=", s(:args, s(:arg, :val)),
                      s(:ivasgn, :"@#{attr}", s(:lvar, :val)))
                  end

                when :attr_reader
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, attr, s(:args),
                      s(:ivar, :"@#{attr}"))
                  end

                when :attr_writer
                  node.children[2..-1].each do |sym_node|
                    attr = sym_node.children.first
                    result << s(:def, :"#{attr}=", s(:args, s(:arg, :val)),
                      s(:ivasgn, :"@#{attr}", s(:lvar, :val)))
                  end

                when :alias_method
                  new_name = node.children[2].children.first
                  old_name = node.children[3].children.first

                  # Strip if names differ only by ?/! suffix
                  new_base = new_name.to_s.sub(/[?!]$/, '')
                  old_base = old_name.to_s.sub(/[?!]$/, '')
                  unless new_base == old_base
                    result << s(:def, new_name, s(:args),
                      s(:send, nil, old_name))
                  end

                when :delegate
                  # Strip delegate calls
                  next

                when :private, :public, :protected
                  # Keep visibility markers (bare ones with no args)
                  if node.children.length == 2
                    result << node
                  end
                  # Skip visibility with specific method names (e.g., private :foo)

                when :include
                  # Strip include calls in concerns — framework modules
                  # (e.g., ActionView::Helpers::TagHelper) don't exist in JS.
                  # The including class handles its own includes.
                  next

                else
                  # Keep other send nodes
                  result << node
                end
              else
                result << node
              end

            when :block
              # Strip included do...end and class_methods do...end
              if node.children[0].type == :send &&
                 node.children[0].children[0].nil? &&
                 [:included, :class_methods].include?(node.children[0].children[1])
                next
              end
              result << node

            when :def, :defs
              # Keep method definitions
              result << node

            else
              # Keep everything else (begin, class, module, etc.)
              result << node
            end
          end

          result
        end
      end
    end

    DEFAULTS.push Rails::Concern
  end
end
