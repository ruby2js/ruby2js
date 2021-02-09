module Ruby2JS
  class Converter

    # (import str const) 

    # NOTE: import is a synthetic 

    handle :import do |path, *args|
      if module_type == :cjs
        # only the subset of import syntaxes generated by filters are handled here
        if Parser::AST::Node === args.first and args.first.type == :attr
          return parse s(:casgn, *args.first.children, 
            s(:send, nil, :require, s(:str, Array(path).first))), :statement
        elsif Array === args.first and args.first.length == 1
          target = args.first.first
          if Parser::AST::Node === target and target.type == :attr and target.children.first == nil
            return parse s(:casgn, *target.children, 
              s(:attr, s(:send, nil, :require, s(:str, Array(path).first)), target.children.last)),
              :statement
          end
        end
      end

      put 'import '

      if args.length == 0
        # import "file.css"
        put path.inspect
      else
        # import (x) from "file.js"
        default_import = !args.first.is_a?(Array) && %i[const send attr str].include?(args.first.type)

        if default_import and args.length > 1
          parse args.shift
          put ', '
          default_import = false
        end

        args = args.first if args.first.is_a?(Array)

        if args.first.type == :array
          args = args.first.children
        end

        # handle the default name or { ConstA, Const B } portion
        put "{ " unless default_import
        args.each_with_index do |arg, index|
          put ', ' unless index == 0
          if arg.type == :str
            put arg.children.first # useful for '*'
          else
            parse arg
          end
        end
        put " }" unless default_import

        from_kwarg_position = 0

        # should there be an as clause? e.g., import React as *
        if path.is_a?(Array) && !path[0].is_a?(String) && path[0].type == :pair && path[0].children[0].children[0] == :as
          put " as #{path[0].children[1].children.last}"

          # advance to the next kwarg, aka from
          from_kwarg_position = 1
        end

        put ' from '

        if path.is_a?(Array) && !path[from_kwarg_position].is_a?(String) && path[from_kwarg_position].type == :pair
          # from: "str" => from "str"
          if path[from_kwarg_position].children[0].children[0] == :from
            put path[from_kwarg_position].children[1].children[0].inspect
          else
            # from is missing
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

      node = args.first
      final_export = false

      if node == :default
        put 'default '
        args.shift
      elsif node.respond_to?(:type) && node.children[1] == :default
        put 'default '
        args[0] = node.children[2]
      elsif node.respond_to?(:type) && [:lvasgn, :casgn].include?(node.type)
        if node.children[0] == :default
          put 'default '
          args[0] = node.children[1]
        else
          put 'const '
        end
      elsif node.respond_to?(:type) &&
        node.type == :array &&
        node.children[0].respond_to?(:type) &&
        (
          node.children[0].type == :const ||
          node.children[0].type == :send ||
          (node.children[0].type == :hash && node.children[0].children[0].children[0].children[0] == :default )
        )
        final_export = true
        put '{ '
        node.children.each_with_index do |arg, index|
          put ', ' unless index == 0
          if arg.type == :hash && arg.children[0].children[0].children[0] == :default
            put arg.children[0].children[1].children[1]
            put ' as default'
          else
            parse arg
          end
        end
        put ' }'
      end

      unless final_export
        args.each_with_index do |arg, index|
          put ', ' unless index == 0
          parse arg
        end
      end
    end
  end
end
