const ruby2js = require("../src/index.js")
const path = require("path")

process.chdir(__dirname);

const watch = process.argv.includes("--watch")
const minify = process.argv.includes("--minify")

const options = {
  entryPoints: ["application.js"],
  bundle: true,
  outdir: path.join(process.cwd(), "app/assets/builds"),
  absWorkingDir: path.join(process.cwd(), "app/javascript"),
  publicPath: "/assets",
  minify,
  plugins: [
    ruby2js({
      extraArgs: ["--preset"]
    })
  ],
}

async function run() {
  if (watch) {
    const ctx = await require("esbuild").context(options)
    await ctx.watch()
  } else {
    await require("esbuild").build(options)
  }
}

run().catch(() => process.exit(1))
