function importAll(r) { r.keys().forEach(r) }
importAll(require.context("elements", true, /_elements?\.js(\.rb)?$/))
