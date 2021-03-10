@ruby2js_options = {filters: ['stimulus'], eslevel: 2022}
eval IO.read "#{__dir__}/webpacker.rb"

insert_into_file Rails.root.join("app/javascript/controllers/index.js").to_s,
  '(\\.rb)?', after: '_controller\\.js'
