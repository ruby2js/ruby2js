# TODO: This feature is deprecated.

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
# Passing multiple parameters can be accomplished by using array index
# syntax (e.g., ~['a', self])
#
# As a part of this rewriting, calls to getters and setters are rewritten
# to match jQuery's convention for getters and setters:
#  http://learn.jquery.com/using-jquery-core/working-with-selections/
#
# Selected DOM properties (namely checked, disabled, readOnly, and required)
# can also use getter and setter syntax.  Additionally, readOnly may be
# spelled 'readonly'.
#
# Of course, using jQuery's style of getter and setter calls is supported,
# and indeed is convenient when using method chaining.
#
# Additionally, the tilde AST rewriting can be avoided by using consecutive
# tildes (~~ is a common Ruby idiom for Math.floor, ~~~ will return the binary
# one's complement.); and the getter and setter AST rewriting can be avoided
# by the use of parenthesis, e.g. (~this).text.
#
# Finally, the fourth parameter of $.post defaults to :json, allowing Ruby
# block syntax to be used for the success function.
# 
# Some examples of before/after conversions:
#
#   ~this.val
#   $(this).val()
#
#   ~"button.continue".html = "Next Step..."
#   $("button.continue").html("Next Step...")
#
#   ~"button".readonly = false
#   $("button").prop("readOnly", false)
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

      def initialize(*args)
        @react = nil
        super
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
        # :attr nodes with :~ method come from consecutive tilde handling
        # Pass them through to the converter which handles :attr
        if node.type == :attr
          return node.updated(nil, [
            node.children[0] ? process(node.children[0]) : nil,
            *node.children[1..-1]
          ])
        end

        if [:call, :[]].include? node.children[1] and node.children.first
          # map $$.call(..), $$.(..), and $$[...] to $(...)
          target = process(node.children.first)
          if target.type == :gvar and target.children == ['$']
            s(:send, nil, '$', *process_all(node.children[2..-1]))
          else
            super
          end

        elsif node.children[1] == :to_a
          process S(:call, node.children[0], :toArray, *node.children[2..-1])

        elsif node.children[1] == :~ and not @react
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
          domprops = %w(checked disabled readonly readOnly required)

          stopProps = false
          rewrite_tilda = proc do |tnode|
            # Example conversion:
            #   before:
            #    (send (send (send (send nil :a) :b) :c) :~)
            #   after:
            #    (send (send (send nil "$" (send nil :a)) :b) :c)
            if tnode.type == :attr
              # :attr nodes created by consecutive tilde handling should pass through
              tnode
            elsif tnode.type == :send and tnode.children[0]
              stopProps = true if tnode.children[1] == :[]
              if tnode.children[1] == :~ and tnode.children[0].children[1] == :~
                # consecutive tildes
                if tnode.children[0].children[0].children[1] == :~
                  result = tnode.children[0].children[0].children[0]
                else
                  result = s(:attr, tnode.children[0].children[0], :~)
                end
                s(:attr, s(:attr, process(result), :~), :~)
              else
                # possible getter/setter
                method = tnode.children[1]
                method = method.to_s.chomp('=') if method =~ /=$/
                method = :each! if method == :each
                rewrite = [rewrite_tilda[tnode.children[0]], 
                  method, *tnode.children[2..-1]]
                if stopProps or props.include? tnode.children[1]
                  rewrite[1] = tnode.children[1]
                  tnode.updated nil, rewrite
                elsif domprops.include? method.to_s
                  method = :readOnly if method.to_s == 'readonly'
                  # Use :send! to force method call output (with parens)
                  s(:send!, rewrite[0], :prop, s(:sym, method), *rewrite[2..-1])
                else
                  # Use :send! to force method call output (with parens)
                  # This is needed for jQuery-style method chaining
                  s(:send!, *rewrite)
                end
              end
            elsif tnode.type == :block
              # method call with a block parameter
              tnode.updated nil, [rewrite_tilda[tnode.children[0]],
                *tnode.children[1..-1]]
            elsif tnode.type == :array
              # innermost expression is an array
              s(:send, nil, '$', *tnode)
            else
              # innermost expression is a scalar
              s(:send, nil, '$', tnode)
            end
          end

          process rewrite_tilda[node].children[0]
        else
          super
        end
      end

      # Example conversion:
      #   before:
      #    $$.post ... do ... end
      #    (block (send (gvar :$$) :post ...) (args) (...))
      #   after:
      #    $$.post ..., proc { ... }, :json
      #    (send (gvar :$$) :post ... 
      #      (block (send nil :proc) (args) (...)) (:sym :json))
      def on_block(node)
        call = node.children.first
        return super unless call.children.first == s(:gvar, :$$)
        return super unless call.children[1] == :post
        return super unless call.children.length <= 4
        children = call.children.dup
        children << s(:str, '') if children.length <= 2
        children << s(:hash) if children.length <= 3
        children << s(:block, s(:send, nil, :proc), *node.children[1..-1])
        children << s(:sym, :json)
        process call.updated nil, children
      end
    end

    DEFAULTS.push JQuery
  end
end
