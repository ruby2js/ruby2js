require_relative './webpack'

run 'yarn add lit-element @ruby2js/webpack-loader'

directory File.expand_path("app/javascript/elements", __dir__),
  Rails.root.join('app/javascript/elements').to_s

append_to_file Rails.root.join('app/javascript/packs/application.js').to_s,
  "\nimport 'elements'\n"

webpack_environment 'lit-element'
