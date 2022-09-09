const path = require("path")
const convert = require('convert-source-map')
const fs = require('fs').promises
const { spawn } = require('child_process');

const spawnChild = async (source, extraArgs, filepath) => {
  const child = spawn('bundle', ['exec', 'ruby2js', '--filepath', filepath, ...extraArgs])

  child.stdin.write(source)
  child.stdin.end()

  let data = "";
  for await (const chunk of child.stdout) {
    data += chunk;
  }
  let error = "";
  for await (const chunk of child.stderr) {
    error += chunk;
  }
  const exitCode = await new Promise((resolve, reject) => {
    child.on('close', resolve);
  });

  if (exitCode) {
    throw new Error(`subprocess error exit ${exitCode}, ${data} ${error}`);
  }
  return data;
}

const ruby2js = (options = {}) => ({
  name: 'ruby2js',
  setup(build) {
    if (!options.buildFilter) options.buildFilter = /\.js\.rb$/
    let extraArgs = []
    if (typeof options.provideSourceMaps === "undefined") {
      options.provideSourceMaps = true
    }
    if (options.provideSourceMaps) {
      extraArgs.push("--sourcemap")
    }
    if (typeof options.extraArgs !== undefined) {
      extraArgs = [...extraArgs, ...(options.extraArgs || [])]
    }

    build.onLoad({ filter: options.buildFilter }, async (args) => {
      const code = await fs.readFile(args.path, 'utf8')
      let js = await spawnChild(code, extraArgs, args.path)

      if (options.provideSourceMaps) {
        js = JSON.parse(js)
        const output = `${js.code}\n`
        const smap = js.sourcemap
        smap.sourcesContent = [code]
        smap.sources[0] = path.basename(args.path)

        return {
          contents: output + convert.fromObject(smap).toComment(),
          loader: 'js'
        }
      } else {
        return {
          contents: js,
          loader: 'js'
        }
      }
    })
  },
})

module.exports = ruby2js
