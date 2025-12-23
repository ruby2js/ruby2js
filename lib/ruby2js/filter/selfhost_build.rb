require 'ruby2js'

module Ruby2JS
  module Filter
    module SelfhostBuild
      include SEXP

      # Lazy-initialized imports
      def import_yaml
        @import_yaml ||= s(:import, ['js-yaml'], s(:attr, nil, :yaml))
      end

      def import_fs_for_yaml
        @import_fs_for_yaml ||= s(:import, ['node:fs'], s(:attr, nil, :fs))
      end

      # Map filter file names to export names
      # Some filters use uppercase (ESM, CJS), others use capitalized (Functions, Return)
      UPPERCASE_FILTERS = %w[esm cjs].freeze

      # Filters with non-standard capitalization that must be preserved
      SPECIAL_CASE_FILTERS = {
        'camelcase' => 'CamelCase',
        'camelCase' => 'CamelCase'
      }.freeze

      def filter_to_export_name(name)
        # Check for special case first
        return SPECIAL_CASE_FILTERS[name] if SPECIAL_CASE_FILTERS.key?(name)
        return SPECIAL_CASE_FILTERS[name.downcase] if SPECIAL_CASE_FILTERS.key?(name.downcase)

        if UPPERCASE_FILTERS.include?(name.downcase)
          name.upcase
        else
          # Capitalize each word for names like 'active_support' → 'ActiveSupport'
          name.split('_').map(&:capitalize).join
        end
      end

      def on_send(node)
        target, method, *args = node.children

        # $LOAD_PATH.unshift(...) → remove entirely
        if target&.type == :gvar && target.children == [:$LOAD_PATH]
          return s(:begin)
        end

        # YAML.load_file(path) or YAML.load_file(path, opts) → yaml.load(fs.readFileSync(path, 'utf8'))
        # Note: js-yaml supports anchors by default, so we ignore the aliases: true option
        if target == s(:const, nil, :YAML) && method == :load_file && args.length >= 1
          prepend_list << import_yaml
          prepend_list << import_fs_for_yaml
          return S(:send, s(:attr, nil, :yaml), :load,
            s(:send, s(:attr, nil, :fs), :readFileSync,
              process(args.first), s(:str, 'utf8')))
        end

        # YAML.dump(obj) → yaml.dump(obj)
        if target == s(:const, nil, :YAML) && method == :dump && args.length == 1
          prepend_list << import_yaml
          return S(:send, s(:attr, nil, :yaml), :dump, process(args.first))
        end

        # require 'yaml', 'json', or 'fileutils' → remove
        # (yaml handled by import above, json built-in, fileutils replaced by node filter)
        if target.nil? && method == :require && args.length == 1 &&
           args.first.type == :str && %w[yaml json fileutils].include?(args.first.children.first)
          return s(:begin)
        end

        # require 'ruby2js' → import * as Ruby2JS from selfhost path; await Ruby2JS.initPrism()
        if target.nil? && method == :require && args.length == 1 &&
           args.first.type == :str && args.first.children.first == 'ruby2js'
          # Default path assumes script is in demo/*/vendor/ruby2js/ relative to demo/selfhost/
          selfhost_path = @options[:selfhost_path] || '../../../selfhost/ruby2js.js'
          # Namespace import with async initialization for selfhost
          # Note: await is s(:send, nil, :await, expr) not s(:await, expr)
          # Path array format: [as_pair, from_pair] for "import * as X from Y"
          return s(:begin,
            s(:import,
              [s(:pair, s(:sym, :as), s(:const, nil, :Ruby2JS)),
               s(:pair, s(:sym, :from), s(:str, selfhost_path))],
              s(:str, '*')),
            s(:send, nil, :await, s(:send, s(:const, nil, :Ruby2JS), :initPrism)))
        end

        # require 'ruby2js/filter/rails' → import Rails filters
        if target.nil? && method == :require && args.length == 1 &&
           args.first.type == :str
          req_path = args.first.children.first
          if req_path.start_with?('ruby2js/filter/')
            filter_name = req_path.sub('ruby2js/filter/', '')
            selfhost_filters = @options[:selfhost_filters] || '../../../selfhost/filters'
            # For paths like 'rails/model', export as 'Rails_Model' to match selfhost
            # For simple paths like 'functions', export as 'Functions'
            parts = filter_name.split('/')
            export_name = parts.map { |p| filter_to_export_name(p) }.join('_')
            # Use named import { X } since selfhost modules use named exports
            return s(:import, ["#{selfhost_filters}/#{filter_name}.js"],
              s(:array, s(:const, nil, export_name.to_sym)))
          end
        end

        # require_relative → import (convert path to .js)
        if target.nil? && method == :require_relative && args.length == 1 &&
           args.first.type == :str
          rel_path = args.first.children.first

          # Special case: erb_compiler should come from selfhost (named export)
          if rel_path.include?('erb_compiler')
            selfhost_path = @options[:selfhost_path] || '../../../selfhost/ruby2js.js'
            selfhost_base = File.dirname(selfhost_path)
            return s(:import, ["#{selfhost_base}/lib/erb_compiler.js"],
              s(:array, s(:const, nil, :ErbCompiler)))
          end

          # Convert .rb to .js, or add .js if no extension
          js_path = if rel_path.end_with?('.rb')
            rel_path.sub(/\.rb$/, '.js')
          else
            "#{rel_path}.js"
          end
          return s(:import, js_path)
        end

        super
      end

      def on_const(node)
        # Ruby2JS::Filter::Rails::Model → Rails_Model.prototype (matching selfhost usage)
        if node.children.first&.type == :const
          parts = []
          n = node
          while n&.type == :const
            parts.unshift(n.children.last)
            n = n.children.first
          end

          # Ruby2JS::Filter::X → X.prototype (selfhost pipeline expects prototype objects)
          if parts[0] == :Ruby2JS && parts[1] == :Filter && parts.length >= 3
            if parts.length == 3
              # Ruby2JS::Filter::ESM → ESM.prototype
              export_name = filter_to_export_name(parts[2].to_s)
              # Use :attr for property access (no parentheses) instead of :send
              return s(:attr, s(:const, nil, export_name.to_sym), :prototype)
            else
              # Ruby2JS::Filter::Rails::Model → Rails_Model.prototype
              filter_parts = parts[2..-1].map { |p| filter_to_export_name(p.to_s) }
              return s(:attr, s(:const, nil, filter_parts.join('_').to_sym), :prototype)
            end
          end
        end

        super
      end

      def on_gvar(node)
        # $0 → `file://${fs.realpathSync(process.argv[1])}` for ESM main script check
        # This works with __FILE__ → import.meta.url conversion from ESM filter
        # Using realpathSync to resolve symlinks (npm bin commands use symlinks)
        if node.children.first == :$0
          # Build: `file://${fs.realpathSync(process.argv[1])}`
          return s(:dstr,
            s(:str, 'file://'),
            s(:begin, s(:send,
              s(:attr, nil, :fs),
              :realpathSync,
              s(:send,
                s(:attr, s(:attr, nil, :process), :argv),
                :[],
                s(:int, 1)))))
        end
        super
      end

      def on_gvasgn(node)
        # $LOAD_PATH = ... → remove
        if node.children.first == :$LOAD_PATH
          return s(:begin)
        end
        super
      end
    end

    DEFAULTS.push SelfhostBuild
  end
end
