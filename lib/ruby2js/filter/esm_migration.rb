require 'ruby2js'

module Ruby2JS
  module Filter
    module ESMMigration
      include SEXP

      def initialize(*args)
        @esm_include = nil
        super
      end

      def process(node)
        return super if @esm_include
        @esm_include = Set.new
        @esm_exclude = Set.new
        @esm_export = nil
        result = super

        esm_walk(result)

        inventory = (@esm_include - @esm_exclude).to_a.sort

        if inventory.empty? and not @esm_export
          result
        else
          list = inventory.map do |name|
             if name == "React" and defined? Ruby2JS::Filter::React
               s(:import, "#{name.downcase}", s(:const, nil, name))
             elsif not %w(JSON Object).include? name
               s(:import, "./#{name.downcase}.js", s(:const, nil, name))
             end
          end

          list.push result

          if @esm_export
            list.push s(:export, :default, s(:const, nil, @esm_export))
          end

          s(:begin, *list.compact)
        end
      end

      # gather constants
      def esm_walk(node)
        # extract ivars and cvars
        if node.type == :const and node.children.first == nil
          @esm_include << node.children.last.to_s
        elsif node.type == :xnode
          name = node.children.first
          @esm_include << name unless name.empty? or name =~ /^[a-z]/
        elsif node.type == :casgn and node.children.first == nil
          @esm_exclude << node.children[1].to_s
        elsif node.type == :class and node.children.first.type == :const
          if node.children.first.children.first == nil
            name = node.children.first.children.last.to_s
            @esm_exclude << name
            @esm_export ||= name
          end
        end

        # recurse
        node.children.each do |child|
          esm_walk(child) if Parser::AST::Node === child
        end
      end
    end

    DEFAULTS.push ESMMigration
  end
end
