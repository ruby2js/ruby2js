module Ruby2JS
  class Converter

    # (begin
    #   (...)
    #   (...))

    handle :begin do |*statements|
      state = @state
      statements.map{ |statement| parse statement, state }.join(@sep)
    end
  end
end
