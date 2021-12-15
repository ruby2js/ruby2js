const Ruby2JS = require('@ruby2js/ruby2js')
const convert = require('convert-source-map')
const path = require('path')
const fs = require('fs').promises

module.exports = (options = {}) => ({
  name: 'ruby2js',
  setup(build) {
    if (!options.buildFilter) options.buildFilter = /\.js\.rb$/

    build.onLoad({ filter: options.buildFilter }, async (args) => {
      const code = await fs.readFile(args.path, 'utf8')
      js = Ruby2JS.convert(code, { ...options, file: args.path })
      const output = js.toString()

      const smap = js.sourcemap
      smap.sourcesContent = [code]
      smap.sources[0] = path.basename(args.path)

      return {
        contents: output + convert.fromObject(smap).toComment(),
        loader: 'js'
      }
    })
  },
})
