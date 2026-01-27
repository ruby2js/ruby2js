module Ruby2JS
  class Converter

    # (defined? :@a)

    # (undefined? :@a)

    # NOTE: undefined is not produced directly by Parser

    handle :defined?, :undefined? do |var|
      op = (@ast.type == :defined? ? :"!==" : :===)

      if [:super, :zsuper].include?(var.type)
        # defined?(super) checks if parent defines the current method
        method = @instance_method || @class_method
        if method
          method_name = method.children[0]
          put "typeof super.#{method_name} #{op} 'undefined'"
        else
          # Outside a method: always undefined
          put(@ast.type == :defined? ? 'false' : 'true')
        end
      else
        put "typeof "; parse var; put " #{ op } 'undefined'"
      end
    end
  end
end
