module Ruby2JS
  class Converter

    # (ivar :@a)

    handle :ivar do |var|
      if self.ivars and self.ivars.include? var
        parse s(:hostvalue, self.ivars[var])
      elsif underscored_private
        parse s(:attr, s(:self), var.to_s.sub('@', '_'))
      else
        parse s(:attr, s(:self), var.to_s.sub('@', '#'))
      end
    end

    handle :hostvalue do |value|
      case value
      when Hash
        parse s(:hash, *value.map {|key, hvalue| 
          case key
          when String
            s(:pair, s(:str, key), s(:hostvalue, hvalue))
          when Symbol
            s(:pair, s(:sym, key), s(:hostvalue, hvalue))
          else
            s(:pair, s(:hostvalue, key), s(:hostvalue, hvalue))
          end
        })
      when Array
        parse s(:array, *value.map {|hvalue| s(:hostvalue, hvalue)})
      when String
        parse s(:str, value)
      when Integer
        parse s(:int, value)
      when Float
        parse s(:float, value)
      when true
        parse s(:true)
      when false
        parse s(:false)
      when nil
        parse s(:nil)
      when Symbol
        parse s(:sym, value)
      else
	value = value.as_json if value.respond_to?(:as_json)

        if value.respond_to?(:to_hash) and Hash === value.to_hash
	  parse s(:hostvalue, value.to_hash)
        elsif value.respond_to?(:to_ary) and Array === value.to_ary
	  parse s(:hostvalue, value.to_ary)
	elsif value.respond_to?(:to_str) and String === value.to_str
	  parse s(:str, value.to_str)
	elsif value.respond_to?(:to_int) and Integer === value.to_int
	  parse s(:int, value.to_int)
	elsif value.respond_to?(:to_sym) and Symbol === value.to_sym
	  parse s(:sym, value.to_sym)
	else
          parse s(:str, value.inspect)
	end
      end
    end
  end
end
