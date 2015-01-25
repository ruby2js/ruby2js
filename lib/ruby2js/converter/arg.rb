module Ruby2JS
  class Converter

    # (arg :a)
    # (blockarg :b)

    # NOTE: process_all appends a nil child for unknown reasons

    handle :arg, :blockarg do |arg, unknown=nil|
      raise NotImplementedError, "argument #{ unknown.inspect }" if unknown
      arg
    end

    # (shadowarg :a)

    handle :shadowarg do |arg, unknown=nil|
      raise NotImplementedError, "argument #{ unknown.inspect }" if unknown
      nil
    end
  end
end
