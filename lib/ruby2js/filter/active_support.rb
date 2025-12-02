require 'ruby2js'

module Ruby2JS
  module Filter
    module ActiveSupport
      include SEXP

      # ActiveSupport core extensions commonly used in Rails templates
      # https://guides.rubyonrails.org/active_support_core_extensions.html

      def on_send(node)
        target, method, *args = node.children

        if method == :blank? && args.empty? && target
          # obj.blank? => obj == null || obj.length === 0 || obj === ''
          target = process(target)
          return s(:or,
            s(:or,
              s(:send, target, :==, s(:nil)),
              s(:send, s(:attr, target, :length), :===, s(:int, 0))),
            s(:send, target, :===, s(:str, '')))
        end

        if method == :present? && args.empty? && target
          # obj.present? => !(obj.blank?)
          # obj != null && obj.length !== 0 && obj !== ''
          target = process(target)
          return s(:and,
            s(:and,
              s(:send, target, :!=, s(:nil)),
              s(:send, s(:attr, target, :length), :!=, s(:int, 0))),
            s(:send, target, :!=, s(:str, '')))
        end

        if method == :presence && args.empty? && target
          # obj.presence => obj.present? ? obj : null
          target = process(target)
          present_check = s(:and,
            s(:and,
              s(:send, target, :!=, s(:nil)),
              s(:send, s(:attr, target, :length), :!=, s(:int, 0))),
            s(:send, target, :!=, s(:str, '')))
          return s(:if, present_check, target, s(:nil))
        end

        if method == :try && args.length >= 1 && target
          # obj.try(:method) => obj?.method
          # obj.try(:method, arg) => obj?.method(arg)
          method_name = args.first
          if method_name.type == :sym
            target = process(target)
            method_sym = method_name.children.first
            remaining_args = args[1..-1].map { |a| process(a) }
            if remaining_args.empty?
              return s(:csend, target, method_sym)
            else
              return s(:csend, target, method_sym, *remaining_args)
            end
          end
        end

        if method == :in? && args.length == 1 && target
          # obj.in?(array) => array.includes(obj)
          target = process(target)
          collection = process(args.first)
          return s(:send, collection, :includes, target)
        end

        if method == :squish && args.empty? && target
          # str.squish => str.trim().replace(/\s+/g, ' ')
          target = process(target)
          trimmed = s(:send, target, :trim)
          return s(:send, trimmed, :replace,
            s(:regexp, s(:str, '\\s+'), s(:regopt, :g)),
            s(:str, ' '))
        end

        if method == :truncate && target && args.length >= 1
          # str.truncate(n) => str.length > n ? str.slice(0, n - 3) + '...' : str
          # str.truncate(n, omission: '...') => custom omission
          target = process(target)
          length = process(args.first)

          omission = '...'
          if args.length > 1 && args[1].type == :hash
            args[1].children.each do |pair|
              if pair.type == :pair && pair.children[0].type == :sym &&
                 pair.children[0].children.first == :omission &&
                 pair.children[1].type == :str
                omission = pair.children[1].children.first
              end
            end
          end

          omission_length = omission.length
          slice_length = s(:send, length, :-, s(:int, omission_length))

          condition = s(:send, s(:attr, target, :length), :>, length)
          truncated = s(:send,
            s(:send, target, :slice, s(:int, 0), slice_length),
            :+, s(:str, omission))

          return s(:if, condition, truncated, target)
        end

        if method == :to_sentence && args.empty? && target
          # arr.to_sentence => arr.length === 0 ? '' :
          #   arr.length === 1 ? arr[0] :
          #   arr.slice(0, -1).join(', ') + ' and ' + arr[arr.length - 1]
          target = process(target)

          # Empty case
          empty_check = s(:send, s(:attr, target, :length), :===, s(:int, 0))

          # Single element case
          single_check = s(:send, s(:attr, target, :length), :===, s(:int, 1))
          single_result = s(:send, target, :[], s(:int, 0))

          # Multiple elements: join all but last with ', ', add ' and ' + last
          all_but_last = s(:send, target, :slice, s(:int, 0), s(:int, -1))
          joined = s(:send, all_but_last, :join, s(:str, ', '))
          last_elem = s(:send, target, :[], s(:send, s(:attr, target, :length), :-, s(:int, 1)))
          multi_result = s(:send, s(:send, joined, :+, s(:str, ' and ')), :+, last_elem)

          return s(:if, empty_check, s(:str, ''),
            s(:if, single_check, single_result, multi_result))
        end

        super
      end
    end

    # Note: Not added to DEFAULTS - must be explicitly requested
    # DEFAULTS.push ActiveSupport
  end
end
