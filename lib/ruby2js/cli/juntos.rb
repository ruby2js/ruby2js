# frozen_string_literal: true

require 'optparse'
require 'yaml'

module Ruby2JS
  module CLI
    module Juntos
      SUBCOMMANDS = %w[dev server build deploy install up migrate db].freeze

      class << self
        def run(args)
          # Parse common flags before subcommand
          common_opts, remaining = parse_common_options(args)

          subcommand = remaining.shift

          unless subcommand
            show_help
            exit 1
          end

          unless SUBCOMMANDS.include?(subcommand)
            if subcommand == '-h' || subcommand == '--help'
              show_help
              exit 0
            end
            abort "Unknown command: #{subcommand}\nRun 'juntos --help' for usage."
          end

          # Apply common options to environment/config
          apply_common_options(common_opts)

          # Dispatch to subcommand
          require "ruby2js/cli/#{subcommand}"
          Ruby2JS::CLI.const_get(subcommand.capitalize).run(remaining)
        end

        private

        def parse_common_options(args)
          options = {
            database: nil,
            environment: nil,
            target: nil
          }

          # We need to extract common flags without consuming subcommand flags
          # Parse known common flags, leave rest for subcommand
          remaining = []
          i = 0

          while i < args.length
            arg = args[i]

            case arg
            when '-d', '--database'
              options[:database] = args[i + 1]
              i += 2
            when /^-d(.+)/, /^--database=(.+)/
              options[:database] = $1
              i += 1
            when '-e', '--environment'
              options[:environment] = args[i + 1]
              i += 2
            when /^-e(.+)/, /^--environment=(.+)/
              options[:environment] = $1
              i += 1
            when '-t', '--target'
              options[:target] = args[i + 1]
              i += 2
            when /^-t(.+)/, /^--target=(.+)/
              options[:target] = $1
              i += 1
            else
              remaining << arg
              i += 1
            end
          end

          [options, remaining]
        end

        def apply_common_options(options)
          # Set RAILS_ENV if specified
          if options[:environment]
            ENV['RAILS_ENV'] = options[:environment]
            ENV['NODE_ENV'] = options[:environment]
          end

          # Database and target are applied by modifying the effective config
          # Store in environment variables for subcommands to read
          ENV['JUNTOS_DATABASE'] = options[:database] if options[:database]
          ENV['JUNTOS_TARGET'] = options[:target] if options[:target]
        end

        def show_help
          puts <<~HELP
            Juntos - Rails patterns, JavaScript runtimes

            Usage: juntos [options] <command> [command-options]

            Commands:
              up        Build and run locally (node, bun, deno, browser)
              dev       Start development server with hot reload
              server    Start production server (requires prior build)
              build     Build for deployment
              deploy    Build and deploy (Vercel, Cloudflare)
              migrate   Run database migrations
              db        D1 database commands (create, migrate, seed, prepare, drop)
              install   Set up project for Juntos

            Common Options:
              -d, --database ADAPTER   Database adapter (dexie, sqlite, turso, etc.)
              -e, --environment ENV    Environment (development, production, test)
              -t, --target TARGET      Deploy target (browser, node, vercel, cloudflare)

            Examples:
              juntos up                              # Build and run (uses database.yml)
              juntos up -t node -d better_sqlite3    # Build and run with Node + SQLite
              juntos dev                             # Start dev server with hot reload
              juntos deploy -t vercel -d neon        # Deploy to Vercel with Neon DB
              juntos db prepare                      # Create, migrate, and seed D1 database

            Run 'juntos <command> --help' for command-specific options.
          HELP
        end
      end
    end
  end
end
