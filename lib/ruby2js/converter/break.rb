module Ruby2JS
  class Converter

    # (break
    #   (int 1))

    handle :break do |n=nil|
      raise NotImplementedError, "break argument #{ n.inspect }" if n
      raise NotImplementedError, "break outside of loop" if @next_token == :return
      'break'
    end
  end
end
