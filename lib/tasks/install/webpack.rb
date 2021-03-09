def webpack_environment(filter)
  insert_into_file Rails.root.join("config/webpacker.yml").to_s,
    "    - .js.rb\n", after: "\n    - .js\n"

  target = Rails.root.join("config/webpack/environment.js").to_s

  if not IO.read(target).include? '@ruby2js/webpack-loader'
    append_to_file target, "\n" + <<~CONFIG
      // Insert rb2js loader at the end of list
      environment.loaders.append('rb2js', {
        test: /\.js\.rb$/,
        use: [
          {
            loader: "babel-loader",
            options: environment.loaders.get('babel').use[0].options
          },

          {
            loader: "@ruby2js/webpack-loader",
            options: {
              autoexports: "default",
              eslevel: 2022,
              filters: [#{filter.inspect}, "esm", "functions"]
            }
          },
        ]
      })
    CONFIG
  else
    insert_into_file target, filter.inspect, after: 'filters: ['
  end
end
