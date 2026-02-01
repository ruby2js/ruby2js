require 'ruby2js'

module Ruby2JS
  module Filter
    module Node
      include SEXP

      # Lazy-initialized import nodes (avoids need for extend SEXP)
      # Using node: prefix for compatibility with Node.js 16+, Bun, and Deno
      def import_child_process
        @import_child_process ||= s(:import, ['node:child_process'],
            s(:attr, nil, :child_process))
      end

      def import_fs
        @import_fs ||= s(:import, ['node:fs'], s(:attr, nil, :fs))
      end

      def import_fs_promises
        @import_fs_promises ||= s(:import, ['node:fs/promises'], s(:attr, nil, :fs))
      end

      # For existsSync - no async equivalent, always use sync version
      def import_fs_sync
        @import_fs_sync ||= s(:import, ['node:fs'], s(:attr, nil, :fsSync))
      end

      def import_os
        @import_os ||= s(:import, ['node:os'], s(:attr, nil, :os))
      end

      def node_import_path
        @node_import_path ||= s(:import, ['node:path'], s(:attr, nil, :path))
      end

      def setup_argv
        @setup_argv ||= s(:lvasgn, :ARGV, s(:send, s(:attr,
            s(:attr, nil, :process), :argv), :slice, s(:int, 2)))
      end

      # Helper to check if async mode is enabled
      def async?
        @options[:async]
      end

      # Helper to generate fs calls - handles sync vs async
      def fs_call(method, *args)
        if async?()
          self.prepend_list << import_fs_promises
          # Remove Sync suffix for async methods
          async_method = method.to_s.sub(/Sync$/, '').to_sym
          S(:send, nil, :await,
            s(:send, s(:attr, nil, :fs), async_method, *args))
        else
          self.prepend_list << import_fs
          s(:send, s(:attr, nil, :fs), method, *args)
        end
      end

      # Special case for existsSync - no async equivalent
      def fs_exists_call(*args)
        if async?()
          self.prepend_list << import_fs_sync
          S(:send, s(:attr, nil, :fsSync), :existsSync, *args)
        else
          self.prepend_list << import_fs
          S(:send, s(:attr, nil, :fs), :existsSync, *args)
        end
      end

      # Helper for fs.glob - async returns iterator, needs Array.fromAsync
      def fs_glob_call(*args)
        if async?()
          self.prepend_list << import_fs_promises
          # await Array.fromAsync(fs.glob(pattern))
          S(:send, nil, :await,
            s(:send, s(:const, nil, :Array), :fromAsync,
              s(:send, s(:attr, nil, :fs), :glob, *args)))
        else
          self.prepend_list << import_fs
          s(:send, s(:attr, nil, :fs), :globSync, *args)
        end
      end

      def on_send(node)
        target, method, *args = node.children

        if target == nil
          if method == :exit and args.length <= 1
            s(:send, s(:attr, nil, :process), :exit, *process_all(args));

          elsif method == :system
            self.prepend_list << import_child_process

            if args.length == 1
              S(:send, s(:attr, nil, :child_process), :execSync,
              process(args.first),
              s(:hash, s(:pair, s(:sym, :stdio), s(:str, 'inherit'))))
            else
              S(:send, s(:attr, nil, :child_process), :execFileSync,
              process(args.first), s(:array, *process_all(args[1..-1])),
              s(:hash, s(:pair, s(:sym, :stdio), s(:str, 'inherit'))))
            end

          elsif \
            method == :require and args.length == 1 and
            args.first.type == :str and
            %w(fileutils pathname tmpdir).include? args.first.children.first
          then
            s(:begin)

          else
            super
          end

        elsif \
          [:File, :IO].include? target.children.last and
          target.type == :const and target.children.first == nil
        then
          if method == :read and args.length == 1
            fs_call(:readFileSync, *process_all(args), s(:str, 'utf8'))

          elsif method == :write and args.length == 2
            fs_call(:writeFileSync, *process_all(args))

          elsif target.children.last == :IO
            super

          elsif [:exist?, :exists?].include? method and args.length == 1
            fs_exists_call(process(args.first))

          elsif method == :directory? and args.length == 1
            # File.directory?(path) → fs.existsSync(path) && fs.statSync(path).isDirectory()
            path_arg = process(args.first)
            S(:and,
              fs_exists_call(path_arg),
              s(:send, fs_call(:statSync, path_arg), :isDirectory))

          elsif method == :file? and args.length == 1
            # File.file?(path) → fs.existsSync(path) && fs.statSync(path).isFile()
            path_arg = process(args.first)
            S(:and,
              fs_exists_call(path_arg),
              s(:send, fs_call(:statSync, path_arg), :isFile))

          elsif method == :symlink? and args.length == 1
            # File.symlink?(path) → fs.lstatSync(path).isSymbolicLink()
            # Use lstat (not stat) to check the link itself, not what it points to
            s(:send, fs_call(:lstatSync, process(args.first)), :isSymbolicLink)

          elsif method == :readlink and args.length == 1
            fs_call(:readlinkSync, process(args.first))

          elsif method == :realpath and args.length == 1
            fs_call(:realpathSync, process(args.first))

          elsif method == :rename and args.length == 2
            fs_call(:renameSync, *process_all(args))

          elsif \
            [:chmod, :lchmod].include? method and
            args.length > 1 and args.first.type == :int
          then
            S(:begin, *args[1..-1].map{|file|
              fs_call(method.to_s + 'Sync', process(file),
                s(:octal, *args.first.children))
            })

          elsif \
            [:chown, :lchown].include? method and args.length > 2 and
            args[0].type == :int and args[1].type == :int
          then
            S(:begin, *args[2..-1].map{|file|
              fs_call(method.to_s + 'Sync', process(file),
                *process_all(args[0..1]))
            })

          elsif method == :link and args.length == 2
            fs_call(:linkSync, *process_all(args))

          elsif method == :symlink and args.length == 2
            fs_call(:symlinkSync, *process_all(args))

          elsif method == :truncate and args.length == 2
            fs_call(:truncateSync, *process_all(args))

          elsif [:stat, :lstat].include? method and args.length == 1
            fs_call(method.to_s + 'Sync', process(args.first))

          elsif method == :unlink and args.length == 1
            S(:begin, *args.map{|file|
              fs_call(:unlinkSync, process(file))
            })

          elsif target.children.last == :File
            if method == :absolute_path or method == :expand_path
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :resolve,
                *process_all(args.reverse))
            elsif method == :absolute_path?
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :isAbsolute, *process_all(args))
            elsif method == :basename
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :basename, *process_all(args))
            elsif method == :dirname
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :dirname, *process_all(args))
            elsif method == :extname
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :extname, *process_all(args))
            elsif method == :join
              self.prepend_list << node_import_path
              S(:send, s(:attr, nil, :path), :join, *process_all(args))
            else
              super
            end
          else
            super
          end

        elsif \
          target.children.last == :FileUtils and
          target.type == :const and target.children.first == nil
        then

          list = proc do |arg|
            if arg.type == :array
              arg.children
            else
              [arg]
            end
          end

          if [:cp, :copy].include? method and args.length == 2
            fs_call(:copyFileSync, *process_all(args))

          elsif [:mv, :move].include? method and args.length == 2
            fs_call(:renameSync, *process_all(args))

          elsif method == :mkdir and args.length == 1
            S(:begin, *list[args.last].map {|file|
              fs_call(:mkdirSync, process(file))
            })

          elsif method == :mkdir_p and args.length == 1
            S(:begin, *list[args.last].map {|file|
              fs_call(:mkdirSync, process(file),
                s(:hash, s(:pair, s(:sym, :recursive), s(:true))))
            })

          elsif method == :rm_rf and args.length == 1
            S(:begin, *list[args.last].map {|file|
              fs_call(:rmSync, process(file),
                s(:hash,
                  s(:pair, s(:sym, :recursive), s(:true)),
                  s(:pair, s(:sym, :force), s(:true))))
            })

          elsif method == :cd and args.length == 1
            S(:send, s(:attr, nil, :process), :chdir, *process_all(args))

          elsif method == :pwd and args.length == 0
            S(:send!, s(:attr, nil, :process), :cwd)

          elsif method == :rmdir and args.length == 1
            S(:begin, *list[args.last].map {|file|
              fs_call(:rmdirSync, process(file))
            })

          elsif method == :ln and args.length == 2
            fs_call(:linkSync, *process_all(args))

          elsif method == :ln_s and args.length == 2
            fs_call(:symlinkSync, *process_all(args))

          elsif method == :rm and args.length == 1
            S(:begin, *list[args.last].map {|file|
              fs_call(:unlinkSync, process(file))
            })

          elsif \
            method == :chmod and args.length == 2 and args.first.type == :int
          then
            S(:begin, *list[args.last].map {|file|
              fs_call(:chmodSync, process(file),
                s(:octal, *args.first.children))
            })

          elsif \
            method == :chown and args.length == 3 and
            args[0].type == :int and args[1].type == :int
          then
            S(:begin, *list[args.last].map {|file|
              fs_call(:chownSync, process(file), *process_all(args[0..1]))
            })

          elsif method == :touch
            S(:begin, *list[args.first].map {|file|
              if async?()
                self.prepend_list << import_fs_promises
                # For async: await fs.writeFile(file, '', {flag: 'a'})
                S(:send, nil, :await,
                  s(:send, s(:attr, nil, :fs), :writeFile, file, s(:str, ''),
                    s(:hash, s(:pair, s(:sym, :flag), s(:str, 'a')))))
              else
                self.prepend_list << import_fs
                S(:send, s(:attr, nil, :fs), :closeSync,
                  s(:send, s(:attr, nil, :fs), :openSync, file, s(:str, "w")))
              end
            })

          else
            super
          end

        elsif \
          target.type == :const and target.children.first == nil and
          target.children.last == :Dir
        then
          if method == :chdir and args.length == 1
            S(:send, s(:attr, nil, :process), :chdir, *process_all(args))
          elsif method == :pwd and args.length == 0
            S(:send!, s(:attr, nil, :process), :cwd)
          elsif method == :entries or method == :children
            # Note: Node.js readdirSync already excludes '.' and '..'
            # so both Ruby's Dir.entries and Dir.children map to readdirSync
            fs_call(:readdirSync, *process_all(args))
          elsif method == :mkdir and args.length == 1
            fs_call(:mkdirSync, process(args.first))
          elsif method == :rmdir and args.length == 1
            fs_call(:rmdirSync, process(args.first))
          elsif method == :mktmpdir and args.length <=1
            if args.length == 0
              prefix = s(:str, 'd')
            elsif args.first.type == :array
              prefix = args.first.children.first
            else
              prefix = args.first
            end

            fs_call(:mkdtempSync, process(prefix))
          elsif method == :home and args.length == 0
            self.prepend_list << import_os
            S(:send!, s(:attr, nil, :os), :homedir)
          elsif method == :tmpdir and args.length == 0
            self.prepend_list << import_os
            S(:send!, s(:attr, nil, :os), :tmpdir)
          elsif [:exist?, :exists?].include? method and args.length == 1
            fs_exists_call(process(args.first))
          elsif method == :glob and args.length == 1
            fs_glob_call(process(args.first))

          else
            super
          end

        # Pathname.new(a).relative_path_from(Pathname.new(b)) → path.relative(b, a)
        elsif method == :relative_path_from and args.length == 1 and
              target&.type == :send and
              target.children[0]&.type == :const and
              const_is?(target.children[0], :Pathname) and
              target.children[1] == :new and
              args.first&.type == :send and
              args.first.children[0]&.type == :const and
              const_is?(args.first.children[0], :Pathname) and
              args.first.children[1] == :new
        then
          self.prepend_list << node_import_path
          # path.relative(from, to) - note: args order is reversed from Ruby
          from_path = process(args.first.children[2])
          to_path = process(target.children[2])
          S(:send, s(:attr, nil, :path), :relative, from_path, to_path)

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        target, method, *args = call.children

        if \
          method == :chdir and args.length == 1 and
          target.children.last == :Dir and
          target.type == :const and target.children.first == nil
        then
          s(:begin,
            s(:gvasgn, :$oldwd, s(:send, s(:attr, nil, :process), :cwd)),
            s(:kwbegin, s(:ensure,
              s(:begin, process(call), process(node.children.last)),
              s(:send, s(:attr, nil, :process), :chdir, s(:gvar, :$oldwd)))))
        else
          super
        end
      end

      # Helper for comparing node.children to [nil, :Symbol] in JS-compatible way
      # Ruby's == compares array values, JS's === compares references
      def const_is?(node, name)
        node.children.first.nil? && node.children.last == name
      end

      def on_const(node)
        if const_is?(node, :ARGV)
          self.prepend_list << setup_argv
          super
        elsif const_is?(node, :ENV)
          S(:attr, s(:attr, nil, :process), :env)
        elsif const_is?(node, :STDIN)
          S(:attr, s(:attr, nil, :process), :stdin)
        elsif const_is?(node, :STDOUT)
          S(:attr, s(:attr, nil, :process), :stdout)
        elsif const_is?(node, :STDERR)
          S(:attr, s(:attr, nil, :process), :stderr)
        elsif node.children.first == s(:const, nil, :File)
          if node.children.last == :SEPARATOR
            self.prepend_list << node_import_path
            S(:attr, s(:attr, nil, :path), :sep)
          elsif node.children.last == :PATH_SEPARATOR
            self.prepend_list << node_import_path
            S(:attr, s(:attr, nil, :path), :delimiter)
          else
            super
          end
        else
          super
        end
      end

      def on_gvar(node)
        # Use element access instead of array comparison for JS compatibility
        if node.children.first == :$stdin
          S(:attr, s(:attr, nil, :process), :stdin)
        elsif node.children.first == :$stdout
          S(:attr, s(:attr, nil, :process), :stdout)
        elsif node.children.first == :$stderr
          S(:attr, s(:attr, nil, :process), :stderr)
        else
          super
        end
      end

      def on_xstr(node)
        self.prepend_list << import_child_process

        children = node.children.dup
        command = children.shift
        while children.length > 0
          child = children.shift
          if \
            child.type == :begin and child.children.length == 1 and
            child.children.first.type == :send and
            child.children.first.children.first == nil
          then
            child = child.children.first
          end
          command = s(:send, command, :+, child)
        end

        s(:send, s(:attr, nil, :child_process), :execSync, command,
          s(:hash, s(:pair, s(:sym, :encoding), s(:str, 'utf8'))))
      end
    end

    DEFAULTS.push Node
  end
end
