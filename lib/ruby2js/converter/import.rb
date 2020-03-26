module Ruby2JS
  class Converter

    # (import str const) 

    # NOTE: import is a synthetic 

    handle :import do |path, *args|
      put 'import '

      args.each_with_index do |arg, index|
        put ', ' unless index == 0
        parse arg
      end

      put ' from '
      put path.inspect
    end

    # (export const) 

    # NOTE: export is a synthetic 

    handle :export do |*args|
      put 'export '

      if args.first == :default
        put 'default '
        args.shift
      end

      args.each_with_index do |arg, index|
        put ', ' unless index == 0
        parse arg
      end
    end
  end
end
