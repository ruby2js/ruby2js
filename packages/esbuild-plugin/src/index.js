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

      const smap = js.sourcemap
      const rubyCode = await fs.readFile(smap.sources[0], 'utf8')
      smap.sourcesContent = [rubyCode]
      smap.sources[0] = path.basename(smap.sources[0])

      const output = js.toString() + convert.fromObject(smap).toComment()
      return {
        contents: output,
        loader: 'js'
      }
    })
  },
})
