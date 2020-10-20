module Ruby2JS
  class Converter

    # (yield
    #   (arg 'a'))

    handle :yield do |*args|
      put '_implicitBlockYield'
      put "("; parse_all(*args, join: ', '); put ')'
    end
  end
end
