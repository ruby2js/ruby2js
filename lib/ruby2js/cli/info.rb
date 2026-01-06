# frozen_string_literal: true

require 'optparse'
require 'yaml'

module Ruby2JS
  module CLI
    module Info
      class << self
        def run(args)
          options = parse_options(args)
          show_info(options)
        end

        private

        def parse_options(args)
          options = { verbose: false }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos info [options]"
            opts.separator ""
            opts.separator "Show current Juntos configuration."
            opts.separator ""

            opts.on("-v", "--verbose", "Show detailed information") do
              options[:verbose] = true
            end

            opts.on("-h", "--help", "Show this help message") do
              puts opts
              exit
            end
          end

          parser.parse!(args)
          options
        end

        def show_info(options)
          puts "Juntos Configuration"
          puts "=" * 40
          puts

          show_environment
          show_database_config
          show_d1_config if options[:verbose]
          show_project_info
          show_dependencies if options[:verbose]
        end

        def show_environment
          puts "Environment:"
          puts "  RAILS_ENV:        #{ENV['RAILS_ENV'] || 'development (default)'}"
          puts "  JUNTOS_DATABASE:  #{ENV['JUNTOS_DATABASE'] || '(not set)'}"
          puts "  JUNTOS_TARGET:    #{ENV['JUNTOS_TARGET'] || '(not set)'}"
          puts
        end

        def show_database_config
          puts "Database Configuration:"

          config_path = 'config/database.yml'
          if File.exist?(config_path)
            begin
              config = YAML.load_file(config_path, aliases: true)
              env = ENV['RAILS_ENV'] || 'development'

              if config && config[env]
                env_config = config[env]
                puts "  config/database.yml (#{env}):"
                puts "    adapter:  #{env_config['adapter'] || '(not set)'}"
                puts "    database: #{env_config['database'] || '(not set)'}"
                puts "    target:   #{env_config['target'] || '(not set)'}" if env_config['target']
              else
                puts "  config/database.yml: No '#{env}' section found"
              end
            rescue => e
              puts "  config/database.yml: Error parsing - #{e.message}"
            end
          else
            puts "  config/database.yml: Not found"
          end
          puts
        end

        def show_d1_config
          puts "D1 Configuration (.env.local):"

          env_file = '.env.local'
          if File.exist?(env_file)
            d1_vars = []
            File.readlines(env_file).each do |line|
              if line =~ /^(D1_DATABASE_ID[^=]*)=(.+)$/
                d1_vars << [$1, $2.strip]
              end
            end

            if d1_vars.any?
              d1_vars.each do |name, value|
                # Show truncated ID for security
                display_value = value.length > 20 ? "#{value[0..7]}...#{value[-4..]}" : value
                puts "  #{name}: #{display_value}"
              end
            else
              puts "  No D1_DATABASE_ID variables found"
            end
          else
            puts "  .env.local: Not found"
          end
          puts
        end

        def show_project_info
          puts "Project:"
          puts "  Directory: #{File.basename(Dir.pwd)}"
          puts "  Rails app: #{File.directory?('app') && File.directory?('config') ? 'Yes' : 'No'}"

          if File.exist?('Gemfile')
            gemfile = File.read('Gemfile')
            if gemfile.include?('ruby2js')
              puts "  ruby2js:   In Gemfile"
            else
              puts "  ruby2js:   Not in Gemfile"
            end
          end

          if File.directory?('dist')
            puts "  dist/:     Built"
            if File.exist?('dist/wrangler.toml')
              puts "  Target:    Cloudflare (wrangler.toml present)"
            elsif File.exist?('dist/vercel.json')
              puts "  Target:    Vercel (vercel.json present)"
            end
          else
            puts "  dist/:     Not built"
          end
          puts
        end

        def show_dependencies
          puts "Dependencies:"

          # Check Node.js
          node_version = `node --version 2>/dev/null`.strip
          puts "  Node.js:   #{node_version.empty? ? 'Not found' : node_version}"

          # Check npm
          npm_version = `npm --version 2>/dev/null`.strip
          puts "  npm:       #{npm_version.empty? ? 'Not found' : npm_version}"

          # Check wrangler
          wrangler_check = system('npx wrangler --version', out: File::NULL, err: File::NULL)
          puts "  wrangler:  #{wrangler_check ? 'Available' : 'Not installed'}"

          # Check vercel
          vercel_check = system('npx vercel --version', out: File::NULL, err: File::NULL)
          puts "  vercel:    #{vercel_check ? 'Available' : 'Not installed'}"

          # Check turso
          turso_check = system('turso --version', out: File::NULL, err: File::NULL)
          puts "  turso:     #{turso_check ? 'Available' : 'Not installed'}"

          puts
        end
      end
    end
  end
end
