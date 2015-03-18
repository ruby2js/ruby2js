require 'ruby2js'

module Ruby2JS
  module Filter
    module Require
      include SEXP

      @@valid_path = /\A[-\w_.]+\Z/

      def self.valid_path=(valid_path)
        @@valid_path = valid_path
      end

      def on_send(node)
        if
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

            segments = basename.split(/[\/\\]/)
            if segments.all? {|path| path =~ @@valid_path and path != '..'}
              filename.untaint 
            end

            if not File.exist? filename and File.exist? filename+".rb"
              filename += '.rb'
            elsif not File.exist? filename and File.exist? filename+".js.rb"
              filename += '.js.rb'
            end

            @options[:file2] = filename
            ast, comments = Ruby2JS.parse(File.read(filename), filename)
            @comments.merge! Parser::Source::Comment.associate(ast, comments)
            process ast
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
