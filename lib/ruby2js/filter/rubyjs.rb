require 'ruby2js'

module Ruby2JS
  module Filter
    module RubyJS
      include SEXP

      def on_send(node)
        if 
          [:capitalize, :center, :chomp, :ljust, :lstrip, :rindex, :rjust,
            :rstrip, :scan, :swapcase, :tr].include? node.children[1]
        then
          s(:send, s(:lvar, :_s), node.children[1],
            *process_all([node.children[0], *node.children[2..-1]]))

        elsif [:strftime].include? node.children[1]
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
