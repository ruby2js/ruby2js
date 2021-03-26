const Ruby2JS = require('@ruby2js/rollup-plugin');
const btoa = require('btoa');

module.exports = options => {
  options = {...options};
  let refresh = options.refresh || {};
  delete options.refresh;

  let ruby2js = Ruby2JS(options);

  return {
    ...refresh,

    transform(code, id, ssr) {
      let js = ruby2js.transform(code, id);

      if (refresh.transform) {

        if (js) {
          code = js.code + 
            "\n//# sourceMappingURL=data:application/json;base64," +
            btoa(JSON.stringify(js.map));

          if (id.endsWith('.rb')) id = id.slice(0, -3);
          if (!id.endsWith('.js')) id += '.js';
        }

        let output = refresh.transform(code, id, ssr)
        return output

      } else {

        return js

      }
    }
  }
}
