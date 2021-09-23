@ruby2js_options = {filters: ['lit']}
@yarn_add='lit'
eval IO.read "#{__dir__}/webpacker.rb"

directory File.expand_path("app/javascript/elements", __dir__),
  Rails.root.join('app/javascript/elements').to_s

append_to_file Rails.root.join('app/javascript/packs/application.js').to_s,
  "\nimport 'elements'\n"
