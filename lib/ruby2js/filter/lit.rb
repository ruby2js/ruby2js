require 'ruby2js'

module Ruby2JS
  module Filter
    module Lit
      include SEXP
      extend  SEXP

      LITELEMENT_IMPORT = s(:import,
        [s(:pair, s(:sym, :from), s(:str, "lit"))],
        [s(:const, nil, :LitElement), s(:attr, nil, :css), s(:attr, nil, :html)])

      # Import just html for Phlex+Lit mode
      # Structure: s(:import, [from_pair], [named_imports])
      HTML_IMPORT = s(:import,
        [s(:pair, s(:sym, :from), s(:str, "lit"))],
        [s(:const, nil, :html)])

      def initialize(node)
        super
        @le_props = nil
        @lit_phlex_mode = false
      end

      def options=(options)
        super
        # Detect if Phlex filter is present for Phlex → Lit compilation
        filters = options[:filters] || Filter::DEFAULTS
        if defined?(Ruby2JS::Filter::Phlex) && filters.include?(Ruby2JS::Filter::Phlex)
          @lit_phlex_mode = true
        end
      end

      # Handle pnode (from Phlex filter) - convert to Lit tagged template
      def on_pnode(node)
        return super unless @lit_phlex_mode

        # Add html import if not already present
        add_html_import

        tag, attrs, *children = node.children

        # Build the template literal content
        dstr_parts = build_lit_template(tag, attrs, children)

        # Wrap in html tagged template
        s(:taglit, s(:sym, :html), s(:dstr, *dstr_parts))
      end

      def add_html_import
        return unless respond_to?(:prepend_list) && respond_to?(:modules_enabled?)
        return unless modules_enabled?

        # Check if we already have the html import
        has_import = prepend_list.any? do |node|
          next false unless node.respond_to?(:type) && node.type == :import
          # Check for our HTML_IMPORT pattern - children[1] can be an array
          second_child = node.children[1]
          if second_child.is_a?(Array)
            second_child.any? { |c| c.respond_to?(:type) && c.type == :const && c.children[1] == :html }
          elsif second_child.respond_to?(:type)
            second_child.type == :const && second_child.children[1] == :html
          else
            false
          end
        end

        prepend_list << HTML_IMPORT unless has_import
      end

      # Handle pnode_text (from Phlex filter)
      def on_pnode_text(node)
        return super unless @lit_phlex_mode

        content = node.children.first
        if content.type == :str
          content
        else
          s(:begin, process(content))
        end
      end

      private

      # Build template literal parts for a pnode
      def build_lit_template(tag, attrs, children)
        parts = []

        if tag.nil?
          # Fragment - just children
          children.each do |child|
            parts.concat(build_lit_child(child))
          end
        elsif tag.to_s[0] =~ /[A-Z]/
          # Component - render as function call within interpolation
          # ${ComponentName.render({props})}
          component_call = s(:send, s(:const, nil, tag), :render, attrs || s(:hash))
          parts << s(:str, '')
          parts << s(:begin, component_call)
          parts << s(:str, '')
        else
          # HTML element
          tag_str = tag.to_s
          opening = "<#{tag_str}"
          opening += build_lit_attrs_static(attrs)

          # Check for dynamic attrs
          dynamic_attrs = build_lit_attrs_dynamic(attrs)
          if dynamic_attrs.empty?
            opening += ">"
            parts << s(:str, opening)
          else
            parts << s(:str, opening)
            dynamic_attrs.each do |attr_part|
              parts.concat(attr_part)
            end
            parts << s(:str, ">")
          end

          # Void elements
          void_elements = %i[area base br col embed hr img input link meta param source track wbr]
          unless void_elements.include?(tag_str.to_sym)
            children.each do |child|
              parts.concat(build_lit_child(child))
            end
            parts << s(:str, "</#{tag_str}>")
          end
        end

        # Merge adjacent string parts
        merge_string_parts(parts)
      end

      def build_lit_child(child)
        parts = []
        case child.type
        when :pnode_text
          content = child.children.first
          if content.type == :str
            parts << content
          else
            parts << s(:begin, process(content))
          end
        when :pnode
          tag, attrs, *grandchildren = child.children
          parts.concat(build_lit_template(tag, attrs, grandchildren))
        when :block
          # Loop - convert to .map() with html template body
          parts << s(:begin, build_lit_loop(child))
        when :for, :for_of
          # Converted loop - wrap body in html template
          parts << s(:begin, build_lit_for_loop(child))
        else
          # Other expression - wrap in interpolation
          parts << s(:begin, process(child))
        end
        parts
      end

      # Convert a block loop to use .map() with html template
      def build_lit_loop(block_node)
        send_node, block_args, block_body = block_node.children
        return process(block_node) unless send_node.type == :send

        target, method, *args = send_node.children

        # Convert .each to .map for template interpolation
        if [:each, :each_with_index].include?(method)
          method = :map
        end

        # Build the body as an html template
        body_parts = []
        if block_body.type == :pnode
          tag, attrs, *children = block_body.children
          body_parts = build_lit_template(tag, attrs, children)
        else
          # Process as regular expression
          return process(block_node)
        end

        # Return array.map(args => html`...`)
        html_body = s(:taglit, s(:sym, :html), s(:dstr, *merge_string_parts(body_parts)))
        s(:block,
          s(:send, process(target), method, *args.map { |a| process(a) }),
          block_args,
          html_body)
      end

      # Handle for/for_of loops
      def build_lit_for_loop(for_node)
        # For now, just process as-is (functions filter may have converted)
        process(for_node)
      end

      def build_lit_attrs_static(attrs)
        return '' unless attrs&.type == :hash

        result = ''
        attrs.children.each do |pair|
          next unless pair.type == :pair
          key_node, value_node = pair.children

          key = case key_node.type
          when :sym then key_node.children.first.to_s
          when :str then key_node.children.first
          else next
          end

          # Convert underscores to dashes
          key = key.gsub('_', '-')

          case value_node.type
          when :str
            result += " #{key}=\"#{value_node.children.first.gsub('"', '&quot;')}\""
          when :sym
            result += " #{key}=\"#{value_node.children.first}\""
          when :true
            result += " #{key}"
          when :false
            # Skip false boolean attributes
          end
        end
        result
      end

      def build_lit_attrs_dynamic(attrs)
        return [] unless attrs&.type == :hash

        result = []
        attrs.children.each do |pair|
          next unless pair.type == :pair
          key_node, value_node = pair.children

          key = case key_node.type
          when :sym then key_node.children.first.to_s
          when :str then key_node.children.first
          else next
          end

          key = key.gsub('_', '-')

          # Only handle dynamic values here
          unless [:str, :sym, :true, :false].include?(value_node.type)
            result << [s(:str, " #{key}=\""), s(:begin, process(value_node)), s(:str, "\"")]
          end
        end
        result
      end

      def merge_string_parts(parts)
        return parts if parts.empty?

        merged = []
        current_str = nil

        parts.each do |part|
          if part.type == :str
            if current_str
              current_str = s(:str, current_str.children.first + part.children.first)
            else
              current_str = part
            end
          else
            merged << current_str if current_str
            current_str = nil
            merged << part
          end
        end

        merged << current_str if current_str
        merged
      end

      public

      def on_ivar(node)
        return super unless @le_props&.include?(node.children.first) # Pragma: hash
        process s(:attr, s(:self), node.children.first.to_s[1..-1])
      end

      def on_ivasgn(node)
        return super unless @le_props&.include?(node.children.first) # Pragma: hash
        return super unless node.children.length > 1

        process s(:send, s(:self), node.children.first.to_s[1..-1]+'=',
          process(node.children[1]))
      end

      def on_op_asgn(node)
        return super unless node.children.first.type == :ivasgn
        var = node.children.first.children.first
        return super unless @le_props&.include?(var) # Pragma: hash
        super node.updated(nil, [s(:attr, s(:attr, nil, :this),
          var.to_s[1..-1]), *node.children[1..-1]])
      end

      def on_class(node)
        class_name, inheritance, *body = node.children
        return super unless inheritance == s(:const, nil, :LitElement)

        @le_props = {}
        le_walk(node)

        self.prepend_list << LITELEMENT_IMPORT if self.modules_enabled?()

        nodes = body.dup
        if nodes.length == 1 and nodes.first&.type == :begin
          nodes = nodes.first.children.dup
        end

        # insert/update static get properties() {}
        unless @le_props.empty?
          values = nodes.find_index {|child| 
            (child.type == :defs and child.children[0..1] == [s(:self), :properties]) or
            (child.type == :send and child.children[0..1] == [s(:self), :properties=])
          }

          if values == nil || values < 0
            props_pairs = @le_props.map {|name, type| # Pragma: entries
              s(:pair, s(:sym, name.to_s[1..-1]),
              s(:hash, s(:pair, s(:sym, :type), s(:const, nil, type || :String))))
            }
            if es2022
              nodes.unshift process(s(:casgn, nil, :properties, s(:hash, *props_pairs)))
            else
              nodes.unshift process(s(:defp, s(:self), :properties, s(:args), s(:return,
                s(:hash, *props_pairs))))
            end
          elsif nodes[values].children.last.type == :hash
            le_props_array = @le_props.map {|name, type| # Pragma: entries
              [s(:sym, name.to_s[1..-1].to_sym),
              s(:hash, s(:pair, s(:sym, :type), s(:const, nil, type || :String)))]
            }
            le_props = le_props_array.to_h.merge(
              nodes[values].children.last.children.map {|pair| pair.children}.to_h
            )

            le_props_final = le_props.map{|name, value| s(:pair, name, value)} # Pragma: entries
            nodes[values] = nodes[values].updated(nil,
              [*nodes[values].children[0..-2], s(:hash, *le_props_final)])
          end
        end

        # customElement is converted to customElements.define
        customElement = nodes.find_index {|child| 
          child&.type == :send and (child.children[0..1] == [nil, :customElement] || child.children[0..1] == [nil, :custom_element])
        }
        if customElement != nil and customElement >= 0 and nodes[customElement].children.length == 3
          nodes[customElement] = nodes[customElement].updated(nil,
            [s(:attr, nil, :customElements), :define,
            nodes[customElement].children.last, class_name])
        end

        # render of a string is converted to a taglit :html
        render = nodes.find_index {|child| 
          child&.type == :def and child.children.first == :render
        }
        if render != nil and render >= 0 and %i[str dstr begin if block].include?(nodes[render].children[2]&.type)
          nodes[render] = nodes[render].updated(:deff,
            [*nodes[render].children[0..1],
            s(:autoreturn, html_wrap(nodes[render].children[2]))])
        end

        # self.styles returning string is converted to a taglit :css
        styles = nodes.find_index {|child| 
          (child&.type == :ivasgn and child.children[0] == :@styles) or
          (child&.type == :defs and child.children[0..1] == [s(:self), :styles]) or
          (child&.type == :send and child.children[0..1] == [s(:self), :styles=])
        }
        if styles != nil and styles >= 0 and %i[str dstr].include?(nodes[styles].children.last&.type)
          string = nodes[styles].children.last
          string = s(:dstr, string) if string.type == :str
          children = string.children.dup

          while children.length > 1 and children.last.type == :str and
            children.last.children.last.strip == ''
            children.pop
          end

          if children.last.type == :str
            children << s(:str, children.pop.children.first.chomp)
          end

          if es2022
            nodes[styles] = nodes[styles].updated(:casgn,
              [nil, :styles, s(:taglit, s(:sym, :css),
              s(:dstr, *children))])
          else
            nodes[styles] = nodes[styles].updated(:defp,
              [s(:self), :styles, s(:args),
              s(:autoreturn, s(:taglit, s(:sym, :css),
              s(:dstr, *children)))])
          end
        end

        # insert super calls into initializer
        initialize = nodes.find_index {|child| 
          child&.type == :def and child.children.first == :initialize
        }
        if initialize != nil and initialize >= 0 and nodes[initialize].children.length == 3
          statements = nodes[initialize].children[2..-1]

          if statements.length == 1 and statements.first.type == :begin
            statements = statements.first.children 
          end

          unless statements.any? {|statement| %i[super zuper].include?  statement.type}
            nodes[initialize] = nodes[initialize].updated(nil,
            [*nodes[initialize].children[0..1],
            s(:begin, s(:zsuper), *statements)])
          end
        end

        # props/methods inherited from LitElement
        props = {
          hasUpdated: s(:self),
          performUpdate: s(:autobind, s(:self)),
          renderRoot: s(:self),
          requestUpdate: s(:autobind, s(:self)),
          shadowRoot: s(:self),
          updateComplete: s(:self),
        }

        # local props
        local_props = @le_props.keys().map {|prop| [prop.to_sym, s(:self)]}.to_h
        props.merge! local_props

        nodes.unshift s(:defineProps, props)

        nodes.pop unless nodes.last

        node.updated(nil, [*node.children[0..1], s(:begin, *process_all(nodes))])
      ensure
        @le_props = nil
      end

      def html_wrap(node)
        return node unless Ruby2JS.ast_node?(node)

        if node.type == :str and node.children.first.strip.start_with? '<'
          s(:taglit, s(:sym, :html), s(:dstr, node))
        elsif node.type == :dstr
          prefix = ''
          node.children.each do |child|
            break unless child.type == :str
            prefix += child.children.first
          end

          return node unless prefix.strip.start_with? '<'

          children = node.children.map do |child|
            if child.type == :str
              child
            else
              html_wrap(child)
            end
          end

          while children.length > 1 and children.last.type == :str and
            children.last.children.last.strip == ''
            children.pop
          end

          if children.last.type == :str
            children << s(:str, children.pop.children.first.chomp)
          end

          s(:taglit, s(:sym, :html), node.updated(nil, children))
        elsif node.type == :begin
          node.updated(nil, node.children.map {|child| html_wrap(child)})
        elsif node.type == :if
          node.updated(nil, [node.children.first,
            *node.children[1..2].map {|child| html_wrap(child)}])
        elsif node.type == :block and
          node.children.first.children[1] == :map
          node.updated(nil, [*node.children[0..1],
            html_wrap(node.children[2])])
        else
          node
        end
      end

      def on_def(node)
        node = super
        return node if [:constructor, :initialize].include?(node.children.first)

        children = node.children[1..-1]

        node.updated nil, [node.children[0], children.first,
          *(children[1..-1].map {|child| html_wrap(child) })]
      end

      # analyze ivar usage
      def le_walk(node)
        node.children.each do |child|
          next unless Ruby2JS.ast_node?(child)

          if child.type == :ivar
            next if child.children.first.to_s.start_with?("@_")

            @le_props[child.children.first] ||= nil
          elsif child.type == :ivasgn || child.type == :op_asgn
            prop = child.children.first
            if prop.respond_to?(:type)
              prop = prop.children.first if prop.type == :ivasgn
              next if prop.respond_to?(:type)
            end

            next if prop.to_s.start_with?("@_")

            @le_props[prop] = case child.children.last.type
              when :str, :dstr
                :String
              when :array
                :Array
              when :int, :float
                :Number
              when :true, :false
                :Boolean
              else
                @le_props[prop] || :Object
            end
          else
            le_walk(child)
          end
        end
      end

      def on_send(node)
        target, method, *args = node.children

        return super if target
        return super unless %i{query queryAll queryAsync}.include? method
        return super unless args.length == 1

        result = s(:csend, s(:attr, s(:self), :renderRoot),
          (method == :query ? 'querySelector' : 'querySelectorAll'),
          args.first)

        if method == :queryAsync
          result = s(:block, s(:send, s(:attr, s(:self), :updateComplete),
            :then), s(:args), result)
        end

        result
      end
    end

    DEFAULTS.push Lit
  end
end
