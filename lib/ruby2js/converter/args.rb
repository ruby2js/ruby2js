module Ruby2JS
  class Converter

   # (args
   #   (arg :a)
   #   (restarg :b)
   #   (blockarg :c))

    # Deduplicate underscore parameters for JS compatibility.
    # Ruby allows multiple _ params; JS arrow functions forbid duplicate names.
    # Renames second and subsequent _ to _$2, _$3, etc.
    def dedup_underscores(node, count)
      if node.type == :arg && node.children[0] == :_
        count[0] += 1
        count[0] > 1 ? s(:arg, :"_$#{count[0]}") : node
      elsif node.type == :mlhs
        s(:mlhs, *node.children.map { |c| dedup_underscores(c, count) })
      else
        node
      end
    end

    handle :args do |*args|
      kwargs = []
      while args.last and
        [:kwarg, :kwoptarg, :kwrestarg].include? args.last.type
        kwargs.unshift args.pop
      end


      if kwargs.length == 1 and kwargs.last.type == :kwrestarg
        # When **name is the only kwarg, treat it as a simple object parameter
        # Don't also output { ...name } which would duplicate the parameter
        args.push s(:arg, *kwargs.last.children)
        kwargs = []
      end

      # Deduplicate _ params (Ruby allows multiple, JS doesn't)
      count = [0]
      args = args.map { |arg| dedup_underscores(arg, count) }

      parse_all(*args, join: ', ')
      if not kwargs.empty?
        put ', ' unless args.empty?
        put '{ '
        kwargs.each_with_index do |kw, index|
          put ', ' unless index == 0
          if kw.type == :kwarg
            put jsvar(kw.children.first)
          elsif kw.type == :kwoptarg
            put jsvar(kw.children.first)
            # Check if default is `undefined` - skip '=' if so (JS default behavior)
            # Using element-wise comparison for selfhost JS compatibility
            default_val = kw.children.last
            is_undefined = default_val.type == :send &&
                           default_val.children[0] == nil &&
                           default_val.children[1] == :undefined
            unless is_undefined
              put '='; parse kw.children.last
            end
          elsif kw.type == :kwrestarg
            put '...'; put jsvar(kw.children.first)
          end
        end
        put ' }'

        put ' = {}' unless kwargs.any? {|kw| kw.type == :kwarg}
      end
    end

    handle :mlhs do |*args|
      put '['
      parse_all(*args, join: ', ')
      put ']'
    end

    # Ruby 2.7+ argument forwarding: def foo(...) / bar(...)
    handle :forward_args do
      put '...args'
    end

    handle :forwarded_args do
      put '...args'
    end
  end
end
