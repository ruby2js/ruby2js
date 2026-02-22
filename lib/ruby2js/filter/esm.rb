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
        @esm_top = nil
        @esm_require_recursive = options[:require_recursive]

        # Component map for import resolution (from builder)
        @esm_component_map = options[:component_map] || {}
        @esm_file_path = options[:file_path]

        # don't convert requires if Require filter is included (it will inline them)
        filters = options[:filters] || Filter::DEFAULTS
        if \
          defined? Ruby2JS::Filter::Require and
          filters.include? Ruby2JS::Filter::Require
        then
          @esm_skip_require = true
        end
      end

      # Resolve a bare specifier to a relative path using the component map
      # e.g., 'components/Button' → './Button.js' or '../components/Button.js'
      def resolve_component_import(specifier)
        return specifier if @esm_component_map.empty?
        return specifier unless specifier.is_a?(String)
        return specifier if specifier.start_with?('.') || specifier.start_with?('/')

        # Check if this is a component import
        target_path = @esm_component_map[specifier]
        return specifier unless target_path

        # Compute relative path from current file to the component
        if @esm_file_path
          current_dir = File.dirname(@esm_file_path)
          relative = Pathname.new(target_path).relative_path_from(Pathname.new(current_dir)).to_s
          # Ensure it starts with ./ for ESM compatibility
          relative = "./#{relative}" unless relative.start_with?('.')
          relative
        else
          # Fallback: just prepend ./ and use the target path
          "./#{target_path}"
        end
      end

      def process(node)
        return super if @esm_top

        list = [node]
        while list.length == 1 and list.first.respond_to?(:type) and list.first.type == :begin
          list = list.first.children.dup
        end

        @esm_top = list

        # Merge standalone "export default" with the following statement
        # This handles: export default; def Foo() ... end => export default def Foo() ... end
        merged = []
        merge_happened = false
        i = 0
        while i < list.length
          child = list[i]
          if child.respond_to?(:type) && child.type == :send &&
             child.children[0..1] == [nil, :export] &&
             child.children[2]&.type == :send &&
             child.children[2].children[0..1] == [nil, :default] &&
             child.children[2].children.length == 2 &&  # just "default" with no args
             i + 1 < list.length
            # Merge with next statement
            next_stmt = list[i + 1]
            merged << s(:send, nil, :export, s(:send, nil, :default, next_stmt))
            i += 2  # skip both statements
            merge_happened = true
          else
            merged << child
            i += 1
          end
        end

        # If we merged, rebuild the node with the merged list
        if merge_happened
          list = merged
          @esm_top = list
          node = node.updated(:begin, list)
        end

        # Process the AST first (let other filters transform it)
        result = super(node)

        # Then apply autoexports to the processed result
        return result unless @esm_autoexports

        # Re-extract the list from the processed result
        list = [result]
        while list.length == 1 and list.first.respond_to?(:type) and list.first.type == :begin
          list = list.first.children.dup
        end

        # Skip autoexports if any child is already an export
        # (another filter like Rails::Seeds may have already handled exports)
        # Note: imports should NOT prevent autoexports - only explicit exports should
        has_exports = list.any? { |c| c.respond_to?(:type) && c.type == :export }
        return result if has_exports

        replaced = []
        list.map! do |child|
          replacement = child

          next child unless child.respond_to?(:type)

          if [:module, :class].include? child.type and
            child.children.first.type == :const and
            child.children.first.children.first == nil \
          then
            replacement = s(:export, child)
          elsif [:module, :class].include?(child.type) and
            child.children.first.type == :const and
            child.children.first.children.first.respond_to?(:type) and
            child.children.first.children.first.type == :const \
          then
            # Namespaced class (e.g., Account::Export < Export)
            # Unwrap namespace for export: export class Export extends Export {}
            # Then assign to parent: Account.Export = Export;
            parent_const = child.children.first.children.first  # (const nil :Account)
            leaf_name = child.children.first.children.last       # :Export
            superclass = child.children[1]
            body = child.children[2..-1]

            # Create unnested class with just the leaf name
            leaf_const = s(:const, nil, leaf_name)
            unnested = child.updated(child.type, [leaf_const, superclass, *body])

            # If leaf name == superclass name, use internal name to avoid TDZ
            # e.g., class Account::Export < Export becomes:
            #   class _Export extends Export {}
            #   export { _Export as Export }
            if superclass and superclass.type == :const and
               superclass.children.last == leaf_name
              internal_name = :"_#{leaf_name}"
              internal_const = s(:const, nil, internal_name)
              unnested = child.updated(child.type, [internal_const, superclass, *body])
              export_as = s(:export, s(:array,
                s(:hash, s(:pair, s(:sym, leaf_name), internal_const))
              ))
              replacement = s(:begin, unnested, export_as)
            else
              replacement = s(:export, unnested)
            end
          elsif child.type == :casgn and child.children.first == nil
            replacement = s(:export, child)
          elsif child.type == :casgn and child.children.first != nil
            # Namespaced constant (e.g., Cards.ClosuresController = ...)
            # Unwrap namespace for export: export const ClosuresController = ...
            leaf_name = child.children[1]
            value = child.children[2]
            unnested = s(:casgn, nil, leaf_name, value)
            replacement = s(:export, unnested)
          elsif child.type == :def
            replacement = s(:export, child)
          end

          if replacement != child
            replaced << replacement
            # Move comments from child to export wrapper to avoid duplication
            child_comments = @comments.get(child)
            if child_comments
              @comments.set(replacement, child_comments)
              @comments.set(child, [])
            end
          end

          replacement
        end

        if replaced.length == 1 and @esm_autoexports == :default
          list.map! do |child|
            if child == replaced.first
              replacement = s(:export, s(:send, nil, :default, *child.children))
              # Move comments from child to export wrapper to avoid duplication
              child_comments = @comments.get(child)
              if child_comments
                @comments.set(replacement, child_comments)
                @comments.set(child, [])
              end
              replacement
            else
              child
            end
          end
        end

        @esm_autoexports = false
        result = s(:begin, *list)
        # Set empty comments on the begin node to prevent it from inheriting
        # comments from its first child via first-loc lookup
        @comments.set(result, [])
        result
      end

      def on_class(node)
                @esm_explicit_tokens << node.children.first.children.last

        super
      end

      def on_def(node)
                @esm_explicit_tokens << node.children.first

        super
      end

      def on_lvasgn(node)
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

        # Map Ruby's __dir__ to ESM equivalent
        # import.meta.dirname returns the directory path (Node 20.11+)
        if target.nil? && method == :__dir__ && args.empty?
          return s(:attr, s(:attr, nil, :"import.meta"), :dirname)
        end

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
          # Strip requires for Ruby-only stdlib modules (built-in in JS)
          if method == :require && %w[json ostruct].include?(args[0].children.first)
            return s(:begin)
          end

          if @options[:file]
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
            path = resolve_component_import(args[0].children[0])
            s(:import, path)
          elsif args.length == 1 and \
            args[0].type == :send and \
            args[0].children[0].nil? and \
            args[0].children[2].type == :send and \
            args[0].children[2].children[0].nil? and \
            args[0].children[2].children[1] == :from and \
            args[0].children[2].children[2].type == :str
            # import name from "file.js"
            #  => import name from "file.js"
                        @esm_explicit_tokens << args[0].children[1]

            path = resolve_component_import(args[0].children[2].children[2].children[0])
            s(:import,
              [path],
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
                        if %i(const send str).include? args[0].type
              @esm_explicit_tokens << args[0].children.last
              imports << process(args.shift)
            end

            if args[0].type == :array
              args[0].children.each {|i| @esm_explicit_tokens << i.children.last}
              imports << process_all(args.shift.children)
            end

            # Resolve component imports for string paths
            if args[0] && args[0].type == :str
              path = resolve_component_import(args[0].children[0])
              s(:import, path, *imports)
            elsif args[0]
              # Hash-based syntax (from:, as:) - resolve paths within the hash
              resolved_children = args[0].children.map do |child|
                if child.type == :pair && child.children[0].children[0] == :from && child.children[1].type == :str
                  # from: "path" - resolve the path
                  resolved_path = resolve_component_import(child.children[1].children[0])
                  s(:pair, child.children[0], s(:str, resolved_path))
                else
                  child
                end
              end
              s(:import, resolved_children, *imports)
            end
          end
        elsif method == :export
          # Collect comments from child nodes BEFORE processing
          # Comments may be on the child (class/module) node, not the send node
          child = args[0]
          child_comments = []
          if child && child.respond_to?(:loc) && child.loc&.respond_to?(:expression)
            child_loc = child.loc.expression
            if child_loc
              if @comments.respond_to?(:forEach)
                # JS selfhost: iterate Map and collect/clear matching entries
                @comments.forEach do |value, key|
                  next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
                  key_loc = key.loc.expression
                  if key_loc && key_loc.begin_pos == child_loc.begin_pos
                    child_comments.push(*value) if value.is_a?(Array)
                    @comments.set(key, [])
                  end
                end
              else
                # Ruby: iterate Hash and collect/clear matching entries
                @comments.each do |key, value|
                  next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
                  key_loc = key.loc.expression
                  if key_loc && key_loc.begin_pos == child_loc.begin_pos
                    child_comments.push(*value) if value.is_a?(Array)
                    @comments[key] = []
                  end
                end
              end
            end
          end
          # Unwrap namespace for namespaced module/class exports
          # e.g., export Cards::ClosuresController → export const ClosuresController
          processed_args = process_all(args)
          if processed_args.length == 1 &&
            processed_args[0].respond_to?(:type) &&
            [:module, :class].include?(processed_args[0].type) &&
            processed_args[0].children.first.respond_to?(:type) &&
            processed_args[0].children.first.type == :const &&
            processed_args[0].children.first.children.first != nil
            child_node = processed_args[0]
            leaf_name = child_node.children.first.children.last
            leaf_const = s(:const, nil, leaf_name)
            unnested = child_node.updated(child_node.type,
              [leaf_const, *child_node.children[1..-1]])
            processed_args = [unnested]
          end
          # Use node.updated to preserve location for comment re-association
          result = node.updated(:export, processed_args)
          # Combine comments from send node and child node
          node_comments = @comments.get(node)
          all_comments = []
          all_comments.push(*node_comments) if node_comments
          all_comments.push(*child_comments)
          # Always set comments on result (even if empty) to prevent
          # first-child-location lookup from stealing comments from internal nodes
          @comments.set(result, all_comments)
          @comments.set(node, [])
          result
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
        # Move comments from child to export wrapper to avoid duplication
        result = s(:export, *process_all(node.children))
        child = node.children.first
        child_comments = child && @comments.get(child)
        if child_comments
          @comments.set(result, child_comments)
          @comments.set(child, [])
        end
        result
      end

      private

      # Convert a file:// URL to a filesystem path
      # Handles both Ruby file paths and JavaScript import.meta.url values
      def url_to_path(file_url)
        return file_url unless file_url.start_with?('file://')

        # Handle file:// URLs (from import.meta.url in JavaScript)
        # Strip file:// prefix and handle file:/// for absolute paths
        path = file_url.sub(/^file:\/\//, '')
        # On Unix, file:///path becomes /path (strip leading //)
        # On Windows, file:///C:/path becomes C:/path
        path = path.sub(/^\/([A-Za-z]:)/, '\1') if path.match?(/^\/[A-Za-z]:/)
        path
      end

      # Convert require/require_relative to import statement by parsing the file
      # and detecting its exports
      def convert_require_to_import(node, method, basename)
        file = url_to_path(@options[:file])
        base_dirname = File.dirname(File.expand_path(file))
        collect_imports_from_file(base_dirname, basename, base_dirname, node)
      end

      # Recursively collect imports from a file
      def collect_imports_from_file(base_dirname, basename, current_dirname, fallback_node)
        filename = File.join(current_dirname, basename)

        if not File.file?(filename) and File.file?(filename + ".rb")
          filename += '.rb'
        elsif not File.file?(filename) and File.file?(filename + ".js.rb")
          filename += '.js.rb'
        end

        return fallback_node unless File.file?(filename)

        realpath = File.realpath(filename)

        # If we've already seen this file, return a reference to it
        if @esm_require_seen[realpath]
          imports = @esm_require_seen[realpath]
          importname = Pathname.new(filename).relative_path_from(Pathname.new(base_dirname)).to_s
          importname = "./#{importname}" unless importname.start_with?('.')
          return s(:import, importname, *imports)
        end

        # Parse the file to find exports
        ast, _comments = Ruby2JS.parse(File.read(filename), filename)
        children = ast.type == :begin ? ast.children : [ast]

        named_exports = []
        default_exports = []
        recursive_imports = []
        file_dirname = File.dirname(filename)

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
                recursive_imports += nested_result.children
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
            importname = Pathname.new(filename).relative_path_from(Pathname.new(base_dirname)).to_s
            importname = "./#{importname}" unless importname.start_with?('.')
            all_imports << s(:import, importname, *imports)
          end
          # Then add nested imports (dependencies come after)
          all_imports += recursive_imports
          return s(:begin, *all_imports) if all_imports.length > 1
          return all_imports.first if all_imports.length == 1
          return fallback_node
        end

        # If no exports found, just return the fallback (original require)
        return fallback_node if imports.empty?

        # Generate import statement
        importname = Pathname.new(filename).relative_path_from(Pathname.new(base_dirname)).to_s
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
