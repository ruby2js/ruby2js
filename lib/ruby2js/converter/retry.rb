module Ruby2JS
  class Converter

    # (retry)
    #
    # The retry keyword re-executes the begin block. In JavaScript, this is
    # implemented by wrapping the try/catch in a while(true) loop and using
    # continue to retry.

    handle :retry do
      put 'continue'
    end
  end
end
