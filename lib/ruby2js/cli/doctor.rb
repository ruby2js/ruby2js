# frozen_string_literal: true

require 'optparse'
require 'yaml'

module Ruby2JS
  module CLI
    module Doctor
      class << self
        def run(args)
          options = parse_options(args)
          run_checks(options)
        end

        private

        def parse_options(args)
          options = { fix: false }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos doctor [options]"
            opts.separator ""
            opts.separator "Check environment and prerequisites for Juntos."
            opts.separator ""

            opts.on("-h", "--help", "Show this help message") do
              puts opts
              exit
            end
          end

          parser.parse!(args)
          options
        end

        def run_checks(options)
          puts "Juntos Doctor"
          puts "=" * 40
          puts

          issues = []
          warnings = []

          # Check Ruby version
          check_ruby(issues, warnings)

          # Check Node.js
          check_node(issues, warnings)

          # Check npm
          check_npm(issues, warnings)

          # Check Rails app structure
          check_rails_app(issues, warnings)

          # Check database.yml
          check_database_config(issues, warnings)

          # Check .env.local for D1
          check_env_local(issues, warnings)

          # Check wrangler (if using D1/Cloudflare)
          check_wrangler(issues, warnings)

          # Check dist directory
          check_dist(issues, warnings)

          # Summary
          puts
          puts "=" * 40

          if issues.empty? && warnings.empty?
            puts "All checks passed! Your environment is ready."
          else
            if warnings.any?
              puts
              puts "Warnings (#{warnings.length}):"
              warnings.each { |w| puts "  - #{w}" }
            end

            if issues.any?
              puts
              puts "Issues (#{issues.length}):"
              issues.each { |i| puts "  - #{i}" }
              puts
              puts "Fix these issues to use Juntos."
              exit 1
            else
              puts
              puts "No critical issues found."
            end
          end
        end

        def check_ruby(issues, warnings)
          print "Checking Ruby... "
          version = RUBY_VERSION

          if Gem::Version.new(version) >= Gem::Version.new('3.2')
            puts "OK (#{version})"
          elsif Gem::Version.new(version) >= Gem::Version.new('3.0')
            puts "OK (#{version})"
            warnings << "Ruby #{version} works but 3.2+ recommended"
          else
            puts "FAIL (#{version})"
            issues << "Ruby 3.0+ required, found #{version}"
          end
        end

        def check_node(issues, warnings)
          print "Checking Node.js... "
          version = `node --version 2>/dev/null`.strip

          if version.empty?
            puts "FAIL"
            issues << "Node.js not found. Install from https://nodejs.org/"
            return
          end

          # Parse version (v22.0.0 -> 22)
          major = version.sub(/^v/, '').split('.').first.to_i

          if major >= 22
            puts "OK (#{version})"
          elsif major >= 18
            puts "OK (#{version})"
            warnings << "Node.js #{version} works but 22+ recommended"
          else
            puts "FAIL (#{version})"
            issues << "Node.js 18+ required, found #{version}"
          end
        end

        def check_npm(issues, warnings)
          print "Checking npm... "
          version = `npm --version 2>/dev/null`.strip

          if version.empty?
            puts "FAIL"
            issues << "npm not found. Usually comes with Node.js."
          else
            puts "OK (#{version})"
          end
        end

        def check_rails_app(issues, warnings)
          print "Checking Rails app structure... "

          if File.directory?('app') && File.directory?('config')
            puts "OK"

            # Check for required directories
            %w[app/models app/controllers app/views config/routes.rb].each do |path|
              unless File.exist?(path)
                warnings << "Missing #{path}"
              end
            end
          else
            puts "FAIL"
            issues << "Not a Rails app directory (missing app/ or config/)"
          end
        end

        def check_database_config(issues, warnings)
          print "Checking config/database.yml... "

          if File.exist?('config/database.yml')
            begin
              config = YAML.load_file('config/database.yml', aliases: true)
              env = ENV['RAILS_ENV'] || 'development'

              if config && config[env]
                adapter = config[env]['adapter']
                if adapter
                  puts "OK (#{adapter})"
                else
                  puts "WARN"
                  warnings << "No adapter specified in database.yml for #{env}"
                end
              else
                puts "WARN"
                warnings << "No #{env} section in database.yml"
              end
            rescue => e
              puts "FAIL"
              issues << "Cannot parse database.yml: #{e.message}"
            end
          else
            puts "MISSING"
            warnings << "No config/database.yml found. Using defaults."
          end
        end

        def check_env_local(issues, warnings)
          print "Checking .env.local... "

          if File.exist?('.env.local')
            content = File.read('.env.local')

            # Check for D1 database ID if using D1
            config_path = 'config/database.yml'
            using_d1 = false

            if File.exist?(config_path)
              config = YAML.load_file(config_path, aliases: true) rescue {}
              env = ENV['RAILS_ENV'] || 'development'
              using_d1 = config.dig(env, 'adapter') == 'd1'
            end

            if using_d1
              if content =~ /D1_DATABASE_ID/
                puts "OK (D1 configured)"
              else
                puts "WARN"
                warnings << "Using D1 but no D1_DATABASE_ID in .env.local. Run: juntos db:create -d d1"
              end
            else
              puts "OK"
            end
          else
            puts "MISSING"
            # Only warn if they're likely using D1
            config_path = 'config/database.yml'
            if File.exist?(config_path)
              config = YAML.load_file(config_path, aliases: true) rescue {}
              env = ENV['RAILS_ENV'] || 'development'
              if config.dig(env, 'adapter') == 'd1'
                warnings << "Using D1 but no .env.local file. Run: juntos db:create -d d1"
              end
            end
          end
        end

        def check_wrangler(issues, warnings)
          # Only check if using D1/Cloudflare
          config_path = 'config/database.yml'
          using_cloudflare = false

          if File.exist?(config_path)
            config = YAML.load_file(config_path, aliases: true) rescue {}
            env = ENV['RAILS_ENV'] || 'development'
            using_cloudflare = config.dig(env, 'adapter') == 'd1'
          end

          # Also check if dist/wrangler.toml exists
          using_cloudflare ||= File.exist?('dist/wrangler.toml')

          return unless using_cloudflare

          print "Checking wrangler CLI... "

          if system('npx wrangler --version', out: File::NULL, err: File::NULL)
            puts "OK"
          else
            puts "MISSING"
            warnings << "wrangler not found. Install with: npm install -D wrangler"
          end
        end

        def check_dist(issues, warnings)
          print "Checking dist/ directory... "

          if File.directory?('dist')
            if File.exist?('dist/package.json')
              puts "OK (built)"

              # Check if node_modules exists
              unless File.directory?('dist/node_modules')
                warnings << "dist/node_modules missing. Run: cd dist && npm install"
              end
            else
              puts "WARN"
              warnings << "dist/ exists but no package.json. Run: juntos build"
            end
          else
            puts "NOT BUILT"
            # Not an issue, just informational
          end
        end
      end
    end
  end
end
