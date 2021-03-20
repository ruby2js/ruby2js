module Ruby2JS
  class Converter

   # (taglit
   #   (arg :tag)
   #   (dstr)

    handle :taglit do |tag, *children|
      begin
        # disable autobinding in tag literals
        save_autobind, @autobind = @autobind, false
      
        if es2015
          put tag.children.first
          parse_all(*children, join: '')
        else
          parse @ast.updated(:send, [nil, tag.children.last, *children])
        end
      ensure
        @autobind = save_autobind
      end
    end
  end
end
