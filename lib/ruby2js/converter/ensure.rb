module Ruby2JS
  class Converter

    # (ensure
    #   (rescue
    #     (send nil :a)
    #     (resbody nil nil
    #       (send nil :b)) nil)
    #  (send nil :c))
    #
    # This handler delegates to :kwbegin which handles ensure blocks

    handle :ensure do |*children|
      parse s(:kwbegin, s(:ensure, *children)), @state
    end
  end
end
