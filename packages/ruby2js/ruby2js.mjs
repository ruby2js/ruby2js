import './ruby2js.js'

// export Ruby2JS both as default and by name, supporting both
// "import Ruby2JS from" and "import { Ruby2JS } from"
export default global.Ruby2JS
export const Ruby2JS = global.Ruby2JS

// export Ruby2JS properties for individual import
export const convert = global.Ruby2JS.convert
export const parse = global.Ruby2JS.parse
export const AST = global.Ruby2JS.AST
export const nil = global.Ruby2JS.nil
