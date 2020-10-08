module Ruby2JS
  class Converter

   # (taglit
   #   (arg :tag)
   #   (dstr)

    handle :taglit do |tag, *children|
      put tag.children.first
      parse_all(*children, join: '')
    end
  end
end