module Ruby2JS
  class Converter

    # (irange
    #   (int 1)
    #   (int 10))
    # (erange
    #   (int 1)
    #   (int 10))

    # Fallback handlers for ranges that aren't consumed by special constructs
    # (for loops, case statements, array slicing). These output $Range objects.
    handle :irange, :erange do |start_val, end_val|
      @need_range_class = true
      put 'new $Range('

      # Handle beginless ranges (..10 or ...10)
      if start_val.nil?
        put 'null'
      else
        parse start_val
      end

      put ', '

      # Handle endless ranges (1.. or 1...)
      if end_val.nil?
        put 'null'
      else
        parse end_val
      end

      # Add excludeEnd flag for exclusive ranges
      if @ast.type == :erange
        put ', true'
      end

      put ')'
    end
  end
end
