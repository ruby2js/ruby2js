#
require 'ruby2js'

module Ruby2JS
  module Filter
    module Stimulus
      include SEXP
      extend  SEXP

      STIMULUS_IMPORT = s(:import,
        [s(:pair, s(:sym, :as), s(:const, nil, :Stimulus)),
          s(:pair, s(:sym, :from), s(:str, "@hotwired/stimulus"))],
          s(:str, '*'))

      STIMULUS_IMPORT_SKYPACK = s(:import,
        [s(:pair, s(:sym, :as), s(:const, nil, :Stimulus)),
          s(:pair, s(:sym, :from), s(:str, "https://cdn.skypack.dev/@hotwired/stimulus"))],
          s(:str, '*'))

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
          inheritance == s(:const, s(:const, nil, :Stimulus), :Controller) or
          inheritance == s(:send, s(:const, nil, :Stimulus), :Controller) or
          @stim_subclasses.include? @namespace.resolve(inheritance)

        if inheritance == s(:const, nil, :Stimulus)
          node = node.updated(nil, [node.children.first,
            s(:const, s(:const, nil, :Stimulus), :Controller),
            *node.children[2..-1]])
        end

        @stim_subclasses << @stim_scope + @namespace.resolve(cname)

        @stim_targets = Set.new
        @stim_values = Set.new
        @stim_classes = Set.new
        @stim_outlets = Set.new
        stim_walk(node)

        if modules_enabled?
          prepend_list << (@options[:import_from_skypack] ?
            STIMULUS_IMPORT_SKYPACK : STIMULUS_IMPORT)
        end

        nodes = body
        if nodes.length == 1 and nodes.first&.type == :begin
          nodes = nodes.first.children.dup
        end

        unless @stim_classes.empty?
          classes = nodes.find_index {|child| 
            child.type == :send and child.children[0..1] == [s(:self), :classes=]
          }

          if classes == nil
            nodes.unshift s(:send, s(:self), :classes=, s(:array, *@stim_classes))
          elsif nodes[classes].children[2].type == :array
            @stim_classes.merge(nodes[classes].children[2].children)
            nodes[classes] = nodes[classes].updated(nil,
              [*nodes[classes].children[0..1], s(:array, *@stim_classes)])
          end
        end

        unless @stim_values.empty?
          values = nodes.find_index {|child| 
            child.type == :send and child.children[0..1] == [s(:self), :values=]
          }

          if values == nil
            nodes.unshift s(:send, s(:self), :values=, s(:hash,
            *@stim_values.map {|name| s(:pair, name, s(:const, nil, :String))}))
          elsif nodes[values].children[2].type == :hash
            stim_values = @stim_values.map {|name| 
              [s(:sym, name.children.first.to_sym), s(:const, nil, :String)]
            }.to_h.merge(
              nodes[values].children[2].children.map {|pair| pair.children}.to_h
            )

            nodes[values] = nodes[values].updated(nil,
              [*nodes[values].children[0..1], s(:hash,
              *stim_values.map{|name, value| s(:pair, name, value)})])
          end
        end

        unless @stim_targets.empty?
          targets = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :targets=]
          }

          if targets == nil
            nodes.unshift s(:send, s(:self), :targets=, s(:array, *@stim_targets))
          elsif nodes[targets].children[2].type == :array
            @stim_targets.merge(nodes[targets].children[2].children)
            nodes[targets] = nodes[targets].updated(nil,
              [*nodes[targets].children[0..1], s(:array, *@stim_targets)])
          end
        end

        unless @stim_outlets.empty?
          outlets = nodes.find_index {|child|
            child.type == :send and child.children[0..1] == [s(:self), :outlets=]
          }

          if outlets == nil
            nodes.unshift s(:send, s(:self), :outlets=, s(:array, *@stim_outlets))
          elsif nodes[outlets].children[2].type == :array
            @stim_outlets.merge(nodes[outlets].children[2].children)
            nodes[outlets] = nodes[outlets].updated(nil,
              [*nodes[outlets].children[0..1], s(:array, *@stim_outlets)])
          end
        end

        props = [:element, :application]

        props += @stim_targets.map do |name|
          name = name.children.first
          ["#{name}Target", "#{name}Targets", "has#{name[0].upcase}#{name[1..-1]}Target"]
        end

        props += @stim_values.map do |name|
          name = name.children.first
          ["#{name}Value", "has#{name[0].upcase}#{name[1..-1]}Value"]
        end

        props += @stim_classes.map do |name|
          name = name.children.first
          ["#{name}Class", "has#{name[0].upcase}#{name[1..-1]}Class"]
        end

        props += @stim_outlets.map do |name|
          name = name.children.first
          ["#{name}Outlet", "#{name}Outlets", "has#{name[0].upcase}#{name[1..-1]}Outlet"]
        end

        props = props.flatten.map {|prop| [prop.to_sym, s(:self)]}.to_h

        props[:initialize] = s(:autobind, s(:self))

        nodes.unshift s(:defineProps, props)

        nodes.pop unless nodes.last

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
              name = s(:str, $1[0].downcase + $1[1..-1])
              @stim_targets.add name if $2 == 'Target'
              @stim_values.add name if $2 == 'Value'
              @stim_classes.add name if $2 == 'Class'
              @stim_outlets.add name if $2 == 'Outlet'
            elsif child.children[1] =~ /^(\w+)Targets?$/
              @stim_targets.add s(:str, $1)
            elsif child.children[1] =~ /^(\w+)Value=?$/
              @stim_values.add s(:str, $1)
            elsif child.children[1] =~ /^(\w+)Class$/
              @stim_classes.add s(:str, $1)
            elsif child.children[1] =~ /^(\w+)Outlets?$/
              @stim_outlets.add s(:str, $1)
            end

          elsif child.type == :send and child.children.length == 3 and
            [s(:self), s(:send, nil, :this)].include? child.children[0]

            if child.children[1] =~ /^(\w+)Value=$/
              @stim_values.add s(:str, $1)
            end

          elsif child.type == :lvasgn
            if child.children[0] =~ /^(\w+)Value$/
              @stim_values.add s(:str, $1)
            end

          elsif child.type == :def
            if child.children[0] =~ /^(\w+)ValueChanged$/
              @stim_values.add s(:str, $1)
            elsif child.children[0] =~ /^(\w+)Outlet(Connected|Disconnected)$/
              @stim_outlets.add s(:str, $1)
            end
          end

        end
      end
    end

    DEFAULTS.push Stimulus
  end
end
