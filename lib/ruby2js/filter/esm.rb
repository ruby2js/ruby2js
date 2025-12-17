require 'ruby2js'
require 'pathname'

Ruby2JS.module_default = :esm

module Ruby2JS
  module Filter
    module ESM
      include SEXP

      def initialize(*args)
        @esm_require_seen = {}
        @esm_explicit_tokens = []
        super
      end

      def options=(options)
        super
        @esm_autoexports = !@disable_autoexports && options[:autoexports]
        @esm_autoexports_option = @esm_autoexports # preserve for require-to-import
        @esm_autoimports = options[:autoimports]
        @esm_defs = options[:defs] || {}
        @esm_explicit_tokens = []
        @esm_top = nil
        @esm_require_recursive = options[:require_recursive]

        # don't convert requires if Require filter is included (it will inline them)
        filters = options[:filters] || Filter::DEFAULTS
        if \
          defined? Ruby2JS::Filter::Require and
          filters.include? Ruby2JS::Filter::Require
        then
          @esm_skip_require = true
        end
      end

      def process(node)
        return super if @esm_top

        list = [node]
        while list.length == 1 and list.first.type == :begin
          list = list.first.children.dup
        end

        @esm_top = list

        return super unless @esm_autoexports

        replaced = []
        list.map! do |child|
          replacement = child

          if [:module, :class].include? child.type and
            child.children.first.type == :const and
            child.children.first.children.first == nil \
          then
            replacement = s(:export, child)
          elsif child.type == :casgn and child.children.first == nil
            replacement = s(:export, child)
          elsif child.type == :def
            replacement = s(:export, child)
          end

          if replacement != child
            replaced << replacement
            @comments[replacement] = @comments[child] if @comments[child]
          end

          replacement
        end

        if replaced.length == 1 and @esm_autoexports == :default
          list.map! do |child|
            if child == replaced.first
              replacement = s(:export, s(:send, nil, :default, *child.children))
              @comments[replacement] = @comments[child] if @comments[child]
              replacement
            else
              child
            end
          end
        end

        @esm_autoexports = false
        process s(:begin, *list)
      end

      def on_class(node)
        @esm_explicit_tokens ||= []
        @esm_explicit_tokens << node.children.first.children.last

        super
      end

      def on_def(node)
        @esm_explicit_tokens ||= []
        @esm_explicit_tokens << node.children.first

        super
      end

      def on_lvasgn(node)
        @esm_explicit_tokens ||= []
        @esm_explicit_tokens << node.children.first

        super
      end

      # Map Ruby's __FILE__ to ESM equivalent
      # import.meta.url returns the full URL (file:///path/to/file.js)
      def on___FILE__(node)
        s(:attr, s(:attr, nil, :"import.meta"), :url)
      end

      def on_send(node)
        target, method, *args = node.children
        found_import = nil  # declare for conditional assignment below

        # import.meta => s(:attr, nil, :"import.meta")
        # This bypasses jsvar escaping of the reserved word 'import'
        if method == :meta and
          target&.type == :send and
          target.children[0].nil? and
          target.children[1] == :import and
          target.children.length == 2
        then
          return process s(:attr, nil, :"import.meta", *args)
        end

        return super unless target.nil?

        # Handle require/require_relative when Require filter is NOT present
        if [:require, :require_relative].include?(method) and
          not @esm_skip_require and
          @esm_top&.include?(@ast) and
          args.length == 1 and
          args[0].type == :str
        then
          # File analysis requires filesystem access (not available in browser)
          # Note: defined?(Window) is truthy in browser JS, falsy in Ruby/Node.js
          if @options[:file] and not defined?(Window)
            return convert_require_to_import(node, method, args[0].children.first)
          else
            # Simple conversion without file analysis
            return s(:import, args[0].children.first)
          end
        end

        if method == :import
          # handle import with no arguments (e.g., import.meta.url)
          return super if args.empty?

          # don't do the conversion if the word import is followed by a paren
          if node.loc.respond_to? :selector
            selector = node.loc.selector
            if selector and selector.source_buffer
              return super if selector.source_buffer.source[selector.end_pos] == '('
            end
          end

          if args[0].type == :str and args.length == 1
            # import "file.css"
            #   => import "file.css"
            s(:import, args[0].children[0])
          elsif args.length == 1 and \
            args[0].type == :send and \
            args[0].children[0].nil? and \
            args[0].children[2].type == :send and \
            args[0].children[2].children[0].nil? and \
            args[0].children[2].children[1] == :from and \
            args[0].children[2].children[2].type == :str
            # import name from "file.js"
            #  => import name from "file.js"
            @esm_explicit_tokens ||= []
            @esm_explicit_tokens << args[0].children[1]

            s(:import,
              [args[0].children[2].children[2].children[0]],
              process(s(:attr, nil, args[0].children[1])))

          else
            # import Stuff, "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, from: "file.js"
            #   => import Stuff from "file.js"
            # import Stuff, as: "*", from: "file.js"
            #   => import Stuff as * from "file.js"
            # import [ Some, Stuff ], from: "file.js"
            #   => import { Some, Stuff } from "file.js"
            # import Some, [ More, Stuff ], from: "file.js"
            #   => import Some, { More, Stuff } from "file.js"
            imports = []
            @esm_explicit_tokens ||= []
            if %i(const send str).include? args[0].type
              @esm_explicit_tokens << args[0].children.last
              imports << process(args.shift)
            end

            if args[0].type == :array
              args[0].children.each {|i| @esm_explicit_tokens << i.children.last}
              imports << process_all(args.shift.children)
            end

            s(:import, args[0].children, *imports) unless args[0].nil?
          end
        elsif method == :export          
          s(:export, *process_all(args))
        elsif target.nil? and found_import = find_autoimport(method)
          self.prepend_list << s(:import, found_import[0], found_import[1])
          super
        else
          super
        end
      end

      def on_const(node)
        found_import = nil  # declare for conditional assignment below
        if node.children.first == nil and found_import = find_autoimport(node.children.last)
          self.prepend_list << s(:import, found_import[0], found_import[1])

          values = @esm_defs[node.children.last]
          
          if values
            values = values.map {|value| 
              if value.to_s.start_with? "@" 
                [value.to_s[1..-1].to_sym, s(:self)]
              else
                [value.to_sym, s(:autobind, s(:self))]
              end
            }.to_h

            @namespace.defineProps values, [node.children.last]
          end
        end

        super
      end

      def on_export(node)
        s(:export, *process_all(node.children))
      end

      private

      # Convert require/require_relative to import statement by parsing the file
      # and detecting its exports
      def convert_require_to_import(node, method, basename)
        # Check for Ruby's File class (not JS File API or browser)
        # Note: RUBY_VERSION is defined in selfhost bundle, so we check for File class
        if defined?(File) and File.respond_to?(:expand_path)
          base_dirname = File.dirname(File.expand_path(@options[:file]))
        else
          # Node.js implementation
          path = require('path')
          url_mod = require('url')
          file_path = @options[:file]
          # Convert file:// URL to path if needed (import.meta.url returns file:// URLs)
          if file_path.start_with?('file://')
            file_path = url_mod.fileURLToPath(file_path)
          end
          base_dirname = path.dirname(path.resolve(file_path))
        end
        collect_imports_from_file(base_dirname, basename, base_dirname, node)
      end

      # Recursively collect imports from a file
      def collect_imports_from_file(base_dirname, basename, current_dirname, fallback_node)
        # Define platform-specific file operations
        # Check for Ruby's File class (not JS File API or browser)
        if defined?(File) and File.respond_to?(:join)
          path_join = ->(a, b) { File.join(a, b) }
          file_exists = ->(f) { File.file?(f) }
          real_path = ->(f) { File.realpath(f) }
          read_file = ->(f) { File.read(f) }
          dir_name = ->(f) { File.dirname(f) }
          relative_path = ->(from, to) { Pathname.new(to).relative_path_from(Pathname.new(from)).to_s }
        else
          # Node.js implementation
          fs = require('fs')
          path = require('path')
          path_join = ->(a, b) { path.join(a, b) }
          file_exists = ->(f) { fs.existsSync(f) and fs.statSync(f).isFile() }
          real_path = ->(f) { fs.realpathSync(f) }
          read_file = ->(f) { fs.readFileSync(f, 'utf8') }
          dir_name = ->(f) { path.dirname(f) }
          relative_path = ->(from, to) { path.relative(from, to) }
        end

        filename = path_join.(current_dirname, basename)

        if not file_exists.(filename) and file_exists.(filename + ".rb")
          filename += '.rb'
        elsif not file_exists.(filename) and file_exists.(filename + ".js.rb")
          filename += '.js.rb'
        end

        return fallback_node unless file_exists.(filename)

        realpath = real_path.(filename)

        # If we've already seen this file, return a reference to it
        if @esm_require_seen[realpath]
          imports = @esm_require_seen[realpath]
          importname = relative_path.(base_dirname, filename)
          importname = "./#{importname}" unless importname.start_with?('.')
          return s(:import, importname, *imports)
        end

        # Parse the file to find exports
        ast, _comments = Ruby2JS.parse(read_file.(filename), filename)
        children = ast.type == :begin ? ast.children : [ast]

        named_exports = []
        default_exports = []
        recursive_imports = []
        file_dirname = dir_name.(filename)

        children.each do |child|
          next unless child

          # Check for require_relative statements when require_recursive is enabled
          if @esm_require_recursive and
             child.type == :send and
             child.children[0].nil? and
             [:require, :require_relative].include?(child.children[1]) and
             child.children[2]&.type == :str
          then
            nested_basename = child.children[2].children.first
            nested_result = collect_imports_from_file(base_dirname, nested_basename, file_dirname, nil)
            if nested_result
              if nested_result.type == :begin
                # Flatten nested begin nodes (multiple imports)
                recursive_imports.concat(nested_result.children)
              elsif nested_result.type == :import
                recursive_imports << nested_result
              end
            end
            next
          end

          # Check for explicit export statements
          if child.type == :send and child.children[0..1] == [nil, :export]
            export_child = child.children[2]
            if export_child&.type == :send and export_child.children[0..1] == [nil, :default]
              # export default ...
              export_child = export_child.children[2]
              target = default_exports
            else
              target = named_exports
            end

            extract_export_names(export_child, target, default_exports)
          elsif @esm_autoexports_option
            # Auto-export mode: export top-level definitions
            extract_export_names(child, named_exports, default_exports)
          end
        end

        # Handle autoexports :default mode
        if @esm_autoexports_option == :default and named_exports.length == 1 and default_exports.empty?
          default_exports = named_exports
          named_exports = []
        end

        # Normalize export names
        default_exports.map! { |name| normalize_export_name(name) }
        named_exports.map! { |name| normalize_export_name(name) }

        # Build imports list for this file
        imports = []
        imports << s(:const, nil, default_exports.first) unless default_exports.empty?
        imports << named_exports.map { |id| s(:const, nil, id) } unless named_exports.empty?

        # Cache for future references
        @esm_require_seen[realpath] = imports

        # If require_recursive, return a begin node with all imports
        if @esm_require_recursive && !recursive_imports.empty?
          all_imports = []
          # Add current file's import first (before its dependencies)
          unless imports.empty?
            importname = relative_path.(base_dirname, filename)
            importname = "./#{importname}" unless importname.start_with?('.')
            all_imports << s(:import, importname, *imports)
          end
          # Then add nested imports (dependencies come after)
          all_imports.concat(recursive_imports)
          return s(:begin, *all_imports) if all_imports.length > 1
          return all_imports.first if all_imports.length == 1
          return fallback_node
        end

        # If no exports found, just return the fallback (original require)
        return fallback_node if imports.empty?

        # Generate import statement
        importname = relative_path.(base_dirname, filename)
        importname = "./#{importname}" unless importname.start_with?('.')

        s(:import, importname, *imports)
      end

      # Extract exportable names from an AST node
      def extract_export_names(child, named_target, default_target)
        return unless child

        if %i[class module].include?(child.type) and
          child.children[0]&.type == :const and
          child.children[0].children[0].nil?
        then
          named_target << child.children[0].children[1]
        elsif child.type == :casgn and child.children[0].nil?
          named_target << child.children[1]
        elsif child.type == :def
          named_target << child.children[0]
        elsif child.type == :send && child.children[1] == :async
          named_target << child.children[2].children[0]
        elsif child.type == :const
          named_target << child.children[1]
        elsif child.type == :array
          child.children.each do |export_stmt|
            if export_stmt.type == :const
              named_target << export_stmt.children[1]
            elsif export_stmt.type == :hash
              # Handle { default: Name } syntax
              export_stmt.children.each do |pair|
                if pair.type == :pair
                  key, value = pair.children
                  if key.type == :sym and key.children[0] == :default and value.type == :const
                    default_target << value.children[1]
                  end
                end
              end
            end
          end
        end
      end

      # Normalize export name (remove ?! suffix, apply camelCase if needed)
      def normalize_export_name(name)
        name = name.to_s.sub(/[?!]$/, '')
        name = camelCase(name) if respond_to?(:camelCase)
        name.to_sym
      end

      private

      def find_autoimport(token)
        return nil unless @esm_autoimports  # truthy check handles both nil and undefined in JS
        @esm_explicit_tokens ||= []
        return nil if @esm_explicit_tokens.include?(token)

        token = camelCase(token) if respond_to?(:camelCase)
        found_key = nil  # declare for conditional assignment below

        if @esm_autoimports[token]
          [@esm_autoimports[token], s(:const, nil, token)]
        elsif found_key = @esm_autoimports.keys.find {|key| key.respond_to?(:each) && key.include?(token)}
          # Ruby: array keys like [:func, :another]
          [@esm_autoimports[found_key], found_key.map {|key| s(:const, nil, key)}]
        elsif found_key = @esm_autoimports.keys.find {|key| key.is_a?(String) && key.include?(',') && key.split(',').include?(token.to_s)}
          # JS: stringified array keys like "func,another" - split to recover array
          key_array = found_key.split(',')
          [@esm_autoimports[found_key], key_array.map {|key| s(:const, nil, key.to_sym)}]
        end
      end
    end

    DEFAULTS.push ESM
  end
end
