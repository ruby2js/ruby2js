#
require 'ruby2js'

module Ruby2JS
  module Filter
    module Stimulus
      include SEXP
      extend  SEXP

      # Named import: import { Controller } from "@hotwired/stimulus"
      STIMULUS_IMPORT = s(:import,
        ["@hotwired/stimulus"],
        [s(:attr, nil, :Controller)])

      def initialize(*args)
        super
        @stim_scope = []
        @stim_subclasses = []
        @stim_outlets = Set.new
      end

      def on_module(node)
        save_scope = @stim_scope
        @stim_scope += @namespace.resolve(node.children.first)
        super
      ensure
        @stim_scope = save_scope
      end

      def on_class(node)
        cname, inheritance, *body = node.children
        return super unless inheritance == s(:const, nil, :Stimulus) or
          inheritance == s(:const, nil, :Controller) or
          inheritance == s(:const, s(:const, nil, :Stimulus), :Controller) or
          inheritance == s(:send, s(:const, nil, :Stimulus), :Controller) or
          @stim_subclasses.include? @namespace.resolve(inheritance)

        # Normalize Stimulus/Stimulus::Controller/Stimulus.Controller to just Controller
        # But preserve inheritance from known subclasses (e.g., DemoController)
        if inheritance == s(:const, nil, :Stimulus) or
           inheritance == s(:const, s(:const, nil, :Stimulus), :Controller) or
           inheritance == s(:send, s(:const, nil, :Stimulus), :Controller)
          node = node.updated(nil, [node.children.first,
            s(:const, nil, :Controller),
            *node.children[2..-1]])
        end

        @stim_subclasses << @stim_scope + @namespace.resolve(cname)

        @stim_targets = Set.new
        @stim_values = Set.new
        @stim_classes = Set.new
        @stim_outlets = Set.new
        stim_walk(node)

        if self.modules_enabled?()
          self.prepend_list << STIMULUS_IMPORT
        end

        nodes = body
        if nodes.length == 1 and nodes.first&.type == :begin
          nodes = nodes.first.children.dup
        end

        unless @stim_classes.size == 0
          classes = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :classes=]
          }

          if classes.nil? || classes == -1
            nodes.unshift s(:send, s(:self), :classes=, s(:array, *[*@stim_classes].map { |c| s(:str, c) }))
          elsif nodes[classes].children[2].type == :array
            nodes[classes].children[2].children.each {|item| @stim_classes << item.children.first}
            nodes[classes] = nodes[classes].updated(nil,
              [*nodes[classes].children[0..1], s(:array, *[*@stim_classes].map { |c| s(:str, c) })])
          end
        end

        unless @stim_values.size == 0
          values = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :values=]
          }

          if values.nil? || values == -1
            nodes.unshift s(:send, s(:self), :values=, s(:hash,
            *[*@stim_values].map {|name| s(:pair, s(:str, name), s(:const, nil, :String))}))
          elsif nodes[values].children[2].type == :hash
            # Get existing pairs from the explicit values= declaration
            existing_pairs = nodes[values].children[2].children
            # Get keys from existing pairs for deduplication
            existing_keys = existing_pairs.map { |pair| pair.children.first.children.first }
            # Build pairs for inferred values, excluding those already declared
            inferred_pairs = [*@stim_values].map { |name|
              next if existing_keys.include?(name) || existing_keys.include?(name.to_sym)
              s(:pair, s(:sym, name.to_sym), s(:const, nil, :String))
            }.compact

            nodes[values] = nodes[values].updated(nil,
              [*nodes[values].children[0..1], s(:hash,
              *inferred_pairs, *existing_pairs)])
          end
        end

        unless @stim_targets.size == 0
          targets = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :targets=]
          }

          if targets.nil? || targets == -1
            nodes.unshift s(:send, s(:self), :targets=, s(:array, *[*@stim_targets].map { |t| s(:str, t) }))
          elsif nodes[targets].children[2].type == :array
            nodes[targets].children[2].children.each {|item| @stim_targets << item.children.first}
            nodes[targets] = nodes[targets].updated(nil,
              [*nodes[targets].children[0..1], s(:array, *[*@stim_targets].map { |t| s(:str, t) })])
          end
        end

        unless @stim_outlets.size == 0
          outlets = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :outlets=]
          }

          if outlets.nil? || outlets == -1
            nodes.unshift s(:send, s(:self), :outlets=, s(:array, *[*@stim_outlets].map { |o| s(:str, o) }))
          elsif nodes[outlets].children[2].type == :array
            nodes[outlets].children[2].children.each {|item| @stim_outlets << item.children.first}
            nodes[outlets] = nodes[outlets].updated(nil,
              [*nodes[outlets].children[0..1], s(:array, *[*@stim_outlets].map { |o| s(:str, o) })])
          end
        end

        # Read-only properties use s(:self)
        readonly_props = [:element, :application]

        readonly_props.push(*[*@stim_targets].map { |name|
          ["#{name}Target", "#{name}Targets", "has#{name[0].upcase}#{name[1..-1]}Target"]
        })

        readonly_props.push(*[*@stim_classes].map { |name|
          ["#{name}Class", "has#{name[0].upcase}#{name[1..-1]}Class"]
        })

        readonly_props.push(*[*@stim_outlets].map { |name|
          ["#{name}Outlet", "#{name}Outlets", "has#{name[0].upcase}#{name[1..-1]}Outlet"]
        })

        # Value properties are read-write, use s(:setter, s(:self)) to support assignment
        value_props = [*@stim_values].map { |name|
          ["#{name}Value", "has#{name[0].upcase}#{name[1..-1]}Value"]
        }

        props = readonly_props.flatten.map {|prop| [prop.to_sym, s(:self)]}.to_h
        props.merge!(value_props.flatten.map {|prop| [prop.to_sym, s(:setter, s(:self))]}.to_h)

        props[:initialize] = s(:autobind, s(:self))

        nodes.unshift s(:defineProps, props)

        nodes.pop unless nodes.last

        # Collect attr_reader/attr_accessor names - these are intentionally property accessors
        attr_reader_names = Set.new
        nodes.each do |n|
          if n.type == :send && %i[attr_reader attr_accessor].include?(n.children[1])
            n.children[2..].each do |arg|
              attr_reader_names.add(arg.children.first) if arg.type == :sym
            end
          end
        end

        # Convert def nodes to defm to ensure they're methods, not getters.
        # Exception: methods overriding attr_reader/attr_accessor stay as getters.
        nodes = nodes.map do |n|
          if n.type == :def && !attr_reader_names.include?(n.children.first)
            n.updated(:defm, n.children)
          else
            n
          end
        end

        node.updated(nil, [*node.children[0..1], s(:begin, *process_all(nodes))])
      end

      # analyze ivar usage
      def stim_walk(node)
        node.children.each do |child|
          next unless Ruby2JS.ast_node?(child)
          stim_walk(child)

          if child.type == :send and child.children.length == 2 and
            [nil, s(:self), s(:send, nil, :this)].include? child.children[0]

            if child.children[1] =~ /^has([A-Z]\w*)(Target|Value|Class|Outlet)$/
              name = $1[0].downcase + $1[1..-1]
              @stim_targets.add name if $2 == 'Target'
              @stim_values.add name if $2 == 'Value'
              @stim_classes.add name if $2 == 'Class'
              @stim_outlets.add name if $2 == 'Outlet'
            elsif child.children[1] =~ /^(\w+)Targets?$/
              @stim_targets.add $1
            elsif child.children[1] =~ /^(\w+)Value=?$/
              @stim_values.add $1
            elsif child.children[1] =~ /^(\w+)Class$/
              @stim_classes.add $1
            elsif child.children[1] =~ /^(\w+)Outlets?$/
              @stim_outlets.add $1
            end

          elsif child.type == :send and child.children.length == 3 and
            [s(:self), s(:send, nil, :this)].include? child.children[0]

            if child.children[1] =~ /^(\w+)Value=$/
              @stim_values.add $1
            end

          elsif child.type == :lvasgn
            if child.children[0] =~ /^(\w+)Value$/
              @stim_values.add $1
            end

          elsif child.type == :def
            if child.children[0] =~ /^(\w+)ValueChanged$/
              @stim_values.add $1
            elsif child.children[0] =~ /^(\w+)Outlet(Connected|Disconnected)$/
              @stim_outlets.add $1
            end
          end

        end
      end
    end

    DEFAULTS.push Stimulus
  end
end
