module Ruby2JS
  class Converter

    # (next
    #   (int 1))

    handle :next do |n=nil|
      raise Error.new("next argument #{ n.inspect }", @ast) if n
      put @next_token.to_s
    end
  end
end
