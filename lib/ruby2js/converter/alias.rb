module Ruby2JS
  class Converter

    # (alias
    #   (sym :new_name)
    #   (sym :old_name))

    handle :alias do |new_name, old_name|
      new_id = new_name.children.first.to_s.sub(/[?!=]$/, '')
      old_id = old_name.children.first.to_s.sub(/[?!=]$/, '')
      put "this.#{jsvar(new_id)} = this.#{jsvar(old_id)}"
    end
  end
end
