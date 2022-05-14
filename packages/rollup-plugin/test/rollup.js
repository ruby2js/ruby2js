const assert = require('assert');
const { rollup } = require('rollup');
const Ruby2JS = require('../index.js');

process.chdir(__dirname);

describe('@ruby2js/rollup-plugin', function() {
  this.timeout(5000);

  it('runs code through ruby2js', async () => {
    let input = "./main.js.rb";

    let bundle = await rollup({
      input,

      plugins: [
        Ruby2JS({
          "filters": ['functions']
        })
      ]
    })

    let js = await bundle.generate({sourcemap: true, format: 'es'});

    assert.strictEqual('console.log(parseInt("2A", 16));\n', js.output[0].code);
    assert.strictEqual('OAAA,CAAK,GAAA,CAAA,QAAA,CAAA,IAAA,EAAU,EAAV,CAAL', js.output[0].map.mappings);
  })
})
