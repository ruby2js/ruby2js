module Ruby2JS
  class Converter

    # (next
    #   (int 1))

    handle :next do |n=nil|
      raise NotImplementedError, "next argument #{ n.inspect }" if n
      @next_token.to_s
    end
  end
end
