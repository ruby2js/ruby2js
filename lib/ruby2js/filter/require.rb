require 'ruby2js'
require 'pathname'

module Ruby2JS
  module Filter
    module Require
      include SEXP

      def initialize(*args)
        @require_expr = nil
        @require_seen = {}
        @require_relative = '.'
        super
      end

      # Check if a node has a Pragma: skip comment on the same line
      def has_skip_pragma?(node)
        return false unless @comments

        # Check comments in _raw array for this node's line
        raw_comments = @comments[:_raw] || []
        return false if raw_comments.empty?

        # Get the line number of the node
        line = nil
        if node.respond_to?(:loc) && node.loc
          loc = node.loc
          if loc.respond_to?(:expression) && loc.expression
            line = loc.expression.line
          elsif loc.respond_to?(:line)
            line = loc.line
          end
        end
        return false unless line

        # Check for Pragma: skip comment on this line
        raw_comments.any? do |comment|
          comment_line = nil
          if comment.respond_to?(:loc) && comment.loc
            comment_line = comment.loc.line
          elsif comment.respond_to?(:location)
            loc = comment.location
            comment_line = loc.respond_to?(:start_line) ? loc.start_line : loc.line
          end
          next false unless comment_line == line

          text = comment.respond_to?(:text) ? comment.text : comment.to_s
          text =~ /#\s*Pragma:\s*skip/i
        end
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

          # Check for Pragma: skip before trying to load the file
          if has_skip_pragma?(node)
            return s(:hide)
          end

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

            realpath = File.realpath(filename)
            if @require_seen[realpath]
              # Already processed this file, skip it
              return s(:hide)
            end

            @require_seen[realpath] = true

            @options[:file2] = filename
            ast, comments = Ruby2JS.parse(File.read(filename), filename)
            # comments is already a hash with associated comments, merge it directly
            @comments.merge!(comments) { |key, old, new| old + new }
            if @comments[ast]
              @comments[node] = (@comments[node] || []) + @comments[ast]
            end

            # Track relative path for nested requires
            save_require_relative = @require_relative
            @require_relative = Pathname.new(@require_relative).join(basename).parent.to_s

            # Inline the file contents
            result = process ast

            @require_relative = save_require_relative
            result
          ensure
            if file2
              @options[:file2] = file2
            else
              @options.delete(:file2)
            end
          end
        else
          super
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
