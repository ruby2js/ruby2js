const { environment } = require('@rails/webpacker')

module.exports = {
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
        eslevel: 2021,
        filters: ["esm", "functions"]
      }
    }
  ]
}
