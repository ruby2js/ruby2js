# frozen_string_literal: true

namespace :ruby2js do
  desc "Transpile Ruby Stimulus controllers to JavaScript"
  task transpile_controllers: :environment do
    require 'ruby2js'

    controllers_path = Rails.root.join("app/javascript/controllers")
    next unless controllers_path.exist?

    filters = [:stimulus, :functions, :esm]
    options = { autoexports: :default }

    Dir[controllers_path.join("*_controller.rb")].each do |rb_path|
      js_path = rb_path.sub(/\.rb$/, '.js')

      if !File.exist?(js_path) || File.mtime(rb_path) > File.mtime(js_path)
        begin
          js = Ruby2JS.convert(File.read(rb_path), filters: filters, **options)
          File.write(js_path, js.to_s)
          puts "Ruby2JS: Transpiled #{File.basename(rb_path)} -> #{File.basename(js_path)}"
        rescue => e
          warn "Ruby2JS: Failed to transpile #{rb_path}: #{e.message}"
        end
      end
    end
  end
end

# Hook into assets:precompile for production builds
if Rake::Task.task_defined?('assets:precompile')
  Rake::Task['assets:precompile'].enhance(['ruby2js:transpile_controllers'])
end
