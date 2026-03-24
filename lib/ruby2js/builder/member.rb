module Ruby2JS
  module Builder
    class Member
      extend Filter::SEXP

      # Getter: get name() { body }
      def self.getter(name, body)
        s(:defget, name, s(:args), body)
      end

      # Getter with cache: get name() { if (this._name) return this._name; return this._name = constructor; }
      def self.cached_getter(name, constructor)
        cache = "_#{name}".to_sym
        s(:defget, name,
          s(:args),
          s(:begin,
            s(:if,
              s(:attr, s(:self), cache),
              s(:return, s(:attr, s(:self), cache)),
              nil),
            s(:return, s(:send, s(:self), "#{cache}=".to_sym, constructor))))
      end

      # Setter: set name(value) { this._name = value; }
      def self.setter(name)
        cache = "_#{name}".to_sym
        s(:def, "#{name}=".to_sym,
          s(:args, s(:arg, :value)),
          s(:send, s(:self), "#{cache}=".to_sym, s(:lvar, :value)))
      end

      # Instance method: name(args) { body }
      def self.method(name, args, body)
        s(:def, name, args, body)
      end

      # Async method: async name(args) { body }
      def self.async(name, args, body)
        s(:async, name, args, body)
      end

      # Getter + setter pair (common pattern for associations)
      def self.accessor(name, constructor)
        s(:begin,
          cached_getter(name, constructor),
          setter(name))
      end
    end
  end
end
