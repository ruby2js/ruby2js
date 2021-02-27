module Ruby2JS
  class Converter

    # (while-post
    #   (true)
    #   (kwbegin
    #     (...)))

    handle :while_post do |condition, block|
      block = block.updated(:begin) if block.type == :kwbegin
      begin
        next_token, @next_token = @next_token, :continue

        puts 'do {'; redoable block; sput '} while ('; parse condition; put ')'
      ensure
        @next_token = next_token
      end
    end
  end
end
