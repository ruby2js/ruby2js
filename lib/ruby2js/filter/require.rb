require 'ruby2js'
require 'pathname'

module Ruby2JS
  module Filter
    module Require
      include SEXP

      @@valid_path = /\A[-\w.]+\Z/

      def self.valid_path=(valid_path)
        @@valid_path = valid_path
      end

      def initialize(*args)
        @require_expr = nil
        super
      end

      def options=(options)
        super
        @require_autoexports = !@disable_autoexports && options[:autoexports]
      end

      def on_send(node)
        if \
          not @require_expr and # only statements
          node.children.length == 3 and
          node.children[0] == nil and
          [:require, :require_relative].include? node.children[1] and
          node.children[2].type == :str and
          @options[:file]
        then

          begin
            file2 = @options[:file2]  

            basename = node.children[2].children.first
            dirname = File.dirname(File.expand_path(@options[:file]))

            if file2 and node.children[1] == :require_relative
              dirname = File.dirname(File.expand_path(file2))
            end

            filename = File.join(dirname, basename)

            if not File.file? filename and File.file? filename+".rb"
              filename += '.rb'
            elsif not File.file? filename and File.file? filename+".js.rb"
              filename += '.js.rb'
            end

            @options[:file2] = filename
            ast, comments = Ruby2JS.parse(File.read(filename), filename)
            @comments.merge! Parser::Source::Comment.associate(ast, comments)
            @comments[node] += @comments[ast]

            children = ast.type == :begin ? ast.children : [ast]

            named_exports = []
            auto_exports = []
            default_exports = []
            children.each do |child|
              if child&.type == :send and child.children[0..1] == [nil, :export]
                child = child.children[2]
                if child&.type == :send and child.children[0..1] == [nil, :default]
                  child = child.children[2]
                  target = default_exports
                else
                  target = named_exports
                end
              elsif @require_autoexports
                target = auto_exports
              else
                next
              end

              if %i[class module].include? child.type and child.children[0].children[0] == nil
                target << child.children[0].children[1]
              elsif child.type == :casgn and child.children[0] == nil
                target << child.children[1]
              elsif child.type == :def
                target << child.children[0]
              end
            end

            if @require_autoexports == :default and auto_exports.length == 1
              default_exports += auto_exports
            else
              named_exports += auto_exports
            end

            imports = []
            imports << s(:const, nil, default_exports.first) unless default_exports.empty?
            imports << named_exports.map {|id| s(:const, nil, id)} unless named_exports.empty?

            if imports.empty?
              process ast
            else
              importname = Pathname.new(filename).relative_path_from(dirname).to_s
              prepend_list << s(:import, importname, *imports)
              process s(:hide, ast)
            end
          ensure
            if file2
              @options[:file2] = file2
            else
              @options.delete(:file2)
            end
          end
        else
          begin
            require_expr, @require_expr = @require_expr, true
            super
          ensure
            @require_expr = require_expr
          end
        end
      end

      def on_lvasgn(node)
        require_expr, @require_expr = @require_expr, true
        super
      ensure
        @require_expr = require_expr
      end

      def on_casgn(node)
        require_expr, @require_expr = @require_expr, true
        super
      ensure
        @require_expr = require_expr
      end
    end

    DEFAULTS.push Require
  end
end
