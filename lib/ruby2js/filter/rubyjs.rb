require 'ruby2js'

module Ruby2JS
  module Filter
    module RubyJS
      include SEXP

      def on_send(node)
        # leave functional style calls alone
        target = node.children.first
        return super if target and [:_s, :_a, :_h, :_n, :_i, :_t].
          include? target.children[1]

        method = node.children[1]
        return super if excluded?(method)

        # leave classic ("OO") style call chains alone
        while target and target.type == :send
          return super if target.children[1] == :R
          target = target.children.first
        end

        if 
          [:capitalize, :center, :chomp, :ljust, :lstrip, :rindex, :rjust,
            :rstrip, :scan, :swapcase, :tr].include? method
        then
          # map selected string functions
          s(:send, s(:lvar, :_s), method,
            *process_all([node.children[0], *node.children[2..-1]]))

        elsif 
          [:at, :compact, :compact!, :delete_at, :delete_at, :flatten, :insert,
          :reverse, :reverse!, :rotate, :rotate, :rotate!, :shift, :shuffle,
          :shuffle!, :slice, :slice!, :transpose, :union, :uniq, :uniq!]
          .include? method
        then
          # map selected array functions
          s(:send, s(:lvar, :_a), method.to_s.sub("!", '_bang'),
            *process_all([node.children[0], *node.children[2..-1]]))


        elsif [:strftime].include? method
          # map selected time functions
          s(:send, s(:lvar, :_t), method,
            *process_all([node.children[0], *node.children[2..-1]]))

        elsif method == :<=>
          s(:send, s(:attr, s(:const, nil, :R), :Comparable), :cmp,
            node.children[0], *node.children[2..-1])

        elsif method == :between?
          s(:send, s(:send, nil, :R, node.children[0]), :between,
            *node.children[2..-1])

        else
          super
        end
      end

      def on_block(node)
        call, args, *block = node.children
        method = call.children[1]
        return super if excluded?(method)

        if 
          [:collect_concat, :count, :cycle, :delete_if, :drop_while,
          :each_index, :each_slice, :each_with_index, :each_with_object,
          :find, :find_all, :flat_map, :inject, :grep, :group_by, :keep_if,
          :map, :max_by, :min_by, :one?, :partition, :reject, :reverse_each,
          :select!, :sort_by, :take_while].include? method
        then
          if 
            [:collect_concat, :count, :delete_if, :drop_while, :find,
            :find_all, :flat_map, :grep, :group_by, :keep_if, :map, :max_by,
            :min_by, :one?, :partition, :reject, :select!, :sort_by,
            :take_while].include? method
          then
            block = [ s(:autoreturn, *block) ]
          end

          lvar = [:each_index, :keep_if, :select!].include?(method) ? :_a : :_e

          if method == :find and call.children.length == 2
            call = s(:send, *call.children, s(:nil))
          elsif method == :inject and call.children.length == 3
            call = s(:send, *call.children, s(:nil))
          elsif method == :select!
            call = s(:send, call.children.first, :select_bang,
              *call.children[2..-1])
          end

          s(:block, s(:send, s(:lvar, lvar), call.children[1],
            *process_all([call.children[0], *call.children[2..-1]])),
            args, *block)
        else
          super
        end
      end

      def on_irange(node)
        s(:send, s(:attr, s(:const, nil, :R), :Range), :new, *node.children)
      end

      def on_erange(node)
        s(:send, s(:attr, s(:const, nil, :R), :Range), :new, *node.children,
          s(:true))
      end
    end

    DEFAULTS.push RubyJS
  end
end
