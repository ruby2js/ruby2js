const ruby2js = require("../src/index.js")
const path = require("path")

process.chdir(__dirname);

const watch = process.argv.includes("--watch")
const minify = process.argv.includes("--minify")

require("esbuild").build({
  entryPoints: ["application.js"],
  bundle: true,
  outdir: path.join(process.cwd(), "app/assets/builds"),
  absWorkingDir: path.join(process.cwd(), "app/javascript"),
  publicPath: "/assets",
  watch,
  minify,
  plugins: [
    ruby2js({
      preset: true
    })
  ],
}).catch(() => process.exit(1))