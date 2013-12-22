module Ruby2JS
  class Converter

    # (while
    #   (true)
    #   (...))

    handle :while do |condition, block|
      begin
        next_token, @next_token = @next_token, :continue
        "while (#{ parse condition }) {#@nl#{ scope block }#@nl}"
      ensure
        @next_token = next_token
      end
    end
  end
end
