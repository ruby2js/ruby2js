module Ruby2JS
  class Converter

   # (assign
   #   (hash)
   #   (hash)
   #   ...

    handle :assign do |target, *args|
      collapsible = false

      collapsible = true if args.length == 1 and args.first.type == :hash and
        args.first.children.length == 1

      collapsible = true if args.length == 1 and args.first.type == :class_module and
        args.first.children.length == 3 and args.first.children.last.is_method?

      if es2015 and not collapsible
        parse s(:send, s(:const, nil, :Object), :assign, target, *args)
      else

        if target == s(:hash)
          copy = [s(:gvasgn, :$$, target)]
          target = s(:gvar, :$$)
          shadow = [s(:shadowarg, :$$)]
        elsif collapsible or
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
            if modname.type == :hash
              s(:begin, *modname.children.map {|pair|
                  s(:send, target, :[]=, *pair.children)
                })
            elsif modname.type == :class_module and
              modname.children[2..-1].all? {|child| 
                child.type == :def and child.is_method?
              }

              s(:begin, *modname.children[2..-1].map {|pair|
                  s(:send, target, :[]=, s(:sym, pair.children.first),
                  pair.updated(:defm, [nil, *pair.children[1..-1]]))
                })
            else
              if modname.type == :lvar or (%i(send const).include? modname.type and
                modname.children.length == 2 and modname.children[0] == nil)

                s(:for, s(:lvasgn, :$_), modname,
                s(:send, target, :[]=,
                s(:lvar, :$_), s(:send, modname, :[], s(:lvar, :$_))))
              else
                shadow += [s(:shadowarg, :$1)]
                s(:begin, s(:gvasgn, :$1, modname),
                s(:for, s(:lvasgn, :$_), s(:gvar, :$1),
                s(:send, target, :[]=,
                s(:lvar, :$_), s(:send, s(:gvar, :$1), :[], s(:lvar, :$_)))))
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
