module Ruby2JS
  class Converter

    # (next
    #   (int 1))

    handle :next do |n=nil|
      if @next_token == :return
        put 'return'
        if n
          put ' '
          parse n
        end
      else
        raise Error.new("next argument #{ n.inspect }", @ast) if n
        put @next_token.to_s
      end
    end
  end
end
