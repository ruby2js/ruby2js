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

        if value.respond_to?(:to_hash) and value.to_hash.is_a?(Hash)
	  parse s(:hostvalue, value.to_hash)
        elsif value.respond_to?(:to_ary) and value.to_ary.is_a?(Array)
	  parse s(:hostvalue, value.to_ary)
	elsif value.respond_to?(:to_str) and value.to_str.is_a?(String)
	  parse s(:str, value.to_str)
	elsif value.respond_to?(:to_int) and value.to_int.is_a?(Integer)
	  parse s(:int, value.to_int)
	elsif value.respond_to?(:to_sym) and value.to_sym.is_a?(Symbol)
	  parse s(:sym, value.to_sym)
	else
          parse s(:str, value.inspect)
	end
      end
    end
  end
end
