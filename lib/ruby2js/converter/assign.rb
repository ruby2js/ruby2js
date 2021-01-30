# Kinda like Object.assign, except it handles properties
#
# Note: Object.defineProperties, Object.getOwnPropertyNames, etc. technically
#   were not part of ES5, but were implemented by IE prior to ES6, and are
#   the only way to implement getters and setters.

module Ruby2JS
  class Converter

   # (assign
   #   target
   #   (hash)
   #   ...

    handle :assign do |target, *args|
      collapsible = false

      nonprop = proc do |node|
        next true unless node.is_a? Parser::AST::Node
        next false if node.type == :pair and node.children.first.type == :prop and es2015
        next true unless node.type == :def
        next false if node.children.first.to_s.end_with? '='
        node.is_method?
      end

      collapsible = true if args.length == 1 and args.first.type == :hash and
        args.first.children.length == 1

      collapsible = true if args.length == 1 and args.first.type == :class_module and
        args.first.children.length == 3 and nonprop[args.first.children.last]

      if es2015 and not collapsible and
        args.all? {|arg| arg.children.all? {|child| nonprop[child]}}
        parse s(:send, s(:const, nil, :Object), :assign, target, *args)
      else

        if target == s(:hash)
          copy = [s(:gvasgn, :$$, target)]
          target = s(:gvar, :$$)
          shadow = [s(:shadowarg, :$$)]
        elsif collapsible or es2015 or
          (%i(send const).include? target.type and
          target.children.length == 2 and target.children[0] == nil)
        then
          copy = []
          shadow = []
        else
          copy = [s(:gvasgn, :$0, target)]
          target = s(:gvar, :$0)
          shadow = [s(:shadowarg, :$0)]
        end

        body = [*copy,
          *args.map {|modname|
            if modname.type == :hash and
              modname.children.all? {|pair| pair.children.first.type == :prop}

              if modname.children.length == 1
                pair = modname.children.first
                s(:send, s(:const, nil, :Object), :defineProperty, target, 
                  s(:sym, pair.children.first.children.last),
                  s(:hash, *pair.children.last.map {|name, value| s(:pair,
                  s(:sym, name), value)}))
              else
                pair = modname.children.first
                s(:send, s(:const, nil, :Object), :defineProperties, target, 
                  s(:hash, *modname.children.map {|pair| s(:pair,
                    s(:sym, pair.children.first.children.last),
                    s(:hash, *pair.children.last.map {|name, value| s(:pair,
                    s(:sym, name), value)})
                  )}))
              end

            elsif modname.type == :hash and
              modname.children.all? {|child| nonprop[child]}

              s(:begin, *modname.children.map {|pair|
                if pair.children.first.type == :prop
                  s(:send, s(:const, nil, :Object), :defineProperty, target, 
                    s(:sym, pair.children.first.children.last),
                    s(:hash, *pair.children.last.map {|name, value| s(:pair,
                    s(:sym, name), value)}))
                else
                  s(:send, target, :[]=, *pair.children)
                end
              })

            elsif modname.type == :class_module and
              modname.children[2..-1].all? {|child| nonprop[child]}

              s(:begin, *modname.children[2..-1].map {|pair|
                  s(:send, target, :[]=, s(:sym, pair.children.first),
                  pair.updated(:defm, [nil, *pair.children[1..-1]]))
                })

            elsif modname.type == :lvar and not es2015
              s(:for, s(:lvasgn, :$_), modname,
              s(:send, target, :[]=,
              s(:lvar, :$_), s(:send, modname, :[], s(:lvar, :$_))))

            else
              if es2017
                s(:send, s(:const, nil, :Object), :defineProperties, target, 
                  s(:send, s(:const, nil, :Object), :getOwnPropertyDescriptors, modname))
              else
                if modname.type == :lvar or (%i(send const).include? modname.type and
                  modname.children.length == 2 and modname.children[0] == nil)

                  object = modname
                else
                  shadow += [s(:shadowarg, :$1)]
                  object = s(:gvar, :$1)
                end

                copy = s(:send,
                  s(:const, nil, :Object), :defineProperties, target,
                  s(:send,
                    s(:send, s(:const, nil, :Object), :getOwnPropertyNames, object),
                    :reduce,
                    s(:block,
                      s(:send, nil, :lambda),
                      s(:args, s(:arg, :$2), s(:arg, :$3)),
                      s(:begin,
                        s(:send,
                          s(:lvar, :$2), :[]=, s(:lvar, :$3),
                          s(:send, s(:const, nil, :Object), :getOwnPropertyDescriptor,
                            object, s(:lvar, :$3))),
                        s(:return, s(:lvar, :$2)))),
                    s(:hash)))


                if object.type == :gvar
                  s(:begin, s(:gvasgn, object.children.last, modname), copy)
                else
                  copy
                end
              end
            end
          }]

        if @state == :statement and shadow.empty?
          parse s(:begin, *body)
        else
          body.push s(:return, target) if @state == :expression
          parse s(:send, s(:block, s(:send, nil, :lambda), s(:args, *shadow),
            s(:begin, *body)), :[])
        end
      end
    end
  end
end
