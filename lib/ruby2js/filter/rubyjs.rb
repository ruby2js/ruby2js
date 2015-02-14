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

        # leave classic ("OO") style call chains alone
        while target and target.type == :send
          return super if target.children[1] == :R
          target = target.children.first
        end

        if 
          [:capitalize, :center, :chomp, :ljust, :lstrip, :rindex, :rjust,
            :rstrip, :scan, :swapcase, :tr].include? node.children[1]
        then
          # map selected string functions
          s(:send, s(:lvar, :_s), node.children[1],
            *process_all([node.children[0], *node.children[2..-1]]))

        elsif [:strftime].include? node.children[1]
          # map selected time functions
          s(:send, s(:lvar, :_t), node.children[1],
            *process_all([node.children[0], *node.children[2..-1]]))

        else
          super
        end
      end
    end

    DEFAULTS.push RubyJS
  end
end
