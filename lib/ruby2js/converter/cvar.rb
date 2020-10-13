module Ruby2JS
  class Converter

    # (cvar :@@a)

    handle :cvar do |var|
      prefix = underscored_private ? '_' : '#$'

      @class_name ||= nil
      if @class_name
        parse @class_name
        put var.to_s.sub('@@', ".#{prefix}")
      elsif @prototype
        put var.to_s.sub('@@', "this.#{prefix}")
      else
        put var.to_s.sub('@@', "this.constructor.#{prefix}")
      end
    end
  end
end
