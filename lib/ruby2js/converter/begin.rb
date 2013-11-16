module Ruby2JS
  class Converter

    # (begin
    #   (...)
    #   (...))

    handle :begin do |*statements|
      statements.map{ |statement| parse statement, :statement }.join(@sep)
    end
  end
end
