require 'ruby2js'
#
# Jquery functions are either invoked using jQuery() or, more commonly, $().
# The former presents no problem, the latter is not legal Ruby.
#
# Accordingly, the first accomodation this filter provides is to map $$ to
# $.  This works find for $$.ajax and the like, but less so for direct calls
# as $$(this) is also a syntax error.  $$.(this) and $$[this] will work
# but are a bit clumsy.
#
# So as a second accomodation, the rarely used binary one's complement unary
# operator (namely, ~) is usurped, and the AST is rewritten to provide the
# effect of this operator being of a higher precedence than method calls.
#
# As a part of this rewriting, calls to getters and setters are rewritten
# to match jQuery's convention for getters and setters:
#  http://learn.jquery.com/using-jquery-core/working-with-selections/
#
# Of course, using jQuery's style of getter and setter calls is supported,
# and indeed is convenient when using method chaining.
#
# Finally, the tilde AST rewriting can be avoided by using consecutive tildes
# (~~ is a common Ruby idiom for Math.floor, ~~~ will return the binary
# one's complement.); and the getter and setter AST rewriting can be avoided
# by the use of parenthesis, e.g. (~this).text.
# 
# Some examples of before/after conversions:
#
#   `this.val
#   $(this).val()
#
#   `"button.continue".html = "Next Step..."
#   $("button.continue").html("Next Step...")
#
#  $$.ajax(
#    url: "/api/getWeather",
#    data: {zipcode: 97201},
#    success: proc do |data|
#      `"#weather-temp".html = "<strong>#{data}</strong> degrees"
#    end
#  )
#
#  $.ajax({
#    url: "/api/getWeather",
#    data: {zipcode: 97201},
#    success: function(data) {
#      $("#weather-temp").html("<strong>" + data + "</strong> degrees");
#    }
#  })

module Ruby2JS
  module Filter
    module JQuery
      include SEXP

      def initialize
        @each = true # disable each mapping, see functions filter
      end

      # map $$ to $
      def on_gvar(node)
        if node.children[0] == :$$
          node.updated nil, ['$']
        else
          super
        end
      end

      def on_send(node)
        if [:call, :[]].include? node.children[1]
          # map $$.call(..), $$.(..), and $$[...] to $(...)
          target = process(node.children.first)
          if target.type == :gvar and target.children == ['$']
            s(:send, nil, '$', *process_all(node.children[2..-1]))
          else
            super
          end

        elsif node.children[1] == :~
          # map ~expression.method to $(expression).method

          if node.children[0] and node.children[0].type == :op_asgn
            asgn = node.children[0]
            if asgn.children[0] and asgn.children[0].type == :send
              inner = asgn.children[0]
              return on_send s(:send, s(:send, inner.children[0],
                (inner.children[1].to_s+'=').to_sym,
                s(:send, s(:send, s(:send, inner.children[0], :~),
                *inner.children[1..-1]), *asgn.children[1..-1])), :~)
            else
              return on_send asgn.updated nil, [s(:send, asgn.children[0], :~),
                *asgn.children[1..-1]]
            end
          end

          # See http://api.jquery.com/category/properties/
          props = :context, :jquery, :browser, :fx, :support, :length, :selector

          rewrite_tilda = proc do |node|
            # Example conversion:
            #   before:
            #    (send (send (send (send nil :a) :b) :c) :~)
            #   after:
            #    (send (send (send nil "$" (send nil :a)) :b) :c)
            if node.type == :send and node.children[0]
              if node.children[1] == :~ and node.children[0].children[1] == :~
                # consecutive tildes
                if node.children[0].children[0].children[1] == :~
                  result = process(node.children[0].children[0].children[0])
                else
                  result = s(:send, process(node.children[0].children[0]), :~)
                end
                s(:send, s(:send, result, :~), :~)
              else
                # possible getter/setter
                method = node.children[1]
                method = method.to_s.chomp('=') if method =~ /=$/
                rewrite = [rewrite_tilda[node.children[0]], 
                  method, *process_all(node.children[2..-1])]
                if props.include? node.children[1]
                  node.updated nil, rewrite
                else
                  s(:send, *rewrite)
                end
              end
            elsif node.type == :block
              # method call with a block parameter
              node.updated nil, [rewrite_tilda[node.children[0]],
                *process_all(node.children[1..-1])]
            else
              # innermost expression
              s(:send, nil, '$', process(node))
            end
          end

          rewrite_tilda[node].children[0]
        else
          super
        end
      end
    end

    DEFAULTS.push JQuery
  end
end
