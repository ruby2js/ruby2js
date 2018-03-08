module Ruby2JS
  class Converter

    # (break
    #   (int 1))

    handle :break do |n=nil|
      raise Error.new("break argument #{ n.inspect }", @ast) if n
      raise Error.new("break outside of loop", @ast) if @next_token == :return
      put 'break'
    end
  end
end
