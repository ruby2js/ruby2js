module Ruby2JS
  class Converter

    # (arg :a)
    # (blockarg :b)

    # NOTE: process_all appends a nil child for unknown reasons

    handle :arg, :blockarg do |arg, unknown=nil|
      raise Error.new("argument #{ unknown.inspect }", @ast) if unknown
      put jsvar(arg)
    end

    # (shadowarg :a)

    handle :shadowarg do |arg, unknown=nil|
      raise Error.new("argument #{ unknown.inspect }", @ast) if unknown
      nil
    end

    # (kwarg :name)
    # These are normally handled in on_args, but may be parsed directly in some contexts
    handle :kwarg do |name, unknown=nil|
      raise Error.new("kwarg argument #{ unknown.inspect }", @ast) if unknown
      put jsvar(name)
    end

    # (kwoptarg :name default_value)
    handle :kwoptarg do |name, default_val, unknown=nil|
      raise Error.new("kwoptarg argument #{ unknown.inspect }", @ast) if unknown
      put jsvar(name)
      # Check if default is `undefined` - skip '=' if so (JS default behavior)
      is_undefined = default_val&.type == :send &&
                     default_val.children[0] == nil &&
                     default_val.children[1] == :undefined
      unless is_undefined
        put '='; parse default_val
      end
    end

    # (kwrestarg :name)
    handle :kwrestarg do |name, unknown=nil|
      raise Error.new("kwrestarg argument #{ unknown.inspect }", @ast) if unknown
      put '...'; put jsvar(name) if name
    end
  end
end
