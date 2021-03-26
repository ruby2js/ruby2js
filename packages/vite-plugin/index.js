const Ruby2JS = require('@ruby2js/ruby2js');
const { extname } = require('path');

module.exports = options => {
  let extensions = options.extensions || ['.rb'];

  return {
    transform(code, id) {
      if (!extensions.includes(extname(id))) return;

      js = Ruby2JS.convert(code, {...options, file: id});

      return {
        code: js.toString(),
        map: js.sourcemap
      }
    }
  }
}
