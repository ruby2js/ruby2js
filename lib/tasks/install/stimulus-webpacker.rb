require_relative './webpack'

run 'yarn add @ruby2js/webpack-loader'

webpack_environment 'stimulus'

insert_into_file Rails.root.join("app/javascript/controllers/index.js").to_s,
  '(\\.rb)?', after: '_controller\\.js'
