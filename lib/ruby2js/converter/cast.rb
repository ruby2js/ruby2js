module Ruby2JS
  class Converter

    # (cast
    #   (expr))
    #
    # Type cast sentinel — marks an expression as having a known type.
    # The parent node (e.g., :array, :hash) carries the type; this node
    # just passes through the inner expression unchanged.

    handle :cast do |expr|
      parse expr
    end
  end
end
