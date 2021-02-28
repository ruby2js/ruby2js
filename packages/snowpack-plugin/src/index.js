const Ruby2JS = require('@ruby2js/ruby2js');
const fsp = require('fs').promises;

module.exports = function (snowpackConfig, pluginOptions) {
  return {
    name: 'ruby2js-plugin',

    resolve: {
      input: ['.js.rb', '.rb'],
      output: ['.js'],
    },

    async load({ filePath }) {
      try {
        return Ruby2JS.convert(
          await fsp.readFile(filePath, 'utf8'),
          { ...pluginOptions, file: filePath }
        ).toString()
      } catch(error) {
        let message = error.message;
        if (error.diagnostic) message += `\n\n${error.diagnostic}`;
        throw new Error(message + "\n")
      }
    }
  }
};
