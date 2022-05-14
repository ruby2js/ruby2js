const assert = require('assert')
const fs = require('fs').promises

describe('@ruby2js/esbuild-plugin', function() {
  this.timeout(5000);

  it('runs code through ruby2js', async () => {
    require("./esbuild.config.js")

    const code = await fs.readFile("app/assets/builds/application.js", { encoding: "utf-8"})

    assert.strictEqual(
`(() => {
  // main.js.rb
  console.log(parseInt("2A", 16));
})();
`, code)
  })
})
