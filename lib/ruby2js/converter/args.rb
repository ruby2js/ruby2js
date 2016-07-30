module Ruby2JS
  class Converter

   # (args
   #   (arg :a)
   #   (restarg :b)
   #   (blockarg :c))

    handle :args do |*args|
      parse_all(*args, join: ', ')
    end
  end
end
