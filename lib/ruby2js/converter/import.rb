module Ruby2JS
  class Converter

    # (import str const) 

    # NOTE: import is a synthetic 

    handle :import do |path, *args|
      put 'import '
      if args.length == 0
        # import "file.css"
        put path.inspect
      else
        # import (x) from "file.js"
        default_import = !args.first.is_a?(Array) && (args.first.type == :const || args.first.type == :send)
        args = args.first if args.first.is_a?(Array)

        # handle the default name or { ConstA, Const B } portion
        put "{ " unless default_import
        args.each_with_index do |arg, index|
          put ', ' unless index == 0
          parse arg
        end
        put " }" unless default_import

        # should there be an as clause? e.g., import React as *
        from_kwarg_position = 0
        if path.is_a?(Array) && !path[0].is_a?(String) && path[0].type == :pair && path[0].children[0].children[0] == :as
          put " as #{path[0].children[1].children[0]}"
          from_kwarg_position = 1
        end

        put ' from '

        if path.is_a?(Array) && !path[from_kwarg_position].is_a?(String) && path[from_kwarg_position].type == :pair
          # from: "str" => from "str"
          if path[from_kwarg_position].children[0].children[0] == :from
            put path[from_kwarg_position].children[1].children[0].inspect
          else
            put '""'
          end
        else
          # handle a str in either an array element or directly passed in
          put path.is_a?(Array) ? path[0].inspect : path.inspect
        end
      end
    end

    # (export const) 

    # NOTE: export is a synthetic 

    handle :export do |*args|
      put 'export '

      if args.first == :default
        put 'default '
        args.shift
      elsif args.first.respond_to?(:type) && args.first.children[1] == :default
        put 'default '
        args[0] = args[0].children[2]
      elsif args.first.respond_to?(:type) && args.first.type == :lvasgn
        if args[0].children[0] == :default
          put 'default '
          args[0] = args[0].children[1]
        else
          put 'const '
        end
      end

      args.each_with_index do |arg, index|
        put ', ' unless index == 0
        parse arg
      end
    end
  end
end
