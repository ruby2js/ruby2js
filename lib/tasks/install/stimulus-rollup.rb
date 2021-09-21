# install rollup plugin
run "yarn add @ruby2js/rollup-plugin"

# configure rollup for ruby2js with stimulus filters
insert_into_file Rails.root.join("rollup.config.js").to_s,
  "import ruby2js from '@ruby2js/rollup-plugin';\n",
  after: /import resolve from .*\n/

insert_into_file Rails.root.join("rollup.config.js").to_s,
  <<-CONFIG, after: "resolve()\n"
    ,ruby2js({
      eslevel: 2020,
      autoexports: 'default',
      filters: ['stimulus', 'esm', 'functions']
    })
  CONFIG

# monkey patch stimulus:manifest:update to find .rb.js controllers too.
# See https://github.com/hotwired/stimulus-rails/issues/76
append_to_file Rails.root.join('config/application.rb').to_s,
  "\n" + <<~'CONFIG'
    require 'stimulus/manifest'

    module Stimulus::Manifest
      def import_and_register_controller(controllers_path, controller_path)
        controller_path = controller_path.relative_path_from(controllers_path).to_s
        module_path = controller_path.split('.').first
        controller_class_name = module_path.camelize.gsub(/::/, "__")
        tag_name = module_path.remove(/_controller/).gsub(/_/, "-").gsub(/\//, "--")

        <<~JS

          import #{controller_class_name} from "./#{controller_path}"
          application.register("#{tag_name}", #{controller_class_name})
        JS
      end

      def extract_controllers_from(directory)
        (directory.children.select { |e| e.to_s =~ /_controller\.js(\.\w+)?$/ } +
          directory.children.select(&:directory?).collect { |d| extract_controllers_from(d) }
        ).flatten.sort
      end
    end
  CONFIG
