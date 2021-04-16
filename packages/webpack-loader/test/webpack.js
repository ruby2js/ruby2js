const assert = require('assert');
const webpack = require('webpack');
const memfs = require('memfs');
const fs = require('fs');
const path = require('path');

process.chdir(__dirname);

describe('@ruby2js/webpack-loader', function() {
  this.timeout(5000);

  it('supports options in webpack config', async () => {
    let compiler = webpack({
      entry: "./main.js.rb",

      output: {
        path: __dirname,
        filename: "main.[contenthash].js"
      },

      resolve: {
        extensions: [".rb.js", ".rb"]
      },

      module: {
        rules: [
          {
            test: /\.js\.rb$/,
            use: [
              {
                loader: '../dist/cjs.js',
                options: {
                  eslevel: 2021,
                  filters: ['functions']
                }
              },
            ]
          },
        ]
      }
    });

    compiler.outputFileSystem = memfs;

    let stats = await new Promise((resolve, reject) => {
      compiler.run((err, stats) => {
        err ? reject(err) : resolve(stats);
      })
    });

    const output = stats.toJson({ source: true }).modules[0].source;

    assert.deepStrictEqual(stats.compilation.errors, []);
    assert.strictEqual(output, 'console.log(`0x2A = ${parseInt("2A", 16)}`)');
  })
})
