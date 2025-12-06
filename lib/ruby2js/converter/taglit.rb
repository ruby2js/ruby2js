module Ruby2JS
  class Converter

   # (taglit
   #   (arg :tag)
   #   (dstr)

    handle :taglit do |tag, *children|
      begin
        # disable autobinding in tag literals
        save_autobind, @autobind = @autobind, false

        put tag.children.first
        parse_all(*children, join: '')
      ensure
        @autobind = save_autobind
      end
    end
  end
end
