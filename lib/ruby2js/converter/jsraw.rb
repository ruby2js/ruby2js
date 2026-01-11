module Ruby2JS
  class Converter

    # (jsraw
    #   "raw javascript code")
    #
    # Outputs the string content verbatim without any transformation.
    # Used internally for pre-compiled JavaScript (e.g., from rbx2_js).

    handle :jsraw do |content|
      put content.to_s
    end
  end
end
