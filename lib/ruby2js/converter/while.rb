module Ruby2JS
  class Converter

    # (while
    #   (true)
    #   (...))

    handle :while do |condition, block|
      begin
        next_token, @next_token = @next_token, :continue

        put 'while ('; parse condition; puts ') {'; scope block; sput '}'
      ensure
        @next_token = next_token
      end
    end
  end
end
